import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../crypto/argon2.dart';
import '../crypto/shamir.dart';
import '../models/share_record.dart';
import '../models/vault_config.dart';

const String _magic = 'IGOTYOU1';
final int _minSupportedVersion = 1;

/// 当前库文件版本（DEVELOPMENT 7.3）。
const int vaultFileVersion = 1;
const int _nonceLength = 12;
const int _macLength = 16;
const int _maxShares = 10000;
const int _maxEntryIdLength = 1024;
const int _maxShareCipherLength = 1024;
const int _maxBodyLength = 64 * 1024 * 1024;

/// 库文件解析/格式异常。
class VaultFileException implements Exception {
  final String message;
  VaultFileException(this.message);
  @override
  String toString() => message;
}

/// 文件头（纯文本，DEVELOPMENT 7.1）：非敏感派生参数 + 解锁参数镜像。
class VaultHeader {
  final int version;
  final Map<String, Object> argonParams;
  final Uint8List salt;
  final VaultConfig config;

  const VaultHeader({
    required this.version,
    required this.argonParams,
    required this.salt,
    required this.config,
  });

  Argon2Deriver get deriver => _deriverFromParams(argonParams, salt);

  Map<String, Object> toJson() => {
        'v': version,
        'argon': argonParams,
        'salt': base64Encode(salt),
        'config': config.toJson(),
      };

  factory VaultHeader.fromJson(Map<String, Object?> json) {
    final version = (json['v']! as num).toInt();
    if (version < _minSupportedVersion || version > vaultFileVersion) {
      throw VaultFileException(version > vaultFileVersion ? '备份版本过高，请升级应用' : '文件损坏');
    }
    return VaultHeader(
      version: version,
      argonParams: (json['argon']! as Map).cast<String, Object>(),
      salt: base64Decode(json['salt']! as String),
      config: VaultConfig.fromJson(json['config']! as Map<String, Object?>),
    );
  }
}

Argon2Deriver _deriverFromParams(Map<String, Object> params, Uint8List salt) {
  try {
    final memory = (params['memory']! as num).toInt();
    final iterations = (params['iterations']! as num).toInt();
    final parallelism = (params['parallelism']! as num).toInt();
    final hashLength = (params['hashLength']! as num).toInt();
    if (memory < 8 * 1024 || memory > 1024 * 1024 ||
        iterations < 1 || iterations > 100 ||
        parallelism < 1 || parallelism > 16 ||
        hashLength < 32 || hashLength > 128 ||
        salt.length < 16 || salt.length > 64) {
      throw VaultFileException('文件损坏');
    }
    return Argon2Deriver(
      memory: memory,
      iterations: iterations,
      parallelism: parallelism,
      hashLength: hashLength,
      salt: salt,
    );
  } on VaultFileException {
    rethrow;
  } on Object catch (_) {
    throw VaultFileException('文件损坏');
  }
}

/// 已解析的库文件元数据。
class VaultFileData {
  final String path;
  final VaultHeader header;
  final List<ShareRecord> shares;
  final int bodyOffset;
  final int bodyLength; // nonce+cipher+tag

  VaultFileData({
    required this.path,
    required this.header,
    required this.shares,
    required this.bodyOffset,
    required this.bodyLength,
  });
}

class VaultFile {
  VaultFile._();

  static bool exists(String path) => File(path).existsSync();

  /// 写库文件（替换原文件，原子替换）。所有载荷均已加密：
  /// [body] 为 BODY 密文（nonce+cipher+tag）。
  static Future<void> write(
    String path, {
    required VaultHeader header,
    required List<ShareRecord> shares,
    required Uint8List body,
  }) async {
    if (shares.length > _maxShares) {
      throw VaultFileException('文件过大');
    }
    if (body.length < _nonceLength + _macLength ||
        body.length > _maxBodyLength) {
      throw VaultFileException('文件损坏');
    }
    for (final s in shares) {
      if (s.entryId.isEmpty ||
          utf8.encode(s.entryId).length > _maxEntryIdLength ||
          s.nonce.length != _nonceLength ||
          s.cipher.length < 32 + _macLength ||
          s.cipher.length > _maxShareCipherLength ||
          s.x <= BigInt.zero ||
          s.x >= Shamir.primeP) {
        throw VaultFileException('文件损坏');
      }
    }
    final tmp = File('$path.tmp');
    if (await tmp.exists()) await tmp.delete();
    final sink = tmp.openWrite();
    try {
      try {
        sink.add(ascii.encode(_magic));
        sink.add(const [0x0A]);
        sink.add(ascii.encode(jsonEncode(header.toJson())));
        sink.add(const [0x0A]);

        // ── SHARES ──
        sink.add(_u32(shares.length));
        for (final s in shares) {
          final id = utf8.encode(s.entryId);
          sink.add(_u16(id.length));
          sink.add(id);
          sink.add(ShamirShims.bigIntToBytes(s.x));
          sink.add(_u16(s.nonce.length));
          sink.add(s.nonce);
          sink.add(_u32(s.cipher.length));
          sink.add(s.cipher);
        }

        // ── BODY ──
        sink.add(_u32(body.length));
        sink.add(body);
        await sink.flush();
      } finally {
        await sink.close();
      }
      await tmp.rename(path);
      await read(path);
    } catch (_) {
      if (await tmp.exists()) await tmp.delete();
      rethrow;
    }
  }

  /// 4 字节大端整数（立即拷贝，避免 IOSink 延迟 flush 共享 buffer）。
  static Uint8List _u32(int v) {
    final b = ByteData(4)..setUint32(0, v);
    return Uint8List.fromList(b.buffer.asUint8List());
  }

  /// 2 字节大端整数（立即拷贝）。
  static Uint8List _u16(int v) {
    final b = ByteData(2)..setUint16(0, v);
    return Uint8List.fromList(b.buffer.asUint8List());
  }

  static Future<VaultFileData> read(String path) async {
    final file = File(path);
    if (!await file.exists()) throw VaultFileException('文件不存在');
    final random = await file.open();
    try {
      var pos = 0;

      final magicBuf = Uint8List(_magic.length + 1);
      pos = await _readFully(random, magicBuf, pos);
      if (ascii.decode(magicBuf.sublist(0, _magic.length)) != _magic) {
        throw VaultFileException('文件损坏');
      }

      final headerJson = await _readLine(random, pos);
      pos = headerJson.$2;
      final header = VaultHeader.fromJson(
        jsonDecode(utf8.decode(headerJson.$1)) as Map<String, Object?>,
      );

      // ── SHARES ──
      final fileLength = await random.length();
      if (fileLength > _maxBodyLength + 16 * 1024 * 1024) {
        throw VaultFileException('文件过大');
      }
      final shareCount = await _readU32(random, pos);
      pos += 4;
      if (shareCount > _maxShares) throw VaultFileException('文件过大');
      final shares = <ShareRecord>[];
      for (var i = 0; i < shareCount; i++) {
        final idLen = await _readU16(random, pos);
        pos += 2;
        if (idLen == 0 || idLen > _maxEntryIdLength) {
          throw VaultFileException('文件损坏');
        }
        final idBytes = await _readBytes(random, pos, idLen);
        pos += idLen;
        final xBytes = await _readBytes(random, pos, 32);
        pos += 32;
        final nonceLen = await _readU16(random, pos);
        pos += 2;
        if (nonceLen != _nonceLength) throw VaultFileException('文件损坏');
        final nonce = await _readBytes(random, pos, nonceLen);
        pos += nonceLen;
        final cipherLen = await _readU32(random, pos);
        pos += 4;
        if (cipherLen < 32 + _macLength || cipherLen > _maxShareCipherLength) {
          throw VaultFileException('文件损坏');
        }
        final cipher = await _readBytes(random, pos, cipherLen);
        pos += cipherLen;
        if (nonce.length != _nonceLength) throw VaultFileException('文件损坏');
        shares.add(ShareRecord(
          entryId: utf8.decode(idBytes),
          x: ShamirShims.bytesToBigInt(xBytes),
          nonce: nonce,
          cipher: cipher,
        ));
      }

      // ── BODY ──
      final bodyLen = await _readU32(random, pos);
      pos += 4;
      if (bodyLen < _nonceLength + _macLength || bodyLen > _maxBodyLength) {
        throw VaultFileException('文件损坏');
      }
      final bodyOffset = pos;
      pos += bodyLen;
      if (pos != fileLength) throw VaultFileException('文件损坏');

      return VaultFileData(
        path: path,
        header: header,
        shares: shares,
        bodyOffset: bodyOffset,
        bodyLength: bodyLen,
      );
    } finally {
      await random.close();
    }
  }

  /// 顺序读取 fileLen 字节（落到给定 buffer），返回新游标。
  static Future<int> _readFully(
    RandomAccessFile random,
    Uint8List buffer,
    int pos,
  ) async {
    await random.setPosition(pos);
    var got = 0;
    while (got < buffer.length) {
      final n = await random.readInto(buffer, got);
      if (n == 0) break;
      got += n;
    }
    if (got < buffer.length) throw VaultFileException('文件损坏');
    return pos + buffer.length;
  }

  static Future<Uint8List> _readBytes(RandomAccessFile random, int pos, int len) async {
    final b = Uint8List(len);
    await _readFully(random, b, pos);
    return b;
  }

  static Future<int> _readByte(RandomAccessFile random, int pos) async {
    final b = await _readBytes(random, pos, 1);
    return b[0];
  }

  static Future<int> _readU16(RandomAccessFile random, int pos) async {
    final d = ByteData.sublistView(await _readBytes(random, pos, 2));
    return d.getUint16(0);
  }

  static Future<int> _readU32(RandomAccessFile random, int pos) async {
    final d = ByteData.sublistView(await _readBytes(random, pos, 4));
    return d.getUint32(0);
  }

  /// 从 pos 读到下一换行，返回 (行字节, 新游标)。
  static Future<(Uint8List, int)> _readLine(RandomAccessFile random, int pos) async {
    final buf = BytesBuilder(copy: false);
    while (true) {
      final b = await _readByte(random, pos);
      pos++;
      if (b == 0x0A) break;
      buf.addByte(b);
    }
    return (buf.toBytes(), pos);
  }

  /// 读取 BODY 密文区（nonce+cipher+tag）。
  static Future<Uint8List> readBody(VaultFileData data) async {
    final bytes = await File(data.path).readAsBytes();
    return bytes.sublist(
      data.bodyOffset,
      data.bodyOffset + data.bodyLength,
    );
  }
}

/// 尺寸/游标等字节转换的轻量粘合（供文件与份额区共用）。
class ShamirShims {
  ShamirShims._();

  static Uint8List bigIntToBytes(BigInt v) => Shamir.bigIntToBytes32(v);
  static BigInt bytesToBigInt(Uint8List b) => ShamirShims._b(b);

  static BigInt _b(Uint8List bytes) {
    var v = BigInt.zero;
    for (final x in bytes) {
      v = (v << 8) | BigInt.from(x);
    }
    return v;
  }
}