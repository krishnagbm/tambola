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
