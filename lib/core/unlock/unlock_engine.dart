import 'dart:async';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

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

  const UnlockSubmitResult({
    required this.hit,
    required this.success,
    required this.failed,
    required this.rejected,
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
    final found = await _findHitShare(kek);

    var hit = false;
    if (found != null) {
      // 按值去重：不同值才计命中。
      if (_hitValues.add(normalized)) {
        _hitShares.add(found);
        hit = true;
      }
    }

    final k = config.hitCount;
    if (_hitValues.length >= k) {
      // 打开成功 → 全部重置（DEVELOPMENT 4.2）。
      _mk = await _reconstructMk();
      state.reset(config);
      _saveState();
      return UnlockSubmitResult(
        hit: hit,
        success: true,
        failed: false,
        rejected: false,
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

  /// 用派生出的 KEK 尝试解密份额，返回第一个解开（命中）的份额及其 y 值。
  /// 多个条目内容相同时一次输入只取一份（去重规则，DEVELOPMENT 3.3）。
  Future<({ShareRecord share, Uint8List y})?> _findHitShare(SecretKey kek) async {
    for (final share in data.shares) {
      final y = await Keychain.tryDecryptShare(share, kek);
      if (y != null) return (share: share, y: y);
    }
    return null;
  }

  Future<Uint8List> _reconstructMk() async {
    final shares = _hitShares.map((e) => e.share).toList();
    final ys = _hitShares.map((e) => e.y).toList();
    return Keychain.reconstructMk(shares, ys: ys);
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