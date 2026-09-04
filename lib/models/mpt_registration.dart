class MptRegistration {
  final String id;
  final String gameId;
  final String userId;
  final String displayName;
  final String avatar;
  final int registrationSeq;
  final String seatStatus; // CONFIRMED, WAITING, ELIGIBLE, NOT_ELIGIBLE, CANCELLED
  final DateTime joinedAt;
  final DateTime updatedAt;

  MptRegistration({
    required this.id,
    required this.gameId,
    required this.userId,
    required this.displayName,
    required this.avatar,
    required this.registrationSeq,
    required this.seatStatus,
    required this.joinedAt,
    required this.updatedAt,
  });

  bool get isConfirmed => seatStatus == 'CONFIRMED' || seatStatus == 'ELIGIBLE';
  bool get isWaiting => seatStatus == 'WAITING';
  bool get isEligible => seatStatus == 'ELIGIBLE';
  bool get isNotEligible => seatStatus == 'NOT_ELIGIBLE';

  factory MptRegistration.fromJson(Map<String, dynamic> json) {
    return MptRegistration(
      id: json['id'] as String,
      gameId: json['game_id'] as String,
      userId: json['user_id'] as String,
      displayName: json['display_name'] as String? ?? 'Player',
      avatar: json['avatar'] as String? ?? 'avatar_1',
      registrationSeq: (json['registration_seq'] as num).toInt(),
      seatStatus: json['seat_status'] as String? ?? 'CONFIRMED',
      joinedAt: json['joined_at'] != null ? DateTime.parse(json['joined_at']) : DateTime.now(),
      updatedAt: json['updated_at'] != null ? DateTime.parse(json['updated_at']) : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'game_id': gameId,
      'user_id': userId,
      'display_name': displayName,
      'avatar': avatar,
      'registration_seq': registrationSeq,
      'seat_status': seatStatus,
      'joined_at': joinedAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}
