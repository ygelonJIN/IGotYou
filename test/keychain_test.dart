import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';

import 'package:igotyou/core/crypto/argon2.dart';
import 'package:igotyou/core/crypto/keychain.dart';
import 'package:igotyou/core/crypto/shamir.dart';
import 'package:igotyou/core/models/entry.dart';
import 'package:igotyou/core/models/share_record.dart';
import 'package:igotyou/core/normalize.dart';

final Random _rnd = Random.secure();

Uint8List secBytes(int n) {
  final b = Uint8List(n);
  for (var i = 0; i < n; i++) {
    b[i] = _rnd.nextInt(256);
  }
  return b;
}

/// 构造钥匙条目（固定 id 保证 x 坐标稳定）。
Entry keyEntry(int seed, String secret, {bool isKey = true}) => Entry(
      id: 'entry-$seed',
      name: '条目 $seed',
      secret: secret,
      note: '',
      isKey: isKey,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

Future<Argon2Deriver> fastDeriver() async => Argon2Deriver(
      // 测试用低成本参数，仅验证逻辑正确性（非性能）。
      memory: 64,
      iterations: 1,
      parallelism: 1,
      hashLength: 32,
      salt: secBytes(16),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Keychain 份额体系', () {
    test('N 中 K：用 K 个正确口令解密份额并重构 MK', () async {
      final mk = Keychain.generateMk();
      final deriver = await fastDeriver();
      final entries = [
        keyEntry(1, 'alpha'),
        keyEntry(2, 'bravo'),
        keyEntry(3, 'charlie'),
        keyEntry(4, 'delta'),
        keyEntry(5, 'echo'),
      ];
      final shares = await Keychain.splitSecret(
        mk: mk,
        keyEntries: entries,
        threshold: 3,
        deriver: deriver,
      );
      expect(shares.length, 5);

      // 任意 K=3 份（取 1、3、5），用各自口令解密 y 并重构。
      final picks = [0, 2, 4];
      final kek1 = await deriver.derive(normalizeSecret(entries[picks[0]].secret));
      final y1 = await Keychain.tryDecryptShare(shares[picks[0]], kek1);
      final kek2 = await deriver.derive(normalizeSecret(entries[picks[2]].secret));
      final y2 = await Keychain.tryDecryptShare(shares[picks[2]], kek2);
      final kek3 = await deriver.derive(normalizeSecret(entries[picks[1]].secret));
      final y3 = await Keychain.tryDecryptShare(shares[picks[1]], kek3);
      expect(y1, isNotNull);
      expect(y2, isNotNull);
      expect(y3, isNotNull);

      final recovered = await Keychain.reconstructMk(
        [shares[picks[0]], shares[picks[2]], shares[picks[1]]],
        ys: [y1!, y2!, y3!],
      );
      expect(recovered, mk);
    });

    test('错误口令解不开任何份额', () async {
      final mk = Keychain.generateMk();
      final deriver = await fastDeriver();
      final entries = [keyEntry(1, 'secret-a')];
      final shares = await Keychain.splitSecret(
        mk: mk,
        keyEntries: entries,
        threshold: 1,
        deriver: deriver,
      );
      final wrongKek = await deriver.derive(normalizeSecret('wrong'));
      expect(await Keychain.tryDecryptShare(shares[0], wrongKek), isNull);
    });

    test('口令 trim + NFC 规范化后仍能命中', () async {
      final mk = Keychain.generateMk();
      final deriver = await fastDeriver();
      final entries = [keyEntry(1, ' 密码\u00C0 ')];
      final shares = await Keychain.splitSecret(
        mk: mk,
        keyEntries: entries,
        threshold: 1,
        deriver: deriver,
      );
      // 输入带前后空格、用 NFD 组合形式（A + 重音符），规范化后应命中。
      final normalized = normalizeSecret('密码\u0041\u0300');
      final kek = await deriver.derive(normalized);
      final y = await Keychain.tryDecryptShare(shares[0], kek);
      expect(y, isNotNull);
    });

    test('重复加密内容：同一口令解开的份额对应其条目', () async {
      final mk = Keychain.generateMk();
      final deriver = await fastDeriver();
      // 两个条目加密内容相同。
      final entries = [keyEntry(1, 'same'), keyEntry(2, 'same')];
      final shares = await Keychain.splitSecret(
        mk: mk,
        keyEntries: entries,
        threshold: 2,
        deriver: deriver,
      );
      final kek = await deriver.derive(normalizeSecret('same'));
      final y1 = await Keychain.tryDecryptShare(shares[0], kek);
      final y2 = await Keychain.tryDecryptShare(shares[1], kek);
      // 输入一次口令，两个份额都能解开（份额各自加密，内容相同不互相影响）。
      expect(y1, isNotNull);
      expect(y2, isNotNull);
    });

    test('entryX 确定性：同一 id 恒得同一坐标', () async {
      final x1 = await Keychain.entryX('abc-123');
      final x2 = await Keychain.entryX('abc-123');
      final x3 = await Keychain.entryX('abc-124');
      expect(x1, x2);
      expect(x1, isNot(x3));
      expect(x1 > BigInt.zero, isTrue);
    });

    test('少于 K 份份额重构不出 MK（信息论保证）', () async {
      final mk = Keychain.generateMk();
      final deriver = await fastDeriver();
      final entries = [
        keyEntry(1, 'a'),
        keyEntry(2, 'b'),
        keyEntry(3, 'c'),
      ];
      final shares = await Keychain.splitSecret(
        mk: mk,
        keyEntries: entries,
        threshold: 2,
        deriver: deriver,
      );
      // 只有 1 份：Shamir.reconstruct 需要 K 份，此处验证单份重构不等于 MK。
      final kek = await deriver.derive(normalizeSecret('a'));
      final y = await Keychain.tryDecryptShare(shares[0], kek);
      expect(y, isNotNull);
      final single = await Keychain.reconstructMk([shares[0]], ys: [y!]);
      expect(single == mk, isFalse);
    });
  });

  group('MK 边界', () {
    test('生成 MK 为 32 字节且落在质数域内', () {
      final mk = Keychain.generateMk();
      expect(mk.length, 32);
      expect(Shamir.bytes32ToBigInt(mk) < Shamir.primeP, isTrue);
    });

    test('超过域范围的 secret 拆分抛错', () async {
      final deriver = await fastDeriver();
      // MK = p（等于质数）→ 越界。
      final outOfRange = Shamir.bigIntToBytes32(Shamir.primeP);
      await expectLater(
        Keychain.splitSecret(
          mk: outOfRange,
          keyEntries: [keyEntry(1, 'x')],
          threshold: 1,
          deriver: deriver,
        ),
        throwsStateError,
      );
    });
  });

  group('ShareRecord', () {
    test('copyWith 保留其余字段', () {
      final s = ShareRecord(
        entryId: 'id',
        x: BigInt.from(7),
        nonce: Uint8List.fromList([1, 2]),
        cipher: Uint8List.fromList([3, 4]),
      );
      final s2 = s.copyWith(cipher: Uint8List.fromList([9]));
      expect(s2.entryId, 'id');
      expect(s2.x, BigInt.from(7));
      expect(s2.nonce, [1, 2]);
      expect(s2.cipher, [9]);
    });
  });
}
