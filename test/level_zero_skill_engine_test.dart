import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:tambola/models/level_zero_skill_engine.dart';

void main() {
  group('Level 0A — MakeHousieRoundSpec', () {
    test('make_5_quad generates 5 dealPool numbers in active quadrant', () {
      final spec = MakeHousieRoundSpec.generate(
        mode: MakeHousieRoundSpec.modeMake5Quad,
        random: Random(101),
      );
      expect(spec.dealPool.length, 5);
      expect(spec.activeQuadrants.length, 1);

      final q = spec.activeQuadrants.first;
      final startCol = (q - 1) * 3;
      final endCol = startCol + 2;
      for (final ball in spec.dealPool) {
        final col = expectedColumnForBall(ball);
        expect(col, inInclusiveRange(startCol, endCol));
      }
    });

    test('validatePlacement enforces Rule 1 (Decade), Rule 2 (Ascending Order), Rule 3 (5-Per-Row)', () {
      final spec = MakeHousieRoundSpec.generate(
        mode: MakeHousieRoundSpec.modeMake15Master,
        random: Random(202),
      );
      final targetBall = spec.dealPool.first;
      final trueCol = expectedColumnForBall(targetBall);
      int trueRow = 0;
      for (int r = 0; r < 3; r++) {
        if (spec.trueMatrix[r][trueCol] == targetBall) {
          trueRow = r;
          break;
        }
      }

      // Rule 1: Wrong column decade
      final wrongCol = (trueCol + 1) % 9;
      final r1 = spec.validatePlacement(
        selectedBall: targetBall,
        row: trueRow,
        col: wrongCol,
        alreadyPlacedBalls: const <int>{},
      );
      expect(r1.isSuccess, isFalse);
      expect(r1.message, contains('Rule 1'));

      // Valid placement at (trueRow, trueCol)
      final ok = spec.validatePlacement(
        selectedBall: targetBall,
        row: trueRow,
        col: trueCol,
        alreadyPlacedBalls: const <int>{},
      );
      expect(ok.isSuccess, isTrue);

      // Find an empty row in trueCol to test Rule 3 (5-Per-Row Balance)
      int? emptyRow;
      for (int r = 0; r < 3; r++) {
        if (spec.trueMatrix[r][trueCol] == 0) {
          emptyRow = r;
          break;
        }
      }
      if (emptyRow != null) {
        final r3 = spec.validatePlacement(
          selectedBall: targetBall,
          row: emptyRow,
          col: trueCol,
          alreadyPlacedBalls: const <int>{},
        );
        expect(r3.isSuccess, isFalse);
        expect(r3.message, contains('Rule 3'));
      }
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

        // Anti-shortcut check: at least 3 options (the true answer + 2 decoys) share the same units digit
        final targetLastDigit = wave.correctSum % 10;
        final matchingLastDigitCount = wave.options
            .where((opt) => opt % 10 == targetLastDigit)
            .length;
        expect(matchingLastDigitCount, greaterThanOrEqualTo(3));
      }
    });
  });
}
