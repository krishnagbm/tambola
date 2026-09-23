class MptUser {
  final String id;
  final String displayName;
  final String avatar;
  final String? avatarUrl;
  final String? email;
  final String? provider;
  final bool isAnonymous;
  final DateTime createdAt;
  final DateTime updatedAt;

  MptUser({
    required this.id,
    required this.displayName,
    required this.avatar,
    this.avatarUrl,
    this.email,
    this.provider,
    this.isAnonymous = true,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isRegistered => !isAnonymous || (email != null && email!.isNotEmpty);

  factory MptUser.fromJson(Map<String, dynamic> json) {
    return MptUser(
      id: json['id'] as String,
      displayName: json['display_name'] as String? ?? 'Lucky Dabber',
      avatar: json['avatar'] as String? ?? 'avatar_1',
      avatarUrl: json['avatar_url'] as String?,
      email: json['email'] as String?,
      provider: json['provider'] as String?,
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
      'avatar_url': avatarUrl,
      'email': email,
      'provider': provider,
      'is_anonymous': isAnonymous,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  MptUser copyWith({
    String? displayName,
    String? avatar,
    String? avatarUrl,
    String? email,
    String? provider,
    bool? isAnonymous,
  }) {
    return MptUser(
      id: id,
      displayName: displayName ?? this.displayName,
      avatar: avatar ?? this.avatar,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      email: email ?? this.email,
      provider: provider ?? this.provider,
      isAnonymous: isAnonymous ?? this.isAnonymous,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }
}

