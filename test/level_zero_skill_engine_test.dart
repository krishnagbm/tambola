import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:tambola/models/level_zero_skill_engine.dart';

void main() {
  group('Level 0A — MakeHousieRoundSpec', () {
    test('make_5_quad generates 5 dealPool numbers in random order and blank active quadrant', () {
      final spec = MakeHousieRoundSpec.generate(
        mode: MakeHousieRoundSpec.modeMake5Quad,
        random: Random(101),
      );
      expect(spec.dealPool.length, 5);
      expect(spec.activeQuadrants.length, 1);

      // Verify dealPool is NOT sorted ascending
      final sortedCopy = List<int>.from(spec.dealPool)..sort();
      expect(spec.dealPool, isNot(equals(sortedCopy)));

      final board = spec.createInitialBoard();
      final q = spec.activeQuadrants.first;
      final startCol = (q - 1) * 3;
      final endCol = startCol + 2;
      for (int r = 0; r < 3; r++) {
        for (int c = startCol; c <= endCol; c++) {
          expect(board[r][c], equals(0));
        }
      }
    });

    test('evaluateCellIssue and isBoardSolved allow unlimited re-drag from wrong cell to right cell', () {
      final spec = MakeHousieRoundSpec.generate(
        mode: MakeHousieRoundSpec.modeMake15Master,
        random: Random(202),
      );
      final board = spec.createInitialBoard();
      final targetBall = spec.dealPool.first;
      final trueCol = expectedColumnForBall(targetBall);
      final wrongCol = (trueCol + 1) % 9;

      // Drop ball in wrong column first
      board[0][wrongCol] = targetBall;
      expect(spec.evaluateCellIssue(board, 0, wrongCol), contains('Rule 1'));
      expect(spec.countValidPlacements(board), equals(0));

      // Drag ball from wrong column to right column
      board[0][wrongCol] = 0;
      board[1][trueCol] = targetBall;
      expect(spec.evaluateCellIssue(board, 1, trueCol), isNull);
      expect(spec.countValidPlacements(board), equals(1));
    });

    test('detects Rule 3 row overflow (e.g. 7 balls in middle row) and solves once balanced to 5 per row', () {
      const trueMatrix = [
        [2, 0, 23, 32, 46, 0, 0, 0, 83],
        [0, 14, 0, 0, 0, 56, 67, 74, 87],
        [8, 15, 0, 39, 0, 57, 0, 77, 0],
      ];
      const spec = MakeHousieRoundSpec(
        mode: MakeHousieRoundSpec.modeMake15Master,
        trueMatrix: trueMatrix,
        activeQuadrants: [1, 2, 3],
        dealPool: [2, 8, 14, 15, 23, 32, 39, 46, 56, 57, 67, 74, 77, 83, 87],
      );

      // Reproduce the exact board from screenshot:
      // Row 1 has 3 numbers, Row 2 (Middle) has 7 numbers (overflowed!), Row 3 has 5 numbers
      final overflowBoard = [
        [2, 0, 0, 32, 0, 0, 0, 0, 83],
        [0, 14, 23, 0, 46, 56, 67, 74, 87],
        [8, 15, 0, 39, 0, 57, 0, 77, 0],
      ];

      expect(spec.isBoardSolved(overflowBoard), isFalse);
      expect(spec.countValidPlacements(overflowBoard), equals(13));
      expect(
        spec.evaluateRowOverflowIssue(overflowBoard),
        contains('Rule 3 (Row Overflow): Middle Row (Row 2) has 7 numbers'),
      );
      final overflowCells = spec.findRowOverflowCells(overflowBoard);
      expect(overflowCells, contains('1_2')); // 23 in Row 2, Col 3
      expect(overflowCells, contains('1_4')); // 46 in Row 2, Col 5
      expect(overflowCells, isNot(contains('1_8'))); // 87 cannot move up to Row 1 because 83 is at 0_8

      // Player drags 23 (Col 3) and 46 (Col 5) from Middle Row (Row 2) up to Top Row (Row 1)
      overflowBoard[1][2] = 0;
      overflowBoard[0][2] = 23;
      overflowBoard[1][4] = 0;
      overflowBoard[0][4] = 46;

      expect(spec.evaluateRowOverflowIssue(overflowBoard), isNull);
      expect(spec.countValidPlacements(overflowBoard), equals(15));
      expect(spec.isBoardSolved(overflowBoard), isTrue);
    });
  });

  group('Level 0B — FixHousieRoundSpec', () {
    test('generates requested number of distinct rule bugs (1, 3, 5)', () {
      final modes = {
        FixHousieRoundSpec.modeFix1: 1,
        FixHousieRoundSpec.modeFix3: 3,
        FixHousieRoundSpec.modeFix5: 5,
      };
      for (final entry in modes.entries) {
        final spec = FixHousieRoundSpec.generate(
          mode: entry.key,
          random: Random(303),
        );
        expect(spec.totalBugs, entry.value);
        expect(spec.bugsByCellKey.length, entry.value);

        for (final bug in spec.bugsByCellKey.values) {
          final bVal = spec.bugMatrix[bug.row][bug.col];
          final cVal = spec.trueMatrix[bug.row][bug.col];
          expect(bVal, equals(bug.bugValue));
          expect(cVal, equals(bug.trueValue));
          expect(bVal, isNot(equals(cVal)));
        }
      }
    });
  });

  group('Level 0C — MathHousieRoundSpec', () {
    test('generates valid arithmetic formulas whose answers exist on the 3x9 ticket', () {
      for (final mode in [
        MathHousieRoundSpec.modeAddSub5,
        MathHousieRoundSpec.modeMulDiv5,
        MathHousieRoundSpec.modeMixed10,
      ]) {
        final spec = MathHousieRoundSpec.generate(
          mode: mode,
          random: Random(404),
        );
        final expectedPrompts = mode == MathHousieRoundSpec.modeMixed10 ? 10 : 5;
        expect(spec.prompts.length, expectedPrompts);

        for (final p in spec.prompts) {
          expect(
            spec.ticketMatrix[p.targetRow][p.targetCol],
            equals(p.targetValue),
          );
          expect(
            expectedColumnForBall(p.targetValue),
            equals(p.targetCol),
          );
        }
      }
    });
  });

  group('Level 0D — SumHousieRoundSpec', () {
    test('computes exact 5-number quadrant sum and includes 2 same-last-digit decoys', () {
      final spec = SumHousieRoundSpec.generate(
        mode: SumHousieRoundSpec.modeSumAll3,
        random: Random(505),
      );
      expect(spec.waves.length, 3);

      for (final wave in spec.waves) {
        final cStart = (wave.quadrant - 1) * 3;
        int manualSum = 0;
        int count = 0;
        for (int r = 0; r < 3; r++) {
          for (int c = cStart; c < cStart + 3; c++) {
            final v = spec.ticketMatrix[r][c];
            if (v > 0) {
              manualSum += v;
              count++;
            }
          }
        }
        expect(count, 5);
        expect(wave.correctSum, equals(manualSum));
        expect(wave.options.length, 4);
        expect(wave.options, contains(wave.correctSum));

        final targetLastDigit = wave.correctSum % 10;
        final matchingLastDigitCount = wave.options
            .where((opt) => opt % 10 == targetLastDigit)
            .length;
        expect(matchingLastDigitCount, greaterThanOrEqualTo(3));
      }
    });
  });
}
