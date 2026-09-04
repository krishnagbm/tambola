class MptTicket {
  final String id;
  final String gameId;
  final String userId;
  final List<List<int>> matrix; // 3x9 grid
  final int ticketNumber;
  final DateTime issuedAt;

  MptTicket({
    required this.id,
    required this.gameId,
    required this.userId,
    required this.matrix,
    this.ticketNumber = 1,
    required this.issuedAt,
  });

  factory MptTicket.fromJson(Map<String, dynamic> json) {
    List<List<int>> parseMatrix(dynamic raw) {
      if (raw is List) {
        return raw.map<List<int>>((row) {
          if (row is List) {
            return row.map<int>((c) => (c as num).toInt()).toList();
          }
          return List.filled(9, 0);
        }).toList();
      }
      return List.generate(3, (_) => List.filled(9, 0));
    }

    return MptTicket(
      id: json['id'] as String,
      gameId: json['game_id'] as String,
      userId: json['user_id'] as String,
      matrix: parseMatrix(json['ticket_matrix']),
      ticketNumber: (json['ticket_number'] as num?)?.toInt() ?? 1,
      issuedAt: json['issued_at'] != null ? DateTime.parse(json['issued_at']) : DateTime.now(),
    );
  }
}
