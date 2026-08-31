/// 保险柜条目，固定三行：名称、加密密钥、内容。
///
/// [doubleLocked] 为 true 时（二次加密条目）：`secret`/`note` 不在文件中存明文
/// （存储值为空串），内容整体加密在 [doubleCipher]（独立盐 [doubleSalt] 派生 KEK），
/// 查看时输入加密密钥现场解密。明文密钥只在会话内存缓存，不落盘。
class Entry {
  final String id;
  final String name;
  final String secret;
  final String note;
  final bool isKey;
  final bool doubleLocked;
  final String? doubleCipher;
  final String? doubleSalt;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Entry({
    required this.id,
    required this.name,
    required this.secret,
    required this.note,
    required this.isKey,
    this.doubleLocked = false,
    this.doubleCipher,
    this.doubleSalt,
    required this.createdAt,
    required this.updatedAt,
  });

  Entry copyWith({
    String? name,
    String? secret,
    String? note,
    bool? isKey,
    bool? doubleLocked,
    String? doubleCipher,
    String? doubleSalt,
    DateTime? updatedAt,
  }) =>
      Entry(
        id: id,
        name: name ?? this.name,
        secret: secret ?? this.secret,
        note: note ?? this.note,
        isKey: isKey ?? this.isKey,
        doubleLocked: doubleLocked ?? this.doubleLocked,
        doubleCipher: doubleCipher ?? this.doubleCipher,
        doubleSalt: doubleSalt ?? this.doubleSalt,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'secret': secret,
        'note': note,
        'isKey': isKey,
        'doubleLocked': doubleLocked,
        if (doubleCipher != null) 'doubleCipher': doubleCipher,
        if (doubleSalt != null) 'doubleSalt': doubleSalt,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory Entry.fromJson(Map<String, Object?> json) => Entry(
        id: json['id']! as String,
        name: json['name']! as String,
        secret: (json['secret'] ?? '') as String,
        note: (json['note'] ?? '') as String,
        isKey: (json['isKey'] ?? false) as bool,
        doubleLocked: (json['doubleLocked'] ?? false) as bool,
        doubleCipher: json['doubleCipher'] as String?,
        doubleSalt: json['doubleSalt'] as String?,
        createdAt: DateTime.parse(json['createdAt']! as String),
        updatedAt: DateTime.parse(json['updatedAt']! as String),
      );
}
