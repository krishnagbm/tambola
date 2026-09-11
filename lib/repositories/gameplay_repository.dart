import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../core/utils/tambola_ticket.dart';
import '../models/mpt_called_number.dart';
import '../models/mpt_claim.dart';
import '../models/mpt_ticket.dart';
import 'package:flutter/foundation.dart';

class GameplayRepository {
  final SupabaseClient _supabase;

  GameplayRepository(this._supabase);

  /// Atomically starts game and deducts credits
  Future<Map<String, dynamic>> startGame(String gameId) async {
    final idempotencyKey = const Uuid().v4();
    try {
      final res = await _supabase.rpc('MPT_start_game_and_charge', params: {
        'p_game_id': gameId,
        'p_idempotency_key': idempotencyKey,
      });
      return res as Map<String, dynamic>;
    } catch (e) {
      debugPrint('MPT_start_game_and_charge failed: $e');
      rethrow;
    }
  }

  /// Calls the next random number for the game
  Future<int?> callNextNumber(String gameId) async {
    try {
      final res = await _supabase.rpc('MPT_call_next_number', params: {
        'p_game_id': gameId,
      });
      if (res is Map<String, dynamic> && res['number'] != null) {
        return (res['number'] as num).toInt();
      }
    } catch (e) {
      // Fallback
      final called = await getCalledNumbers(gameId);
      final calledSet = called.map((e) => e.number).toSet();
      final uncalled = List.generate(90, (i) => i + 1).where((n) => !calledSet.contains(n)).toList();
      if (uncalled.isEmpty) return null;

      uncalled.shuffle();
      final nextNum = uncalled.first;
      await _supabase.from('MPT_called_numbers').insert({
        'game_id': gameId,
        'number': nextNum,
        'call_seq': called.length + 1,
      });
      return nextNum;
    }
    return null;
  }

  /// Gets all called numbers so far
  Future<List<MptCalledNumber>> getCalledNumbers(String gameId) async {
    final res = await _supabase
        .from('MPT_called_numbers')
        .select()
        .eq('game_id', gameId)
        .order('call_seq', ascending: true);

    return (res as List).map((e) => MptCalledNumber.fromJson(e)).toList();
  }

  /// Smart Polling stream for called numbers (1.5s interval, 0 WebSocket connections)
  Stream<List<MptCalledNumber>> watchCalledNumbers(String gameId) async* {
    while (true) {
      try {
        final list = await getCalledNumbers(gameId);
        yield list;
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 1500));
    }
  }

  /// Gets player's issued ticket for the game with guaranteed server uniqueness
  Future<MptTicket> getOrCreatePlayerTicket(String gameId) async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) throw Exception('Auth required');

    // 1. Direct fetch if ticket is already generated (bulk game start path)
    final res = await _supabase
        .from('MPT_player_tickets')
        .select()
        .eq('game_id', gameId)
        .eq('user_id', uid)
        .maybeSingle();

    if (res != null) {
      return MptTicket.fromJson(res);
    }

    // 2. Canonical Server-Side RPC Path (Guaranteed uniqueness & registration_seq ticket_number)
    try {
      final rpcRes = await _supabase.rpc('MPT_get_or_create_player_ticket', params: {
        'p_game_id': gameId,
      });
      if (rpcRes != null) {
        return MptTicket.fromJson(rpcRes as Map<String, dynamic>);
      }
    } catch (_) {
      // Fallback below if RPC is unavailable in offline/mock environment
    }

    // 3. Fallback path (Direct table insert with registration_seq lookup & uniqueness check)
    final reg = await _supabase
        .from('MPT_game_registrations')
        .select('registration_seq')
        .eq('game_id', gameId)
        .eq('user_id', uid)
        .maybeSingle();

    final ticketSeq = (reg?['registration_seq'] as int?) ?? 1;

    List<List<int>> matrix = TambolaTicketHelper.generateSqlEquivalentTicket();

    // Up to 5 attempts to check against existing tickets in this room on fallback
    for (int attempt = 0; attempt < 5; attempt++) {
      final exists = await _supabase
          .from('MPT_player_tickets')
          .select('id')
          .eq('game_id', gameId)
          .eq('ticket_matrix', matrix)
          .maybeSingle();

      if (exists == null) {
        break;
      }
      matrix = TambolaTicketHelper.generateSqlEquivalentTicket();
    }

    final row = await _supabase.from('MPT_player_tickets').insert({
      'game_id': gameId,
      'user_id': uid,
      'ticket_matrix': matrix,
      'ticket_number': ticketSeq,
    }).select().single();

    return MptTicket.fromJson(row);
  }

  /// Submits prize claim with server validation
  Future<Map<String, dynamic>> submitClaim({
    required String gameId,
    required String prizeType,
    required List<int> markedNumbers,
  }) async {
    final idempotencyKey = const Uuid().v4();
    try {
      final res = await _supabase.rpc('MPT_submit_claim', params: {
        'p_game_id': gameId,
        'p_prize_type': prizeType,
        'p_marked_numbers': markedNumbers,
        'p_idempotency_key': idempotencyKey,
      });
      return res as Map<String, dynamic>;
    } catch (e) {
      // Direct table claim fallback if RPC is offline
      final uid = _supabase.auth.currentUser?.id;
      final called = await getCalledNumbers(gameId);
      final calledSet = called.map((e) => e.number).toSet();
      final markedSet = markedNumbers.toSet();

      // Check all marked numbers were actually called
      final uncalled = markedSet.difference(calledSet);
      if (uncalled.isNotEmpty) {
        return {
          'status': 'BOGEY',
          'reason': 'Contains uncalled numbers: ${uncalled.join(', ')}',
        };
      }

      // Check if prize already won
      final existingWins = await _supabase
          .from('MPT_claims')
          .select()
          .eq('game_id', gameId)
          .eq('prize_type', prizeType)
          .eq('status', 'APPROVED');

      if ((existingWins as List).isNotEmpty) {
        return {
          'status': 'REJECTED',
          'reason': 'Prize already won by another player',
        };
      }

      // Record approved claim
      final claimRef = 'MPT-REW-${DateTime.now().millisecondsSinceEpoch % 10000}';
      await _supabase.from('MPT_claims').insert({
        'game_id': gameId,
        'user_id': uid,
        'prize_type': prizeType,
        'status': 'APPROVED',
        'marked_numbers': markedNumbers,
      });

      return {
        'status': 'APPROVED',
        'prize_type': prizeType,
        'claim_reference': claimRef,
      };
    }
  }

  /// Ends the game and finalizes results
  Future<void> endGame(String gameId) async {
    await _supabase.from('MPT_games').update({
      'status': 'COMPLETED',
      'completed_at': DateTime.now().toIso8601String(),
    }).eq('id', gameId);
  }

  /// Smart Polling stream for game claims (2s interval, 0 WebSocket connections)
  Stream<List<MptClaim>> watchClaims(String gameId) async* {
    while (true) {
      try {
        final res = await _supabase
            .from('MPT_claims')
            .select('*, user:MPT_users(display_name, avatar)')
            .eq('game_id', gameId)
            .order('submitted_at', ascending: false);
        yield (res as List).map((e) => MptClaim.fromJson(e)).toList();
      } catch (_) {}
      await Future.delayed(const Duration(seconds: 2));
    }
  }
}
