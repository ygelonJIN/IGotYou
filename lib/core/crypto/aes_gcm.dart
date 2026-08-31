import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';

/// AES-256-GCM 加解密封装。
///
/// 每次加密使用独立随机 nonce，解密时需提供 nonce（从 SecretBox 提取）。
class AesGcmCipher {
  final AesGcm _algorithm = AesGcm.with256bits();

  /// 加密 [plainText] 并返回 nonce + cipherText + mac 的拼接字节。
  Future<Uint8List> encrypt(String plainText, SecretKey key) async {
    final secretBox = await _algorithm.encryptString(
      plainText,
      secretKey: key,
    );
    return secretBox.concatenation();
  }

  /// 解密由 [encrypt] 产生的拼接字节 -> 原字符串。
  Future<String> decrypt(Uint8List concatenated, SecretKey key) async {
    final secretBox = SecretBox.fromConcatenation(
      concatenated,
      macLength: 16,
      nonceLength: 12,
    );
    return _algorithm.decryptString(secretBox, secretKey: key);
  }

  /// 加密原始字节，返回 SecretBox。
  Future<SecretBox> encryptBytes(Uint8List data, SecretKey key) async {
    return _algorithm.encrypt(data, secretKey: key);
  }

  /// 解密 SecretBox 返回原始字节。
  Future<Uint8List> decryptBytes(SecretBox box, SecretKey key) async {
    final out = await _algorithm.decrypt(box, secretKey: key);
    return Uint8List.fromList(out);
  }

  /// 从拼接字节重建 SecretBox（nonce = 12, mac = 16）。
  static SecretBox boxFromConcat(Uint8List concat) {
    return SecretBox.fromConcatenation(
      concat,
      macLength: 16,
      nonceLength: 12,
    );
  }
}