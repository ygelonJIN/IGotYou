import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:igotyou/core/models/vault_config.dart';
import 'package:igotyou/core/unlock/attempt_state.dart';

const VaultConfig _cfg = VaultConfig.defaults();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AttemptState 状态机（DEVELOPMENT 4）', () {
    test('fresh：机会 = M，无冷却', () {
      final s = AttemptState.fresh(_cfg);
      expect(s.remainingChances, VaultConfig.defaultRoundChances);
      expect(s.inCooldown, isFalse);
      expect(s.cooldownIndex, 0);
    });

    test('进入冷却：序号 +1，时长按序列', () {
      final s = AttemptState.fresh(_cfg);
      final now = DateTime(2026, 8, 30, 12, 0, 0);
      s.enterCooldown(_cfg, now);
      expect(s.inCooldown, isTrue);
      expect(s.cooldownIndex, 1);
      expect(s.remainingChances, 0);
      // 默认 [1] 分钟：冷却到 12:01:00。
      expect(s.remainingCooldownMs(now), 60000);
      expect(s.remainingCooldownMs(now.add(const Duration(minutes: 1))), 0);
    });

    test('连续失败：冷却时长按 1,2,4 递增', () {
      final s = AttemptState.fresh(_cfg);
      final now = DateTime(2026, 8, 30, 12, 0, 0);
      s.enterCooldown(_cfg, now);
      expect(s.cooldownIndex, 1);
      expect(s.remainingCooldownMs(now), 60000);

      s.enterCooldown(_cfg, now.add(const Duration(hours: 1)));
      expect(s.cooldownIndex, 2);
      expect(s.remainingCooldownMs(now.add(const Duration(hours: 1))), 120000);

      s.enterCooldown(_cfg, now.add(const Duration(hours: 2)));
      expect(s.cooldownIndex, 3);
      expect(s.remainingCooldownMs(now.add(const Duration(hours: 2))), 240000);
    });

    test('冷却到期后：机会 = C', () {
      final s = AttemptState.fresh(_cfg);
      final now = DateTime(2026, 8, 30, 12, 0, 0);
      s.enterCooldown(_cfg, now);
      s.advanceIfCooldownDone(_cfg, now.add(const Duration(minutes: 2)));
      expect(s.inCooldown, isFalse);
      expect(s.remainingChances, VaultConfig.defaultCooldownChances);
    });

    test('冷却中 advanceIfCooldownDone 不重置', () {
      final s = AttemptState.fresh(_cfg);
      final now = DateTime(2026, 8, 30, 12, 0, 0);
      s.enterCooldown(_cfg, now);
      s.advanceIfCooldownDone(_cfg, now.add(const Duration(seconds: 30)));
      expect(s.inCooldown, isTrue);
    });

    test('打开成功 reset：满血回 0', () {
      final s = AttemptState.fresh(_cfg);
      final now = DateTime(2026, 8, 30, 12, 0, 0);
      s.enterCooldown(_cfg, now);
      s.enterCooldown(_cfg, now.add(const Duration(hours: 1)));
      s.reset(_cfg);
      expect(s.remainingChances, VaultConfig.defaultRoundChances);
      expect(s.cooldownIndex, 0);
      expect(s.inCooldown, isFalse);
    });
  });

  group('AttemptState 持久化（DEVELOPMENT 4.4）', () {
    test('写文件 → 读文件往返', () async {
      final dir = await Directory.systemTemp.createTemp('attempt_state_test');
      addTearDown(() => dir.delete(recursive: true));
      final path = '${dir.path}/attempt_state.json';

      final s = AttemptState.fresh(_cfg)
        ..remainingChances = 7
        ..cooldownIndex = 3
        ..cooldownUntilMs = 9999;
      await s.save(path);

      final loaded = await AttemptState.load(path, _cfg);
      expect(loaded.remainingChances, 7);
      expect(loaded.cooldownIndex, 3);
      expect(loaded.cooldownUntilMs, 9999);
    });

    test('文件不存在 → 满血', () async {
      final dir = await Directory.systemTemp.createTemp('attempt_state_test');
      addTearDown(() => dir.delete(recursive: true));
      final s = await AttemptState.load('${dir.path}/missing.json', _cfg);
      expect(s.remainingChances, VaultConfig.defaultRoundChances);
      expect(s.cooldownIndex, 0);
    });

    test('文件内容损坏 → 满血', () async {
      final dir = await Directory.systemTemp.createTemp('attempt_state_test');
      addTearDown(() => dir.delete(recursive: true));
      final path = '${dir.path}/attempt_state.json';
      await File(path).writeAsString('not json{{');
      final s = await AttemptState.load(path, _cfg);
      expect(s.remainingChances, VaultConfig.defaultRoundChances);
    });

    test('保存失败不抛异常（静默）', () async {
      final s = AttemptState.fresh(_cfg);
      await s.save('/nonexistent_dir_xyz/attempt_state.json');
      // 不抛即通过。
    });
  });

  group('AttemptState 序列化', () {
    test('toJson 字段完整', () {
      final s = AttemptState.fresh(_cfg);
      final json = s.toJson();
      expect(jsonEncode(json), contains('remainingChances'));
      expect(jsonEncode(json), contains('cooldownIndex'));
      expect(jsonEncode(json), contains('cooldownUntilMs'));
    });
  });
}
