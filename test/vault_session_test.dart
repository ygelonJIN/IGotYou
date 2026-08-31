import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:igotyou/core/crypto/aes_gcm.dart';
import 'package:igotyou/core/crypto/argon2.dart';
import 'package:igotyou/core/crypto/keychain.dart';
import 'package:igotyou/core/file/vault_file.dart';
import 'package:igotyou/core/models/entry.dart';
import 'package:igotyou/core/models/vault_config.dart';
import 'package:igotyou/core/vault_session.dart';

final Random _rnd = Random.secure();

Uint8List secBytes(int n) {
  final b = Uint8List(n);
  for (var i = 0; i < n; i++) {
    b[i] = _rnd.nextInt(256);
  }
  return b;
}

Argon2Deriver fastDeriver({Uint8List? salt}) => Argon2Deriver(
      memory: 64,
      iterations: 1,
      parallelism: 1,
      hashLength: 32,
      salt: salt ?? secBytes(16),
    );

Entry entry(int seed, String secret, {bool isKey = true}) => Entry(
      id: 'entry-$seed',
      name: '条目 $seed',
      secret: secret,
      note: '',
      isKey: isKey,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

/// 写入真实格式库文件，用低成本 Argon2（其余与生产一致），返回打开的会话。
Future<VaultSession> openSession(
  Directory dir, {
  required List<Entry> entries,
  required VaultConfig config,
}) async {
  final mk = Keychain.generateMk();
  final deriver = fastDeriver();
  final keyEntries = entries.where((e) => e.isKey).toList();
  final shares = await Keychain.splitSecret(
    mk: mk,
    keyEntries: keyEntries,
    threshold: config.hitCount,
    deriver: deriver,
  );
  final header = VaultHeader(
    version: vaultFileVersion,
    argonParams: deriver.params,
    salt: Uint8List.fromList(deriver.salt),
    config: config,
  );
  final bodyJson = jsonEncode({
    'entries': entries.map((e) => e.toJson()).toList(),
    'config': config.toJson(),
  });
  final body = await AesGcmCipher().encrypt(bodyJson, SecretKeyData(mk));
  final path = '${dir.path}/vault.igotyou';
  await VaultFile.write(
    path,
    header: header,
    shares: shares,
    body: body,
  );
  return VaultSession.open(path: path, fileData: await VaultFile.read(path), mk: mk);
}

/// 测试辅助：绕过会话访问 BODY 明文（供二次加密测试读取落盘状态）。
class VaultSessionTestHelper {
  /// 解密 BODY 返回库 JSON。
  static Future<Map<String, Object?>> decryptBody(
    VaultFileData data,
    VaultSession session,
  ) async {
    final cipher = await VaultFile.readBody(data);
    final jsonStr = await AesGcmCipher().decrypt(cipher, SecretKeyData(session.mk));
    return jsonDecode(jsonStr) as Map<String, Object?>;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('vault_session_test');
  });
  tearDown(() async {
    await dir.delete(recursive: true);
  });

  group('最后一把钥匙守卫（DEVELOPMENT 6.4 硬约束下限）', () {
    test('关掉最后一把钥匙 → 抛 StateError，条目与配置不变', () async {
      final session = await openSession(
        dir,
        entries: [entry(1, 'a', isKey: true), entry(2, 'b', isKey: false)],
        config: const VaultConfig.defaults().copyWith(hitCount: 1),
      );
      final lastKey = session.entries.singleWhere((e) => e.isKey);
      final beforeEntries = session.entries.map((e) => e.toJson()).toList();
      final beforeK = session.config.hitCount;

      expect(() => session.setEntryKey(lastKey, false), throwsStateError);
      expect(session.keyCount, 1);
      expect(session.config.hitCount, beforeK);
      expect(
        session.entries.map((e) => e.toJson()).toList(),
        beforeEntries,
      );

      // 保存后库仍可用：份额非空。
      await session.save();
      final data = await VaultFile.read('${dir.path}/vault.igotyou');
      expect(data.shares, isNotEmpty);
    });

    test('删除最后一把钥匙 → 抛 StateError，条目保留', () async {
      final session = await openSession(
        dir,
        entries: [entry(1, 'a', isKey: true), entry(2, 'b', isKey: false)],
        config: const VaultConfig.defaults().copyWith(hitCount: 1),
      );
      final lastKey = session.entries.singleWhere((e) => e.isKey);

      expect(() => session.deleteEntry(lastKey.id), throwsStateError);
      expect(session.keyCount, 1);
      expect(session.entryById(lastKey.id), isNotNull);
    });

    test('关闭非最后一把钥匙：成功，K 自动下调到剩余钥匙数', () async {
      final session = await openSession(
        dir,
        entries: [
          entry(1, 'a', isKey: true),
          entry(2, 'b', isKey: true),
          entry(3, 'c', isKey: false),
        ],
        config: const VaultConfig.defaults().copyWith(hitCount: 2),
      );
      final keyA = session.entryById('entry-1')!;
      final adjustedK = session.setEntryKey(keyA, false);
      expect(adjustedK, 1);
      expect(session.keyCount, 1);
      expect(session.config.hitCount, 1);

      // 保存后份额仍为 1 把（剩余钥匙），未锁死。
      await session.save();
      final data = await VaultFile.read('${dir.path}/vault.igotyou');
      expect(data.shares.length, 1);
    });

    test('K 恒 ≥ 1：把配置 K 钳回下限，绝不写 0 阈值份额', () async {
      final session = await openSession(
        dir,
        entries: [entry(1, 'a', isKey: true), entry(2, 'b', isKey: false)],
        config: const VaultConfig.defaults().copyWith(hitCount: 1),
      );
      // 直接写入非法配置 K=0（模拟历史脏数据），触发一次 addEntry 强制约束。
      // addEntry 走 _enforceKConstraint，应把 K 拉回 1。
      session.config = const VaultConfig.defaults().copyWith(hitCount: 0);
      session.addEntry(name: 'c', secret: 'c', note: '', isKey: true);
      expect(session.config.hitCount, 1);
      expect(session.keyCount, 2);

      await session.save();
      final data = await VaultFile.read('${dir.path}/vault.igotyou');
      expect(data.header.config.hitCount, 1);
      expect(data.shares, isNotEmpty);
    });

    test('打开后仅改非钥匙条目（无重切分）保存 → 份额不丢，库仍可开', () async {
      final session = await openSession(
        dir,
        entries: [
          entry(1, 'a', isKey: true),
          entry(2, 'b', isKey: true),
          entry(3, 'c', isKey: false),
        ],
        config: const VaultConfig.defaults().copyWith(hitCount: 2),
      );
      // 只改非钥匙条目的备注：不触发重切分（_sharesDirty = false）。
      final nonKey = session.entries.singleWhere((e) => !e.isKey);
      session.updateEntry(nonKey, note: '改备注');

      await session.save();
      final data = await VaultFile.read('${dir.path}/vault.igotyou');
      expect(data.shares.length, session.keyCount); // == 2，绝不能为 0
      expect(data.shares, isNotEmpty);

      // 库文件仍可正常解析。
      final bodyCipher = await VaultFile.readBody(data);
      expect(bodyCipher, isNotEmpty);
    });

    test('打开后仅改钥匙条目的名称（secret 未变）保存 → 份额不丢', () async {
      final session = await openSession(
        dir,
        entries: [entry(1, 'a', isKey: true), entry(2, 'b', isKey: false)],
        config: const VaultConfig.defaults().copyWith(hitCount: 1),
      );
      final key = session.entries.singleWhere((e) => e.isKey);
      session.updateEntry(key, name: '改名'); // secret 未变 → 不重切分

      await session.save();
      final data = await VaultFile.read('${dir.path}/vault.igotyou');
      expect(data.shares.length, session.keyCount); // == 1
      expect(data.shares, isNotEmpty);
    });

    test('两把钥匙同一口令 = 一把钥匙：K 钳到 1，绝不锁死', () async {
      final session = await openSession(
        dir,
        entries: [
          entry(1, '相同口令', isKey: true),
          entry(2, '相同口令', isKey: true),
        ],
        config: const VaultConfig.defaults().copyWith(hitCount: 2),
      );
      expect(session.distinctKeyCount, 1);
      // 触发约束：K 必须从 2 钳到 1（否则 2 个不同口令永远凑不齐）。
      session.addEntry(name: 'c', secret: 'c', note: '', isKey: false);
      expect(session.config.hitCount, 1);

      await session.save();
      final data = await VaultFile.read('${dir.path}/vault.igotyou');
      expect(data.header.config.hitCount, 1);
      expect(data.shares.length, 2); // 份额仍按钥匙条目各一份，可命中一次
      expect(data.shares, isNotEmpty);
    });

    test('updateConfig 拒绝 K > 不同口令数（设置页防护）', () async {
      final session = await openSession(
        dir,
        entries: [
          entry(1, '相同口令', isKey: true),
          entry(2, '相同口令', isKey: true),
          entry(3, '另一口令', isKey: true),
        ],
        config: const VaultConfig.defaults().copyWith(hitCount: 1),
      );
      expect(session.distinctKeyCount, 2);
      final err = session.updateConfig(
        const VaultConfig.defaults().copyWith(hitCount: 3),
      );
      expect(err, isNotNull); // 3 > 2 种口令 → 拒绝
      expect(session.config.hitCount, 1);

      // K=2 恰好等于不同口令数 → 允许。
      final ok = session.updateConfig(
        const VaultConfig.defaults().copyWith(hitCount: 2),
      );
      expect(ok, isNull);
      expect(session.config.hitCount, 2);
    });
  });

  group('二次加密（DEVELOPMENT 8.5b）', () {
    test('开启后：正文落盘为空、载荷加密存储、密钥不落盘', () async {
      final session = await openSession(
        dir,
        entries: [entry(1, 'a', isKey: true)],
        config: const VaultConfig.defaults().copyWith(hitCount: 1),
      );
      final e = session.entries.first;
      await session.setDoubleLock(e, 'secret-key-1');
      await session.save();

      final data = await VaultFile.read('${dir.path}/vault.igotyou');
      final bodyJson = await VaultSessionTestHelper.decryptBody(data, session);
      final stored = bodyJson['entries'] as List<Object?>? ?? [];
      final storedEntry = stored.first as Map<String, Object?>;
      expect(storedEntry['secret'], '');
      expect(storedEntry['note'], '');
      expect(storedEntry['doubleLocked'], true);
      expect(storedEntry['doubleCipher'], isNotNull);
      expect(storedEntry['doubleSalt'], isNotNull);
      // 密钥本身绝不落盘。
      final jsonStr = jsonEncode(bodyJson);
      expect(jsonStr.contains('secret-key-1'), isFalse);
    });

    test('查看：正确密钥解密出原文，错误密钥抛错', () async {
      final session = await openSession(
        dir,
        entries: [entry(1, 'a', isKey: true)],
        config: const VaultConfig.defaults().copyWith(hitCount: 1),
      );
      final e = session.entries.first;
      await session.setDoubleLock(e, 'secret-key-1');

      final (secret, note) = await session.unlockDoubleLock(e, 'secret-key-1');
      expect(secret, 'a');
      expect(note, '');

      await expectLater(
        session.unlockDoubleLock(e, 'wrong'),
        throwsA(isA<StateError>()),
      );
    });

    test('开启后编辑内容：用缓存密钥重加密，落盘仍无明文', () async {
      final session = await openSession(
        dir,
        entries: [entry(1, 'a', isKey: true)],
        config: const VaultConfig.defaults().copyWith(hitCount: 1),
      );
      final e = session.entries.first;
      await session.setDoubleLock(e, 'secret-key-1');

      // 门禁验证一次（缓存密钥），随后编辑正文（secret/note 均传明文）。
      await session.unlockDoubleLock(e, 'secret-key-1');
      await session.updateDoubleEntry(
        session.entryById(e.id)!,
        secret: 'a',
        note: '新内容',
      );
      await session.save();

      final (secret, note) = await session.unlockDoubleLock(
        session.entryById(e.id)!,
        'secret-key-1',
      );
      expect(secret, 'a');
      expect(note, '新内容');

      final data = await VaultFile.read('${dir.path}/vault.igotyou');
      final bodyJson = await VaultSessionTestHelper.decryptBody(data, session);
      final stored = (bodyJson['entries'] as List<Object?>).first as Map<String, Object?>;
      expect(stored['secret'], '');
      expect(stored['note'], '');
      expect(jsonEncode(bodyJson).contains('新内容'), isFalse);
    });

    test('作为钥匙的二次加密条目：解锁用该密钥可命中（份额兼容）', () async {
      final session = await openSession(
        dir,
        entries: [entry(1, 'a', isKey: true)],
        config: const VaultConfig.defaults().copyWith(hitCount: 1),
      );
      final e = session.entries.first;
      await session.setDoubleLock(e, 'secret-key-1');
      await session.save();

      // 重新打开库（模拟解锁），用加密密钥派生 KEK 解份额。
      final data = await VaultFile.read('${dir.path}/vault.igotyou');
      final deriver = data.header.deriver;
      final kek = await deriver.derive('secret-key-1');
      final found = await Keychain.tryDecryptShare(data.shares.first, kek);
      expect(found, isNotNull, reason: '份额应可用加密密钥解密');
    });

    test('修改密钥：旧密钥失效、新密钥生效', () async {
      final session = await openSession(
        dir,
        entries: [entry(1, 'a', isKey: true)],
        config: const VaultConfig.defaults().copyWith(hitCount: 1),
      );
      final e = session.entries.first;
      await session.setDoubleLock(e, 'old-key');
      await session.changeDoubleKey(e, 'old-key', 'new-key');

      await expectLater(
        session.unlockDoubleLock(session.entryById(e.id)!, 'old-key'),
        throwsA(isA<StateError>()),
      );
      final (secret, _) = await session.unlockDoubleLock(
        session.entryById(e.id)!,
        'new-key',
      );
      expect(secret, 'a');
    });

    test('关闭二次加密：正文回填明文、可正常查看', () async {
      final session = await openSession(
        dir,
        entries: [entry(1, 'a', isKey: true)],
        config: const VaultConfig.defaults().copyWith(hitCount: 1),
      );
      final e = session.entries.first;
      await session.setDoubleLock(e, 'secret-key-1');
      await session.clearDoubleLock(e, 'secret-key-1');

      final cleared = session.entryById(e.id)!;
      expect(cleared.doubleLocked, isFalse);
      expect(cleared.secret, 'a');
    });

    test('锁定清空密钥缓存；二次加密钥匙无缓存时重切份额抛错', () async {
      final session = await openSession(
        dir,
        entries: [entry(1, 'a', isKey: true), entry(2, 'b', isKey: false)],
        config: const VaultConfig.defaults().copyWith(hitCount: 1),
      );
      final e = session.entries.first;
      await session.setDoubleLock(e, 'secret-key-1');
      await session.save();

      // 重新打开库（模拟锁定后再次解锁）：密钥缓存为空。
      final data = await VaultFile.read('${dir.path}/vault.igotyou');
      final mk = Uint8List.fromList(session.mk);
      final reopened = await VaultSession.open(
        path: '${dir.path}/vault.igotyou',
        fileData: data,
        mk: mk,
      );
      // 未输入密钥前，触发重切份额（addEntry 默认 isKey）应抛缺密钥异常。
      reopened.addEntry(name: 'c', secret: 'c', note: '', isKey: true);
      await expectLater(
        reopened.save(),
        throwsA(isA<VaultKeyMissingException>()),
      );
      // 输入正确密钥后可正常保存。
      await reopened.unlockDoubleLock(reopened.entries.first, 'secret-key-1');
      await reopened.save();
      expect(reopened.entries.first.doubleLocked, isTrue);
    });

    test('关闭二次加密预检：其他二次加密钥匙密钥缺失时先报错，状态不变', () async {
      final session = await openSession(
        dir,
        entries: [entry(1, 'a', isKey: true), entry(2, 'b', isKey: true)],
        config: const VaultConfig.defaults().copyWith(hitCount: 1),
      );
      await session.setDoubleLock(session.entries[0], 'secret-key-1');
      await session.setDoubleLock(session.entries[1], 'secret-key-2');
      await session.save();

      // 重新打开库（模拟锁定后再次解锁）：密钥缓存为空。
      final data = await VaultFile.read('${dir.path}/vault.igotyou');
      final mk = Uint8List.fromList(session.mk);
      final reopened = await VaultSession.open(
        path: '${dir.path}/vault.igotyou',
        fileData: data,
        mk: mk,
      );
      // 只查看条目 2（缓存其密钥），条目 1 未查看 → 关闭条目 2 二次加密
      // 应预检报缺条目 1 密钥，且状态不被破坏（不会出现"已关闭但保存失败"）。
      await reopened.unlockDoubleLock(reopened.entries[1], 'secret-key-2');
      await expectLater(
        reopened.clearDoubleLock(reopened.entries[1], 'secret-key-2'),
        throwsA(isA<VaultKeyMissingException>()),
      );
      expect(reopened.entries[1].doubleLocked, isTrue);
      expect(reopened.entries[1].secret, '');
    });
  });
}
