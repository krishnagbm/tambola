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
      id: 'ba630f87-517a-44e2-8da9-e96e235d3c36',
      name: 'Family Pack (1–5 Players)',
      minPlayers: 1,
      maxPlayers: 5,
      creditsRequired: 0,
      displayOrder: 1,
    ),
    MptCapacityTier(
      id: '078da739-b20f-478e-b8af-3bf9da2bc193',
      name: 'Small Party (6–15 Players)',
      minPlayers: 6,
      maxPlayers: 15,
      creditsRequired: 15,
      displayOrder: 2,
    ),
    MptCapacityTier(
      id: '972884d4-b175-4bdf-abfe-3a4aa7e2e4c8',
      name: 'Standard Event (16–25 Players)',
      minPlayers: 16,
      maxPlayers: 25,
      creditsRequired: 25,
      displayOrder: 3,
    ),
    MptCapacityTier(
      id: 'edb014bd-e2f5-4881-bc7e-85edb105429f',
      name: 'Large Gala (26–100 Players)',
      minPlayers: 26,
      maxPlayers: 100,
      creditsRequired: 100,
      displayOrder: 4,
    ),
    MptCapacityTier(
      id: '0c195125-d897-4d0e-a4d0-12e39f77c991',
      name: 'Mega Event (101–250 Players)',
      minPlayers: 101,
      maxPlayers: 250,
      creditsRequired: 250,
      displayOrder: 6,
    ),
    MptCapacityTier(
      id: '38978e8f-f5f3-40b3-80e2-9c31c2b04d02',
      name: 'Corporate League (251–500 Players)',
      minPlayers: 251,
      maxPlayers: 500,
      creditsRequired: 500,
      displayOrder: 7,
    ),
    MptCapacityTier(
      id: 'c7b9ff1e-3ba0-4a8d-98c4-e0360335391b',
      name: 'Enterprise Gala (501–1000 Players)',
      minPlayers: 501,
      maxPlayers: 1000,
      creditsRequired: 1000,
      displayOrder: 8,
    ),
    MptCapacityTier(
      id: '2a7955e1-6932-43b1-84b1-0675d182db26',
      name: 'Coliseum / Global (1001–2500 Players)',
      minPlayers: 1001,
      maxPlayers: 2500,
      creditsRequired: 2500,
      displayOrder: 9,
    ),
  ];
}

