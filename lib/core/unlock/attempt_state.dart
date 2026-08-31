import 'dart:convert';
import 'dart:io';

import '../models/vault_config.dart';

/// 尝试状态（DEVELOPMENT 4.4）：存库外独立明文小文件，不含任何秘密内容。
///
/// 字段：
/// - [remainingChances] 当前轮剩余机会数
/// - [cooldownIndex]    当前冷却序号 i（每次打开失败 +1，打开成功归 0）
/// - [cooldownUntilMs]  冷却到期时间戳（毫秒），0 表示不在冷却
///
/// 该文件丢失 → 视为无失败记录，机会满血（可接受：仅放宽尝试限制）。
class AttemptState {
  int remainingChances;
  int cooldownIndex;
  int cooldownUntilMs;

  AttemptState({
    required this.remainingChances,
    this.cooldownIndex = 0,
    this.cooldownUntilMs = 0,
  });

  /// 满血状态：机会 = 每轮机会数 M，无冷却。
  factory AttemptState.fresh(VaultConfig config) =>
      AttemptState(remainingChances: config.roundChances);

  bool get inCooldown => cooldownUntilMs > 0;

  Map<String, Object> toJson() => {
        'remainingChances': remainingChances,
        'cooldownIndex': cooldownIndex,
        'cooldownUntilMs': cooldownUntilMs,
      };

  factory AttemptState.fromJson(Map<String, Object?> json) => AttemptState(
        remainingChances: (json['remainingChances']! as num).toInt(),
        cooldownIndex: (json['cooldownIndex'] as num? ?? 0).toInt(),
        cooldownUntilMs: (json['cooldownUntilMs'] as num? ?? 0).toInt(),
      );

  /// 从文件加载；不存在或解析失败 → 满血（见 DEVELOPMENT 4.4）。
  static Future<AttemptState> load(String path, VaultConfig config) async {
    final file = File(path);
    try {
      if (!await file.exists()) return AttemptState.fresh(config);
      final json =
          jsonDecode(await file.readAsString()) as Map<String, Object?>;
      return AttemptState.fromJson(json);
    } catch (_) {
      return AttemptState.fresh(config);
    }
  }

  /// 保存到文件；失败时静默忽略（状态丢失仅放宽尝试限制，无安全影响）。
  Future<void> save(String path) async {
    try {
      await File(path).writeAsString(jsonEncode(toJson()));
    } catch (_) {}
  }

  /// 打开成功 → 全部重置（DEVELOPMENT 4.2/5.4）。
  void reset(VaultConfig config) {
    remainingChances = config.roundChances;
    cooldownIndex = 0;
    cooldownUntilMs = 0;
  }

  /// 打开失败 → 冷却序号 +1，进入冷却（时长取序列第 cooldownIndex 个值）。
  void enterCooldown(VaultConfig config, DateTime now) {
    cooldownIndex += 1;
    final minutes = config.cooldownDurationMinutes(cooldownIndex);
    remainingChances = 0;
    cooldownUntilMs = now.add(Duration(minutes: minutes)).millisecondsSinceEpoch;
  }

  /// 冷却结束 → 新一轮，机会 = C（DEVELOPMENT 4.2）。
  void finishCooldown(VaultConfig config) {
    cooldownUntilMs = 0;
    remainingChances = config.cooldownChances;
  }

  /// 返回距冷却结束的剩余毫秒；不在冷却或已到期返回 0。
  int remainingCooldownMs(DateTime now) {
    if (!inCooldown) return 0;
    final left = cooldownUntilMs - now.millisecondsSinceEpoch;
    return left > 0 ? left : 0;
  }

  /// 若冷却已到期则推进到新一轮（机会 = C）。
  void advanceIfCooldownDone(VaultConfig config, DateTime now) {
    if (inCooldown && remainingCooldownMs(now) == 0) {
      finishCooldown(config);
    }
  }
}
