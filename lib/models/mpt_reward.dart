class MptReward {
  final String id;
  final String gameId;
  final String userId;
  final String prizeType;
  final String? claimId;
  final String claimReference;
  final String status; // AVAILABLE_TO_CLAIM, CLAIMED, VOID
  final String? verifiedByAdminId;
  final DateTime? claimedAt;
  final DateTime createdAt;

  // Enriched game & organizer context (joined from MPT_games / MPT_users)
  final String? gameName;
  final String? inviteCode;
  final DateTime? gameDate;
  final String? organizerName;

  // Enriched winner context (for Organizer claims management)
  final String? winnerName;
  final String? winnerAvatar;

  MptReward({
    required this.id,
    required this.gameId,
    required this.userId,
    required this.prizeType,
    this.claimId,
    required this.claimReference,
    required this.status,
    this.verifiedByAdminId,
    this.claimedAt,
    required this.createdAt,
    this.gameName,
    this.inviteCode,
    this.gameDate,
    this.organizerName,
    this.winnerName,
    this.winnerAvatar,
  });

  bool get isAvailable => status == 'AVAILABLE_TO_CLAIM';
  bool get isClaimed => status == 'CLAIMED';

  factory MptReward.fromJson(Map<String, dynamic> json) {
    // Game context may be nested under a 'MPT_games' key (Supabase join)
    final gameMap = json['MPT_games'] as Map<String, dynamic>?;
    // Organizer name may be nested under 'MPT_users' inside the game map
    final organizerMap = gameMap?['MPT_users'] as Map<String, dynamic>?;

    DateTime? gameDate;
    if (gameMap != null) {
      final raw =
          gameMap['completed_at'] ??
          gameMap['started_at'] ??
          gameMap['created_at'];
      if (raw != null) gameDate = DateTime.tryParse(raw.toString());
    } else if (json['game_date'] != null) {
      gameDate = DateTime.tryParse(json['game_date'].toString());
    }

    return MptReward(
      id: json['id'].toString(),
      gameId: json['game_id'].toString(),
      userId: json['user_id'].toString(),
      prizeType: json['prize_type'].toString(),
      claimId: json['claim_id']?.toString(),
      claimReference: json['claim_reference'].toString(),
      status: json['status'] as String? ?? 'AVAILABLE_TO_CLAIM',
      verifiedByAdminId: json['verified_by_admin_id']?.toString(),
      claimedAt: json['claimed_at'] != null
          ? DateTime.tryParse(json['claimed_at'].toString())
          : null,
      createdAt: json['created_at'] != null
          ? (DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now())
          : DateTime.now(),
      gameName:
          (gameMap?['name'] as String?) ?? (json['game_name'] as String?),
      inviteCode:
          (gameMap?['invite_code'] as String?) ??
          (json['invite_code'] as String?),
      gameDate: gameDate,
      organizerName:
          (organizerMap?['display_name'] as String?) ??
          (json['organizer_name'] as String?),
      winnerName: json['winner_name'] as String?,
      winnerAvatar: json['winner_avatar'] as String?,
    );
  }
}
