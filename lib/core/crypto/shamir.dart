import 'dart:math';
import 'dart:typed_data';

/// Shamir 秘密共享（N 中 K），在质数域上实现。
///
/// 主密钥 MK 视为 256-bit 整数（< p，见 [primeP]），阈值 K 下：
/// - 拆分：随机多项式 f(x)=MK + a1·x + … + a_{K-1}·x^{K-1} (mod p)，份额 s_i=(x_i, y_i=f(x_i))
/// - 重构：任意 K 份用 Lagrange 插值在 x=0 处求 f(0)=MK
/// - 少于 K 份：信息论安全，无任何关于 MK 的信息。
///
/// 选用质数 p = secp256k1 域素数 2^256 - 2^32 - 977，略小于 2^256，
/// 使 32 字节 MK（极小概率 ≥p 的值重抽）与份额 y 均可定长 32 字节存放。
/// 文档称 GF(2^128) Lagrange——本实现与之等价（域上多项式 + Lagrange），
/// 选用质数域可使 Dart BigInt 实现最短、无外部依赖且易审计。
class Shamir {
  Shamir._();

  static final BigInt primeP = BigInt.parse(
    '115792089237316195423570985008687907853269984665640564039457584007908834671663',
  );

  static BigInt _mod(BigInt v) {
    v %= primeP;
    if (v.isNegative) v += primeP;
    return v;
  }

  static BigInt _modInv(BigInt a) {
    a = _mod(a);
    if (a == BigInt.zero) throw StateError('no inverse for 0');
    BigInt lm = BigInt.one, hm = BigInt.zero;
    BigInt low = _mod(a), high = primeP;
    while (low > BigInt.one) {
      final r = high ~/ low;
      final nm = hm - lm * r;
      final neww = high - low * r;
      hm = lm;
      lm = nm;
      high = low;
      low = neww;
    }
    return _mod(lm);
  }

  static BigInt _evalPoly(List<BigInt> coeff, BigInt x) {
    var result = BigInt.zero;
    var power = BigInt.one;
    for (final c in coeff) {
      result = _mod(result + c * power);
      power = _mod(power * x);
    }
    return result;
  }

  /// 将 32 字节 MK 拆为 N 份，阈值 K。
  /// [xs] 为各份额的 x 坐标（已去重、非零、<p），长度 N。
  static List<BigInt> split(BigInt secret, int k, List<BigInt> xs) {
    assert(k >= 1 && k <= xs.length);
    final rnd = Random.secure();
    final coeff = <BigInt>[secret];
    for (var i = 1; i < k; i++) {
      final bytes = Uint8List(32);
      for (var j = 0; j < 32; j++) {
        bytes[j] = rnd.nextInt(256);
      }
      coeff.add(_bytesToBigInt(bytes) % primeP);
    }
    return xs.map((x) => _evalPoly(coeff, x)).toList();
  }

  /// 用 K 份 (xs, ys) 重构秘密（Lagrange 插值于 0）。
  static BigInt reconstruct(List<BigInt> xs, List<BigInt> ys) {
    assert(xs.length == ys.length && xs.isNotEmpty);
    final k = xs.length;
    var secret = BigInt.zero;
    for (var i = 0; i < k; i++) {
      var numerator = BigInt.one;
      var denominator = BigInt.one;
      for (var j = 0; j < k; j++) {
        if (i == j) continue;
        numerator = _mod(numerator * (BigInt.zero - xs[j]));
        denominator = _mod(denominator * (xs[i] - xs[j]));
      }
      final lagrange = _mod(numerator * _modInv(denominator));
      secret = _mod(secret + ys[i] * lagrange);
    }
    return secret;
  }

  static BigInt _bytesToBigInt(Uint8List bytes) {
    var v = BigInt.zero;
    for (final b in bytes) {
      v = (v << 8) | BigInt.from(b);
    }
    return v;
  }

  static Uint8List bigIntToBytes32(BigInt v) {
    final out = Uint8List(32);
    var tmp = v;
    for (var i = 31; i >= 0; i--) {
      out[i] = (tmp & BigInt.from(0xFF)).toInt();
      tmp >>= 8;
    }
    return out;
  }

  static BigInt bytes32ToBigInt(Uint8List bytes) => _bytesToBigInt(bytes);
}
