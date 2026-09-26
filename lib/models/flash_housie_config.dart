import 'dart:math';

/// Represents the current visual phase of the proprietary NeuroWave™ Spotlight
/// for an active FlashHousie™ cycle.
enum NeuroWavePhase {
  /// Waiting for the host to start the cycle/game
  waitingToStart,

  /// Dynamic stage readiness countdown before the column wave fires
  stageReadiness,

  /// Active column-by-column spotlight wave (only [visibleColumn] is unmasked)
  columnWave,

  /// 5-second memory consolidation pause between active quadrants (FlashHousie 10/15)
  memoryLockInPause,

  /// NeuroWave™ sweep finished; cells are masked [?] and ball calling is active
  callingActive,
}

class NeuroWaveState {
  final NeuroWavePhase phase;
  final int? visibleColumn; // 0..8 when phase == NeuroWavePhase.columnWave
  final int? activeQuadrant; // 1, 2, or 3 during wave/pause
  final int remainingSeconds;
  final double progress; // 0.0 to 1.0
  final String statusLabel;

  const NeuroWaveState({
    required this.phase,
    this.visibleColumn,
    this.activeQuadrant,
    required this.remainingSeconds,
    required this.progress,
    required this.statusLabel,
  });

  bool get isCallingReady => phase == NeuroWavePhase.callingActive;
  bool get isRevealing =>
      phase == NeuroWavePhase.stageReadiness ||
      phase == NeuroWavePhase.columnWave ||
      phase == NeuroWavePhase.memoryLockInPause;

  int get remainingMsInPhase => remainingSeconds * 1000;
}

class FlashHousieCycleSpec {
  final int cycleIndex; // 1-based
  final String label; // e.g. 'R1-Q2', 'R2-Q1+Q3'
  final String prizeKey; // e.g. 'ROUND_1'
  final List<int> activeQuadrants; // Subset of [1, 2, 3]
  final List<List<int>> ticketMatrix; // 3x9 matrix
  final List<int> trueNumbers;
  final List<int> decoyNumbers;
  final List<int> drawPool;
  final List<int> calledNumbers;
  final int? startedAtMs;
  final int randomLaunchDelaySec; // 5..9 seconds
  final String? winnerUserId;
  final String? winnerName;
  final String? winnerAvatar;
  final int? winnerCorrectCount;
  final int? winnerReactionMs;

  const FlashHousieCycleSpec({
    required this.cycleIndex,
    required this.label,
    required this.prizeKey,
    required this.activeQuadrants,
    required this.ticketMatrix,
    required this.trueNumbers,
    required this.decoyNumbers,
    required this.drawPool,
    this.calledNumbers = const [],
    this.startedAtMs,
    this.randomLaunchDelaySec = 6,
    this.winnerUserId,
    this.winnerName,
    this.winnerAvatar,
    this.winnerCorrectCount,
    this.winnerReactionMs,
  });

  String get roundBadgeLabel => label;

  int get calledCount => calledNumbers.length;

  bool get isCompleted => calledNumbers.length >= drawPool.length && drawPool.isNotEmpty;

  int? get latestCalledNumber => calledNumbers.isNotEmpty ? calledNumbers.last : null;

  bool isColumnInActiveQuadrant(int col) {
    final q = (col ~/ 3) + 1;
    return activeQuadrants.contains(q);
  }

  /// Calculates the live NeuroWave™ Spotlight state at [nowMs]
  /// (Internal engineering note: random launch delay + single-column 1.8s wave
  /// ensures all numbers in a quadrant never appear in the same frame).
  NeuroWaveState computeNeuroWaveState(int nowMs) {
    if (startedAtMs == null) {
      return const NeuroWaveState(
        phase: NeuroWavePhase.waitingToStart,
        remainingSeconds: 0,
        progress: 0.0,
        statusLabel: 'Waiting for Host to Launch Round...',
      );
    }

    // If balls have already been called in this cycle, spotlight is complete
    if (calledNumbers.isNotEmpty) {
      return const NeuroWaveState(
        phase: NeuroWavePhase.callingActive,
        remainingSeconds: 0,
        progress: 1.0,
        statusLabel: 'NeuroWave™ Locked • Tap Recalled Cells!',
      );
    }

    final elapsedMs = max(0, nowMs - startedAtMs!);
    final launchDelayMs = randomLaunchDelaySec * 1000;

    // 1. Dynamic Stage Readiness Window (Displayed as a 12s countdown that launches at launchDelayMs)
    if (elapsedMs < launchDelayMs) {
      const displayTotalMs = 12000;
      final fakeRemainingSec = ((displayTotalMs - elapsedMs) / 1000).ceil().clamp(1, 15);
      return NeuroWaveState(
        phase: NeuroWavePhase.stageReadiness,
        remainingSeconds: fakeRemainingSec,
        progress: (elapsedMs / displayTotalMs).clamp(0.0, 1.0),
        statusLabel: '⚡ NeuroWave™ Spotlight Preparing... Focus on Grid ($fakeRemainingSec s)',
      );
    }

    // 2. Column-by-Column Wave (1800ms per column = 5400ms per quadrant) + 5000ms pause between quadrants
    const colDurationMs = 1800;
    const quadWaveMs = colDurationMs * 3; // 5400ms
    const pauseBetweenQuadsMs = 5000;

    int waveElapsedMs = elapsedMs - launchDelayMs;
    for (int i = 0; i < activeQuadrants.length; i++) {
      final q = activeQuadrants[i];
      if (waveElapsedMs < quadWaveMs) {
        final colOffset = (waveElapsedMs ~/ colDurationMs).clamp(0, 2);
        final globalCol = (q - 1) * 3 + colOffset;
        final colRemainingMs = quadWaveMs - waveElapsedMs;
        return NeuroWaveState(
          phase: NeuroWavePhase.columnWave,
          visibleColumn: globalCol,
          activeQuadrant: q,
          remainingSeconds: (colRemainingMs / 1000).ceil().clamp(1, 6),
          progress: (waveElapsedMs / quadWaveMs).clamp(0.0, 1.0),
          statusLabel: '🔦 NeuroWave™ Spotlight: Quadrant Q$q • Column ${colOffset + 1} of 3',
        );
      }
      waveElapsedMs -= quadWaveMs;

      // If there is another quadrant after this one, insert 5-second Memory Lock-In Pause
      if (i < activeQuadrants.length - 1) {
        if (waveElapsedMs < pauseBetweenQuadsMs) {
          final pauseRemSec = ((pauseBetweenQuadsMs - waveElapsedMs) / 1000).ceil().clamp(1, 5);
          final nextQ = activeQuadrants[i + 1];
          return NeuroWaveState(
            phase: NeuroWavePhase.memoryLockInPause,
            activeQuadrant: q,
            remainingSeconds: pauseRemSec,
            progress: (waveElapsedMs / pauseBetweenQuadsMs).clamp(0.0, 1.0),
            statusLabel: '🧠 Lock Q$q in Memory! Next Spotlight (Q$nextQ) in ${pauseRemSec}s...',
          );
        }
        waveElapsedMs -= pauseBetweenQuadsMs;
      }
    }

    // 3. Wave complete -> Ready for ball calls!
    return const NeuroWaveState(
      phase: NeuroWavePhase.callingActive,
      remainingSeconds: 0,
      progress: 1.0,
      statusLabel: '🔒 Grid Locked! Listen to Caller & Tap Matching Cell!',
    );
  }

  FlashHousieCycleSpec copyWith({
    List<int>? calledNumbers,
    int? startedAtMs,
    String? winnerUserId,
    String? winnerName,
    String? winnerAvatar,
    int? winnerCorrectCount,
    int? winnerReactionMs,
  }) {
    return FlashHousieCycleSpec(
      cycleIndex: cycleIndex,
      label: label,
      prizeKey: prizeKey,
      activeQuadrants: activeQuadrants,
      ticketMatrix: ticketMatrix,
      trueNumbers: trueNumbers,
      decoyNumbers: decoyNumbers,
      drawPool: drawPool,
      calledNumbers: calledNumbers ?? this.calledNumbers,
      startedAtMs: startedAtMs ?? this.startedAtMs,
      randomLaunchDelaySec: randomLaunchDelaySec,
      winnerUserId: winnerUserId ?? this.winnerUserId,
      winnerName: winnerName ?? this.winnerName,
      winnerAvatar: winnerAvatar ?? this.winnerAvatar,
      winnerCorrectCount: winnerCorrectCount ?? this.winnerCorrectCount,
      winnerReactionMs: winnerReactionMs ?? this.winnerReactionMs,
    );
  }

  factory FlashHousieCycleSpec.fromJson(Map<String, dynamic> json) {
    final rawMatrix = json['ticket_matrix'] as List? ?? [];
    final matrix = rawMatrix
        .map((row) => (row as List).map((e) => (e as num).toInt()).toList())
        .toList();

    List<int> parseIntList(dynamic v) {
      if (v is List) return v.map((e) => (e as num).toInt()).toList();
      return const [];
    }

    return FlashHousieCycleSpec(
      cycleIndex: (json['cycle_index'] as num?)?.toInt() ?? 1,
      label: json['label'] as String? ?? 'R1-Q1',
      prizeKey: json['prize_key'] as String? ?? 'ROUND_1',
      activeQuadrants: parseIntList(json['active_quadrants']),
      ticketMatrix: matrix.length == 3
          ? matrix
          : List.generate(3, (_) => List.filled(9, 0)),
      trueNumbers: parseIntList(json['true_numbers']),
      decoyNumbers: parseIntList(json['decoy_numbers']),
      drawPool: parseIntList(json['draw_pool']),
      calledNumbers: parseIntList(json['called_numbers']),
      startedAtMs: (json['started_at_ms'] as num?)?.toInt(),
      randomLaunchDelaySec: (json['random_launch_delay_sec'] as num?)?.toInt() ?? 6,
      winnerUserId: json['winner_user_id'] as String?,
      winnerName: json['winner_name'] as String?,
      winnerAvatar: json['winner_avatar'] as String?,
      winnerCorrectCount: (json['winner_correct_count'] as num?)?.toInt(),
      winnerReactionMs: (json['winner_reaction_ms'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'cycle_index': cycleIndex,
      'label': label,
      'prize_key': prizeKey,
      'active_quadrants': activeQuadrants,
      'ticket_matrix': ticketMatrix,
      'true_numbers': trueNumbers,
      'decoy_numbers': decoyNumbers,
      'draw_pool': drawPool,
      'called_numbers': calledNumbers,
      'started_at_ms': startedAtMs,
      'random_launch_delay_sec': randomLaunchDelaySec,
      'winner_user_id': winnerUserId,
      'winner_name': winnerName,
      'winner_avatar': winnerAvatar,
      'winner_correct_count': winnerCorrectCount,
      'winner_reaction_ms': winnerReactionMs,
    };
  }
}

class FlashHousieConfig {
  static const String modeClassic90 = 'BINGO_90';
  static const String modeFlash5 = 'FLASH_5';
  static const String modeFlash10 = 'FLASH_10';
  static const String modeFlash15 = 'FLASH_15';

  final String mode; // 'FLASH_5', 'FLASH_10', 'FLASH_15'
  final int totalCycles;
  final int currentCycle; // 1..totalCycles
  final int cellsPerQuadrant; // 5 (Standard) or 9 (Full 3x3 Quadrant)
  final int decoysPerColumn; // 1 or 2
  final int freezePenaltySec; // default 3
  final List<FlashHousieCycleSpec> cycles;
  final Map<String, String> awardedWinners; // prizeKey -> userId
  final Map<String, String> awardedWinnerNames; // prizeKey -> displayName

  const FlashHousieConfig({
    required this.mode,
    required this.totalCycles,
    this.currentCycle = 1,
    this.cellsPerQuadrant = 5,
    this.decoysPerColumn = 1,
    this.freezePenaltySec = 3,
    required this.cycles,
    this.awardedWinners = const {},
    this.awardedWinnerNames = const {},
  });

  static FlashHousieConfig? fromPrizeGiftsConfig(
    Map<String, dynamic> prizeGiftsConfig,
  ) {
    final raw = prizeGiftsConfig['_flash_housie'];
    if (raw is Map) {
      return FlashHousieConfig.fromJson(Map<String, dynamic>.from(raw));
    }
    return null;
  }

  String get modeDisplayName {
    switch (mode) {
      case modeFlash5:
        return 'FlashHousie™ 5 (1 Quadrant)';
      case modeFlash10:
        return 'FlashHousie™ 10 (2 Quadrants)';
      case modeFlash15:
        return 'FlashHousie™ 15 (3 Quadrants)';
      default:
        return 'Classic 90-Ball Tambola';
    }
  }

  String get displayTitle => modeDisplayName;

  FlashHousieCycleSpec get activeCycleSpec {
    final idx = (currentCycle - 1).clamp(0, cycles.length - 1);
    return cycles[idx];
  }

  NeuroWaveState computeNeuroWaveState(int nowMs) =>
      activeCycleSpec.computeNeuroWaveState(nowMs);

  bool get isLastCycle => currentCycle >= totalCycles;

  int get totalTargetNumbersAcrossAllCycles =>
      cycles.fold(0, (sum, c) => sum + c.trueNumbers.length);

  FlashHousieConfig copyWith({
    int? currentCycle,
    List<FlashHousieCycleSpec>? cycles,
    Map<String, String>? awardedWinners,
    Map<String, String>? awardedWinnerNames,
  }) {
    return FlashHousieConfig(
      mode: mode,
      totalCycles: totalCycles,
      currentCycle: currentCycle ?? this.currentCycle,
      cellsPerQuadrant: cellsPerQuadrant,
      decoysPerColumn: decoysPerColumn,
      freezePenaltySec: freezePenaltySec,
      cycles: cycles ?? this.cycles,
      awardedWinners: awardedWinners ?? this.awardedWinners,
      awardedWinnerNames: awardedWinnerNames ?? this.awardedWinnerNames,
    );
  }

  /// Generates a complete multi-cycle FlashHousie™ configuration
  factory FlashHousieConfig.generate({
    required String mode,
    required int totalCycles,
    int cellsPerQuadrant = 5,
    int decoysPerColumn = 1,
    Random? random,
  }) {
    final rng = random ?? Random();
    final cyclesList = <FlashHousieCycleSpec>[];

    // Pre-build quadrant schedule across cycles
    final quadrantSchedule = <List<int>>[];
    if (mode == modeFlash5) {
      // Shuffle [1, 2, 3] in blocks of 3 so every 3 cycles covers Q1, Q2, Q3 on the same 3x9 card!
      List<int> bag = [];
      for (int i = 0; i < totalCycles; i++) {
        if (bag.isEmpty) {
          bag = [1, 2, 3]..shuffle(rng);
        }
        quadrantSchedule.add([bag.removeLast()]);
      }
    } else if (mode == modeFlash10) {
      final pairs = [
        [1, 2],
        [1, 3],
        [2, 3],
      ];
      List<List<int>> bag = [];
      for (int i = 0; i < totalCycles; i++) {
        if (bag.isEmpty) {
          bag = List<List<int>>.from(pairs)..shuffle(rng);
        }
        quadrantSchedule.add(bag.removeLast());
      }
    } else {
      for (int i = 0; i < totalCycles; i++) {
        quadrantSchedule.add([1, 2, 3]);
      }
    }

    // Generate base 3x9 ticket(s). For FlashHousie 5, a single 3x9 ticket cleanly holds Q1, Q2, and Q3 across 3 rounds!
    List<List<int>> sharedTicket = _generateBaseMatrix(
      cellsPerQuadrant: cellsPerQuadrant,
      rng: rng,
    );

    for (int i = 0; i < totalCycles; i++) {
      final cycleNum = i + 1;
      // Refresh base ticket every 3 cycles for Flash 5, or every cycle for Flash 10 / Flash 15
      if (mode != modeFlash5 || (i > 0 && i % 3 == 0)) {
        sharedTicket = _generateBaseMatrix(
          cellsPerQuadrant: cellsPerQuadrant,
          rng: rng,
        );
      }

      final activeQuads = List<int>.from(quadrantSchedule[i])..sort();
      final quadNames = activeQuads.map((q) => 'Q$q').join('+');
      final label = 'R$cycleNum-$quadNames';
      final prizeKey = 'ROUND_$cycleNum';

      // Extract true numbers & generate 1–2 decoy numbers per active column
      final trueNums = <int>[];
      final decoyNums = <int>[];

      for (final q in activeQuads) {
        final startCol = (q - 1) * 3;
        for (int c = startCol; c < startCol + 3; c++) {
          final colMin = c == 0 ? 1 : c * 10;
          final colMax = c == 8 ? 90 : (c * 10 + 9);
          final colTrue = <int>{};
          for (int r = 0; r < 3; r++) {
            final v = sharedTicket[r][c];
            if (v > 0) {
              trueNums.add(v);
              colTrue.add(v);
            }
          }
          final candidates = <int>[
            for (int n = colMin; n <= colMax; n++)
              if (!colTrue.contains(n)) n,
          ]..shuffle(rng);

          decoyNums.addAll(candidates.take(decoysPerColumn));
        }
      }

      trueNums.sort();
      decoyNums.sort();
      final pool = <int>[...trueNums, ...decoyNums]..shuffle(rng);

      // Random suspense launch delay after 5th second (6..9 seconds)
      final randomDelay = 6 + rng.nextInt(4);

      cyclesList.add(
        FlashHousieCycleSpec(
          cycleIndex: cycleNum,
          label: label,
          prizeKey: prizeKey,
          activeQuadrants: activeQuads,
          ticketMatrix: sharedTicket
              .map((row) => List<int>.from(row))
              .toList(),
          trueNumbers: trueNums,
          decoyNumbers: decoyNums,
          drawPool: pool,
          calledNumbers: const [],
          randomLaunchDelaySec: randomDelay,
        ),
      );
    }

    return FlashHousieConfig(
      mode: mode,
      totalCycles: totalCycles,
      currentCycle: 1,
      cellsPerQuadrant: cellsPerQuadrant,
      decoysPerColumn: decoysPerColumn,
      freezePenaltySec: 3,
      cycles: cyclesList,
    );
  }

  /// Generates a 3x9 matrix where EVERY 3x3 quadrant has exactly [cellsPerQuadrant] numbers (5 or 9),
  /// strictly sorted vertically within each column's decade range.
  static List<List<int>> _generateBaseMatrix({
    required int cellsPerQuadrant,
    required Random rng,
  }) {
    if (cellsPerQuadrant >= 9) {
      // Full 9-cell quadrant mode: 3 sorted numbers in every column (all 27 cells filled)
      final matrix = List.generate(3, (_) => List.filled(9, 0));
      for (int c = 0; c < 9; c++) {
        final minVal = c == 0 ? 1 : c * 10;
        final maxVal = c == 8 ? 90 : (c * 10 + 9);
        final pool = List.generate(maxVal - minVal + 1, (i) => minVal + i)
          ..shuffle(rng);
        final chosen = pool.take(3).toList()..sort();
        for (int r = 0; r < 3; r++) {
          matrix[r][c] = chosen[r];
        }
      }
      return matrix;
    }

    // Standard 5-numbers-per-quadrant mode (15 total across 3 quadrants: 5 in Q1, 5 in Q2, 5 in Q3)
    final matrix = List.generate(3, (_) => List.filled(9, 0));
    for (int q = 0; q < 3; q++) {
      final startCol = q * 3;
      // In a 3x3 quadrant with 5 numbers: two columns have 2 numbers, one column has 1 number
      final colCounts = [2, 2, 1]..shuffle(rng);
      // Ensure each of the 3 rows gets 1 or 2 numbers (sum = 5)
      final rowTemplates = <List<List<int>>>[
        [
          [0, 2],
          [0, 1],
          [2],
        ],
        [
          [0, 1],
          [1, 2],
          [0],
        ],
        [
          [0, 2],
          [1, 2],
          [1],
        ],
      ]..shuffle(rng);
      final chosenTemplate = rowTemplates.first;

      // Map columns with count=2 to the first two template slots, and count=1 to the third
      int twoIdx = 0;
      for (int offset = 0; offset < 3; offset++) {
        final c = startCol + offset;
        final minVal = c == 0 ? 1 : c * 10;
        final maxVal = c == 8 ? 90 : (c * 10 + 9);
        final count = colCounts[offset];
        final rows = count == 2 ? chosenTemplate[twoIdx++] : chosenTemplate[2];
        final pool = List.generate(maxVal - minVal + 1, (i) => minVal + i)
          ..shuffle(rng);
        final nums = pool.take(count).toList()..sort();
        for (int i = 0; i < rows.length; i++) {
          matrix[rows[i]][c] = nums[i];
        }
      }
    }
    return matrix;
  }

  factory FlashHousieConfig.fromJson(Map<String, dynamic> json) {
    final rawCycles = json['cycles'] as List? ?? [];
    final rawWinners = json['awarded_winners'];
    final rawWinnerNames = json['awarded_winner_names'];
    return FlashHousieConfig(
      mode: json['mode'] as String? ?? modeFlash5,
      totalCycles: (json['total_cycles'] as num?)?.toInt() ?? 3,
      currentCycle: (json['current_cycle'] as num?)?.toInt() ?? 1,
      cellsPerQuadrant: (json['cells_per_quadrant'] as num?)?.toInt() ?? 5,
      decoysPerColumn: (json['decoys_per_column'] as num?)?.toInt() ?? 1,
      freezePenaltySec: (json['freeze_penalty_sec'] as num?)?.toInt() ?? 3,
      cycles: rawCycles
          .map((e) => FlashHousieCycleSpec.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      awardedWinners: rawWinners is Map
          ? rawWinners.map((k, v) => MapEntry(k.toString(), v.toString()))
          : const {},
      awardedWinnerNames: rawWinnerNames is Map
          ? rawWinnerNames.map((k, v) => MapEntry(k.toString(), v.toString()))
          : const {},
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'mode': mode,
      'total_cycles': totalCycles,
      'current_cycle': currentCycle,
      'cells_per_quadrant': cellsPerQuadrant,
      'decoys_per_column': decoysPerColumn,
      'freeze_penalty_sec': freezePenaltySec,
      'cycles': cycles.map((c) => c.toJson()).toList(),
      'awarded_winners': awardedWinners,
      'awarded_winner_names': awardedWinnerNames,
    };
  }
}

/// Model for Option-B Live TV Board & Leaderboard rows in `MPT_memory_round_scores`
class MptMemoryRoundScore {
  final String id;
  final String gameId;
  final String userId;
  final String displayName;
  final String avatar;
  final int cycleIndex;
  final String quadrantLabel;
  final List<int> correctNumbers;
  final int correctCount;
  final int wrongTapCount;
  final int totalReactionMs;
  final int? lastRecalledNumber;
  final int? lastReactionMs;
  final DateTime updatedAt;

  const MptMemoryRoundScore({
    required this.id,
    required this.gameId,
    required this.userId,
    required this.displayName,
    required this.avatar,
    required this.cycleIndex,
    required this.quadrantLabel,
    required this.correctNumbers,
    required this.correctCount,
    required this.wrongTapCount,
    required this.totalReactionMs,
    this.lastRecalledNumber,
    this.lastReactionMs,
    required this.updatedAt,
  });

  int get cycleNumber => cycleIndex;

  int get cumulativeReactionMs => totalReactionMs;

  /// Canonical FlashHousie™ tie-breaker comparator:
  /// 1. Highest [correctCount]
  /// 2. Fewest [wrongTapCount]
  /// 3. Fastest [totalReactionMs]
  static int compareStandings(MptMemoryRoundScore a, MptMemoryRoundScore b) {
    final cmpCorrect = b.correctCount.compareTo(a.correctCount);
    if (cmpCorrect != 0) return cmpCorrect;
    final cmpWrong = a.wrongTapCount.compareTo(b.wrongTapCount);
    if (cmpWrong != 0) return cmpWrong;
    return a.totalReactionMs.compareTo(b.totalReactionMs);
  }

  factory MptMemoryRoundScore.fromJson(Map<String, dynamic> json) {
    final rawCorrect = json['correct_numbers'];
    final correctList = rawCorrect is List
        ? rawCorrect.map((e) => (e as num).toInt()).toList()
        : <int>[];

    return MptMemoryRoundScore(
      id: json['id']?.toString() ?? '',
      gameId: json['game_id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? '',
      displayName: json['display_name'] as String? ?? 'Player',
      avatar: json['avatar'] as String? ?? '🎉',
      cycleIndex: (json['cycle_index'] as num?)?.toInt() ?? 1,
      quadrantLabel: json['quadrant_label'] as String? ?? 'R1-Q1',
      correctNumbers: correctList,
      correctCount: (json['correct_count'] as num?)?.toInt() ?? correctList.length,
      wrongTapCount: (json['wrong_tap_count'] as num?)?.toInt() ?? 0,
      totalReactionMs: (json['total_reaction_ms'] as num?)?.toInt() ?? 0,
      lastRecalledNumber: (json['last_recalled_number'] as num?)?.toInt(),
      lastReactionMs: (json['last_reaction_ms'] as num?)?.toInt(),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'].toString())
          : DateTime.now(),
    );
  }
}
