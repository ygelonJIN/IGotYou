import 'dart:async';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../crypto/aes_gcm.dart';
import '../crypto/argon2.dart';
import '../crypto/keychain.dart';
import '../file/vault_file.dart';
import '../models/share_record.dart';
import '../models/vault_config.dart';
import '../normalize.dart';
import 'attempt_state.dart';

/// 一次盲输提交的结果（供 UI 呈现，遵循盲输原则：不含命中数）。
class UnlockSubmitResult {
  final bool hit; // 本次是否命中（新的不同值）
  final bool success; // 打开成功
  final bool failed; // 打开失败（本轮机会耗尽，进入冷却）
  final bool rejected; // 提交被拒绝（冷却中）
  final bool needsRepair; // 份额所在多项式阶数 > 当前 K，需继续输入更多钥匙口令

  const UnlockSubmitResult({
    required this.hit,
    required this.success,
    required this.failed,
    required this.rejected,
    this.needsRepair = false,
  });

  static const UnlockSubmitResult rejectedResult = UnlockSubmitResult(
    hit: false,
    success: false,
    failed: false,
    rejected: true,
  );
}

/// 解锁引擎（DEVELOPMENT 3/4/11）：命中判定、按值去重、机会与冷却状态机。
///
/// 不持有任何明文秘密；命中的份额点 (x, y) 仅存在于内存，打开成功后用于重构 MK，
/// 锁定/冷却开始时立即清空。
class UnlockEngine {
  final VaultFileData data;
  final String statePath;

  late AttemptState state;

  final Set<String> _hitValues = {}; // 已命中的不同规范化值（去重）
  final List<({ShareRecord share, Uint8List y})> _hitShares = [];

  /// 本轮命中份额对应条目 id → 规范化口令。与命中记录同生命周期：
  /// 打开成功后供会话缓存二次加密钥匙口令（自动修复份额，17.20）。
  final Map<String, String> _hitPasswords = {};
  Uint8List? _mk;

  UnlockEngine({required this.data, required this.statePath})
      : state = AttemptState.fresh(data.header.config);

  VaultConfig get config => data.header.config;
  Argon2Deriver get deriver => data.header.deriver;

  int get remainingChances => state.remainingChances;
  bool get inCooldown => state.inCooldown;
  bool get isUnlocked => _mk != null;

  /// 还差几个不同值可打开（K - 已命中不同值数）。
  int get hitsToOpen => config.hitCount - _hitValues.length;

  /// 是否"最后一步"（DEVELOPMENT 8.2）：已命中 K-1 个、只差一个正确值即可打开。
  /// K=1 时恒为 false——任何命中即打开。
  bool get isLastStep => config.hitCount > 1 && hitsToOpen <= 1;

  /// 是否经由存量库份额修复路径打开（累计命中数 > K）：份额所在多项式
  /// 阶数高于当前 K。打开后会话应标记下次保存全量重切（17.18）。
  bool get repairedShares => _hitShares.length > config.hitCount;

  /// 本轮命中份额对应条目 → 规范化口令（只含本次打开会话中的命中）。
  Map<String, String> get hitPasswords => Map.unmodifiable(_hitPasswords);

  /// 从库外状态文件加载尝试状态；文件丢失视为满血（DEVELOPMENT 4.4）。
  Future<void> loadState() async {
    state = await AttemptState.load(statePath, config);
    state.advanceIfCooldownDone(config, DateTime.now());
    if (!state.inCooldown) _resetRound();
  }

  void _saveState() {
    unawaited(state.save(statePath));
  }

  void _resetRound() {
    _hitValues.clear();
    _hitShares.clear();
    _hitPasswords.clear();
  }

  /// 盲输提交一个值。返回结果并推进状态机（DEVELOPMENT 11）。
  Future<UnlockSubmitResult> submit(String raw) async {
    final now = DateTime.now();
    final wasCooldown = state.inCooldown;
    state.advanceIfCooldownDone(config, now);
    if (wasCooldown && !state.inCooldown) _resetRound();

    if (state.inCooldown) return UnlockSubmitResult.rejectedResult;

    // 每输入一次消耗一次机会（无论是否命中、是否重复）。
    state.remainingChances -= 1;

    final normalized = normalizeSecret(raw);
    final kek = await deriver.derive(normalized);
    final hits = await _findHitShares(kek);

    var hit = false;
    for (final h in hits) {
      // 记录命中口令 → 条目：同一口令命中多份额时全部记录（供自动修复）。
      _hitPasswords[h.share.entryId] = normalized;
      // 按值去重：同一值只计一次命中、只取第一个份额点。
      if (!hit && _hitValues.add(normalized)) {
        _hitShares.add(h);
        hit = true;
      }
    }

    final k = config.hitCount;
    if (_hitValues.length >= k) {
      // 份额达阈值：先验证重构出的 MK 能否真正解密 BODY。
      // 检测到旧版本落盘的存量库（份额多项式阶数 > 当前 K）时不立即声明成功，
      // 而是保留已累积的份额、继续接受更多钥匙口令——D+1 个不同份额通过
      // Lagrange 插值可在更高阶多项式上恢复正确的 MK（DEVELOPMENT 17.15）。
      final mk = await _reconstructMk();
      if (await _verifyMk(mk)) {
        _mk = mk;
        state.reset(config);
        _saveState();
        return UnlockSubmitResult(
          hit: hit,
          success: true,
          failed: false,
          rejected: false,
        );
      }
      // MK 无效（存量库份额多项式阶数 > K）：保留本次命中份额，
      // 继续接受更多钥匙口令；告诉 UI 需要更多钥匙来修复份额。
      _saveState();
      return UnlockSubmitResult(
        hit: hit,
        success: false,
        failed: false,
        rejected: false,
        needsRepair: true,
      );
    }

    if (state.remainingChances <= 0) {
      // 打开失败 → 冷却序号 +1，清空本轮命中记录。
      state.enterCooldown(config, now);
      _resetRound();
      _saveState();
      return UnlockSubmitResult(
        hit: hit,
        success: false,
        failed: true,
        rejected: false,
      );
    }

    _saveState();
    return UnlockSubmitResult(
      hit: hit,
      success: false,
      failed: false,
      rejected: false,
    );
  }

  /// 用派生出的 KEK 尝试解密全部份额，返回所有解开（命中）的份额及其 y 值。
  /// 多个条目共用同一口令时一次输入会解开多份，全部返回供口令记录
  /// （命中计数仍按值去重，见 [submit]）。
  Future<List<({ShareRecord share, Uint8List y})>> _findHitShares(
    SecretKey kek,
  ) async {
    final result = <({ShareRecord share, Uint8List y})>[];
    for (final share in data.shares) {
      final y = await Keychain.tryDecryptShare(share, kek);
      if (y != null) result.add((share: share, y: y));
    }
    return result;
  }

  Future<Uint8List> _reconstructMk() async {
    final shares = _hitShares.map((e) => e.share).toList();
    final ys = _hitShares.map((e) => e.y).toList();
    return Keychain.reconstructMk(shares, ys: ys);
  }

  /// 用重构出的 MK 尝试解密 BODY，验证其有效性。
  /// 文件损坏（BODY 密文被篡改）或份额多项式不匹配时返回 false。
  Future<bool> _verifyMk(Uint8List mk) async {
    try {
      final bodyCipher = await VaultFile.readBody(data);
      await AesGcmCipher().decrypt(bodyCipher, SecretKeyData(mk));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 锁定：清空 MK 与命中记录；机会与冷却状态保留（DEVELOPMENT 3.5）。
  void lock() {
    _mk = null;
    _resetRound();
  }

  /// 取出重构的 MK（成功后调用），引擎内部的 MK 同时清零。
  Uint8List takeMk() {
    final mk = _mk;
    if (mk == null) throw StateError('not unlocked');
    _mk = null;
    return mk;
  }
}