class MptTriviaQuestion {
  final String id;
  final String category;
  final String categoryName;
  final String question;
  final List<String> options;
  final int correctIndex;
  final String correctAnswer;

  MptTriviaQuestion({
    required this.id,
    required this.category,
    required this.categoryName,
    required this.question,
    required this.options,
    required this.correctIndex,
    required this.correctAnswer,
  });

  factory MptTriviaQuestion.fromJson(Map<String, dynamic> json) {
    return MptTriviaQuestion(
      id: json['id'] as String? ?? '',
      category: json['category'] as String? ?? 'GENERAL',
      categoryName: json['category_name'] as String? ?? 'Recall Challenge',
      question: json['question'] as String? ?? '',
      options: (json['options'] as List?)?.map((e) => e.toString()).toList() ?? [],
      correctIndex: (json['correct_index'] as num?)?.toInt() ?? 0,
      correctAnswer: json['correct_answer'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'category': category,
    'category_name': categoryName,
    'question': question,
    'options': options,
    'correct_index': correctIndex,
    'correct_answer': correctAnswer,
  };
}

class MptGameTriviaRound {
  final String id;
  final String gameId;
  final List<MptTriviaQuestion> questions;
  final String status; // PENDING, COUNTDOWN, ACTIVE, COMPLETED
  final int timeGapSeconds;
  final int secondsPerQuestion;
  final int currentQuestionIndex;
  final DateTime? startsAt;
  final DateTime? startedAt;
  final DateTime? completedAt;

  MptGameTriviaRound({
    required this.id,
    required this.gameId,
    required this.questions,
    required this.status,
    required this.timeGapSeconds,
    this.secondsPerQuestion = 15,
    this.currentQuestionIndex = 0,
    this.startsAt,
    this.startedAt,
    this.completedAt,
  });

  bool get isCountdown => status == 'COUNTDOWN' && completedAt == null;
  bool get isActive => status == 'ACTIVE' && completedAt == null;
  bool get isCompleted => status == 'COMPLETED' || completedAt != null;

  factory MptGameTriviaRound.fromJson(Map<String, dynamic> json) {
    final rawQ = json['questions'];
    final qList = <MptTriviaQuestion>[];
    if (rawQ is List) {
      for (final item in rawQ) {
        if (item is Map<String, dynamic>) {
          qList.add(MptTriviaQuestion.fromJson(item));
        } else if (item is Map) {
          qList.add(MptTriviaQuestion.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }

    return MptGameTriviaRound(
      id: json['id'] as String,
      gameId: json['game_id'] as String,
      questions: qList,
      status: json['status'] as String? ?? 'PENDING',
      timeGapSeconds: (json['time_gap_seconds'] as num?)?.toInt() ?? 15,
      secondsPerQuestion: (json['seconds_per_question'] as num?)?.toInt() ?? 15,
      currentQuestionIndex: (json['current_question_index'] as num?)?.toInt() ?? 0,
      startsAt: json['starts_at'] != null ? DateTime.parse(json['starts_at']).toLocal() : null,
      startedAt: json['started_at'] != null ? DateTime.parse(json['started_at']).toLocal() : null,
      completedAt: json['completed_at'] != null ? DateTime.parse(json['completed_at']).toLocal() : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MptGameTriviaRound &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          status == other.status &&
          currentQuestionIndex == other.currentQuestionIndex;

  @override
  int get hashCode => Object.hash(id, status, currentQuestionIndex);
}

class MptTriviaWinner {
  final String id;
  final String gameId;
  final String userId;
  final String userName;
  final String? userAvatar;
  final int rank;
  final int totalScore;
  final int correctCount;
  final int avgResponseTimeMs;
  final String title;

  MptTriviaWinner({
    required this.id,
    required this.gameId,
    required this.userId,
    required this.userName,
    this.userAvatar,
    required this.rank,
    required this.totalScore,
    required this.correctCount,
    required this.avgResponseTimeMs,
    required this.title,
  });

  factory MptTriviaWinner.fromJson(Map<String, dynamic> json) {
    return MptTriviaWinner(
      id: json['id'] as String,
      gameId: json['game_id'] as String,
      userId: json['user_id'] as String,
      userName: json['user_name'] as String? ?? 'Player',
      userAvatar: json['user_avatar'] as String?,
      rank: (json['rank'] as num?)?.toInt() ?? 1,
      totalScore: (json['total_score'] as num?)?.toInt() ?? 0,
      correctCount: (json['correct_count'] as num?)?.toInt() ?? 0,
      avgResponseTimeMs: (json['avg_response_time_ms'] as num?)?.toInt() ?? 0,
      title: json['title'] as String? ?? 'Observation Champ 🥇',
    );
  }
}
