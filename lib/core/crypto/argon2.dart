import 'dart:convert';
import 'package:cryptography/cryptography.dart';

/// Argon2id 口令派生封装。
///
/// 默认参数：memory=64MiB, iterations=3, parallelism=1, hashLength=32。
/// 派生输入为 trim + NFC 规范化后的口令 UTF-8 字节。
/// 全部钥匙条目共用同一个全局 salt（读取时从文件头获取）。
class Argon2Deriver {
  final Argon2id _algorithm;
  final List<int> _salt;

  Argon2Deriver({
    int memory = 64 * 1024, // 64 MiB（KiB 单位）
    int iterations = 3,
    int parallelism = 1,
    int hashLength = 32,
    required List<int> salt,
  })  : _salt = _validatedSalt(
          memory: memory,
          iterations: iterations,
          parallelism: parallelism,
          hashLength: hashLength,
          salt: salt,
        ),
        _algorithm = Argon2id(
          memory: memory,
          iterations: iterations,
          parallelism: parallelism,
          hashLength: hashLength,
        );

  static List<int> _validatedSalt({
    required int memory,
    required int iterations,
    required int parallelism,
    required int hashLength,
    required List<int> salt,
  }) {
    _validateParameters(
      memory: memory,
      iterations: iterations,
      parallelism: parallelism,
      hashLength: hashLength,
      salt: salt,
    );
    return List.unmodifiable(salt);
  }

  static void _validateParameters({
    required int memory,
    required int iterations,
    required int parallelism,
    required int hashLength,
    required List<int> salt,
  }) {
    if (memory < 8 || memory > 1024 * 1024) {
      throw ArgumentError('Argon2 memory out of range');
    }
    if (iterations < 1 || iterations > 100) {
      throw ArgumentError('Argon2 iterations out of range');
    }
    if (parallelism < 1 || parallelism > 16) {
      throw ArgumentError('Argon2 parallelism out of range');
    }
    if (hashLength < 32 || hashLength > 128) {
      throw ArgumentError('Argon2 hash length out of range');
    }
    if (salt.length < 16 || salt.length > 64) {
      throw ArgumentError('Argon2 salt length out of range');
    }
  }

  /// 全局 salt 字节（供文件头序列化与测试使用）。
  List<int> get salt => _salt;

  /// 派生参数（用于序列化到文件头）。
  Map<String, Object> get params => {
        'memory': _algorithm.memory,
        'iterations': _algorithm.iterations,
        'parallelism': _algorithm.parallelism,
        'hashLength': _algorithm.hashLength,
        'salt': base64Encode(_salt),
      };

  /// 从规范化的口令字符串派生 256-bit 密钥。
  Future<SecretKey> derive(String normalizedPassword) async {
    return _algorithm.deriveKey(
      secretKey: SecretKey(utf8.encode(normalizedPassword)),
      nonce: _salt,
    );
  }
}