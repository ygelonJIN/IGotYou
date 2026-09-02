/// 维护层（结构）数据（方案三 17.20）：藏在 BODY 密文内、随主体一起受 MK 保护。
///
/// 结构密钥 SK = HMAC-SHA256(key: MK, msg: "IGOTYOU1:structure:v1")，
/// 每次解锁可重新派生（可恢复的维护凭证），用户无需记忆任何额外密码。
/// SK 只用于加密 [keyEnvelopes]——
/// 每个二次加密条目的口令（规范化后）以 AES-GCM 封套形式存于此处——
/// 份额重切（改 K / 增删钥匙 / 钥匙改密）需要该口令时直接解封套恢复，
/// 不再要求用户重新输入。封套内容是密文，明文口令只存在于会话内存。
///
/// 条目层（内容二次加密）与维护层彻底解耦：查看/修改条目内容仍需
/// 输入该条目的密码（见 VaultSession 门禁），维护层不感知"用户看过没有"。
class VaultStructure {
  /// 条目 id → 口令封套（base64(AES-GCM(SK, 规范化口令))）。
  /// 仅含二次加密条目（是否钥匙不限：非钥匙条目日后打开钥匙开关时
  /// 份额重切同样不再索要密码）。
  final Map<String, String> keyEnvelopes;

  const VaultStructure({this.keyEnvelopes = const {}});

  static const int currentVersion = 1;

  Map<String, Object> toJson() => {
    'v': currentVersion,
    'keyEnvelopes': keyEnvelopes,
  };

  factory VaultStructure.fromJson(Map<String, Object?>? json) {
    if (json == null) return const VaultStructure();
    return VaultStructure(
      keyEnvelopes: (json['keyEnvelopes'] as Map<String, Object?>? ?? const {})
          .map((k, v) => MapEntry(k, v! as String)),
    );
  }
}
