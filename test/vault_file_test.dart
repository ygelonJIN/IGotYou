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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('vault_file_test');
  });
  tearDown(() async {
    await dir.delete(recursive: true);
  });

  group('VaultFile 读写（DEVELOPMENT 7）', () {
    test('写入 → 读回：header/shares/body 完整往返', () async {
      final mk = Keychain.generateMk();
      final deriver = fastDeriver();
      final entries = [entry(1, 'a'), entry(2, 'b'), entry(3, 'c')];
      final cfg = const VaultConfig.defaults().copyWith(hitCount: 2);
      final shares = await Keychain.splitSecret(
        mk: mk,
        keyEntries: entries,
        threshold: 2,
        deriver: deriver,
      );
      final header = VaultHeader(
        version: vaultFileVersion,
        argonParams: deriver.params,
        salt: Uint8List.fromList(deriver.salt),
        config: cfg,
      );
      final bodyJson = jsonEncode({
        'entries': entries.map((e) => e.toJson()).toList(),
        'config': cfg.toJson(),
      });
      final body = await AesGcmCipher().encrypt(bodyJson, SecretKeyData(mk));

      final path = '${dir.path}/vault.igotyou';
      await VaultFile.write(
        path,
        header: header,
        shares: shares,
        body: body,
      );

      final data = await VaultFile.read(path);
      expect(data.header.version, vaultFileVersion);
      expect(data.header.config.hitCount, 2);
      expect(data.shares.length, 3);
      expect(data.bodyOffset, greaterThan(0));

      // BODY 密文可解密还原。
      final bodyCipher = await VaultFile.readBody(data);
      final json = await AesGcmCipher().decrypt(bodyCipher, SecretKeyData(mk));
      final map = jsonDecode(json) as Map<String, Object?>;
      expect((map['entries'] as List).length, 3);
      expect((map['config'] as Map)['hitCount'], 2);
    });

    test('两个库文件可并存（不同路径）', () async {
      final mk = Keychain.generateMk();
      final deriver = fastDeriver();
      final cfg = const VaultConfig.defaults();
      final header = VaultHeader(
        version: vaultFileVersion,
        argonParams: deriver.params,
        salt: Uint8List.fromList(deriver.salt),
        config: cfg,
      );
      final body = await AesGcmCipher().encrypt(
        jsonEncode({'entries': <Object>[], 'config': cfg.toJson()}),
        SecretKeyData(mk),
      );
      await VaultFile.write(
        '${dir.path}/a.igotyou',
        header: header,
        shares: const [],
        body: body,
      );
      await VaultFile.write(
        '${dir.path}/b.igotyou',
        header: header,
        shares: const [],
        body: body,
      );
      final a = await VaultFile.read('${dir.path}/a.igotyou');
      final b = await VaultFile.read('${dir.path}/b.igotyou');
      expect(a.path, '${dir.path}/a.igotyou');
      expect(b.path, '${dir.path}/b.igotyou');
    });

    test('magic 错误 → 文件损坏', () async {
      final path = '${dir.path}/bad.igotyou';
      await File(path).writeAsBytes(ascii.encode('NOTIGOTYOU1\n'));
      await expectLater(VaultFile.read(path), throwsA(isA<VaultFileException>()));
    });

    test('magic 正确但 JSON 损坏 → 文件损坏', () async {
      final path = '${dir.path}/bad.igotyou';
      await File(path).writeAsBytes(ascii.encode('IGOTYOU1\n{not-json'));
      await expectLater(VaultFile.read(path), throwsA(isA<VaultFileException>()));
    });

    test('不存在的文件 → 文件不存在', () async {
      await expectLater(
        VaultFile.read('${dir.path}/missing.igotyou'),
        throwsA(isA<VaultFileException>()),
      );
    });

    test('版本过高 → 备份版本过高，请升级应用', () async {
      final path = '${dir.path}/future.igotyou';
      await File(path).writeAsBytes(ascii.encode(
        'IGOTYOU1\n{"v": 999, "argon": {}, "salt": "", "config": {}}\n',
      ));
      await expectLater(
        VaultFile.read(path),
        throwsA(predicate((e) => '$e'.contains('备份版本过高'))),
      );
    });
  });

  group('VaultSession（DEVELOPMENT 5.7/8.1）', () {
    test('create → 落盘 → open（用 MK）→ 条目与配置一致', () async {
      final path = '${dir.path}/vault.igotyou';
      final session = await VaultSession.create(
        path: path,
        name: '我的银行',
        secret: 'p@ssw0rd',
        note: '工资卡',
      );
      expect(session.entries.length, 1);
      expect(session.entries.first.name, '我的银行');
      expect(session.entries.first.isKey, isTrue);
      expect(session.config.hitCount, 1, reason: '首个条目即钥匙，K 自动降为 1');

      await session.save();
      final fileData = await VaultFile.read(path);
      // 用同 MK 打开。
      final reopened = await VaultSession.open(
        path: path,
        fileData: fileData,
        mk: session.mk,
      );
      expect(reopened.entries.length, 1);
      expect(reopened.entries.first.secret, 'p@ssw0rd');
      expect(reopened.config.hitCount, 1);
    });

    test('BODY 与 HEADER 镜像 config 不一致 → 文件损坏', () async {
      final path = '${dir.path}/vault.igotyou';
      final session = await VaultSession.create(path: path, name: 'x', secret: 'y');
      // 篡改 HEADER 中的 config 镜像（不改 BODY）。
      final bytes = await File(path).readAsBytes();
      final headerJson = _readHeader(bytes);
      headerJson['config'] = const VaultConfig.defaults().toJson(); // 与 BODY(hitCount=1) 冲突
      final newHeaderLine = <int>[
        ...ascii.encode(jsonEncode(headerJson)),
        0x0A,
      ];
      final newBytes = <int>[
        ...bytes.sublist(0, _magicLineLen(bytes)),
        ...newHeaderLine,
        ...bytes.sublist(_magicLineLen(bytes) + _headerLineLen(bytes)),
      ];
      await File(path).writeAsBytes(newBytes, flush: true);

      final fileData = await VaultFile.read(path);
      await expectLater(
        VaultSession.open(path: path, fileData: fileData, mk: session.mk),
        throwsA(isA<VaultFileException>()),
      );
    });

    test('锁定清零内存（entries 清空）', () async {
      final path = '${dir.path}/vault.igotyou';
      final session = await VaultSession.create(path: path, name: 'x', secret: 'y');
      expect(session.entries.length, 1);
      session.lock();
      expect(session.entries, isEmpty);
    });
  });
}

int _magicLineLen(Uint8List bytes) => bytes.indexOf(0x0A) + 1;

int _headerLineLen(Uint8List bytes) {
  final start = _magicLineLen(bytes);
  return bytes.indexOf(0x0A, start) - start + 1;
}

Map<String, Object?> _readHeader(Uint8List bytes) {
  final start = _magicLineLen(bytes);
  final end = bytes.indexOf(0x0A, start);
  return jsonDecode(utf8.decode(bytes.sublist(start, end))) as Map<String, Object?>;
}
