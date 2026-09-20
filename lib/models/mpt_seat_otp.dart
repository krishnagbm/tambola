class MptSeatOtp {
  final String id;
  final String gameId;
  final int seatNumber;
  final String otpCode;
  final String status; // 'UNCLAIMED', 'CLAIMED', 'REVOKED'
  final String? claimedByUserId;
  final DateTime? claimedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  MptSeatOtp({
    required this.id,
    required this.gameId,
    required this.seatNumber,
    required this.otpCode,
    this.status = 'UNCLAIMED',
    this.claimedByUserId,
    this.claimedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isClaimed => status == 'CLAIMED';
  bool get isUnclaimed => status == 'UNCLAIMED';
  bool get isRevoked => status == 'REVOKED';

  factory MptSeatOtp.fromJson(Map<String, dynamic> json) {
    return MptSeatOtp(
      id: json['id'] as String,
      gameId: json['game_id'] as String,
      seatNumber: json['seat_number'] as int? ?? 1,
      otpCode: json['otp_code'] as String? ?? '',
      status: json['status'] as String? ?? 'UNCLAIMED',
      claimedByUserId: json['claimed_by_user_id'] as String?,
      claimedAt: json['claimed_at'] != null ? DateTime.parse(json['claimed_at']) : null,
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at']) : DateTime.now(),
      updatedAt: json['updated_at'] != null ? DateTime.parse(json['updated_at']) : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'game_id': gameId,
      'seat_number': seatNumber,
      'otp_code': otpCode,
      'status': status,
      'claimed_by_user_id': claimedByUserId,
      'claimed_at': claimedAt?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}
