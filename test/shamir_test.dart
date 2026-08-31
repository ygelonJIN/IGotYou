import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:cryptography/cryptography.dart';

import 'package:igotyou/core/crypto/shamir.dart';
import 'package:igotyou/core/crypto/aes_gcm.dart';

final Random _rnd = Random.secure();

/// 生成长度为 [n] 的随机字节。
Uint8List secBytes(int n) {
  final b = Uint8List(n);
  for (var i = 0; i < n; i++) {
    b[i] = _rnd.nextInt(256);
  }
  return b;
}

BigInt _mk() => Shamir.bytes32ToBigInt(secBytes(32)) % Shamir.primeP;

List<BigInt> distinctXs(int n) {
  final xs = <BigInt>{};
  var i = 0;
  while (xs.length < n) {
    xs.add(BigInt.from(++i));
  }
  return xs.toList();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final rnd = _rnd;

  group('Shamir 秘密共享', () {
    test('N 中 K：任意 K 份可重构 MK', () {
      final k = 3;
      final n = 5;
      final secret = _mk();
      final xs = distinctXs(n);
      final ys = Shamir.split(secret, k, xs);
      // 用第 0、2、4 份（非连续）重构。
      final picks = [0, 2, 4];
      final got = Shamir.reconstruct(
        picks.map((i) => xs[i]).toList(),
        picks.map((i) => ys[i]).toList(),
      );
      expect(got, secret);
    });

    test('阈值任意组合：全选与乱序选取结果一致', () {
      final k = 2;
      final n = 4;
      final secret = _mk();
      final xs = distinctXs(n);
      final ys = Shamir.split(secret, k, xs);
      // 乱序取 K 份。
      final order = [3, 1];
      final got = Shamir.reconstruct(
        order.map((i) => xs[i]).toList(),
        order.map((i) => ys[i]).toList(),
      );
      expect(got, secret);
    });

    test('少于 K 份无法重构（信息论保证）', () {
      final k = 3;
      final n = 4;
      final secret = _mk();
      final xs = distinctXs(n);
      final ys = Shamir.split(secret, k, xs);
      // 只取 2 份，重构结果不应等于原秘密（大概率不同）。
      final partialYs = ys.take(2).toList();
      final partialXs = xs.take(2).toList();
      final got = Shamir.reconstruct(partialXs, partialYs);
      // 信息论上少于 K 份无关于秘密的信息，这里验证结果几乎必然不等于。
      expect(got == secret, isFalse);
    });

    test('K=1：任一份即完整秘密', () {
      final n = 3;
      final secret = _mk();
      final xs = distinctXs(n);
      final ys = Shamir.split(secret, 1, xs);
      for (var i = 0; i < n; i++) {
        expect(Shamir.reconstruct([xs[i]], [ys[i]]), secret);
      }
    });

    test('bytes32ToBigInt / bigIntToBytes32 定长往返', () {
      final bytes = Uint8List(32);
      for (var i = 0; i < 32; i++) {
        bytes[i] = rnd.nextInt(256);
      }
      expect(
        Shamir.bigIntToBytes32(Shamir.bytes32ToBigInt(bytes)),
        bytes,
      );
    });
  });

  group('AesGcmCipher', () {
    test('字符串加解密往返', () async {
      final cipher = AesGcmCipher();
      final key = SecretKey(secBytes(32));
      const text = '你好，世界 hello 123 !@#';
      final enc = await cipher.encrypt(text, key);
      expect(await cipher.decrypt(enc, key), text);
    });

    test('字节加解密往返（SecretBox）', () async {
      final cipher = AesGcmCipher();
      final key = SecretKey(secBytes(32));
      final raw = secBytes(64);
      final box = await cipher.encryptBytes(raw, key);
      expect(await cipher.decryptBytes(box, key), raw);
    });

    test('拼接字节重建 SecretBox 并解密', () async {
      final cipher = AesGcmCipher();
      final key = SecretKey(secBytes(32));
      final raw = secBytes(48);
      final box = await cipher.encryptBytes(raw, key);
      final concat = Uint8List.fromList([...box.nonce, ...box.cipherText, ...box.mac.bytes]);
      final rebuilt = AesGcmCipher.boxFromConcat(concat);
      expect(await cipher.decryptBytes(rebuilt, key), raw);
    });

    test('错误密钥解密抛错（认证）', () async {
      final cipher = AesGcmCipher();
      final k1 = SecretKey(secBytes(32));
      final k2 = SecretKey(secBytes(32));
      final enc = await cipher.encrypt('correct key only', k1);
      await expectLater(
        cipher.decrypt(enc, k2),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    });
  });
}