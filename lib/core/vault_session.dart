import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

import 'crypto/aes_gcm.dart';
import 'crypto/argon2.dart';
import 'crypto/keychain.dart';
import 'file/vault_file.dart';
import 'models/entry.dart';
import 'models/share_record.dart';
import 'models/vault_config.dart';
import 'normalize.dart';

/// 二次加密条目的密文载荷（JSON 序列化后整体 AES-GCM 加密）。
class DoubleLockPayload {
  final String secret;
  final String note;

  const DoubleLockPayload({required this.secret, required this.note});

  Map<String, Object?> toJson() => {'secret': secret, 'note': note};

  factory DoubleLockPayload.fromJson(Map<String, Object?> json) =>
      DoubleLockPayload(
        secret: (json['secret'] ?? '') as String,
        note: (json['note'] ?? '') as String,
      );
}

/// 二次加密条目缺失明文密钥（重切分/编辑时需要）。
class VaultKeyMissingException implements Exception {
  final String entryName;
  VaultKeyMissingException(this.entryName);

  @override
  String toString() => '需要条目「$entryName」的加密密钥';
}

/// BODY 密文内的库 JSON 结构。
class VaultBody {
  final List<Entry> entries;
  final VaultConfig config;

  const VaultBody({required this.entries, required this.config});

  Map<String, Object> toJson() => {
        'entries': entries.map((e) => e.toJson()).toList(),
        'config': config.toJson(),
      };

  factory VaultBody.fromJson(Map<String, Object?> json) => VaultBody(
        entries: (json['entries'] as List<Object?>)
            .map((e) => Entry.fromJson(e! as Map<String, Object?>))
            .toList(),
        config: VaultConfig.fromJson(json['config']! as Map<String, Object?>),
      );
}

/// 保险柜会话（DEVELOPMENT 5.7）：解锁后解密数据驻留内存，锁定清零。
///
/// 负责：BODY 解密/加密、份额随钥匙集重建、保存、锁定。
class VaultSession extends ChangeNotifier {
  final String path;
  final VaultFileData fileData;
  final Uint8List mk;
  final AesGcmCipher _aes = AesGcmCipher();

  /// 内存中的明文条目（唯一权威列表，改动后需 [save] 落盘）。
  List<Entry> entries;

  /// 内存中的权威配置。
  VaultConfig config;

  /// 份额是否需要重建（钥匙集/口令/阈值变化后置 true）。
  bool _sharesDirty = true;

  /// 份额对应的钥匙 id 集：与 [_shares] 同步维护，
  /// 用于判断份额变更属于"纯新增/纯移除"（可增量处理）还是"改密/换阈值"
  /// （必须全量重切）。
  Set<String> _sharesKeyIds = const {};

  /// 二次加密条目的明文密钥缓存（会话内存，锁定清空，不落盘）。
  final Map<String, String> _doubleKeys = {};

  VaultSession._({
    required this.path,
    required this.fileData,
    required this.mk,
    required this.entries,
    required this.config,
  }) {
    _sharesDirty = _needsResplit();
    // 文件份额与当前钥匙集一致时直接采用：解锁后首次保存不必无谓地
    // 全量重切，也解锁"只给新钥匙补份额"的增量路径。
    if (!_sharesDirty) {
      _shares = List.of(fileData.shares);
      _sharesKeyIds = fileData.shares.map((s) => s.entryId).toSet();
    }
  }

  /// 解锁后打开会话：用 MK 解密 BODY，加载条目与配置。
  static Future<VaultSession> open({
    required String path,
    required VaultFileData fileData,
    required Uint8List mk,
  }) async {
    final body = await _decryptBody(fileData, mk);
    return VaultSession._(
      path: path,
      fileData: fileData,
      mk: mk,
      entries: body.entries,
      config: body.config,
    );
  }

  /// 首次创建保险柜（DEVELOPMENT 8.1）。
  /// 生成 MK、盐、首个条目自动标记为钥匙、K=1。
  static Future<VaultSession> create({
    required String path,
    required String name,
    required String secret,
    String note = '',
  }) async {
    final mk = Keychain.generateMk();
    final rnd = Random.secure();
    final salt = Uint8List(16);
    for (var i = 0; i < 16; i++) {
      salt[i] = rnd.nextInt(256);
    }
    final deriver = Argon2Deriver(salt: salt);
    final now = DateTime.now();
    final entry = Entry(
      id: _uuid(),
      name: name,
      secret: secret,
      note: note,
      isKey: true,
      createdAt: now,
      updatedAt: now,
    );
    final config = const VaultConfig.defaults().copyWith(hitCount: 1);
    final shares = await Keychain.splitSecret(
      mk: mk,
      keyEntries: [entry],
      threshold: 1,
      deriver: deriver,
    );
    final header = VaultHeader(
      version: vaultFileVersion,
      argonParams: deriver.params,
      salt: salt,
      config: config,
    );
    final bodyJson = jsonEncode(VaultBody(entries: [entry], config: config).toJson());
    final aes = AesGcmCipher();
    final body = await aes.encrypt(bodyJson, SecretKeyData(mk));
    await VaultFile.write(
      path,
      header: header,
      shares: shares,
      body: body,
    );
    final fileData = await VaultFile.read(path);
    return VaultSession._(
      path: path,
      fileData: fileData,
      mk: mk,
      entries: [entry],
      config: config,
    );
  }

  static Future<VaultBody> _decryptBody(VaultFileData fileData, Uint8List mk) async {
    final aes = AesGcmCipher();
    final bodyCipher = await VaultFile.readBody(fileData);
    final bodyJson = await aes.decrypt(bodyCipher, SecretKeyData(mk));
    final map = jsonDecode(bodyJson) as Map<String, Object?>;
    final body = VaultBody.fromJson(map);
    // 镜像校验：BODY 内 config 与 HEADER 镜像不一致 → 文件损坏（DEVELOPMENT 7.1）。
    if (body.config.toJson().toString() != fileData.header.config.toJson().toString()) {
      throw VaultFileException('文件损坏');
    }
    return body;
  }

  bool _needsResplit() {
    final currentIds = fileData.shares.map((s) => s.entryId).toSet();
    final keyIds = entries.where((e) => e.isKey).map((e) => e.id).toSet();
    return currentIds.length != keyIds.length || !currentIds.containsAll(keyIds);
  }

  // ── 查询 ──

  int get keyCount => entries.where((e) => e.isKey).length;

  /// 可达成命中数意义上的有效钥匙数 = 不同钥匙口令数。
  ///
  /// 多把钥匙共用同一口令时，打开只能命中一次（按值去重），
  /// 故在 K 约束里只算一把；否则 K 会被设成实际达不到的 2+，库永久打不开。
  /// 二次加密钥匙条目按会话内缓存明文密钥去重；密钥缺失（未查看过）时
  /// 保守地**不计入**（K 只会被钳低、不会因未知口令被钳高而锁死），
  /// 但至少返回 1 保证 K ≥ 1。
  int get distinctKeyCount {
    final known = <String>{};
    for (final e in keyEntries) {
      if (e.doubleLocked && !_doubleKeys.containsKey(e.id)) continue;
      known.add(normalizeSecret(_keySecret(e)));
    }
    return known.isEmpty ? 1 : known.length;
  }

  List<Entry> get keyEntries => entries.where((e) => e.isKey).toList();

  Entry? entryById(String id) {
    for (final e in entries) {
      if (e.id == id) return e;
    }
    return null;
  }

  /// 与其他条目加密内容相同者（用于重复标注，DEVELOPMENT 8.4）。
  Entry? findDuplicateSecret(String secret, {String? exceptId}) {
    for (final e in entries) {
      if (e.id == exceptId) continue;
      if (e.secret == secret) return e;
    }
    return null;
  }

  // ── 二次加密（DEVELOPMENT 8.5b）──
  // 开启/关闭/修改均需用户提供密钥；明文密钥只缓存于会话内存（_doubleKeys），
  // 锁定清空、不落盘。作为钥匙的二次加密条目，其份额 KEK 从该密钥派生
  // （解锁时输入该密钥即可命中），故份额重切需要缓存密钥，缺失时抛
  // [VaultKeyMissingException] 由 UI 引导输入。

  /// 派生参数（与文件头一致，仅换独立盐）。
  Argon2Deriver _doubleDeriver(Uint8List salt) {
    final p = fileData.header.argonParams;
    return Argon2Deriver(
      memory: (p['memory']! as num).toInt(),
      iterations: (p['iterations']! as num).toInt(),
      parallelism: (p['parallelism']! as num).toInt(),
      hashLength: (p['hashLength']! as num).toInt(),
      salt: salt,
    );
  }

  static Uint8List _randomSalt() {
    final rnd = Random.secure();
    final salt = Uint8List(16);
    for (var i = 0; i < 16; i++) {
      salt[i] = rnd.nextInt(256);
    }
    return salt;
  }

  /// 除 [exceptId] 外，作为钥匙的二次加密条目中明文密钥未缓存者名称。
  /// 份额重切需要这些密钥，缺失时需先查看对应条目输入密钥。
  List<String> _missingDoubleKeyNames({String? exceptId}) {
    return entries
        .where((e) =>
            e.id != exceptId &&
            e.isKey &&
            e.doubleLocked &&
            !_doubleKeys.containsKey(e.id))
        .map((e) => e.name)
        .toList();
  }

  /// 开启二次加密：用 [key] 加密 secret/note 到 doubleCipher，条目正文清空。
  Future<void> setDoubleLock(Entry entry, String key) async {
    final cur = entryById(entry.id) ?? entry;
    if (cur.doubleLocked) throw StateError('已开启二次加密');
    final missing = _missingDoubleKeyNames(exceptId: cur.id);
    if (cur.isKey && missing.isNotEmpty) {
      throw VaultKeyMissingException(missing.join('、'));
    }
    final salt = _randomSalt();
    final deriver = _doubleDeriver(salt);
    final kek = await deriver.derive(normalizeSecret(key));
    final payload = jsonEncode(
      DoubleLockPayload(secret: cur.secret, note: cur.note).toJson(),
    );
    final cipher = await _aes.encrypt(payload, kek);
    final i = entries.indexWhere((e) => e.id == cur.id);
    entries[i] = cur.copyWith(
      secret: '',
      note: '',
      doubleLocked: true,
      doubleCipher: base64Encode(cipher),
      doubleSalt: base64Encode(salt),
      updatedAt: DateTime.now(),
    );
    _doubleKeys[cur.id] = key;
    if (cur.isKey) _sharesDirty = true;
    notifyListeners();
  }

  /// 关闭二次加密：用 [key] 解密后回填明文，移除缓存。
  Future<void> clearDoubleLock(Entry entry, String key) async {
    final cur = entryById(entry.id) ?? entry;
    if (!cur.doubleLocked) throw StateError('未开启二次加密');
    // 预检：关闭后若触发份额重切（本条目是钥匙），其余二次加密钥匙条目
    // 必须已缓存明文密钥，否则 save() 会抛 VaultKeyMissingException——
    // 先报清楚，避免状态已改但保存失败（DEVELOPMENT 17.13）。
    final missing = _missingDoubleKeyNames(exceptId: cur.id);
    if (cur.isKey && missing.isNotEmpty) {
      throw VaultKeyMissingException(missing.join('、'));
    }
    final payload = await _decryptDouble(cur, key);
    final i = entries.indexWhere((e) => e.id == cur.id);
    entries[i] = cur.copyWith(
      secret: payload.secret,
      note: payload.note,
      doubleLocked: false,
      doubleCipher: null,
      doubleSalt: null,
      updatedAt: DateTime.now(),
    );
    _doubleKeys.remove(cur.id);
    if (cur.isKey) _sharesDirty = true;
    notifyListeners();
  }

  /// 修改二次加密密钥：旧密钥验证通过后，用新密钥重新加密内容。
  Future<void> changeDoubleKey(
    Entry entry,
    String oldKey,
    String newKey,
  ) async {
    final cur = entryById(entry.id) ?? entry;
    if (!cur.doubleLocked) throw StateError('未开启二次加密');
    final missing = _missingDoubleKeyNames(exceptId: cur.id);
    if (cur.isKey && missing.isNotEmpty) {
      throw VaultKeyMissingException(missing.join('、'));
    }
    final payload = await _decryptDouble(cur, oldKey);
    final salt = _randomSalt();
    final deriver = _doubleDeriver(salt);
    final kek = await deriver.derive(normalizeSecret(newKey));
    final cipher = await _aes.encrypt(
      jsonEncode(payload.toJson()),
      kek,
    );
    final i = entries.indexWhere((e) => e.id == cur.id);
    entries[i] = cur.copyWith(
      doubleCipher: base64Encode(cipher),
      doubleSalt: base64Encode(salt),
      updatedAt: DateTime.now(),
    );
    _doubleKeys[cur.id] = newKey;
    if (cur.isKey) _sharesDirty = true;
    notifyListeners();
  }

  /// 验证密钥并解密二次加密内容；成功则缓存密钥供后续编辑/重切份额。
  /// 返回明文 (secret, note)。
  Future<(String secret, String note)> unlockDoubleLock(
    Entry entry,
    String key,
  ) async {
    final cur = entryById(entry.id) ?? entry;
    final payload = await _decryptDouble(cur, key);
    _doubleKeys[cur.id] = key;
    return (payload.secret, payload.note);
  }

  Future<DoubleLockPayload> _decryptDouble(Entry entry, String key) async {
    if (!entry.doubleLocked || entry.doubleCipher == null || entry.doubleSalt == null) {
      throw StateError('条目未开启二次加密');
    }
    final deriver = _doubleDeriver(base64Decode(entry.doubleSalt!));
    final kek = await deriver.derive(normalizeSecret(key));
    try {
      final payloadJson = await _aes.decrypt(
        base64Decode(entry.doubleCipher!),
        kek,
      );
      return DoubleLockPayload.fromJson(
        jsonDecode(payloadJson) as Map<String, Object?>,
      );
    } catch (_) {
      throw StateError('加密密钥不正确');
    }
  }

  /// 份额重切/去重统计时，二次加密钥匙条目取缓存明文密钥；缺失抛异常。
  String _keySecret(Entry e) {
    if (!e.doubleLocked) return e.secret;
    final k = _doubleKeys[e.id];
    if (k == null) throw VaultKeyMissingException(e.name);
    return k;
  }


  Entry addEntry({
    required String name,
    required String secret,
    String note = '',
    bool isKey = true,
  }) {
    final now = DateTime.now();
    final entry = Entry(
      id: _uuid(),
      name: name,
      secret: secret,
      note: note,
      isKey: isKey,
      createdAt: now,
      updatedAt: now,
    );
    entries.add(entry);
    if (isKey) _sharesDirty = true;
    _enforceKConstraint();
    notifyListeners();
    return entry;
  }

  /// 份额是否待重切（新建流程降级时需恢复快照）。
  bool get sharesDirty => _sharesDirty;

  /// 把刚加入的钥匙条目降级为非钥匙，份额状态恢复到加入前。
  ///
  /// 仅限创建流程在份额重切失败（如二次加密钥匙明文缺失）时调用：
  /// 条目保留、不再是钥匙，之后保存不再触发重切，因此不会索要其他条目的密码。
  /// [sharesDirty] 传入加入该钥匙前的值，避免跳过真正需要的重切。
  void downgradeToNonKey(String entryId, {required bool sharesDirty}) {
    final i = entries.indexWhere((e) => e.id == entryId);
    if (i < 0 || !entries[i].isKey) return;
    entries[i] = entries[i].copyWith(isKey: false);
    _sharesDirty = sharesDirty;
    _enforceKConstraint();
    notifyListeners();
  }

  void updateEntry(Entry entry, {String? name, String? secret, String? note}) {
    final oldSecret = entry.secret;
    final updated = entry.copyWith(
      name: name,
      secret: secret,
      note: note,
      updatedAt: DateTime.now(),
    );
    final i = entries.indexWhere((e) => e.id == entry.id);
    if (i < 0) return;
    entries[i] = updated;
    if (updated.isKey && secret != null && secret != oldSecret) {
      _sharesDirty = true;
    }
    notifyListeners();
  }

  /// 更新二次加密条目：正文用缓存的明文密钥重新加密进 doubleCipher。
  /// 未传的 secret/note 字段保留原加密内容（从旧载荷解密补齐）；
  /// 密钥缓存缺失抛 [VaultKeyMissingException]。
  Future<void> updateDoubleEntry(
    Entry entry, {
    String? name,
    String? secret,
    String? note,
  }) async {
    if (!entry.doubleLocked) {
      updateEntry(entry, name: name, secret: secret, note: note);
      return;
    }
    final key = _doubleKeys[entry.id];
    if (key == null) throw VaultKeyMissingException(entry.name);
    // 解密旧载荷，未传字段保留原文，避免覆盖成空串。
    final old = await _decryptDouble(entry, key);
    final payload = DoubleLockPayload(
      secret: secret ?? old.secret,
      note: note ?? old.note,
    );
    final deriver = _doubleDeriver(base64Decode(entry.doubleSalt!));
    final kek = await deriver.derive(normalizeSecret(key));
    final cipher = await _aes.encrypt(jsonEncode(payload.toJson()), kek);
    final i = entries.indexWhere((e) => e.id == entry.id);
    if (i < 0) return;
    entries[i] = entry.copyWith(
      name: name,
      doubleCipher: base64Encode(cipher),
      updatedAt: DateTime.now(),
    );
    notifyListeners();
  }

  /// 切换"作为钥匙"。若因此触发钥匙数 < K 的硬约束，自动下调 K。
  /// 返回调整后新的 K；未调整返回 null。
  ///
  /// 最后一把钥匙不允许关闭：关闭后钥匙数为 0，份额列表将为空，
  /// 主密钥再也无法重建（DEVELOPMENT 6.4 硬约束下限）。
  int? setEntryKey(Entry entry, bool isKey) {    final i = entries.indexWhere((e) => e.id == entry.id);
    if (i < 0 || entries[i].isKey == isKey) return null;
    if (entries[i].isKey && !isKey && keyCount <= 1) {
      throw StateError('至少保留一把钥匙，否则保险柜将永久锁死');
    }
    entries[i] = entries[i].copyWith(isKey: isKey);
    _sharesDirty = true;
    final adjustedK = _enforceKConstraint();
    notifyListeners();
    return adjustedK;
  }

  /// 删除条目。若因此触发钥匙数 < K 的硬约束，自动下调 K。
  /// 返回调整后新的 K；未调整返回 null。
  ///
  /// 最后一把钥匙不允许删除（原因同上）。
  int? deleteEntry(String id) {
    final entry = entryById(id);
    if (entry == null) return null;
    if (entry.isKey && keyCount <= 1) {
      throw StateError('至少保留一把钥匙，否则保险柜将永久锁死');
    }
    entries.removeWhere((e) => e.id == id);
    _sharesDirty = true;
    final adjustedK = _enforceKConstraint();
    notifyListeners();
    return adjustedK;
  }

  // ── 配置 ──

  String? updateConfig(VaultConfig newConfig) {
    final err = newConfig.validate(keyCount: distinctKeyCount);
    if (err != null) return err;
    config = newConfig;
    _sharesDirty = true;
    notifyListeners();
    return null;
  }

  /// 保存：K 自动调整为可达成的最大值（DEVELOPMENT 6.4 硬约束）。
  /// 双向钳制：K ≤ 不同钥匙口令数（向上界，防止"重复口令锁死"），K ≥ 1（向下界）。
  /// 返回调整后的新 K；未调整返回 null。
  int? _enforceKConstraint() {
    final k = config.hitCount;
    final upper = distinctKeyCount < 1 ? 1 : distinctKeyCount;
    final clamped = k > upper ? upper : (k < 1 ? 1 : k);
    if (clamped == k) return null;
    config = config.copyWith(hitCount: clamped);
    return clamped;
  }

  // ── 保存 / 锁定 ──

  /// 落盘：重加密 BODY、按需重建份额。
  ///
  /// 份额必须与当前钥匙集一致才能写盘：会话打开时 `_shares` 为空，
  /// 且钥匙集未变时 `_sharesDirty` 为 false，若不校验此处会把空份额写盘
  /// 导致主密钥无法重建、库永久锁死。故只要数量不匹配即重切分。
  Future<void> save() async {
    if (_sharesDirty || _shares.length != keyEntries.length) {
      await _resplitShares();
    }
    final bodyJson = jsonEncode(VaultBody(entries: entries, config: config).toJson());
    final body = await _aes.encrypt(bodyJson, SecretKeyData(mk));

    final header = VaultHeader(
      version: vaultFileVersion,
      argonParams: fileData.header.argonParams,
      salt: fileData.header.salt,
      config: config, // 镜像同步（DEVELOPMENT 7.1）
    );
    await VaultFile.write(
      path,
      header: header,
      shares: _shares,
      body: body,
    );
    _sharesDirty = false;
    notifyListeners();
  }

  List<ShareRecord> _shares = [];

  Future<void> _resplitShares() async {
    final keys = keyEntries;
    if (keys.isEmpty || config.hitCount < 1 || config.hitCount > keys.length) {
      throw StateError('钥匙配置无效：需要至少一把钥匙');
    }
    final deriver = fileData.header.deriver;
    final keyIds = keys.map((e) => e.id).toSet();
    // 纯移除：多项式未变，直接丢弃被删钥匙的份额即可——不重切旧份额、
    // 不需要其他钥匙的明文，删除也无需索要二次加密密码。
    if (_sharesKeyIds.isNotEmpty &&
        keyIds.length < _sharesKeyIds.length &&
        keyIds.every(_sharesKeyIds.contains)) {
      _shares = _shares.where((s) => keyIds.contains(s.entryId)).toList();
      _sharesKeyIds = keyIds;
      return;
    }
    // 纯新增：只在现有份额上补新钥匙的份额，不重切旧份额——
    // 无需全部钥匙的明文（二次加密钥匙未查看时不用索要密码）。
    final added = await _tryAddShares(keys, deriver);
    if (added != null) {
      _shares = added;
      _sharesKeyIds = keyIds;
      return;
    }
    // 其余（钥匙改密/二次加密开闭/命中数变化/混合变更）：
    // 全量重切（需要每把钥匙的明文；缺失时抛 VaultKeyMissingException）。
    _shares = await Keychain.splitSecret(
      mk: mk,
      keyEntries: keys,
      threshold: config.hitCount,
      deriver: deriver,
      keyFor: _keySecret,
    );
    _sharesKeyIds = keyIds;
  }

  /// 增量补份额：现有份额 + 新增钥匙的份额。
  ///
  /// 仅当现有份额对应的钥匙仍是钥匙、且钥匙集是"纯新增"（无移除/改密）时
  /// 尝试；可解密份额不足阈值、或份额与当前明文不匹配时返回 null，
  /// 由调用方回退全量重切。
  Future<List<ShareRecord>?> _tryAddShares(
    List<Entry> keys,
    Argon2Deriver deriver,
  ) async {
    if (_shares.isEmpty) return null;
    final shareIds = _shares.map((s) => s.entryId).toSet();
    final keyIds = keys.map((e) => e.id).toSet();
    final addedIds = keyIds.difference(shareIds);
    if (addedIds.isEmpty) return null; // 不是新增场景
    if (!shareIds.every(keyIds.contains)) return null; // 有钥匙被移除/改密
    final newShares = <ShareRecord>[];
    for (final id in addedIds) {
      final newKey = keys.firstWhere((e) => e.id == id);
      try {
        final share = await Keychain.addShare(
          newKey: newKey,
          existingShares: [..._shares, ...newShares],
          keyEntries: keys,
          threshold: config.hitCount,
          deriver: deriver,
          keyFor: _keySecret,
        );
        if (share == null) return null;
        newShares.add(share);
      } on VaultKeyMissingException {
        return null; // 新钥匙本身明文缺失：回退全量（由全量重切统一处理）
      }
    }
    return [..._shares, ...newShares];
  }

  /// 恢复刚删除的条目（删除保存失败时回滚内存状态，界面保持原状）。
  void restoreEntry(Entry entry, {required bool sharesDirty}) {
    if (entryById(entry.id) != null) return;
    entries.add(entry);
    _sharesDirty = sharesDirty;
    _enforceKConstraint();
    notifyListeners();
  }

  /// 锁定：清空全部解密数据、二次加密密钥缓存与主密钥（DEVELOPMENT 5.7），强制 GC。
  void lock() {
    entries = const [];
    _shares = const [];
    _sharesKeyIds = const {};
    _doubleKeys.clear();
    mk.fillRange(0, mk.length, 0);
    notifyListeners();
  }

  static String _uuid() {
    final rnd = Random.secure();
    final bytes = Uint8List(16);
    for (var i = 0; i < 16; i++) {
      bytes[i] = rnd.nextInt(256);
    }
    bytes[6] = (bytes[6] & 0x0F) | 0x40;
    bytes[8] = (bytes[8] & 0x3F) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}
