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
import 'models/vault_structure.dart';
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

  /// 维护层结构块（方案三 17.20）：二次加密口令封套等，随 BODY 一起受 MK 保护。
  final VaultStructure structure;

  const VaultBody({
    required this.entries,
    required this.config,
    this.structure = const VaultStructure(),
  });

  Map<String, Object> toJson() => {
    'entries': entries.map((e) => e.toJson()).toList(),
    'config': config.toJson(),
    'structure': structure.toJson(),
  };

  factory VaultBody.fromJson(Map<String, Object?> json) => VaultBody(
    entries: (json['entries'] as List<Object?>)
        .map((e) => Entry.fromJson(e! as Map<String, Object?>))
        .toList(),
    config: VaultConfig.fromJson(json['config']! as Map<String, Object?>),
    structure: VaultStructure.fromJson(
      json['structure'] as Map<String, Object?>?,
    ),
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

  /// 当前 [_shares] 所在多项式的生成阈值（K）。仅全量重切时更新，
  /// 增量路径（纯移除/纯新增）保持多项式与阈值不变。
  /// 打开会话时以文件头 config 初始化；阈值与当前 K 不一致 ⇒ 必须全量重切。
  int _sharesThreshold = 0;

  /// 钥匙口令相关变化（改密 / 二次加密开闭）后置 true：即使钥匙集是
  /// "纯移除/纯新增"，也必须全量重切——否则旧口令份额残留，解锁命中失败。
  bool _sharesSecretDirty = false;

  /// 二次加密条目的明文密钥缓存（会话内存，锁定清空，不落盘）。
  final Map<String, String> _doubleKeys = {};

  /// 维护层结构密钥（方案三 17.20）：由 MK 派生，解锁后即可恢复；
  /// 只用于解/写口令封套（份额重切），绝不用于自动解密条目内容。
  late final Uint8List _structureKey;

  /// 从口令封套恢复的二次加密条目口令（规范化后，会话内存，锁定清空）。
  /// 与 [_doubleKeys] 分离：[_doubleKeys] 存用户本轮实测输入（供内容编辑），
  /// 此处存封套恢复值（供份额重切/去重计数）。
  final Map<String, String> _structureKeys = {};

  /// 内存中的结构块（可变的封套表，落盘时随 BODY 加密写入）。
  late VaultStructure _structure;

  /// 门禁已校验通过、但尚未人工点击「查看」的明文密钥（会话内存，锁定清空）。
  /// 与 [_doubleKeys] 分离：确认进入前不算"已缓存"（份额重切/编辑不认）。
  final Map<String, String> _pendingDoubleKeys = {};

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
      _sharesThreshold = fileData.header.config.hitCount;
    }
  }

  /// 解锁后打开会话：用 MK 解密 BODY，加载条目、配置与维护层结构块。
  static Future<VaultSession> open({
    required String path,
    required VaultFileData fileData,
    required Uint8List mk,
  }) async {
    final body = await _decryptBody(fileData, mk);
    return _withStructure(
      path: path,
      fileData: fileData,
      mk: mk,
      entries: body.entries,
      config: body.config,
      structure: body.structure,
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
    final bodyJson = jsonEncode(
      VaultBody(entries: [entry], config: config).toJson(),
    );
    final aes = AesGcmCipher();
    final body = await aes.encrypt(bodyJson, SecretKeyData(mk));
    await VaultFile.write(path, header: header, shares: shares, body: body);
    final fileData = await VaultFile.read(path);
    return _withStructure(
      path: path,
      fileData: fileData,
      mk: mk,
      entries: [entry],
      config: config,
      structure: const VaultStructure(),
    );
  }

  /// 共用的会话构造：派生结构密钥、解开全部口令封套（失败跳过——
  /// 该条目视为"未恢复"，重切时按存量库路径引导输入）。
  static Future<VaultSession> _withStructure({
    required String path,
    required VaultFileData fileData,
    required Uint8List mk,
    required List<Entry> entries,
    required VaultConfig config,
    required VaultStructure structure,
  }) async {
    final session = VaultSession._(
      path: path,
      fileData: fileData,
      mk: mk,
      entries: entries,
      config: config,
    );
    session._structureKey = await Keychain.structureKey(mk);
    session._structure = structure.keyEnvelopes.isEmpty
        ? VaultStructure(keyEnvelopes: {})
        : structure;
    for (final e in structure.keyEnvelopes.entries) {
      final pw = await Keychain.unwrapStructurePassword(
        session._structureKey,
        e.value,
      );
      if (pw != null) session._structureKeys[e.key] = pw;
    }
    return session;
  }

  static Future<VaultBody> _decryptBody(
    VaultFileData fileData,
    Uint8List mk,
  ) async {
    final aes = AesGcmCipher();
    final bodyCipher = await VaultFile.readBody(fileData);
    final bodyJson = await aes.decrypt(bodyCipher, SecretKeyData(mk));
    final map = jsonDecode(bodyJson) as Map<String, Object?>;
    final body = VaultBody.fromJson(map);
    // 镜像校验：BODY 内 config 与 HEADER 镜像不一致 → 文件损坏（DEVELOPMENT 7.1）。
    if (body.config.toJson().toString() !=
        fileData.header.config.toJson().toString()) {
      throw VaultFileException('文件损坏');
    }
    return body;
  }

  bool _needsResplit() {
    final currentIds = fileData.shares.map((s) => s.entryId).toSet();
    final keyIds = entries.where((e) => e.isKey).map((e) => e.id).toSet();
    return currentIds.length != keyIds.length ||
        !currentIds.containsAll(keyIds);
  }

  // ── 查询 ──

  int get keyCount => entries.where((e) => e.isKey).length;

  /// 可达成命中数意义上的有效钥匙数 = 不同钥匙口令数。
  ///
  /// 多把钥匙共用同一口令时，打开只能命中一次（按值去重），
  /// 故在 K 约束里只算一把；否则 K 会被设成实际达不到的 2+，库永久打不开。
  /// 非二次加密钥匙取正文口令；二次加密钥匙取会话缓存（[_doubleKeys]）或
  /// 维护层封套恢复值（[_structureKeys]，方案三 17.20）——封套使口令计数
  /// 不再依赖"本会话是否看过该条目"。封套与缓存均缺失（存量库未查看未输血）
  /// 时保守地**不计入**（K 只会被钳低、不会因未知口令被钳高而锁死），
  /// 但至少返回 1 保证 K ≥ 1。
  int get distinctKeyCount {
    final known = <String>{};
    for (final e in keyEntries) {
      final pw = e.doubleLocked
          ? (_doubleKeys[e.id] ?? _structureKeys[e.id])
          : e.secret;
      if (pw == null) continue;
      known.add(normalizeSecret(pw));
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
  // （解锁时输入该密钥即可命中）。
  //
  // 份额重切与条目内容彻底解耦（方案三 17.20）：重切需要该密钥派生新份额
  // KEK——若本会话已输入过（_doubleKeys）直接用，否则从维护层口令封套
  // （_structureKeys，由 MK 派生的结构密钥解开）恢复。因此**改 K / 增删钥匙
  // 等结构操作不再索要其他二次加密钥匙的口令**；查看/修改条目内容仍走门禁
  // 输入该条目的密码（条目层），两层的权限来源互不依赖。

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

  /// 维护层封套写入：用结构密钥把规范化口令加密进结构块（BODY 内），
  /// 并同步会话内封套恢复表。写入前会先补建可变的封套表。
  Future<void> _writeStructureEnvelope(String entryId, String password) async {
    if (_structure.keyEnvelopes.isEmpty) {
      _structure = VaultStructure(keyEnvelopes: {});
    }
    final envelope = await Keychain.wrapStructurePassword(
      _structureKey,
      normalizeSecret(password),
    );
    _structure.keyEnvelopes[entryId] = envelope;
    _structureKeys[entryId] = normalizeSecret(password);
  }

  /// 开启二次加密：用 [key] 加密 secret/note 到 doubleCipher，条目正文清空。
  /// 同时写入维护层口令封套——此后结构重切不再需要用户重新输入本条目口令
  /// （非钥匙条目也写：将来打开钥匙开关同样免输入）。
  Future<void> setDoubleLock(Entry entry, String key) async {
    final cur = entryById(entry.id) ?? entry;
    if (cur.doubleLocked) throw StateError('已开启二次加密');
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
    await _writeStructureEnvelope(cur.id, key);
    if (cur.isKey) {
      _sharesDirty = true;
      _sharesSecretDirty = true;
    }
    notifyListeners();
  }

  /// 关闭二次加密：用 [key] 解密后回填明文，移除缓存与维护层封套。
  Future<void> clearDoubleLock(Entry entry, String key) async {
    final cur = entryById(entry.id) ?? entry;
    if (!cur.doubleLocked) throw StateError('未开启二次加密');
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
    _structureKeys.remove(cur.id);
    _structure.keyEnvelopes.remove(cur.id);
    if (cur.isKey) {
      _sharesDirty = true;
      _sharesSecretDirty = true;
    }
    notifyListeners();
  }

  /// 修改二次加密密钥：旧密钥验证通过后，用新密钥重新加密内容，
  /// 并更新维护层口令封套（份额重切随新口令走）。
  Future<void> changeDoubleKey(
    Entry entry,
    String oldKey,
    String newKey,
  ) async {
    final cur = entryById(entry.id) ?? entry;
    if (!cur.doubleLocked) throw StateError('未开启二次加密');
    final payload = await _decryptDouble(cur, oldKey);
    final salt = _randomSalt();
    final deriver = _doubleDeriver(salt);
    final kek = await deriver.derive(normalizeSecret(newKey));
    final cipher = await _aes.encrypt(jsonEncode(payload.toJson()), kek);
    final i = entries.indexWhere((e) => e.id == cur.id);
    entries[i] = cur.copyWith(
      doubleCipher: base64Encode(cipher),
      doubleSalt: base64Encode(salt),
      updatedAt: DateTime.now(),
    );
    _doubleKeys[cur.id] = newKey;
    await _writeStructureEnvelope(cur.id, newKey);
    if (cur.isKey) {
      _sharesDirty = true;
      _sharesSecretDirty = true;
    }
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

  /// 门禁提交校验（与首次解锁盲输同逻辑）：
  /// 只验证密钥、暂存"待确认"状态，不执行解锁、不进入编辑态；
  /// 正确返回 true，错误返回 false。
  Future<bool> submitDoubleLock(Entry entry, String key) async {
    final cur = entryById(entry.id) ?? entry;
    try {
      await _decryptDouble(cur, key);
    } on StateError {
      return false;
    }
    _pendingDoubleKeys[cur.id] = key;
    return true;
  }

  /// 门禁确认：点「查看」后缓存密钥并解密正文，返回明文 (secret, note)。
  /// 无待确认密钥返回 null（界面应保持在门禁态）。
  Future<(String secret, String note)?> confirmDoubleLock(String id) async {
    final key = _pendingDoubleKeys.remove(id);
    if (key == null) return null;
    final cur = entryById(id);
    if (cur == null || !cur.doubleLocked) return null;
    final payload = await _decryptDouble(cur, key);
    _doubleKeys[id] = key;
    return (payload.secret, payload.note);
  }

  Future<DoubleLockPayload> _decryptDouble(Entry entry, String key) async {
    if (!entry.doubleLocked ||
        entry.doubleCipher == null ||
        entry.doubleSalt == null) {
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

  /// 份额重切/去重统计时，二次加密钥匙条目取会话实测口令（[_doubleKeys]）
  /// 或维护层封套恢复口令（[_structureKeys]，方案三 17.20）；两者皆无抛异常。
  String _shareSecret(Entry e) {
    if (!e.doubleLocked) return e.secret;
    final k = _doubleKeys[e.id] ?? _structureKeys[e.id];
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
      _sharesSecretDirty = true;
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
  int? setEntryKey(Entry entry, bool isKey) {
    final i = entries.indexWhere((e) => e.id == entry.id);
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

  /// 存量库修复路径打开后调用（见 UnlockEngine.repairedShares）：
  /// 份额所在多项式阶数高于当前 K，标记下次保存必须全量重切。
  /// 二次加密钥匙明文口令可从维护层封套恢复（方案三 17.20），无封套的
  /// 存量库仍会抛 [VaultKeyMissingException] 引导输入一次（随后封套落盘自愈）。
  void markSharesForResplit() {
    _sharesDirty = true;
    _sharesThreshold = 0; // 与任何合法 K 均不等 ⇒ needResplit 恒 true
  }

  /// 把解锁引擎命中到的口令按条目缓存（仅二次加密钥匙条目，17.20）：
  /// 用户在解锁页已输入且该口令确实解开了对应份额——与门禁查看同等级，
  /// 供随后的份额修复重切直接使用，无需用户进库后再逐个查看条目。
  /// 仅在口令能解开该条目二次加密内容时才缓存；不符则跳过（不猜测，
  /// 后续保存会走 [VaultKeyMissingException] 引导输入正确密钥）。
  Future<void> seedDoubleKeys(Map<String, String> byEntryId) async {
    for (final e in keyEntries) {
      if (!e.doubleLocked || _doubleKeys.containsKey(e.id)) continue;
      final p = byEntryId[e.id];
      if (p == null) continue;
      try {
        await unlockDoubleLock(e, p); // 验证通过即写入 _doubleKeys
      } on StateError {
        // 口令与条目内容不符：不缓存。
      }
    }
  }

  /// 落盘：重加密 BODY、按需重建份额。
  ///
  /// 份额必须与当前钥匙集一致才能写盘：会话打开时 `_shares` 为空，
  /// 且钥匙集未变时 `_sharesDirty` 为 false，若不校验此处会把空份额写盘
  /// 导致主密钥无法重建、库永久锁死。故只要数量不匹配即重切分。
  Future<void> save() async {
    // 清理孤儿封套：已删除/已关闭二次加密的条目封套不随落盘残留。
    final alive = entries.where((e) => e.doubleLocked).map((e) => e.id).toSet();
    final oldShares = _shares;
    final oldShareIds = _sharesKeyIds;
    final oldSharesThreshold = _sharesThreshold;
    final oldSharesSecretDirty = _sharesSecretDirty;
    final oldStructure = _structure;
    final oldStructureEnvelopes = Map<String, String>.from(
      _structure.keyEnvelopes,
    );
    final oldStructureKeys = Map<String, String>.from(_structureKeys);
    try {
      // 结构块清理也属于本次事务，失败时必须恢复。
      _structure.keyEnvelopes.removeWhere(
        (id, _) => !alive.contains(id),
      );
      _structureKeys.removeWhere((id, _) => !alive.contains(id));
      if (_sharesDirty || _shares.length != keyEntries.length) {
        await _resplitShares();
      }
      final bodyJson = jsonEncode(
        VaultBody(
          entries: entries,
          config: config,
          structure: _structure,
        ).toJson(),
      );
      final body = await _aes.encrypt(bodyJson, SecretKeyData(mk));

      final header = VaultHeader(
        version: vaultFileVersion,
        argonParams: fileData.header.argonParams,
        salt: fileData.header.salt,
        config: config, // 镜像同步（DEVELOPMENT 7.1）
      );
      await VaultFile.write(path, header: header, shares: _shares, body: body);
      _sharesDirty = false;
      notifyListeners();
    } catch (_) {
      _shares = oldShares;
      _sharesKeyIds = oldShareIds;
      _sharesThreshold = oldSharesThreshold;
      _sharesSecretDirty = oldSharesSecretDirty;
      _structure = oldStructure;
      _structure.keyEnvelopes
        ..clear()
        ..addAll(oldStructureEnvelopes);
      _structureKeys
        ..clear()
        ..addAll(oldStructureKeys);
      rethrow;
    }
  }

  List<ShareRecord> _shares = [];

  /// 存量库自愈（方案三 17.20）：本会话已输入口令、但维护层封套缺失的
  /// 二次加密条目，补写封套（口令封套随 BODY 落盘）。此后即使不输入，
  /// 结构重切也能从未缓存中恢复口令。
  Future<void> _healStructureKeys() async {
    for (final e in entries) {
      if (!e.doubleLocked) continue;
      if (_structureKeys.containsKey(e.id)) continue;
      final p = _doubleKeys[e.id];
      if (p == null) continue;
      await _writeStructureEnvelope(e.id, p);
    }
  }

  Future<void> _resplitShares() async {
    // 存量库自愈：本会话输入过口令但封套缺失的二次加密钥匙，先补写封套
    // （此后结构维护不再索要其口令）；两者皆无的仍由 _shareSecret 抛
    // VaultKeyMissingException 引导输入一次。
    await _healStructureKeys();
    final keys = keyEntries;
    if (keys.isEmpty || config.hitCount < 1 || config.hitCount > keys.length) {
      throw StateError('钥匙配置无效：需要至少一把钥匙');
    }
    final deriver = fileData.header.deriver;
    final keyIds = keys.map((e) => e.id).toSet();
    // 阈值（K）或钥匙口令变化 ⇒ 多项式/口令绑定变化，必须全量重切后再写盘。
    // 增量路径（纯移除/纯新增）只允许在多项式与口令均未变时使用；否则会
    // 留下高阶多项式份额，而在更低的 K 下重构出错误 MK——解锁页"打开成功"
    // 后进入会话时解密 BODY 必然失败（打开失败）。
    final needResplit =
        config.hitCount != _sharesThreshold || _sharesSecretDirty;
    // 纯移除：多项式未变，直接丢弃被删钥匙的份额即可——不重切旧份额、
    // 不需要其他钥匙的明文，删除也无需索要二次加密密码。
    if (!needResplit &&
        _sharesKeyIds.isNotEmpty &&
        keyIds.length < _sharesKeyIds.length &&
        keyIds.every(_sharesKeyIds.contains)) {
      _shares = _shares.where((s) => keyIds.contains(s.entryId)).toList();
      _sharesKeyIds = keyIds;
      return;
    }
    // 纯新增：只在现有份额上补新钥匙的份额，不重切旧份额——
    // 无需全部钥匙的明文（二次加密钥匙未查看时不用索要密码）。
    if (!needResplit) {
      final added = await _tryAddShares(keys, deriver);
      if (added != null) {
        _shares = added;
        _sharesKeyIds = keyIds;
        return;
      }
    }
    // 其余（阈值变化/钥匙改密/二次加密开闭/混合变更）：
    // 全量重切。每把钥匙的明文口令：普通条目取正文，二次加密条目取会话
    // 缓存或维护层封套恢复值（方案三 17.20）；均缺失才抛 VaultKeyMissingException。
    _shares = await Keychain.splitSecret(
      mk: mk,
      keyEntries: keys,
      threshold: config.hitCount,
      deriver: deriver,
      keyFor: _shareSecret,
    );
    _sharesKeyIds = keyIds;
    _sharesThreshold = config.hitCount;
    _sharesSecretDirty = false;
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
          keyFor: _shareSecret,
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

  /// 锁定：清空全部解密数据、二次加密密钥缓存、维护层口令恢复表与主密钥
  /// （DEVELOPMENT 5.7），强制 GC。结构密钥随之清空，下次解锁从 MK 重新派生。
  void lock() {
    entries = const [];
    _shares = const [];
    _sharesKeyIds = const {};
    _sharesThreshold = 0;
    _sharesSecretDirty = false;
    _doubleKeys.clear();
    _structureKeys.clear();
    _structure = VaultStructure(keyEnvelopes: {});
    _pendingDoubleKeys.clear();
    mk.fillRange(0, mk.length, 0);
    _structureKey.fillRange(0, _structureKey.length, 0);
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
