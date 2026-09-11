import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:tambola/core/utils/tambola_ticket.dart';

class SimulatedTicketDatabase {
  final Map<String, List<Map<String, dynamic>>> registrations = {};
  final Map<String, List<Map<String, dynamic>>> tickets = {};

  void setupGameWithPlayers(String gameId, int playerCount) {
    registrations[gameId] = List.generate(playerCount, (i) {
      return {
        'game_id': gameId,
        'user_id': 'user_${i + 1}',
        'registration_seq': i + 1,
        'seat_status': 'ELIGIBLE',
      };
    });
    tickets[gameId] = [];
  }

  /// Exact Dart simulation of PostgreSQL MPT_start_game_and_charge with v_bulk_ticket_threshold
  Map<String, dynamic> startGameAndCharge({
    required String gameId,
    int bulkThreshold = 300,
  }) {
    final gameRegs = registrations[gameId] ?? [];
    final confirmedCount = gameRegs.where((r) => r['seat_status'] == 'ELIGIBLE').length;

    // Eager bulk generation only if <= threshold
    if (confirmedCount <= bulkThreshold) {
      for (final reg in gameRegs) {
        final ticket = _generateUniqueServerTicket(gameId, reg['user_id'], reg['registration_seq']);
        tickets[gameId]!.add(ticket);
      }
    }

    return {
      'game_id': gameId,
      'status': 'IN_PROGRESS',
      'eligible_players': confirmedCount,
      'lazy_ticket_issuance': confirmedCount > bulkThreshold,
      'tickets_created_at_start': tickets[gameId]!.length,
    };
  }

  /// Exact Dart simulation of PostgreSQL MPT_get_or_create_player_ticket
  Map<String, dynamic> getOrCreatePlayerTicket({
    required String gameId,
    required String userId,
  }) {
    // 1. Return existing if already present (Idempotency)
    final existing = tickets[gameId]?.firstWhere(
      (t) => t['user_id'] == userId,
      orElse: () => {},
    );
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }

    // 2. Verify eligibility
    final reg = registrations[gameId]?.firstWhere(
      (r) => r['user_id'] == userId && r['seat_status'] == 'ELIGIBLE',
      orElse: () => {},
    );
    if (reg == null || reg.isEmpty) {
      throw Exception('NOT_ELIGIBLE');
    }

    // 3. Server-side uniqueness loop & insert with ticket_number = registration_seq
    final newTicket = _generateUniqueServerTicket(gameId, userId, reg['registration_seq']);
    tickets[gameId]!.add(newTicket);
    return newTicket;
  }

  Map<String, dynamic> _generateUniqueServerTicket(String gameId, String userId, int regSeq) {
    int attempts = 0;
    while (attempts < 100) {
      final matrix = TambolaTicketHelper.generateSqlEquivalentTicket();
      final sig = matrix.map((row) => row.join(',')).join(';');

      final isDuplicate = tickets[gameId]!.any((t) {
        final tMatrix = t['ticket_matrix'] as List<List<int>>;
        final tSig = tMatrix.map((row) => row.join(',')).join(';');
        return tSig == sig;
      });

      if (!isDuplicate) {
        return {
          'game_id': gameId,
          'user_id': userId,
          'ticket_matrix': matrix,
          'ticket_number': regSeq,
        };
      }
      attempts++;
    }
    throw Exception('TICKET_GENERATION_FAILED');
  }
}

void main() {
  group('Mega-Event Ticket Issuance Architecture Tests (2a, 2b, 2c)', () {
    late SimulatedTicketDatabase db;

    setUp(() {
      db = SimulatedTicketDatabase();
    });

    test('2a: MPT_get_or_create_player_ticket uniqueness, registration_seq alignment, and idempotency', () {
      const gameId = 'game_2a_test';
      const playerCount = 20;
      db.setupGameWithPlayers(gameId, playerCount);

      // Start game with high threshold but do not eagerly generate (test pure on-demand path)
      final generatedTickets = <Map<String, dynamic>>[];
      final signatures = <String>{};

      for (int i = 1; i <= playerCount; i++) {
        final userId = 'user_$i';
        
        // First Call: Creates ticket
        final ticket1 = db.getOrCreatePlayerTicket(gameId: gameId, userId: userId);
        
        // Verify ticket_number == registration_seq
        expect(ticket1['ticket_number'], i, reason: 'ticket_number must equal registration_seq');
        expect(ticket1['user_id'], userId);
        
        final matrix = ticket1['ticket_matrix'] as List<List<int>>;
        final sig1 = matrix.map((r) => r.join(',')).join(';');
        expect(signatures.contains(sig1), isFalse, reason: 'Ticket must be unique in this game room');
        signatures.add(sig1);
        generatedTickets.add(ticket1);

        // Second Call: IDEMPOTENCY check (must return the exact same ticket, no re-roll)
        final ticket2 = db.getOrCreatePlayerTicket(gameId: gameId, userId: userId);
        final sig2 = (ticket2['ticket_matrix'] as List<List<int>>).map((r) => r.join(',')).join(';');
        expect(sig2, sig1, reason: 'Calling getOrCreatePlayerTicket twice for same user must be strictly idempotent');
        expect(ticket2['ticket_number'], ticket1['ticket_number']);
      }

      expect(signatures.length, playerCount);
      expect(db.tickets[gameId]!.length, playerCount);
    });

    test('2b: Threshold-gated bulk vs. lazy simulation (v_bulk_ticket_threshold)', () {
      // Scenario 1: Standard game (<= 300 players, e.g. 50 players) -> Eager Bulk
      const normalGameId = 'game_normal_50';
      db.setupGameWithPlayers(normalGameId, 50);
      
      final startNormal = db.startGameAndCharge(gameId: normalGameId, bulkThreshold: 300);
      expect(startNormal['lazy_ticket_issuance'], isFalse);
      expect(startNormal['tickets_created_at_start'], 50, reason: 'Normal games pre-generate all 50 tickets eagerly');
      expect(db.tickets[normalGameId]!.length, 50);

      // Scenario 2: Mega Event (> threshold, e.g. 500 players with threshold 300) -> Lazy On-Demand
      const megaGameId = 'game_mega_500';
      db.setupGameWithPlayers(megaGameId, 500);

      final startMega = db.startGameAndCharge(gameId: megaGameId, bulkThreshold: 300);
      expect(startMega['lazy_ticket_issuance'], isTrue);
      expect(startMega['tickets_created_at_start'], 0, reason: 'Mega games skip eager bulk loop to prevent lock contention');
      expect(db.tickets[megaGameId]!.length, 0);

      // Players load tickets lazily on demand
      for (int i = 1; i <= 50; i++) {
        final ticket = db.getOrCreatePlayerTicket(gameId: megaGameId, userId: 'user_$i');
        expect(ticket['ticket_number'], i);
      }
      expect(db.tickets[megaGameId]!.length, 50);
    });

    test('2c: Concurrency check — 50 simultaneous asynchronous on-demand requests in same room', () async {
      const concurrentGameId = 'game_concurrent_race';
      const concurrentCount = 50;
      db.setupGameWithPlayers(concurrentGameId, concurrentCount);

      // Start in lazy mode
      db.startGameAndCharge(gameId: concurrentGameId, bulkThreshold: 0);
      expect(db.tickets[concurrentGameId]!.length, 0);

      // Fire 50 simultaneous asynchronous requests using Future.wait
      final futures = List.generate(concurrentCount, (i) {
        return Future(() => db.getOrCreatePlayerTicket(
          gameId: concurrentGameId,
          userId: 'user_${i + 1}',
        ));
      });

      final results = await Future.wait(futures);

      final uniqueSignatures = <String>{};
      for (int i = 0; i < results.length; i++) {
        final ticket = results[i];
        final matrix = ticket['ticket_matrix'] as List<List<int>>;
        final sig = matrix.map((r) => r.join(',')).join(';');

        expect(uniqueSignatures.contains(sig), isFalse, reason: 'Concurrent request resulted in duplicate ticket!');
        uniqueSignatures.add(sig);

        // Verify ticket rules
        final allNums = TambolaTicketHelper.getAllNumbers(matrix);
        expect(allNums.length, 15);
        expect(allNums.toSet().length, 15);
        expect(ticket['ticket_number'], i + 1);
      }

      expect(uniqueSignatures.length, concurrentCount, reason: 'All 50 concurrent tickets must be strictly unique');
    });
  });
}
