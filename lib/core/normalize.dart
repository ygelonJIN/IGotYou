import 'package:unorm_dart/unorm_dart.dart' as unorm;

/// 命中判定前的口令规范化：去首尾空白 + NFC 规范化（DEVELOPMENT 3.3）。
String normalizeSecret(String raw) => unorm.nfc(raw.trim());