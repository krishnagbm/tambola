class MptClaim {
  final String id;
  final String gameId;
  final String userId;
  final String prizeType;
  final String status; // SUBMITTED, APPROVED, REJECTED, BOGEY
  final String? rejectionReason;
  final String? userName;
  final String? userAvatar;
  final DateTime submittedAt;
  final DateTime? processedAt;

  MptClaim({
    required this.id,
    required this.gameId,
    required this.userId,
    required this.prizeType,
    required this.status,
    this.rejectionReason,
    this.userName,
    this.userAvatar,
    required this.submittedAt,
    this.processedAt,
  });

  factory MptClaim.fromJson(Map<String, dynamic> json) {
    final userData = json['user'] as Map<String, dynamic>?;
    return MptClaim(
      id: json['id'] as String,
      gameId: json['game_id'] as String,
      userId: json['user_id'] as String,
      prizeType: json['prize_type'] as String,
      status: json['status'] as String? ?? 'SUBMITTED',
      rejectionReason: json['rejection_reason'] as String?,
      userName: userData?['display_name'] as String?,
      userAvatar: userData?['avatar'] as String?,
      submittedAt: json['submitted_at'] != null ? DateTime.parse(json['submitted_at']) : DateTime.now(),
      processedAt: json['processed_at'] != null ? DateTime.parse(json['processed_at']) : null,
    );
  }
}
