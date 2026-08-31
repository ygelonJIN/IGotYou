import 'package:flutter_test/flutter_test.dart';

import 'package:igotyou/core/models/vault_config.dart';

void main() {
  group('VaultConfig 冷却序列（DEVELOPMENT 4.1）', () {
    test('默认 [1]×2：1,2,4,8,…', () {
      const cfg = VaultConfig.defaults();
      expect(cfg.cooldownDurationMinutes(1), 1);
      expect(cfg.cooldownDurationMinutes(2), 2);
      expect(cfg.cooldownDurationMinutes(3), 4);
      expect(cfg.cooldownDurationMinutes(4), 8);
      expect(cfg.cooldownDurationMinutes(10), 512);
    });

    test('baseSequence=[10,10,10] ×2：前三次 10，之后 20,40,80', () {
      const cfg = VaultConfig(
        hitCount: 3,
        roundChances: 30,
        cooldownChances: 1,
        cooldownBase: [10, 10, 10],
        cooldownGrowth: 2,
      );
      expect(cfg.cooldownDurationMinutes(1), 10);
      expect(cfg.cooldownDurationMinutes(2), 10);
      expect(cfg.cooldownDurationMinutes(3), 10);
      expect(cfg.cooldownDurationMinutes(4), 20);
      expect(cfg.cooldownDurationMinutes(5), 40);
      expect(cfg.cooldownDurationMinutes(6), 80);
    });

    test('baseSequence=[5] ×1：固定 5', () {
      const cfg = VaultConfig(
        hitCount: 3,
        roundChances: 30,
        cooldownChances: 1,
        cooldownBase: [5],
        cooldownGrowth: 1,
      );
      for (var i = 1; i <= 6; i++) {
        expect(cfg.cooldownDurationMinutes(i), 5);
      }
    });

    test('baseSequence=[2,3] ×2：2,3,6,12,24', () {
      const cfg = VaultConfig(
        hitCount: 3,
        roundChances: 30,
        cooldownChances: 1,
        cooldownBase: [2, 3],
        cooldownGrowth: 2,
      );
      expect(cfg.cooldownDurationMinutes(1), 2);
      expect(cfg.cooldownDurationMinutes(2), 3);
      expect(cfg.cooldownDurationMinutes(3), 6);
      expect(cfg.cooldownDurationMinutes(4), 12);
      expect(cfg.cooldownDurationMinutes(5), 24);
    });
  });

  group('VaultConfig 约束校验（DEVELOPMENT 6.4）', () {
    test('默认参数合法', () {
      expect(const VaultConfig.defaults().validate(), isNull);
    });

    test('K=0 非法；K ≤ 钥匙数合法', () {
      const cfg = VaultConfig.defaults();
      expect(
        cfg.copyWith(hitCount: 0).validate(keyCount: 3),
        '命中数最小 1',
      );
      expect(cfg.copyWith(hitCount: 3).validate(keyCount: 3), isNull);
    });

    test('K 超过钥匙数非法', () {
      expect(
        const VaultConfig.defaults().copyWith(hitCount: 5).validate(keyCount: 2),
        '当前钥匙密码 2 种，命中数最大 2',
      );
    });

    test('M/C/冷却序列/增长率非法值均被拒绝', () {
      const cfg = VaultConfig.defaults();
      expect(cfg.copyWith(roundChances: 0).validate(), '机会数最小 1');
      expect(cfg.copyWith(cooldownChances: 0).validate(), '冷却后机会数最小 1');
      expect(cfg.copyWith(cooldownBase: []).validate(), '冷却序列不能为空');
      expect(
        cfg.copyWith(cooldownBase: [1, 0]).validate(),
        '冷却时长最小 1 分钟',
      );
      expect(cfg.copyWith(cooldownGrowth: 0).validate(), '冷却增长率最小 1');
    });
  });

  group('VaultConfig 序列化', () {
    test('toJson / fromJson 往返', () {
      const cfg = VaultConfig(
        hitCount: 4,
        roundChances: 12,
        cooldownChances: 2,
        cooldownBase: [3, 5],
        cooldownGrowth: 3,
      );
      final json = cfg.toJson();
      final back = VaultConfig.fromJson(json);
      expect(back.hitCount, 4);
      expect(back.roundChances, 12);
      expect(back.cooldownChances, 2);
      expect(back.cooldownBase, [3, 5]);
      expect(back.cooldownGrowth, 3);
    });

    test('copyWith 默认保持原值', () {
      const cfg = VaultConfig.defaults();
      final copy = cfg.copyWith(hitCount: 7);
      expect(copy.hitCount, 7);
      expect(copy.roundChances, VaultConfig.defaultRoundChances);
      expect(copy.cooldownBase, VaultConfig.defaultCooldownBase);
    });
  });
}
