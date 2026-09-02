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
import 'package:igotyou/core/unlock/unlock_engine.dart';
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
/// [shareThreshold] 可指定与配置 K 不同的份额拆分阈值（模拟 17.17 存量库形态）。
Future<VaultSession> openSession(
  Directory dir, {
  required List<Entry> entries,
  required VaultConfig config,
  int? shareThreshold,
}) async {
  final mk = Keychain.generateMk();
  final deriver = fastDeriver();
  final keyEntries = entries.where((e) => e.isKey).toList();
  final shares = await Keychain.splitSecret(
    mk: mk,
    keyEntries: keyEntries,
    threshold: shareThreshold ?? config.hitCount,
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
  await VaultFile.write(path, header: header, shares: shares, body: body);
  return VaultSession.open(
    path: path,
    fileData: await VaultFile.read(path),
    mk: mk,
  );
}

/// 测试辅助：绕过会话访问 BODY 明文（供二次加密测试读取落盘状态）。
class VaultSessionTestHelper {
  /// 解密 BODY 返回库 JSON。
  static Future<Map<String, Object?>> decryptBody(
    VaultFileData data,
    VaultSession session,
  ) async {
    final cipher = await VaultFile.readBody(data);
    final jsonStr = await AesGcmCipher().decrypt(
      cipher,
      SecretKeyData(session.mk),
    );
    return jsonDecode(jsonStr) as Map<String, Object?>;
  }
}

/// 用 MK 直接解密 BODY 返回库 JSON（不依赖会话对象）。
Future<Map<String, Object?>> decryptBodyWithMk(
  VaultFileData data,
  Uint8List mk,
) async {
  final cipher = await VaultFile.readBody(data);
  final jsonStr = await AesGcmCipher().decrypt(cipher, SecretKeyData(mk));
  return jsonDecode(jsonStr) as Map<String, Object?>;
}

/// 模拟存量库：从已保存的库中剥掉维护层结构块（旧版本 BODY 无封套）。
Future<void> stripStructure(
  String path,
  VaultFileData data,
  Uint8List mk,
) async {
  final body = await decryptBodyWithMk(data, mk);
  body.remove('structure');
  final bodyBytes = await AesGcmCipher().encrypt(
    jsonEncode(body),
    SecretKeyData(mk),
  );
  await VaultFile.write(
    path,
    header: VaultHeader(
      version: vaultFileVersion,
      argonParams: data.header.argonParams,
      salt: data.header.salt,
      config: data.header.config,
    ),
    shares: data.shares,
    body: bodyBytes,
  );
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
      expect(session.entries.map((e) => e.toJson()).toList(), beforeEntries);

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
        entries: [entry(1, '相同口令', isKey: true), entry(2, '相同口令', isKey: true)],
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

    test('两段式门禁：提交只暂存，确认后才进入正式缓存', () async {
      final session = await openSession(
        dir,
        entries: [entry(1, 'a', isKey: true)],
        config: const VaultConfig.defaults().copyWith(hitCount: 1),
      );
      final e = session.entries.first;
      await session.setDoubleLock(e, 'secret-key-1');
      await session.save();

      final ok = await session.submitDoubleLock(e, 'secret-key-1');
      expect(ok, isTrue);

      // 提交后尚未确认：编辑/重切仍不应认作已缓存密钥。
      await expectLater(
        session.updateDoubleEntry(
          session.entryById(e.id)!,
          note: 'after-submit',
        ),
        throwsA(isA<VaultKeyMissingException>()),
      );

      final unlocked = await session.confirmDoubleLock(e.id);
      expect(unlocked, isNotNull);
      expect(unlocked!.$1, 'a');
      expect(unlocked.$2, '');

      // 进入正式缓存后才可编辑。
      await session.updateDoubleEntry(
        session.entryById(e.id)!,
        note: 'after-confirm',
      );
      expect(await session.confirmDoubleLock(e.id), isNull);
      final reopened = session.entryById(e.id)!;
      expect(reopened.doubleLocked, isTrue);
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
      final stored =
          (bodyJson['entries'] as List<Object?>).first as Map<String, Object?>;
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

    test('锁定清空密钥缓存；二次加密钥匙无缓存时重切份额仍成功（维护层封套恢复）', () async {
      final session = await openSession(
        dir,
        entries: [entry(1, 'a', isKey: true), entry(2, 'b', isKey: false)],
        config: const VaultConfig.defaults().copyWith(hitCount: 1),
      );
      final e = session.entries.first;
      await session.setDoubleLock(e, 'secret-key-1');
      await session.save();

      // 重新打开库（模拟锁定后再次解锁）：实测密钥缓存清空，
      // 但口令封套（结构密钥解开）可恢复 → 重切份额无需用户再输入。
      final data = await VaultFile.read('${dir.path}/vault.igotyou');
      final mk = Uint8List.fromList(session.mk);
      final reopened = await VaultSession.open(
        path: '${dir.path}/vault.igotyou',
        fileData: data,
        mk: mk,
      );
      reopened.addEntry(name: 'c', secret: 'c', note: '', isKey: true);
      await reopened.save(); // 不再抛 VaultKeyMissingException
      expect(reopened.entries.first.doubleLocked, isTrue);

      // 条目层不受影响：查看内容仍必须输入该条目的密码（封套不用于自动解密）。
      await expectLater(
        reopened.unlockDoubleLock(reopened.entries.first, 'wrong'),
        throwsA(isA<StateError>()),
      );
      final (secret, _) = await reopened.unlockDoubleLock(
        reopened.entries.first,
        'secret-key-1',
      );
      expect(secret, 'a');
    });

    test('seedDoubleKeys：存量库解锁命中口令自动缓存；新库靠封套计数即可改设置', () async {
      final session = await openSession(
        dir,
        entries: [entry(1, 'a', isKey: true), entry(2, 'b', isKey: true)],
        config: const VaultConfig.defaults().copyWith(hitCount: 1),
      );
      // 两把钥匙开启二次加密（独立口令 pw-a / pw-b），落盘。
      await session.setDoubleLock(session.entries[0], 'pw-a');
      await session.setDoubleLock(session.entries[1], 'pw-b');
      await session.save();

      // 重新打开（模拟锁定后再解锁）：实测缓存已清空，但口令封套可恢复
      // → distinctKeyCount 精确计 2 种口令（不再依赖"本会话是否看过"）。
      final data = await VaultFile.read('${dir.path}/vault.igotyou');
      final reopened = await VaultSession.open(
        path: '${dir.path}/vault.igotyou',
        fileData: data,
        mk: Uint8List.fromList(session.mk),
      );
      expect(reopened.distinctKeyCount, 2);

      // 无需 seed：直接设置 K=2 保存即成功（无缺口令弹窗）——份额按 K=2 全量重切。
      expect(
        reopened.updateConfig(
          const VaultConfig.defaults().copyWith(hitCount: 2),
        ),
        isNull,
      );
      await reopened.save();

      // 双口令按 K=2 正常解锁，MK 与原始一致。
      final data2 = await VaultFile.read('${dir.path}/vault.igotyou');
      final engine = UnlockEngine(
        data: data2,
        statePath: '${dir.path}/attempt_state.json',
      );
      await engine.loadState();
      final r1 = await engine.submit('pw-a');
      expect(r1.success, isFalse);
      final r2 = await engine.submit('pw-b');
      expect(r2.success, isTrue);
      expect(engine.takeMk(), session.mk);
    });

    test('关闭二次加密：其他二次加密钥匙未查看也能完成（维护层不索密）', () async {
      final session = await openSession(
        dir,
        entries: [entry(1, 'a', isKey: true), entry(2, 'b', isKey: true)],
        config: const VaultConfig.defaults().copyWith(hitCount: 1),
      );
      await session.setDoubleLock(session.entries[0], 'secret-key-1');
      await session.setDoubleLock(session.entries[1], 'secret-key-2');
      await session.save();

      // 重新打开库（模拟锁定后再次解锁）：条目 1 未查看、口令未实测输入。
      final data = await VaultFile.read('${dir.path}/vault.igotyou');
      final mk = Uint8List.fromList(session.mk);
      final reopened = await VaultSession.open(
        path: '${dir.path}/vault.igotyou',
        fileData: data,
        mk: mk,
      );
      // 直接关闭条目 2 的二次加密：条目 1 的口令由维护层封套恢复，
      // 重切份额不再索要 → 不再抛 VaultKeyMissingException，状态正常。
      await reopened.clearDoubleLock(reopened.entries[1], 'secret-key-2');
      await reopened.save();

      final cleared = reopened.entryById('entry-2')!;
      expect(cleared.doubleLocked, isFalse);
      expect(cleared.secret, 'b');

      // 条目层不变：条目 1 仍是二次加密，查看仍需输入其口令。
      await expectLater(
        reopened.unlockDoubleLock(reopened.entries[0], 'wrong'),
        throwsA(isA<StateError>()),
      );
      final (s1, _) = await reopened.unlockDoubleLock(
        reopened.entries[0],
        'secret-key-1',
      );
      expect(s1, 'a');
    });
  });

  group('份额重切与 K 变化（DEVELOPMENT 17.15）', () {
    test('K 下调 + 同一次保存删除钥匙 → 份额全量重切，单口令仍可重构正确 MK', () async {
      final session = await openSession(
        dir,
        entries: [
          entry(1, 'a', isKey: true),
          entry(2, 'b', isKey: true),
          entry(3, 'c', isKey: true),
        ],
        config: const VaultConfig.defaults().copyWith(hitCount: 2),
      );
      // 同一会话内 K 2→1 再删一把钥匙，两次变更同一次落盘。
      expect(
        session.updateConfig(
          const VaultConfig.defaults().copyWith(hitCount: 1),
        ),
        isNull,
      );
      session.deleteEntry('entry-3');
      await session.save();

      // 份额数 = 剩余钥匙数。
      final data = await VaultFile.read('${dir.path}/vault.igotyou');
      expect(data.shares.length, 2);

      // K=1：任意一把剩余钥匙单口令即应重构出原始 MK（不是错误的中间值）。
      final mk = session.mk;
      final engine = UnlockEngine(
        data: data,
        statePath: '${dir.path}/attempt_state.json',
      );
      await engine.loadState();
      final r = await engine.submit('a');
      expect(r.success, isTrue);
      expect(engine.takeMk(), mk);
    });

    test('删除钥匙自动下调 K → 同一次落盘即全量重切，剩余钥匙可正常解锁', () async {
      final session = await openSession(
        dir,
        entries: [
          entry(1, 'a', isKey: true),
          entry(2, 'b', isKey: true),
          entry(3, 'c', isKey: true),
        ],
        config: const VaultConfig.defaults().copyWith(hitCount: 3),
      );
      // 连删两把钥匙：_enforceKConstraint 自动把 K 钳到 1，同一会话同一次落盘。
      session.deleteEntry('entry-3');
      session.deleteEntry('entry-2');
      await session.save();
      expect(session.config.hitCount, 1);

      final data = await VaultFile.read('${dir.path}/vault.igotyou');
      expect(data.shares.length, 1);

      final mk = session.mk;
      final engine = UnlockEngine(
        data: data,
        statePath: '${dir.path}/attempt_state.json',
      );
      await engine.loadState();
      final r = await engine.submit('a');
      expect(r.success, isTrue);
      expect(engine.takeMk(), mk);
    });

    test('K 下调 + 同一次保存新增钥匙 → 份额全量重切，单口令仍可重构正确 MK', () async {
      final session = await openSession(
        dir,
        entries: [entry(1, 'a', isKey: true), entry(2, 'b', isKey: true)],
        config: const VaultConfig.defaults().copyWith(hitCount: 2),
      );
      expect(
        session.updateConfig(
          const VaultConfig.defaults().copyWith(hitCount: 1),
        ),
        isNull,
      );
      session.addEntry(name: '条目 3', secret: 'c', note: '', isKey: true);
      await session.save();

      final data = await VaultFile.read('${dir.path}/vault.igotyou');
      expect(data.shares.length, 3);

      final mk = session.mk;
      final engine = UnlockEngine(
        data: data,
        statePath: '${dir.path}/attempt_state.json',
      );
      await engine.loadState();
      final r = await engine.submit('a');
      expect(r.success, isTrue);
      expect(engine.takeMk(), mk);
    });

    test('开启二次加密 + 同一次保存删除其他钥匙 → 全量重切，新口令可命中', () async {
      final session = await openSession(
        dir,
        entries: [
          entry(1, 'a', isKey: true),
          entry(2, 'b', isKey: true),
          entry(3, 'c', isKey: true),
        ],
        config: const VaultConfig.defaults().copyWith(hitCount: 1),
      );
      // 同一会话、同一落盘内：条目 1 开启二次加密，同时删除钥匙 C。
      await session.setDoubleLock(session.entries.first, 'secret-key-1');
      session.deleteEntry('entry-3');
      await session.save();

      final data = await VaultFile.read('${dir.path}/vault.igotyou');
      expect(data.shares.length, 2);

      // 重新打开后密钥缓存为空：二次加密的新口令应能命中并重构正确 MK。
      final mk = session.mk;
      final engine = UnlockEngine(
        data: data,
        statePath: '${dir.path}/attempt_state.json',
      );
      await engine.loadState();
      final r = await engine.submit('secret-key-1');
      expect(r.success, isTrue);
      expect(engine.takeMk(), mk);
    });

    test('K 不变仅删除钥匙 → 走增量丢弃，打开仍正确且不索要其他钥匙明文', () async {
      final session = await openSession(
        dir,
        entries: [
          entry(1, 'a', isKey: true),
          entry(2, 'b', isKey: true),
          entry(3, 'c', isKey: true),
        ],
        config: const VaultConfig.defaults().copyWith(hitCount: 1),
      );
      session.deleteEntry('entry-3');
      await session.save();

      final data = await VaultFile.read('${dir.path}/vault.igotyou');
      expect(data.shares.length, 2);

      final mk = session.mk;
      final engine = UnlockEngine(
        data: data,
        statePath: '${dir.path}/attempt_state.json',
      );
      await engine.loadState();
      final r = await engine.submit('a');
      expect(r.success, isTrue);
      expect(engine.takeMk(), mk);
    });

    test('K 上调 + 同一次保存新增钥匙 → 全量重切，双口令重构正确 MK', () async {
      final session = await openSession(
        dir,
        entries: [entry(1, 'a', isKey: true), entry(2, 'b', isKey: true)],
        config: const VaultConfig.defaults().copyWith(hitCount: 1),
      );
      expect(
        session.updateConfig(
          const VaultConfig.defaults().copyWith(hitCount: 2),
        ),
        isNull,
      );
      session.addEntry(name: '条目 3', secret: 'c', note: '', isKey: true);
      await session.save();

      final data = await VaultFile.read('${dir.path}/vault.igotyou');
      expect(data.shares.length, 3);

      final mk = session.mk;
      final engine = UnlockEngine(
        data: data,
        statePath: '${dir.path}/attempt_state.json',
      );
      await engine.loadState();
      final r1 = await engine.submit('a');
      expect(r1.success, isFalse);
      final r2 = await engine.submit('c');
      expect(r2.success, isTrue);
      expect(engine.takeMk(), mk);
    });

    test('存量库形态（K=1 配置 + K=2 份额）：修复路径打开，标记重切后保存即修复', () async {
      // 份额按 K=2 拆分（degree-1 多项式），配置 K=1——17.17 描述的存量库。
      final entries = [entry(1, 'pw-a'), entry(2, 'pw-b')];
      final cfg = const VaultConfig.defaults().copyWith(hitCount: 1);
      final session = await openSession(
        dir,
        entries: entries,
        config: cfg,
        shareThreshold: 2,
      );
      final mk = session.mk;
      final data = await VaultFile.read('${dir.path}/vault.igotyou');

      // 解锁引擎：1 次命中 → needsRepair，2 次命中 → 修复成功（> K 打开）。
      final engine = UnlockEngine(
        data: data,
        statePath: '${dir.path}/attempt_state.json',
      );
      await engine.loadState();
      final r1 = await engine.submit('pw-a');
      expect(r1.needsRepair, isTrue);
      expect(r1.success, isFalse);
      final r2 = await engine.submit('pw-b');
      expect(r2.success, isTrue);
      expect(engine.repairedShares, isTrue);
      expect(engine.takeMk(), mk);

      // 会话标记重切：仅保存（无任何改动）即全量重切为 K=1 份额。
      session.markSharesForResplit();
      await session.save();
      final data2 = await VaultFile.read('${dir.path}/vault.igotyou');
      expect(data2.header.config.hitCount, 1);

      // 修复后任意单一口令即可打开（degree-0 份额）。
      final engine2 = UnlockEngine(
        data: data2,
        statePath: '${dir.path}/attempt_state2.json',
      );
      await engine2.loadState();
      final r = await engine2.submit('pw-a');
      expect(r.success, isTrue);
      expect(r.needsRepair, isFalse);
      expect(engine2.takeMk(), mk);
    });
  });

  group('方案三：维护层与条目层解耦（DEVELOPMENT 17.20）', () {
    /// 打开库文件返回"未输入任何二次加密口令"的全新会话（模拟锁定后再解锁）。
    Future<VaultSession> reopenFresh(
      VaultSession session, {
      required String path,
    }) async {
      final data = await VaultFile.read(path);
      return VaultSession.open(
        path: path,
        fileData: data,
        mk: Uint8List.fromList(session.mk),
      );
    }

    test('改 K 下调：二次加密钥匙未输入口令也能重切，单口令解锁真正生效', () async {
      final session = await openSession(
        dir,
        entries: [entry(1, 'a'), entry(2, 'b')],
        config: const VaultConfig.defaults().copyWith(hitCount: 2),
      );
      await session.setDoubleLock(session.entries[0], 'pw-a');
      await session.setDoubleLock(session.entries[1], 'pw-b');
      await session.save();
      final path = '${dir.path}/vault.igotyou';

      // 重新打开（不输入任何口令）→ 改 K=1 → 保存：不得抛缺钥异常。
      final reopened = await reopenFresh(session, path: path);
      expect(
        reopened.updateConfig(
          const VaultConfig.defaults().copyWith(hitCount: 1),
        ),
        isNull,
      );
      await reopened.save();

      // K=1 真正生效：任意单一口令即可打开，份额按 K=1 重切。
      final data = await VaultFile.read(path);
      final engine = UnlockEngine(
        data: data,
        statePath: '${dir.path}/attempt_state.json',
      );
      await engine.loadState();
      final r = await engine.submit('pw-a');
      expect(r.success, isTrue);
      expect(r.needsRepair, isFalse, reason: '份额应已按 K=1 重切，不再需要第二个口令');
      expect(engine.takeMk(), session.mk);
    });

    test('改 K 上调：封套计数使 K 校验通过，双口令解锁生效且无需 seed', () async {
      final session = await openSession(
        dir,
        entries: [entry(1, 'a'), entry(2, 'b')],
        config: const VaultConfig.defaults().copyWith(hitCount: 1),
      );
      await session.setDoubleLock(session.entries[0], 'pw-a');
      await session.setDoubleLock(session.entries[1], 'pw-b');
      await session.save();
      final path = '${dir.path}/vault.igotyou';

      final reopened = await reopenFresh(session, path: path);
      // 封套恢复 → distinctKeyCount = 2，改 K=2 不再因"没看过条目"被拒。
      expect(reopened.distinctKeyCount, 2);
      expect(
        reopened.updateConfig(
          const VaultConfig.defaults().copyWith(hitCount: 2),
        ),
        isNull,
      );
      await reopened.save();

      // 双口令按 K=2 解锁，MK 一致。
      final data = await VaultFile.read(path);
      final engine = UnlockEngine(
        data: data,
        statePath: '${dir.path}/attempt_state.json',
      );
      await engine.loadState();
      expect((await engine.submit('pw-a')).success, isFalse);
      final r2 = await engine.submit('pw-b');
      expect(r2.success, isTrue);
      expect(engine.takeMk(), session.mk);
    });

    test('改 M：二次加密钥匙未输入口令也能保存', () async {
      final session = await openSession(
        dir,
        entries: [entry(1, 'a'), entry(2, 'b')],
        config: const VaultConfig.defaults().copyWith(hitCount: 1),
      );
      await session.setDoubleLock(session.entries[0], 'pw-a');
      await session.setDoubleLock(session.entries[1], 'pw-b');
      await session.save();
      final path = '${dir.path}/vault.igotyou';

      final reopened = await reopenFresh(session, path: path);
      expect(
        reopened.updateConfig(
          const VaultConfig.defaults().copyWith(roundChances: 7),
        ),
        isNull,
      );
      await reopened.save(); // 不抛 VaultKeyMissingException
      final data = await VaultFile.read(path);
      expect(data.header.config.roundChances, 7);
    });

    test('口令封套不落明文：BODY 内无口令字符串，封套随结构块加密存储', () async {
      final session = await openSession(
        dir,
        entries: [entry(1, 'a'), entry(2, 'b')],
        config: const VaultConfig.defaults().copyWith(hitCount: 1),
      );
      await session.setDoubleLock(session.entries[0], 'pw-甲#秘密');
      await session.setDoubleLock(session.entries[1], 'pw-b');
      await session.save();

      final data = await VaultFile.read('${dir.path}/vault.igotyou');
      final bodyJson = await decryptBodyWithMk(data, session.mk);
      final structure = bodyJson['structure'] as Map<String, Object?>;
      final envelopes = (structure['keyEnvelopes']! as Map)
          .cast<String, Object?>();
      expect(envelopes.length, 2);
      final textual = jsonEncode(bodyJson);
      expect(textual.contains('pw-甲#秘密'), isFalse);
      expect(textual.contains('pw-b'), isFalse);
    });

    test('修改二次加密密码：封套随新口令更新，旧口令不再命中份额', () async {
      final session = await openSession(
        dir,
        entries: [entry(1, 'a')],
        config: const VaultConfig.defaults().copyWith(hitCount: 1),
      );
      final e = session.entries.first;
      await session.setDoubleLock(e, 'old-pw');
      await session.save();
      final path = '${dir.path}/vault.igotyou';

      final reopened = await reopenFresh(session, path: path);
      await reopened.changeDoubleKey(
        reopened.entries.first,
        'old-pw',
        'new-pw',
      );
      await reopened.save();

      // 重新打开（不输入任何口令）→ 份额已按新口令重加密，旧口令不再命中。
      final reopened2 = await reopenFresh(session, path: path);
      final data = await VaultFile.read(path);
      final engine = UnlockEngine(
        data: data,
        statePath: '${dir.path}/attempt_state.json',
      );
      await engine.loadState();
      expect((await engine.submit('old-pw')).success, isFalse);
      final r2 = await engine.submit('new-pw');
      expect(r2.success, isTrue);
      expect(engine.takeMk(), session.mk);
      expect(reopened2.entryById('entry-1')!.doubleLocked, isTrue);
    });

    test('删除二次加密钥匙：不输入其口令即可保存，封套随删除清理', () async {
      final session = await openSession(
        dir,
        entries: [entry(1, 'a'), entry(2, 'b')],
        config: const VaultConfig.defaults().copyWith(hitCount: 1),
      );
      await session.setDoubleLock(session.entries[0], 'pw-a');
      await session.setDoubleLock(session.entries[1], 'pw-b');
      await session.save();
      final path = '${dir.path}/vault.igotyou';

      final reopened = await reopenFresh(session, path: path);
      reopened.deleteEntry('entry-2');
      await reopened.save(); // 不抛缺钥异常

      final data = await VaultFile.read(path);
      expect(data.shares.length, 1);
      final bodyJson = await decryptBodyWithMk(data, session.mk);
      final structure = bodyJson['structure'] as Map<String, Object?>;
      final envelopes = (structure['keyEnvelopes']! as Map)
          .cast<String, Object?>();
      expect(envelopes.keys.toList(), ['entry-1']);

      // 剩余钥匙仍可正常解锁。
      final engine = UnlockEngine(
        data: data,
        statePath: '${dir.path}/attempt_state.json',
      );
      await engine.loadState();
      final r = await engine.submit('pw-a');
      expect(r.success, isTrue);
      expect(engine.takeMk(), session.mk);
    });

    test('切换钥匙开关：二次加密钥匙未输入口令也可保存', () async {
      final session = await openSession(
        dir,
        entries: [entry(1, 'a'), entry(2, 'b')],
        config: const VaultConfig.defaults().copyWith(hitCount: 1),
      );
      await session.setDoubleLock(session.entries[0], 'pw-a');
      await session.setDoubleLock(session.entries[1], 'pw-b');
      await session.save();
      final path = '${dir.path}/vault.igotyou';

      final reopened = await reopenFresh(session, path: path);
      reopened.setEntryKey(reopened.entryById('entry-2')!, false);
      await reopened.save(); // 不抛缺钥异常

      final data = await VaultFile.read(path);
      expect(data.shares.length, 1);
      final engine = UnlockEngine(
        data: data,
        statePath: '${dir.path}/attempt_state.json',
      );
      await engine.loadState();
      final r = await engine.submit('pw-a');
      expect(r.success, isTrue);
      expect(engine.takeMk(), session.mk);
    });

    test('非钥匙条目开启二次加密时输一次密码，日后切钥匙不再索要', () async {
      final session = await openSession(
        dir,
        entries: [entry(1, 'a')],
        config: const VaultConfig.defaults().copyWith(hitCount: 1),
      );
      final created = session.addEntry(
        name: '新增',
        secret: 'n-secret',
        isKey: false,
      );
      await session.setDoubleLock(created, 'n-pw'); // 仅此一次输入
      await session.save();
      final path = '${dir.path}/vault.igotyou';

      // 重新打开（不输入任何口令）→ 把新条目切为钥匙 → 保存成功。
      final reopened = await reopenFresh(session, path: path);
      reopened.setEntryKey(reopened.entryById(created.id)!, true);
      await reopened.save(); // 不抛缺钥异常

      final data = await VaultFile.read(path);
      expect(data.shares.length, 2);
      final engine = UnlockEngine(
        data: data,
        statePath: '${dir.path}/attempt_state.json',
      );
      await engine.loadState();
      final r = await engine.submit('n-pw');
      expect(r.success, isTrue);
      expect(engine.takeMk(), session.mk);
    });

    test('存量库自愈：无封套时首次结构变更索要一次口令，补写封套后永久免费', () async {
      final session = await openSession(
        dir,
        entries: [entry(1, 'a'), entry(2, 'b')],
        config: const VaultConfig.defaults().copyWith(hitCount: 1),
      );
      await session.setDoubleLock(session.entries[0], 'pw-a');
      await session.setDoubleLock(session.entries[1], 'pw-b');
      await session.save();
      final path = '${dir.path}/vault.igotyou';

      // 剥掉结构块 → 模拟旧版本落盘的存量库（无封套）。
      final data0 = await VaultFile.read(path);
      await stripStructure(path, data0, session.mk);
      final data = await VaultFile.read(path);
      final legacy = await VaultSession.open(
        path: path,
        fileData: data,
        mk: Uint8List.fromList(session.mk),
      );
      expect(legacy.distinctKeyCount, 1); // 无封套、无实测缓存 → 保守计 1

      // 改结构保存：本会话先缓存 pw-a（解锁已输入），pw-b 仍缺 → 索要一次。
      legacy.addEntry(name: 'c', secret: 'c', note: '', isKey: true);
      await legacy.seedDoubleKeys({'entry-1': 'pw-a'});
      await expectLater(
        legacy.save(),
        throwsA(isA<VaultKeyMissingException>()),
      );
      // 输入 pw-b 一次 → 保存成功 → 两张封套都落盘（自愈）。
      await legacy.seedDoubleKeys({'entry-2': 'pw-b'});
      await legacy.save();
      expect(legacy.entries.any((e) => e.name == 'c'), isTrue);

      // 再次重新打开：封套恢复，改结构永久不再索要口令。
      final healed = await reopenFresh(session, path: path);
      expect(healed.distinctKeyCount, 2);
      healed.addEntry(name: 'd', secret: 'd', note: '', isKey: true);
      await healed.save(); // 不抛缺钥异常
    });
  });
}
