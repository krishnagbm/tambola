class MptCapacityTier {
  final String id;
  final String name;
  final int minPlayers;
  final int maxPlayers;
  final int creditsRequired;
  final bool isActive;
  final int displayOrder;

  const MptCapacityTier({
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
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      minPlayers: json['min_players'] as int? ?? 1,
      maxPlayers: json['max_players'] as int? ?? 5,
      creditsRequired: json['credits_required'] as int? ?? 0,
      isActive: json['is_active'] as bool? ?? true,
      displayOrder: json['display_order'] as int? ?? 0,
    );
  }

  static const List<MptCapacityTier> defaultTiers = [
    MptCapacityTier(
      id: 'tier_1_5',
      name: 'Family Pack (1–5 Players)',
      minPlayers: 1,
      maxPlayers: 5,
      creditsRequired: 0,
      displayOrder: 1,
    ),
    MptCapacityTier(
      id: 'tier_6_15',
      name: 'Small Party (6–15 Players)',
      minPlayers: 6,
      maxPlayers: 15,
      creditsRequired: 15,
      displayOrder: 2,
    ),
    MptCapacityTier(
      id: 'tier_16_25',
      name: 'Medium Group (16–25 Players)',
      minPlayers: 16,
      maxPlayers: 25,
      creditsRequired: 25,
      displayOrder: 3,
    ),
    MptCapacityTier(
      id: 'tier_26_50',
      name: 'Large Group (26–50 Players)',
      minPlayers: 26,
      maxPlayers: 50,
      creditsRequired: 50,
      displayOrder: 4,
    ),
    MptCapacityTier(
      id: 'tier_51_100',
      name: 'Club Event (51–100 Players)',
      minPlayers: 51,
      maxPlayers: 100,
      creditsRequired: 100,
      displayOrder: 5,
    ),
    MptCapacityTier(
      id: 'tier_101_250',
      name: 'Mega Event (101–250 Players)',
      minPlayers: 101,
      maxPlayers: 250,
      creditsRequired: 250,
      displayOrder: 6,
    ),
  ];
}

