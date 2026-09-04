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
  });

  bool get isAvailable => status == 'AVAILABLE_TO_CLAIM';
  bool get isClaimed => status == 'CLAIMED';

  factory MptReward.fromJson(Map<String, dynamic> json) {
    return MptReward(
      id: json['id'] as String,
      gameId: json['game_id'] as String,
      userId: json['user_id'] as String,
      prizeType: json['prize_type'] as String,
      claimId: json['claim_id'] as String?,
      claimReference: json['claim_reference'] as String,
      status: json['status'] as String? ?? 'AVAILABLE_TO_CLAIM',
      verifiedByAdminId: json['verified_by_admin_id'] as String?,
      claimedAt: json['claimed_at'] != null ? DateTime.parse(json['claimed_at']) : null,
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at']) : DateTime.now(),
    );
  }
}
