class MptCalledNumber {
  final String id;
  final String gameId;
  final int number;
  final int callSeq;
  final DateTime calledAt;

  MptCalledNumber({
    required this.id,
    required this.gameId,
    required this.number,
    required this.callSeq,
    required this.calledAt,
  });

  factory MptCalledNumber.fromJson(Map<String, dynamic> json) {
    return MptCalledNumber(
      id: json['id'] as String,
      gameId: json['game_id'] as String,
      number: (json['number'] as num).toInt(),
      callSeq: (json['call_seq'] as num).toInt(),
      calledAt: json['called_at'] != null ? DateTime.parse(json['called_at']) : DateTime.now(),
    );
  }
}
