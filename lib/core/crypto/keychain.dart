import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../models/entry.dart';
import '../models/share_record.dart';
import '../normalize.dart';
import 'aes_gcm.dart';
import 'argon2.dart';
import 'shamir.dart';

/// 密钥体系（DEVELOPMENT 5）：MK 生成、份额拆分/重构、密钥派生。
class Keychain {
  Keychain._();

  static final AesGcmCipher _aesGcm = AesGcmCipher();
  static final Random _rng = Random.secure();

  /// 生成 256-bit 随机主密钥 MK。
  static Uint8List generateMk() {
    final bytes = Uint8List(32);
    for (var i = 0; i < 32; i++) {
      bytes[i] = _rng.nextInt(256);
    }
    return bytes;
  }

  /// 条目身份的 128-bit 确定性 x 坐标：SHA-256(entryId) 高 16 字节。
  static Future<BigInt> entryX(String entryId) async {
    final hash = await Sha256().hash(utf8.encode(entryId));
    final sub = hash.bytes.sublist(0, 16);
    var v = BigInt.zero;
    for (final b in sub) {
      v = (v << 8) | BigInt.from(b);
    }
    return v;
  }

  /// 把 MK 拆成 N 份份额（N = 钥匙条目数，阈值 K），每份用对应口令加密。
  /// [keyFor] 提供每把钥匙用于派生 KEK 的明文口令：默认取 [Entry.secret]；
  /// 二次加密条目由会话传入缓存明文（缺失时抛错由会话兜底）。
  static Future<List<ShareRecord>> splitSecret({
    required Uint8List mk,
    required List<Entry> keyEntries,
    required int threshold,
    required Argon2Deriver deriver,
    String Function(Entry entry)? keyFor,
  }) async {
    final secret = Shamir.bytes32ToBigInt(mk);
    if (secret >= Shamir.primeP) {
      throw StateError('MK out of field range');
    }
    final xs = <BigInt>{};
    final xsOrdered = <BigInt>[];
    for (final e in keyEntries) {
      var x = await entryX(e.id);
      x %= Shamir.primeP;
      if (x == BigInt.zero || xs.contains(x)) {
        // 理论极低概率：id 哈希碰撞或为 0，改写为递推值。
        var suffix = BigInt.from(xs.length + 1);
        x = _mod(x + suffix, Shamir.primeP);
      }
      xs.add(x);
      xsOrdered.add(x);
    }
    final ys = Shamir.split(secret, threshold, xsOrdered);

    final shares = <ShareRecord>[];
    for (var i = 0; i < keyEntries.length; i++) {
      final yBytes = Shamir.bigIntToBytes32(ys[i]);
      final keySecret = keyFor?.call(keyEntries[i]) ?? keyEntries[i].secret;
      final kek = await deriver.derive(normalizeSecret(keySecret));
      final box = await _aesGcm.encryptBytes(yBytes, kek);
      shares.add(ShareRecord(
        entryId: keyEntries[i].id,
        x: xsOrdered[i],
        nonce: Uint8List.fromList(box.nonce),
        cipher: Uint8List.fromList([...box.cipherText, ...box.mac.bytes]),
      ));
    }
    return shares;
  }

  /// 用派生出的 [kek] 尝试解密一份份额；成功返回 32 字节 y，失败返回 null。
  static Future<Uint8List?> tryDecryptShare(ShareRecord share, SecretKey kek) async {
    try {
      final concat = Uint8List.fromList([...share.nonce, ...share.cipher]);
      final box = SecretBox.fromConcatenation(concat, nonceLength: 12, macLength: 16);
      return await _aesGcm.decryptBytes(box, kek);
    } catch (_) {
      return null;
    }
  }

  /// 增量补份额：保持现有份额不变，只给 [newKey] 生成新份额。
  ///
  /// 现有份额是同一多项式上的点；用阈值 K 份**可解密**的旧份额
  /// （明文密钥 → KEK → 解密 y）做 Lagrange 插值，在同一多项式上求出
  /// 新钥匙的 y，再用新钥匙自己的密码加密。
  ///
  /// 无需全部钥匙的明文：明文缺失的份额保持原样、不参与插值。
  /// 可解密份额不足 K、或某份份额明文在手却解不开（钥匙改过密）时返回 null，
  /// 调用方应回退全量重切。
  static Future<ShareRecord?> addShare({
    required Entry newKey,
    required List<ShareRecord> existingShares,
    required List<Entry> keyEntries,
    required int threshold,
    required Argon2Deriver deriver,
    required String Function(Entry entry) keyFor,
  }) async {
    if (existingShares.isEmpty || threshold < 1) return null;
    final xs = <BigInt>[];
    final ys = <BigInt>[];
    for (final share in existingShares) {
      Entry? entry;
      for (final e in keyEntries) {
        if (e.id == share.entryId) {
          entry = e;
          break;
        }
      }
      if (entry == null) return null; // 份额对应的钥匙已不存在 → 不能增量
      String plain;
      try {
        plain = keyFor(entry);
      } catch (_) {
        continue; // 明文缺失（如未查看的二次加密钥匙）：份额保持原样
      }
      final kek = await deriver.derive(normalizeSecret(plain));
      final y = await tryDecryptShare(share, kek);
      if (y == null) return null; // 明文在手却解不开 → 钥匙改过密 → 全量重切
      xs.add(share.x);
      ys.add(Shamir.bytes32ToBigInt(y));
      if (xs.length >= threshold) break;
    }
    if (xs.length < threshold) return null;

    // 新钥匙的 x 坐标（与 splitSecret 相同的去零/去重规避）。
    final existingXs = existingShares.map((s) => s.x).toSet();
    var xNew = await entryX(newKey.id);
    xNew %= Shamir.primeP;
    if (xNew == BigInt.zero || existingXs.contains(xNew)) {
      var suffix = BigInt.from(existingShares.length + 1);
      xNew = _mod(xNew + suffix, Shamir.primeP);
    }
    final yNew = Shamir.evaluateAt(xs, ys, xNew);
    final yBytes = Shamir.bigIntToBytes32(yNew);
    final kek = await deriver.derive(normalizeSecret(keyFor(newKey)));
    final box = await _aesGcm.encryptBytes(yBytes, kek);
    return ShareRecord(
      entryId: newKey.id,
      x: xNew,
      nonce: Uint8List.fromList(box.nonce),
      cipher: Uint8List.fromList([...box.cipherText, ...box.mac.bytes]),
    );
  }

  /// 从若干份额点 (x, y) 重构 MK（阈值份额数）。
  static Future<Uint8List> reconstructMk(
    List<ShareRecord> shares, {
    required List<Uint8List> ys,
  }) async {
    final xs = shares.map((s) => s.x).toList();
    final secrets = ys.map(Shamir.bytes32ToBigInt).toList();
    final secret = Shamir.reconstruct(xs, secrets);
    return Shamir.bigIntToBytes32(secret);
  }

  static BigInt _mod(BigInt v, BigInt m) {
    v %= m;
    if (v.isNegative) v += m;
    return v;
  }
}