import 'dart:math';
import 'flash_housie_config.dart';

/// Shared helper for column decade range labels (0-indexed col 0..8).
String columnDecadeLabel(int col) {
  switch (col) {
    case 0:
      return '1–9';
    case 8:
      return '80–90';
    default:
      return '${col * 10}–${col * 10 + 9}';
  }
}

/// Returns the expected 0-indexed column (0..8) for any valid Tambola ball 1..90.
int expectedColumnForBall(int number) {
  if (number <= 0) return 0;
  if (number <= 9) return 0;
  if (number >= 80) return 8;
  return number ~/ 10;
}

// ============================================================================
// LEVEL 0A: MakeHousie™ (Ticket Rule Builder)
// ============================================================================

class MakePlacementResult {
  final bool isSuccess;
  final String message;
  final bool isRulePenalty;

  const MakePlacementResult({
    required this.isSuccess,
    required this.message,
    this.isRulePenalty = false,
  });
}

class MakeHousieRoundSpec {
  static const String modeMake5Quad = 'make_5_quad';
  static const String modeMake15Guided = 'make_15_guided';
  static const String modeMake15Master = 'make_15_master';

  final String mode;
  final List<List<int>> trueMatrix; // 3x9 canonical valid ticket
  final List<int> activeQuadrants; // [1], [2], [3] or [1, 2, 3]
  final List<int> dealPool; // numbers the player needs to place

  const MakeHousieRoundSpec({
    required this.mode,
    required this.trueMatrix,
    required this.activeQuadrants,
    required this.dealPool,
  });

  bool isColumnActive(int col) {
    final q = (col ~/ 3) + 1;
    return activeQuadrants.contains(q);
  }

  /// Generate a new MakeHousie round.
  factory MakeHousieRoundSpec.generate({
    required String mode,
    Random? random,
  }) {
    final rng = random ?? Random();
    final matrix = FlashHousieConfig.generateBalancedTicketMatrix(rng);

    List<int> activeQuads;
    if (mode == modeMake5Quad) {
      activeQuads = [rng.nextInt(3) + 1];
    } else {
      activeQuads = const [1, 2, 3];
    }

    final pool = <int>[];
    for (int r = 0; r < 3; r++) {
      for (int c = 0; c < 9; c++) {
        final q = (c ~/ 3) + 1;
        if (activeQuads.contains(q) && matrix[r][c] > 0) {
          pool.add(matrix[r][c]);
        }
      }
    }

    if (mode == modeMake15Master) {
      pool.shuffle(rng);
    } else {
      pool.sort();
    }

    return MakeHousieRoundSpec(
      mode: mode,
      trueMatrix: matrix,
      activeQuadrants: activeQuads,
      dealPool: pool,
    );
  }

  /// Validates placing [selectedBall] into cell ([row], [col]).
  MakePlacementResult validatePlacement({
    required int selectedBall,
    required int row,
    required int col,
    required Set<int> alreadyPlacedBalls,
  }) {
    final expectedCol = expectedColumnForBall(selectedBall);

    // Rule 1: Column Decade Check
    if (col != expectedCol) {
      return MakePlacementResult(
        isSuccess: false,
        isRulePenalty: true,
        message:
            'Rule 1 (Column Decade): Ball $selectedBall belongs in Col ${expectedCol + 1} (${columnDecadeLabel(expectedCol)}), not Col ${col + 1} (${columnDecadeLabel(col)})!',
      );
    }

    final trueValAtCell = trueMatrix[row][col];

    // Rule 3: 5-Per-Row & Active Slot Check
    if (trueValAtCell == 0) {
      // Find which row(s) in this column actually hold numbers
      int correctRow = 0;
      for (int r = 0; r < 3; r++) {
        if (trueMatrix[r][col] == selectedBall) {
          correctRow = r;
          break;
        }
      }
      return MakePlacementResult(
        isSuccess: false,
        isRulePenalty: mode == modeMake15Master,
        message:
            'Rule 3 (5-Per-Row Balance): Row ${row + 1} is reserved for other columns so every row has 5 numbers. Place $selectedBall in Row ${correctRow + 1}!',
      );
    }

    // Rule 2: Vertical Ascending Order Check within the right column
    if (trueValAtCell != selectedBall) {
      int correctRow = 0;
      for (int r = 0; r < 3; r++) {
        if (trueMatrix[r][col] == selectedBall) {
          correctRow = r;
          break;
        }
      }
      final relation = selectedBall < trueValAtCell ? 'smaller' : 'larger';
      final posWord = selectedBall < trueValAtCell ? 'above' : 'below';
      return MakePlacementResult(
        isSuccess: false,
        isRulePenalty: true,
        message:
            'Rule 2 (Ascending Order): In Col ${col + 1}, $selectedBall is $relation than $trueValAtCell, so it must sit $posWord it (Row ${correctRow + 1})!',
      );
    }

    return MakePlacementResult(
      isSuccess: true,
      message:
          '✓ Placed $selectedBall in Col ${col + 1} (${columnDecadeLabel(col)}), Row ${row + 1}!',
    );
  }
}

// ============================================================================
// LEVEL 0B: FixHousie™ (Spot the Mistake)
// ============================================================================

class FixBugSpec {
  final int row;
  final int col;
  final int trueValue;
  final int bugValue;
  final String bugType; // 'DECADE', 'ORDER', 'TWIN', 'RANGE'
  final String explanation;

  const FixBugSpec({
    required this.row,
    required this.col,
    required this.trueValue,
    required this.bugValue,
    required this.bugType,
    required this.explanation,
  });

  String get cellKey => '${row}_$col';
}

class FixHousieRoundSpec {
  static const String modeFix1 = 'fix_1';
  static const String modeFix3 = 'fix_3';
  static const String modeFix5 = 'fix_5';

  final String mode;
  final List<List<int>> trueMatrix;
  final List<List<int>> bugMatrix;
  final Map<String, FixBugSpec> bugsByCellKey;

  const FixHousieRoundSpec({
    required this.mode,
    required this.trueMatrix,
    required this.bugMatrix,
    required this.bugsByCellKey,
  });

  int get totalBugs => bugsByCellKey.length;

  factory FixHousieRoundSpec.generate({
    required String mode,
    Random? random,
  }) {
    final rng = random ?? Random();
    final trueMat = FlashHousieConfig.generateBalancedTicketMatrix(rng);
    final bugMat = List<List<int>>.generate(
      3,
      (r) => List<int>.from(trueMat[r]),
    );

    final targetBugCount = mode == modeFix1
        ? 1
        : (mode == modeFix5 ? 5 : 3);

    // Collect all non-empty cells
    final filledCells = <(int, int)>[];
    for (int r = 0; r < 3; r++) {
      for (int c = 0; c < 9; c++) {
        if (trueMat[r][c] > 0) {
          filledCells.add((r, c));
        }
      }
    }
    filledCells.shuffle(rng);

    final bugs = <String, FixBugSpec>{};
    final usedCols = <int>{};

    // Pass 1: Prefer at most 1 bug per column so bugs don't mask each other
    for (final (r, c) in filledCells) {
      if (bugs.length >= targetBugCount) break;
      if (usedCols.contains(c)) continue;

      final spec = _createBugForCell(
        trueMat: trueMat,
        row: r,
        col: c,
        bugIndex: bugs.length,
        rng: rng,
      );
      usedCols.add(c);
      bugMat[r][c] = spec.bugValue;
      bugs[spec.cellKey] = spec;
    }

    return FixHousieRoundSpec(
      mode: mode,
      trueMatrix: trueMat,
      bugMatrix: bugMat,
      bugsByCellKey: bugs,
    );
  }

  static FixBugSpec _createBugForCell({
    required List<List<int>> trueMat,
    required int row,
    required int col,
    required int bugIndex,
    required Random rng,
  }) {
    final trueVal = trueMat[row][col];
    // Check if column has another filled cell for ORDER or TWIN bugs
    final otherRowsInCol = <int>[];
    for (int r = 0; r < 3; r++) {
      if (r != row && trueMat[r][col] > 0) {
        otherRowsInCol.add(r);
      }
    }

    final bugKind = bugIndex % 4;
    // 0: Wrong Column Decade
    // 1: Out of Range (>90) or Wrong Decade
    // 2: Vertical Order Inversion (if multi-number col)
    // 3: Twin Duplicate (if multi-number col)

    if (bugKind == 2 && otherRowsInCol.isNotEmpty) {
      final otherRow = otherRowsInCol.first;
      final otherVal = trueMat[otherRow][col];
      final colMax = col == 8 ? 90 : (col * 10 + 9);
      final colMin = col == 0 ? 1 : (col * 10);
      if (row < otherRow && otherVal < colMax) {
        // Upper cell made larger than lower cell!
        final invertedVal = otherVal + 1;
        return FixBugSpec(
          row: row,
          col: col,
          trueValue: trueVal,
          bugValue: invertedVal,
          bugType: 'ORDER BUG',
          explanation:
              '✓ Fixed Order Bug! $invertedVal in Row ${row + 1} was larger than $otherVal below it in Col ${col + 1} → restored to $trueVal.',
        );
      } else if (row > otherRow && otherVal > colMin) {
        // Lower cell made smaller than upper cell!
        final invertedVal = otherVal - 1;
        return FixBugSpec(
          row: row,
          col: col,
          trueValue: trueVal,
          bugValue: invertedVal,
          bugType: 'ORDER BUG',
          explanation:
              '✓ Fixed Order Bug! $invertedVal in Row ${row + 1} was smaller than $otherVal above it in Col ${col + 1} → restored to $trueVal.',
        );
      }
    }

    if (bugKind == 3 && otherRowsInCol.isNotEmpty) {
      final otherRow = otherRowsInCol.first;
      final twinVal = trueMat[otherRow][col];
      return FixBugSpec(
        row: row,
        col: col,
        trueValue: trueVal,
        bugValue: twinVal,
        bugType: 'TWIN BUG',
        explanation:
            '✓ Fixed Twin Duplicate! Ball $twinVal appeared twice in Col ${col + 1} → restored to $trueVal.',
      );
    }

    if (bugKind == 1) {
      final outVal = 91 + rng.nextInt(9); // 91..99
      return FixBugSpec(
        row: row,
        col: col,
        trueValue: trueVal,
        bugValue: outVal,
        bugType: 'RANGE >90 BUG',
        explanation:
            '✓ Fixed Range Bug! Ball $outVal exceeds 90 (max Tambola ball is 90) → restored to $trueVal.',
      );
    }

    // Default: Wrong Column Decade Bug
    final wrongCol = (col + 1 + rng.nextInt(7)) % 9;
    final wrongBase = wrongCol == 0 ? 1 : wrongCol * 10;
    final wrongVal = wrongBase + rng.nextInt(8);
    return FixBugSpec(
      row: row,
      col: col,
      trueValue: trueVal,
      bugValue: wrongVal,
      bugType: 'DECADE BUG',
      explanation:
          '✓ Fixed Decade Bug! Ball $wrongVal was in Col ${col + 1} (${columnDecadeLabel(col)}) → restored to $trueVal.',
    );
  }
}

// ============================================================================
// LEVEL 0C: MathHousie™ (Formula-to-Grid Hunt)
// ============================================================================

class MathFormulaPrompt {
  final String expression;
  final int targetValue;
  final int targetRow;
  final int targetCol;

  const MathFormulaPrompt({
    required this.expression,
    required this.targetValue,
    required this.targetRow,
    required this.targetCol,
  });
}

class MathHousieRoundSpec {
  static const String modeAddSub5 = 'math_add_sub';
  static const String modeMulDiv5 = 'math_mul_div';
  static const String modeMixed10 = 'math_mixed_10';

  final String mode;
  final List<List<int>> ticketMatrix;
  final List<MathFormulaPrompt> prompts;

  const MathHousieRoundSpec({
    required this.mode,
    required this.ticketMatrix,
    required this.prompts,
  });

  factory MathHousieRoundSpec.generate({
    required String mode,
    Random? random,
  }) {
    final rng = random ?? Random();
    final matrix = FlashHousieConfig.generateBalancedTicketMatrix(rng);

    final cells = <(int, int, int)>[];
    for (int r = 0; r < 3; r++) {
      for (int c = 0; c < 9; c++) {
        if (matrix[r][c] > 0) {
          cells.add((r, c, matrix[r][c]));
        }
      }
    }
    cells.shuffle(rng);

    final count = mode == modeMixed10 ? 10 : 5;
    final selected = cells.take(count).toList();
    final prompts = <MathFormulaPrompt>[];

    for (int i = 0; i < selected.length; i++) {
      final (r, c, target) = selected[i];
      final useMulDiv = mode == modeMulDiv5 || (mode == modeMixed10 && i.isOdd);
      final expr = useMulDiv
          ? _buildMulDivExpression(target, rng)
          : _buildAddSubExpression(target, rng);
      prompts.add(
        MathFormulaPrompt(
          expression: expr,
          targetValue: target,
          targetRow: r,
          targetCol: c,
        ),
      );
    }

    return MathHousieRoundSpec(
      mode: mode,
      ticketMatrix: matrix,
      prompts: prompts,
    );
  }

  static String _buildAddSubExpression(int target, Random rng) {
    if (rng.nextBool() && target >= 12) {
      final a = 4 + rng.nextInt(target - 5);
      final b = target - a;
      return '$a + $b = ?';
    } else {
      final extra = 5 + rng.nextInt(22);
      final top = target + extra;
      return '$top − $extra = ?';
    }
  }

  static String _buildMulDivExpression(int target, Random rng) {
    // Check clean factor pairs first
    final factors = <(int, int)>[];
    for (int f = 2; f <= 12; f++) {
      if (target % f == 0 && (target ~/ f) >= 2 && (target ~/ f) <= 15) {
        factors.add((target ~/ f, f));
      }
    }
    if (factors.isNotEmpty) {
      if (rng.nextBool() && target <= 30) {
        final mult = 2 + rng.nextInt(4);
        return '${target * mult} ÷ $mult = ?';
      }
      final (a, b) = factors[rng.nextInt(factors.length)];
      return '$a × $b = ?';
    }
    // For prime or non-factorable numbers, build clean (a × b) + c
    final b = 2 + rng.nextInt(7); // 2..8
    final a = (target ~/ b).clamp(1, 12);
    final prod = a * b;
    final diff = target - prod;
    if (diff == 0) {
      return '$a × $b = ?';
    } else if (diff > 0) {
      return '($a × $b) + $diff = ?';
    } else {
      return '($a × $b) − ${diff.abs()} = ?';
    }
  }
}

// ============================================================================
// LEVEL 0D: SumHousie™ (Quadrant Rapid Addition MCQ)
// ============================================================================

class SumWaveSpec {
  final int quadrant; // 1, 2, or 3
  final List<int> quadrantNumbers; // 5 numbers
  final int correctSum;
  final List<int> options; // 4 sorted MCQ options with same-last-digit decoys

  const SumWaveSpec({
    required this.quadrant,
    required this.quadrantNumbers,
    required this.correctSum,
    required this.options,
  });
}

class SumHousieRoundSpec {
  static const String modeSumQ1 = 'sum_q1';
  static const String modeSumQ2 = 'sum_q2';
  static const String modeSumAll3 = 'sum_all_3';

  final String mode;
  final List<List<int>> ticketMatrix;
  final List<SumWaveSpec> waves;

  const SumHousieRoundSpec({
    required this.mode,
    required this.ticketMatrix,
    required this.waves,
  });

  factory SumHousieRoundSpec.generate({
    required String mode,
    Random? random,
  }) {
    final rng = random ?? Random();
    final matrix = FlashHousieConfig.generateBalancedTicketMatrix(rng);

    final targetQuads = mode == modeSumQ1
        ? const [1]
        : (mode == modeSumQ2 ? const [2] : const [1, 2, 3]);

    final waves = <SumWaveSpec>[];
    for (final q in targetQuads) {
      final startCol = (q - 1) * 3;
      final nums = <int>[];
      for (int r = 0; r < 3; r++) {
        for (int c = startCol; c < startCol + 3; c++) {
          if (matrix[r][c] > 0) {
            nums.add(matrix[r][c]);
          }
        }
      }
      nums.sort();
      final sum = nums.fold<int>(0, (acc, v) => acc + v);

      // Anti-Shortcut Last-Digit Rule:
      // Include 2 decoys with the exact same units digit (+10, -10 or +20)
      // and 1 close neighbor (+2 or -2) so players must add full numbers!
      final optSet = <int>{sum};
      optSet.add(sum >= 25 ? sum - 10 : sum + 20);
      optSet.add(sum + 10);
      optSet.add(rng.nextBool() ? sum + 2 : (sum > 15 ? sum - 2 : sum + 4));
      while (optSet.length < 4) {
        optSet.add(sum + (optSet.length * 5));
      }
      final options = optSet.toList()..sort();

      waves.add(
        SumWaveSpec(
          quadrant: q,
          quadrantNumbers: nums,
          correctSum: sum,
          options: options,
        ),
      );
    }

    return SumHousieRoundSpec(
      mode: mode,
      ticketMatrix: matrix,
      waves: waves,
    );
  }
}
