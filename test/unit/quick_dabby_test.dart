import 'package:flutter_test/flutter_test.dart';
import 'package:tambola/models/mpt_game.dart';

void main() {
  group('Quick Dabby & Duration Calculation Tests', () {
    test('MptGame correctly parses callingMode and isQuickDabby', () {
      final quickGameJson = {
        'id': 'test-quick-123',
        'admin_user_id': 'user-1',
        'name': 'Quick Dabby Sprint',
        'invite_code': 'QD1234',
        'status': 'IN_PROGRESS',
        'initial_funded_capacity': 5,
        'funded_capacity': 5,
        'prizes_config': ['EARLY_FIVE', 'FULL_HOUSE'],
        'prize_gifts_config': {
          '_calling_mode': 'QUICK_DABBY',
        },
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      };

      final game = MptGame.fromJson(quickGameJson);
      expect(game.callingMode, 'QUICK_DABBY');
      expect(game.isQuickDabby, isTrue);
    });

    test('MptGame defaults to CLASSIC calling mode when not specified', () {
      final classicGameJson = {
        'id': 'test-classic-456',
        'admin_user_id': 'user-2',
        'name': 'Classic 90-Ball Tambola',
        'invite_code': 'CL4567',
        'status': 'OPEN',
        'initial_funded_capacity': 5,
        'funded_capacity': 5,
        'prizes_config': ['EARLY_FIVE', 'FULL_HOUSE'],
        'prize_gifts_config': {},
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      };

      final game = MptGame.fromJson(classicGameJson);
      expect(game.callingMode, 'CLASSIC');
      expect(game.isQuickDabby, isFalse);
    });

    test('Active ticket numbers pool extraction deduplicates numbers accurately', () {
      // 2 sample player tickets (3x9 grids)
      final ticket1 = [
        [4, 0, 23, 0, 41, 0, 62, 0, 85],
        [0, 12, 0, 34, 0, 56, 0, 77, 0],
        [7, 0, 29, 0, 48, 0, 69, 0, 89],
      ];
      final ticket2 = [
        [4, 15, 0, 31, 0, 52, 0, 71, 0], // shares 4 with ticket1
        [0, 0, 23, 0, 44, 0, 66, 0, 88], // shares 23 with ticket1
        [9, 18, 0, 38, 0, 59, 0, 79, 0],
      ];

      final pool = <int>{};
      for (final t in [ticket1, ticket2]) {
        for (final row in t) {
          for (final cell in row) {
            if (cell > 0 && cell <= 90) {
              pool.add(cell);
            }
          }
        }
      }

      // Ticket 1 has 14 numbers, Ticket 2 has 14 numbers, sharing {4, 23}
      // Unique numbers should be exactly 14 + 14 - 2 = 26
      expect(pool.length, 26);
      expect(pool.contains(4), isTrue);
      expect(pool.contains(23), isTrue);
      expect(pool.contains(1), isFalse); // Not on any ticket
    });

    test('Game duration calculation computes accurate MM:SS and Xm Ys', () {
      final startedAt = DateTime(2026, 10, 28, 14, 0, 0);
      final completedAt = DateTime(2026, 10, 28, 14, 5, 24); // 5m 24s

      final diff = completedAt.difference(startedAt);
      expect(diff.inMinutes, 5);
      expect(diff.inSeconds % 60, 24);

      final m = diff.inMinutes;
      final s = diff.inSeconds % 60;
      final clockFormat = '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
      final textFormat = m > 0 ? '${m}m ${s}s' : '${s}s';

      expect(clockFormat, '05:24');
      expect(textFormat, '5m 24s');
    });
  });
}
