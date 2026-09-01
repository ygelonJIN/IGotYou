// 临时验证脚本：增量补份额（addShare）数学正确性。
// 运行：dart run tool/verify_add_share.dart
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

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

Argon2Deriver fastDeriver() => Argon2Deriver(
      memory: 64,
      iterations: 1,
      parallelism: 1,
      hashLength: 32,
      salt: secBytes(16),
    );

Entry entry(int seed, String secret) => Entry(
      id: 'entry-$seed',
      name: 'n$seed',
      secret: secret,
      note: '',
      isKey: true,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

var _failures = 0;

void check(bool cond, String name) {
  if (cond) {
    stdout.writeln('PASS  $name');
  } else {
    stdout.writeln('FAIL  $name');
    _failures++;
  }
}

/// 用份额列表 + 对应明文解密出 y，再重构 MK。
Future<Uint8List> reconstructWith(
  List<ShareRecord> shares,
  List<Entry> entries,
  Argon2Deriver deriver,
  String Function(Entry) keyFor,
) async {
  final ys = <Uint8List>[];
  for (final s in shares) {
    final e = entries.firstWhere((x) => x.id == s.entryId);
    final kek = await deriver.derive(normalizeSecret(keyFor(e)));
    final y = await Keychain.tryDecryptShare(s, kek);
    if (y == null) throw StateError('cannot decrypt share ${s.entryId}');
    ys.add(y);
  }
  return Keychain.reconstructMk(shares, ys: ys);
}

String Function(Entry) plainFor(Map<String, String> secrets) =>
    (Entry e) => secrets[e.id]!;

Future<void> main() async {
  final deriver = fastDeriver();
  final mk = Keychain.generateMk();

  // ── 1. 基础回归：evaluateAt(x,0) == reconstruct ──
  {
    final xs = [BigInt.from(1), BigInt.from(2), BigInt.from(5)];
    final coeff = [BigInt.from(9), BigInt.from(7), BigInt.from(3)];
    final ys = xs.map((x) {
      var r = BigInt.zero;
      var p = BigInt.one;
      for (final c in coeff) {
        r = (r + c * p) % Shamir.primeP;
        p = (p * x) % Shamir.primeP;
      }
      return r;
    }).toList();
    check(
      Shamir.reconstruct(xs, ys) == BigInt.from(9),
      'evaluateAt(0) == reconstruct',
    );
    check(
      Shamir.evaluateAt(xs, ys, BigInt.from(2)) == BigInt.from(35),
      'evaluateAt(x=2) == f(2)',
    );
  }

  // ── 2. 阈值 K 下增量补份额 → 用新份额 + K-1 旧份额重构出 MK ──
  for (final (k, n) in [(1, 2), (2, 3), (3, 4), (2, 4)]) {
    final entries = [for (var i = 1; i <= n; i++) entry(i, 'pw$i')];
    final secrets = {for (final e in entries) e.id: e.secret};
    final shares = await Keychain.splitSecret(
      mk: mk,
      keyEntries: entries,
      threshold: k,
      deriver: deriver,
      keyFor: plainFor(secrets),
    );
    final newKey = entry(99, 'pw99');
    final added = await Keychain.addShare(
      newKey: newKey,
      existingShares: shares,
      keyEntries: [...entries, newKey],
      threshold: k,
      deriver: deriver,
      keyFor: plainFor({...secrets, newKey.id: newKey.secret}),
    );
    check(added != null, 'K=$k N=$n: addShare 成功');
    if (added == null) continue;
    // 用新份额 + (K-1) 份旧份额重构
    final pick = [added, ...shares.take(k - 1)];
    final mk1 = await reconstructWith(pick, [...entries, newKey], deriver,
        plainFor({...secrets, newKey.id: newKey.secret}));
    check(mk1.length == mk.length && _bytesEq(mk1, mk),
        'K=$k N=$n: 新份额+K-1旧份额重构出 MK');
    // 旧份额仍然有效（多项式未变）
    final mk2 = await reconstructWith(shares.take(k).toList(), entries, deriver,
        plainFor(secrets));
    check(_bytesEq(mk2, mk), 'K=$k N=$n: 旧份额仍可重构 MK');
  }

  // ── 3. 用户场景：111 普通 + 222 二次加密（明文缺失），K=1，加 333 ──
  {
    final e111 = entry(1, '111');
    final e222 = entry(2, '222');
    final secrets = {e111.id: '111', e222.id: '222'};
    final shares = await Keychain.splitSecret(
      mk: mk,
      keyEntries: [e111, e222],
      threshold: 1,
      deriver: deriver,
      keyFor: plainFor(secrets),
    );
    final e333 = entry(3, '333');
    final allSecrets = {...secrets, e333.id: e333.secret};
    // 222 的明文对 keyFor 不可见（模拟二次加密未查看）
    String hide222(Entry e) {
      if (e.id == e222.id) throw StateError('missing');
      return allSecrets[e.id]!;
    }

    final added = await Keychain.addShare(
      newKey: e333,
      existingShares: shares,
      keyEntries: [e111, e222, e333],
      threshold: 1,
      deriver: deriver,
      keyFor: hide222,
    );
    check(added != null, 'K=1 + 一把钥匙明文缺失：增量成功');
    if (added != null) {
      final mk1 = await reconstructWith([added], [e111, e222, e333], deriver,
          (e) => e.secret);
      check(_bytesEq(mk1, mk), 'K=1：仅用 333 新份额即可重构 MK');
    }
  }

  // ── 4. 可解密份额不足阈值 → null ──
  {
    final e1 = entry(1, 'a');
    final e2 = entry(2, 'b');
    final secrets = {e1.id: 'a', e2.id: 'b'};
    final shares = await Keychain.splitSecret(
      mk: mk,
      keyEntries: [e1, e2],
      threshold: 2,
      deriver: deriver,
      keyFor: plainFor(secrets),
    );
    final e3 = entry(3, 'c');
    String? hideAllBut(Entry e, String visibleId) {
      if (e.id != visibleId) throw StateError('missing');
      return secrets[e.id];
    }

    final added = await Keychain.addShare(
      newKey: e3,
      existingShares: shares,
      keyEntries: [e1, e2, e3],
      threshold: 2,
      deriver: deriver,
      keyFor: (e) => hideAllBut(e, e1.id)!,
    );
    check(added == null, 'K=2 只有 1 份可解密：返回 null（回退全量）');
  }

  // ── 5. 钥匙改过密（明文在手但旧份额解不开）→ null ──
  {
    final e1 = entry(1, 'oldpw');
    final secrets = {e1.id: 'oldpw'};
    final shares = await Keychain.splitSecret(
      mk: mk,
      keyEntries: [e1],
      threshold: 1,
      deriver: deriver,
      keyFor: plainFor(secrets),
    );
    final e2 = entry(2, 'new');
    final changed = {e1.id: 'newpw'}; // 钥匙 1 的密码已改
    final added = await Keychain.addShare(
      newKey: e2,
      existingShares: shares,
      keyEntries: [e1, e2],
      threshold: 1,
      deriver: deriver,
      keyFor: plainFor(changed),
    );
    check(added == null, '改过密的旧份额：返回 null（回退全量）');
  }

  // ── 6. 连续加两把钥匙（addedIds 多个）──
  {
    final e1 = entry(1, 'a');
    final shares = await Keychain.splitSecret(
      mk: mk,
      keyEntries: [e1],
      threshold: 1,
      deriver: deriver,
      keyFor: (e) => e.secret,
    );
    final e2 = entry(2, 'b');
    final s2 = await Keychain.addShare(
      newKey: e2,
      existingShares: shares,
      keyEntries: [e1, e2],
      threshold: 1,
      deriver: deriver,
      keyFor: (e) => e.secret,
    );
    final e3 = entry(3, 'c');
    final s3 = await Keychain.addShare(
      newKey: e3,
      existingShares: [...shares, s2!],
      keyEntries: [e1, e2, e3],
      threshold: 1,
      deriver: deriver,
      keyFor: (e) => e.secret,
    );
    check(s3 != null, '连续增量补第二把钥匙成功');
    if (s3 != null) {
      final mk1 = await reconstructWith([s3], [e1, e2, e3], deriver,
          (e) => e.secret);
      check(_bytesEq(mk1, mk), '第二把新份额可重构 MK');
    }
  }

  if (_failures > 0) {
    stderr.writeln('$_failures 项失败');
    exitCode = 1;
  } else {
    stdout.writeln('全部通过');
  }
}

bool _bytesEq(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
