class MptCapacityTier {
  final String id;
  final String name;
  final int minPlayers;
  final int maxPlayers;
  final int creditsRequired;
  final bool isActive;
  final int displayOrder;

  MptCapacityTier({
    required this.id,
    required this.name,
    required this.minPlayers,
    required this.maxPlayers,
    required this.creditsRequired,
    this.isActive = true,
    this.displayOrder = 0,
  });

  factory MptCapacityTier.fromJson(Map<String, dynamic> json) {
    return MptCapacityTier(
      id: json['id'] as String,
      name: json['name'] as String,
      minPlayers: json['min_players'] as int,
      maxPlayers: json['max_players'] as int,
      creditsRequired: json['credits_required'] as int,
      isActive: json['is_active'] as bool? ?? true,
      displayOrder: json['display_order'] as int? ?? 0,
    );
  }
}
