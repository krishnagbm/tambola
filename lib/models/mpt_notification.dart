class MptNotification {
  final String id;
  final String userId;
  final String? gameId;
  final String type; // SEAT_CONFIRMED, CAPACITY_WARNING, GAME_STARTED, CLAIM_RESULT, REWARD_ISSUED
  final String title;
  final String message;
  final Map<String, dynamic>? payload;
  final bool isRead;
  final DateTime createdAt;

  MptNotification({
    required this.id,
    required this.userId,
    this.gameId,
    required this.type,
    required this.title,
    required this.message,
    this.payload,
    this.isRead = false,
    required this.createdAt,
  });

  factory MptNotification.fromJson(Map<String, dynamic> json) {
    return MptNotification(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      gameId: json['game_id'] as String?,
      type: json['type'] as String,
      title: json['title'] as String,
      message: json['message'] as String,
      payload: json['payload'] as Map<String, dynamic>?,
      isRead: json['is_read'] as bool? ?? false,
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at']) : DateTime.now(),
    );
  }
}
