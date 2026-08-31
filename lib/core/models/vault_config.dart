/// 解锁参数，全部可自定义（DEVELOPMENT 6.2）。
///
/// [hitCount]          K 解锁所需命中的不同口令数
/// [roundChances]      M 每轮机会数
/// [cooldownChances]   C 冷却后每轮机会数
/// [cooldownBase]      冷却基础序列（分钟）
/// [cooldownGrowth]    冷却增长率
class VaultConfig {
  final int hitCount;
  final int roundChances;
  final int cooldownChances;
  final List<int> cooldownBase;
  final int cooldownGrowth;

  const VaultConfig({
    required this.hitCount,
    required this.roundChances,
    required this.cooldownChances,
    required this.cooldownBase,
    required this.cooldownGrowth,
  });

  static const int defaultHitCount = 3;
  static const int defaultRoundChances = 30;
  static const int defaultCooldownChances = 1;
  static const List<int> defaultCooldownBase = [1];
  static const int defaultCooldownGrowth = 2;

  const VaultConfig.defaults()
      : hitCount = defaultHitCount,
        roundChances = defaultRoundChances,
        cooldownChances = defaultCooldownChances,
        cooldownBase = defaultCooldownBase,
        cooldownGrowth = defaultCooldownGrowth;

  /// 冷却序列第 i 次（i 从 1 起）的时长（分钟），见 DEVELOPMENT 4.1。
  int cooldownDurationMinutes(int i) {
    assert(i >= 1);
    if (i <= cooldownBase.length) return cooldownBase[i - 1];
    final steps = i - cooldownBase.length;
    var factor = 1;
    for (var s = 0; s < steps; s++) {
      factor *= cooldownGrowth;
    }
    return cooldownBase.last * factor;
  }

  /// 约束校验：K ≥ 1、M ≥ 1、C ≥ 1、冷却序列每项 ≥ 1、增长率 ≥ 1。
  /// [keyCount] 传入当前钥匙数，用于校验 K ≤ N。
  String? validate({int? keyCount}) {
    if (hitCount < 1) return '命中数最小 1';
    if (keyCount != null && hitCount > keyCount) {
      return '当前钥匙密码 $keyCount 种，命中数最大 $keyCount';
    }
    if (roundChances < 1) return '机会数最小 1';
    if (cooldownChances < 1) return '冷却后机会数最小 1';
    if (cooldownBase.isEmpty) return '冷却序列不能为空';
    if (cooldownBase.any((m) => m < 1)) return '冷却时长最小 1 分钟';
    if (cooldownGrowth < 1) return '冷却增长率最小 1';
    return null;
  }

  VaultConfig copyWith({
    int? hitCount,
    int? roundChances,
    int? cooldownChances,
    List<int>? cooldownBase,
    int? cooldownGrowth,
  }) =>
      VaultConfig(
        hitCount: hitCount ?? this.hitCount,
        roundChances: roundChances ?? this.roundChances,
        cooldownChances: cooldownChances ?? this.cooldownChances,
        cooldownBase: cooldownBase ?? this.cooldownBase,
        cooldownGrowth: cooldownGrowth ?? this.cooldownGrowth,
      );

  Map<String, Object> toJson() => {
        'hitCount': hitCount,
        'roundChances': roundChances,
        'cooldownChances': cooldownChances,
        'cooldownBase': cooldownBase,
        'cooldownGrowth': cooldownGrowth,
      };

  factory VaultConfig.fromJson(Map<String, Object?> json) => VaultConfig(
        hitCount: (json['hitCount']! as num).toInt(),
        roundChances: (json['roundChances']! as num).toInt(),
        cooldownChances: (json['cooldownChances']! as num).toInt(),
        cooldownBase: (json['cooldownBase'] as List<Object?>)
            .map((v) => (v! as num).toInt())
            .toList(),
        cooldownGrowth: (json['cooldownGrowth']! as num).toInt(),
      );
}
