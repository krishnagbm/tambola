class MptGame {
  final String id;
  final String adminUserId;
  final String name;
  final String inviteCode;
  final String status; // DRAFT, OPEN, READY_TO_START, STARTING, IN_PROGRESS, COMPLETED, CLOSED
  final String? plannedCapacityTierId;
  final int initialFundedCapacity;
  final int fundedCapacity;
  final int? finalCapacity;
  final DateTime? scheduledAt;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final List<String> prizesConfig;
  final int stateVersion;
  final DateTime createdAt;
  final DateTime updatedAt;

  MptGame({
    required this.id,
    required this.adminUserId,
    required this.name,
    required this.inviteCode,
    required this.status,
    this.plannedCapacityTierId,
    required this.initialFundedCapacity,
    required this.fundedCapacity,
    this.finalCapacity,
    this.scheduledAt,
    this.startedAt,
    this.completedAt,
    required this.prizesConfig,
    this.stateVersion = 1,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isOpen => status == 'OPEN' || status == 'READY_TO_START';
  bool get isLobbyOpen => isOpen;
  bool get isInProgress => status == 'IN_PROGRESS';
  bool get isCompleted => status == 'COMPLETED' || status == 'CLOSED';

  factory MptGame.fromJson(Map<String, dynamic> json) {
    List<String> parsePrizes(dynamic val) {
      if (val is List) {
        return val.map((e) => e.toString()).toList();
      }
      return ['EARLY_FIVE', 'TOP_LINE', 'MIDDLE_LINE', 'BOTTOM_LINE', 'FOUR_CORNERS', 'FULL_HOUSE'];
    }

    return MptGame(
      id: json['id'] as String,
      adminUserId: json['admin_user_id'] as String,
      name: json['name'] as String,
      inviteCode: json['invite_code'] as String,
      status: json['status'] as String? ?? 'OPEN',
      plannedCapacityTierId: json['planned_capacity_tier_id'] as String?,
      initialFundedCapacity: json['initial_funded_capacity'] as int? ?? 25,
      fundedCapacity: json['funded_capacity'] as int? ?? 25,
      finalCapacity: json['final_capacity'] as int?,
      scheduledAt: json['scheduled_at'] != null ? DateTime.parse(json['scheduled_at']) : null,
      startedAt: json['started_at'] != null ? DateTime.parse(json['started_at']) : null,
      completedAt: json['completed_at'] != null ? DateTime.parse(json['completed_at']) : null,
      prizesConfig: parsePrizes(json['prizes_config']),
      stateVersion: json['state_version'] as int? ?? 1,
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at']) : DateTime.now(),
      updatedAt: json['updated_at'] != null ? DateTime.parse(json['updated_at']) : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'admin_user_id': adminUserId,
      'name': name,
      'invite_code': inviteCode,
      'status': status,
      'planned_capacity_tier_id': plannedCapacityTierId,
      'initial_funded_capacity': initialFundedCapacity,
      'funded_capacity': fundedCapacity,
      'final_capacity': finalCapacity,
      'scheduled_at': scheduledAt?.toIso8601String(),
      'started_at': startedAt?.toIso8601String(),
      'completed_at': completedAt?.toIso8601String(),
      'prizes_config': prizesConfig,
      'state_version': stateVersion,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}
