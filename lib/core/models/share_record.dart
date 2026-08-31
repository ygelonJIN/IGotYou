import 'dart:typed_data';

/// 份额记录（DEVELOPMENT 6.3），存于库文件的 SHARES 明文信封区。
/// [cipher] 为份额 y_i（32 字节）经该条目口令派生 KEK 加密后的密文 + 认证标签。
/// [nonce] 为对应 AES-GCM nonce。
class ShareRecord {
  final String entryId;
  final BigInt x;
  final Uint8List nonce;
  final Uint8List cipher;

  const ShareRecord({
    required this.entryId,
    required this.x,
    required this.nonce,
    required this.cipher,
  });

  ShareRecord copyWith({Uint8List? nonce, Uint8List? cipher}) => ShareRecord(
        entryId: entryId,
        x: x,
        nonce: nonce ?? this.nonce,
        cipher: cipher ?? this.cipher,
      );
}