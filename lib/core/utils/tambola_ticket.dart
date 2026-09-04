import 'dart:math';

class TambolaTicketHelper {
  /// Generates a valid standard 3x9 Tambola ticket matrix
  /// 3 rows, 9 columns. Exactly 5 numbers per row (15 numbers total).
  /// Column ranges:
  /// Col 0: 1–9, Col 1: 10–19, Col 2: 20–29, Col 3: 30–39, Col 4: 40–49,
  /// Col 5: 50–59, Col 6: 60–69, Col 7: 70–79, Col 8: 80–90.
  static List<List<int>> generateTicket([Random? random]) {
    final rng = random ?? Random();

    for (int attempt = 0; attempt < 200; attempt++) {
      final ticket = _tryGenerateSingleTicket(rng);
      if (ticket != null) {
        return ticket;
      }
    }

    // High-safety deterministic permutation fallback using random seed offset (never identical)
    return _generateSeededTicket(rng.nextInt(1000000));
  }

  static List<List<int>>? _tryGenerateSingleTicket(Random rng) {
    // 1. Determine number of items per column (sum = 15, each between 1 and 3)
    final colCounts = List.filled(9, 1);
    var remaining = 6;
    while (remaining > 0) {
      final col = rng.nextInt(9);
      if (colCounts[col] < 3) {
        colCounts[col]++;
        remaining--;
      }
    }

    // 2. Select rows for each column such that each of the 3 rows has exactly 5 items
    final gridMask = List.generate(3, (_) => List.filled(9, false));

    // Place columns with 3 items first (they must occupy all 3 rows)
    for (int col = 0; col < 9; col++) {
      if (colCounts[col] == 3) {
        gridMask[0][col] = true;
        gridMask[1][col] = true;
        gridMask[2][col] = true;
      }
    }

    // Place columns with 2 items and 1 item using constraint satisfaction
    final remainingCols = <int>[];
    for (int col = 0; col < 9; col++) {
      if (colCounts[col] < 3) {
        remainingCols.add(col);
      }
    }
    remainingCols.shuffle(rng);

    // Try finding valid row assignment
    bool placed = _assignRows(gridMask, remainingCols, 0, colCounts);
    if (!placed) return null;

    // Verify exactly 5 items in each row
    for (int r = 0; r < 3; r++) {
      final count = gridMask[r].where((b) => b).length;
      if (count != 5) return null;
    }

    // 3. Populate numbers for each column in strictly sorted order
    final matrix = List.generate(3, (_) => List.filled(9, 0));

    for (int col = 0; col < 9; col++) {
      final minVal = col == 0 ? 1 : col * 10;
      final maxVal = col == 8 ? 90 : (col * 10 + 9);
      final range = List.generate(maxVal - minVal + 1, (i) => minVal + i)..shuffle(rng);
      final count = colCounts[col];
      final chosen = range.take(count).toList()..sort();

      var numIdx = 0;
      for (int row = 0; row < 3; row++) {
        if (gridMask[row][col]) {
          matrix[row][col] = chosen[numIdx++];
        }
      }
    }

    return matrix;
  }

  static bool _assignRows(List<List<bool>> mask, List<int> cols, int colIndex, List<int> counts) {
    if (colIndex >= cols.length) {
      return mask[0].where((b) => b).length == 5 &&
          mask[1].where((b) => b).length == 5 &&
          mask[2].where((b) => b).length == 5;
    }

    final col = cols[colIndex];
    final count = counts[col];

    List<List<int>> options;
    if (count == 1) {
      options = [[0], [1], [2]];
    } else if (count == 2) {
      options = [[0, 1], [0, 2], [1, 2]];
    } else {
      options = [[0, 1, 2]];
    }
    options.shuffle();

    for (final opt in options) {
      // Check if adding exceeds 5 in any row
      bool canPlace = true;
      for (final r in opt) {
        if (mask[r].where((b) => b).length >= 5) {
          canPlace = false;
          break;
        }
      }

      if (canPlace) {
        for (final r in opt) {
          mask[r][col] = true;
        }
        if (_assignRows(mask, cols, colIndex + 1, counts)) {
          return true;
        }
        for (final r in opt) {
          mask[r][col] = false;
        }
      }
    }

    return false;
  }

  static List<List<int>> _generateSeededTicket(int seed) {
    final rng = Random(seed);
    // Standard valid template with dynamic numbers
    final patterns = [
      [true, false, true, false, true, false, true, false, true],
      [false, true, false, true, false, true, false, true, true],
      [true, false, true, false, true, true, false, true, false],
    ];

    final matrix = List.generate(3, (_) => List.filled(9, 0));
    for (int col = 0; col < 9; col++) {
      final minVal = col == 0 ? 1 : col * 10;
      final maxVal = col == 8 ? 90 : (col * 10 + 9);
      final count = (patterns[0][col] ? 1 : 0) + (patterns[1][col] ? 1 : 0) + (patterns[2][col] ? 1 : 0);
      final range = List.generate(maxVal - minVal + 1, (i) => minVal + i)..shuffle(rng);
      final chosen = range.take(count).toList()..sort();
      var idx = 0;
      for (int r = 0; r < 3; r++) {
        if (patterns[r][col]) {
          matrix[r][col] = chosen[idx++];
        }
      }
    }
    return matrix;
  }

  /// Extracts all 15 positive numbers from the 3x9 matrix
  static List<int> getAllNumbers(List<List<int>> matrix) {
    final numbers = <int>[];
    for (final row in matrix) {
      for (final cell in row) {
        if (cell > 0) numbers.add(cell);
      }
    }
    return numbers;
  }

  /// Check prize winning patterns against a set of called/marked numbers
  static bool checkEarlyFive(List<List<int>> matrix, Set<int> marked) {
    final all = getAllNumbers(matrix);
    return all.where((n) => marked.contains(n)).length >= 5;
  }

  static bool checkTopLine(List<List<int>> matrix, Set<int> marked) {
    final row0 = matrix[0].where((n) => n > 0).toList();
    if (row0.length != 5) return false;
    return row0.every((n) => marked.contains(n));
  }

  static bool checkMiddleLine(List<List<int>> matrix, Set<int> marked) {
    final row1 = matrix[1].where((n) => n > 0).toList();
    if (row1.length != 5) return false;
    return row1.every((n) => marked.contains(n));
  }

  static bool checkBottomLine(List<List<int>> matrix, Set<int> marked) {
    final row2 = matrix[2].where((n) => n > 0).toList();
    if (row2.length != 5) return false;
    return row2.every((n) => marked.contains(n));
  }

  static bool checkFourCorners(List<List<int>> matrix, Set<int> marked) {
    final topRow = matrix[0].where((n) => n > 0).toList();
    final bottomRow = matrix[2].where((n) => n > 0).toList();
    if (topRow.length < 2 || bottomRow.length < 2) return false;

    final c1 = topRow.first;
    final c2 = topRow.last;
    final c3 = bottomRow.first;
    final c4 = bottomRow.last;

    return marked.contains(c1) && marked.contains(c2) && marked.contains(c3) && marked.contains(c4);
  }

  static bool checkFullHouse(List<List<int>> matrix, Set<int> marked) {
    final all = getAllNumbers(matrix);
    if (all.length != 15) return false;
    return all.every((n) => marked.contains(n));
  }

  /// Evaluates whether the given marked numbers satisfy a specific prize pattern
  static bool validatePrizePattern(List<List<int>> matrix, Set<int> marked, String prizeType) {
    switch (prizeType) {
      case 'EARLY_FIVE':
        return checkEarlyFive(matrix, marked);
      case 'TOP_LINE':
        return checkTopLine(matrix, marked);
      case 'MIDDLE_LINE':
        return checkMiddleLine(matrix, marked);
      case 'BOTTOM_LINE':
        return checkBottomLine(matrix, marked);
      case 'FOUR_CORNERS':
        return checkFourCorners(matrix, marked);
      case 'FULL_HOUSE':
      case 'SECOND_FULL_HOUSE':
        return checkFullHouse(matrix, marked);
      default:
        return false;
    }
  }
}
