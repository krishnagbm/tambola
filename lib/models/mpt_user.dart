class MptUser {
  final String id;
  final String displayName;
  final String avatar;
  final bool isAnonymous;
  final DateTime createdAt;
  final DateTime updatedAt;

  MptUser({
    required this.id,
    required this.displayName,
    required this.avatar,
    this.isAnonymous = true,
    required this.createdAt,
    required this.updatedAt,
  });

  factory MptUser.fromJson(Map<String, dynamic> json) {
    return MptUser(
      id: json['id'] as String,
      displayName: json['display_name'] as String? ?? 'My Name',
      avatar: json['avatar'] as String? ?? 'avatar_1',
      isAnonymous: json['is_anonymous'] as bool? ?? true,
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at']) : DateTime.now(),
      updatedAt: json['updated_at'] != null ? DateTime.parse(json['updated_at']) : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'display_name': displayName,
      'avatar': avatar,
      'is_anonymous': isAnonymous,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  MptUser copyWith({
    String? displayName,
    String? avatar,
    bool? isAnonymous,
  }) {
    return MptUser(
      id: id,
      displayName: displayName ?? this.displayName,
      avatar: avatar ?? this.avatar,
      isAnonymous: isAnonymous ?? this.isAnonymous,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }
}
