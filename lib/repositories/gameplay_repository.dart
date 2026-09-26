import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../core/utils/tambola_ticket.dart';
import '../models/flash_housie_config.dart';
import '../models/mpt_called_number.dart';
import '../models/mpt_claim.dart';
import '../models/mpt_game.dart';
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

      // If this is a FlashHousie™ game, automatically launch Cycle 1's NeuroWave™ Spotlight
      try {
        final gameRow = await _supabase
            .from('MPT_games')
            .select()
            .eq('id', gameId)
            .maybeSingle();
        if (gameRow != null) {
          final game = MptGame.fromJson(gameRow);
          if (game.isFlashHousie &&
              game.flashHousieConfig!.activeCycleSpec.startedAtMs == null) {
            await launchFlashHousieCycle(game: game, cycleIndex: 1);
          }
        }
      } catch (e) {
        debugPrint('Auto-launch FlashHousie Cycle 1 non-fatal warning: $e');
      }

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
      final resultMap = Map<String, dynamic>.from(res as Map);

      // Defensive guarantee: if claim was APPROVED, ensure reward row exists in MPT_rewards
      if (resultMap['status'] == 'APPROVED') {
        final uid = _supabase.auth.currentUser?.id;
        final claimId = resultMap['claim_id'] as String?;
        final claimRef = resultMap['claim_reference'] as String?;
        if (uid != null && claimRef != null && claimRef.isNotEmpty) {
          try {
            final existingReward = await _supabase
                .from('MPT_rewards')
                .select('id')
                .eq('claim_reference', claimRef)
                .maybeSingle();
            if (existingReward == null) {
              await _supabase.from('MPT_rewards').insert({
                'game_id': gameId,
                'user_id': uid,
                'prize_type': prizeType,
                'claim_id': claimId,
                'claim_reference': claimRef,
                'status': 'AVAILABLE_TO_CLAIM',
              });
            }
          } catch (_) {}
        }
      }

      return resultMap;
    } catch (e) {
      debugPrint('MPT_submit_claim RPC fallback triggered: $e');
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

      // Record approved claim with canonical Dab-Housie-XXXX-XXXX format
      final rawHex = const Uuid().v4().replaceAll('-', '').toUpperCase();
      final claimRef =
          'Dab-Housie-${rawHex.substring(0, 4)}-${rawHex.substring(4, 8)}';
      final claimRes = await _supabase
          .from('MPT_claims')
          .insert({
            'game_id': gameId,
            'user_id': uid,
            'prize_type': prizeType,
            'status': 'APPROVED',
            'marked_numbers': markedNumbers,
          })
          .select()
          .maybeSingle();

      try {
        await _supabase.from('MPT_rewards').insert({
          'game_id': gameId,
          'user_id': uid,
          'prize_type': prizeType,
          'claim_id': claimRes?['id'],
          'claim_reference': claimRef,
          'status': 'AVAILABLE_TO_CLAIM',
        });
      } catch (rewardErr) {
        debugPrint('Fallback MPT_rewards insert failed: $rewardErr');
      }

      return {
        'status': 'APPROVED',
        'prize_type': prizeType,
        'claim_reference': claimRef,
      };
    }
  }

  /// Ends the game, marks it COMPLETED, and archives it to Hall of Fame
  Future<void> endGame(String gameId) async {
    try {
      await _supabase.rpc('MPT_archive_concluded_game', params: {
        'p_game_id': gameId,
      });
    } catch (_) {
      await _supabase.from('MPT_games').update({
        'status': 'COMPLETED',
        'completed_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', gameId);
    }
  }

  /// Smart Polling stream for game claims (2s interval, 0 WebSocket connections)
  Stream<List<MptClaim>> watchClaims(String gameId) async* {
    while (true) {
      try {
        final rpcRes = await _supabase.rpc('MPT_get_game_claims', params: {'p_game_id': gameId});
        if (rpcRes is List) {
          yield (rpcRes).map((e) => MptClaim.fromJson(Map<String, dynamic>.from(e as Map))).toList();
        } else {
          final res = await _supabase
              .from('MPT_claims')
              .select('*, user:MPT_users(display_name, avatar)')
              .eq('game_id', gameId)
              .order('submitted_at', ascending: false);
          yield (res as List).map((e) => MptClaim.fromJson(e)).toList();
        }
      } catch (_) {
        try {
          final res = await _supabase
              .from('MPT_claims')
              .select('*')
              .eq('game_id', gameId)
              .order('submitted_at', ascending: false);
          yield (res as List).map((e) => MptClaim.fromJson(e)).toList();
        } catch (_) {}
      }
      await Future.delayed(const Duration(seconds: 2));
    }
  }

  // ===========================================================================
  // FLASHHOUSIE™ 5 / 10 / 15 & NEUROWAVE™ SPOTLIGHT ENGINE
  // ===========================================================================

  /// Persists an updated [FlashHousieConfig] into `MPT_games.prize_gifts_config['_flash_housie']`
  Future<void> updateFlashHousieConfig({
    required String gameId,
    required Map<String, dynamic> currentPrizeGiftsConfig,
    required FlashHousieConfig updatedConfig,
  }) async {
    final nextPrizeGifts = Map<String, dynamic>.from(currentPrizeGiftsConfig);
    nextPrizeGifts['_flash_housie'] = updatedConfig.toJson();
    await _supabase
        .from('MPT_games')
        .update({
          'prize_gifts_config': nextPrizeGifts,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', gameId);
  }

  /// Launches the NeuroWave™ Spotlight countdown for [cycleIndex]
  Future<void> launchFlashHousieCycle({
    required MptGame game,
    required int cycleIndex,
  }) async {
    final config = game.flashHousieConfig;
    if (config == null) return;

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final updatedCycles = config.cycles.map((c) {
      if (c.cycleIndex == cycleIndex) {
        return c.copyWith(startedAtMs: nowMs);
      }
      return c;
    }).toList();

    final updatedConfig = config.copyWith(
      currentCycle: cycleIndex,
      cycles: updatedCycles,
    );

    await updateFlashHousieConfig(
      gameId: game.id,
      currentPrizeGiftsConfig: game.prizeGiftsConfig,
      updatedConfig: updatedConfig,
    );
  }

  /// Draws the next number from the active FlashHousie™ cycle's constrained pool
  /// (True Quadrant Numbers + 1–2 Decoys/Col).
  Future<int?> callNextFlashHousieNumber(MptGame game) async {
    final config = game.flashHousieConfig;
    if (config == null) return null;

    final activeSpec = config.activeCycleSpec;
    final calledSet = activeSpec.calledNumbers.toSet();
    final remaining = activeSpec.drawPool
        .where((n) => !calledSet.contains(n))
        .toList();

    if (remaining.isEmpty) return null;

    final nextNum = remaining.first;
    final updatedCalled = [...activeSpec.calledNumbers, nextNum];

    final updatedCycles = config.cycles.map((c) {
      if (c.cycleIndex == activeSpec.cycleIndex) {
        return c.copyWith(calledNumbers: updatedCalled);
      }
      return c;
    }).toList();

    final updatedConfig = config.copyWith(cycles: updatedCycles);
    await updateFlashHousieConfig(
      gameId: game.id,
      currentPrizeGiftsConfig: game.prizeGiftsConfig,
      updatedConfig: updatedConfig,
    );

    // Best-effort insert into MPT_called_numbers for audio/legacy stream compatibility
    try {
      final existing = await getCalledNumbers(game.id);
      final alreadyInTable = existing.any((e) => e.number == nextNum);
      if (!alreadyInTable) {
        await _supabase.from('MPT_called_numbers').insert({
          'game_id': game.id,
          'number': nextNum,
          'call_seq': existing.length + 1,
        });
      }
    } catch (_) {}

    return nextNum;
  }

  /// Upserts a player's live memory recall score into `MPT_memory_round_scores` (Option-B Live TV Board)
  Future<void> upsertMemoryRoundScore({
    required String gameId,
    required int cycleIndex,
    required String quadrantLabel,
    required String displayName,
    required String avatar,
    required List<int> correctNumbers,
    required int wrongTapCount,
    required int totalReactionMs,
    int? lastRecalledNumber,
    int? lastReactionMs,
  }) async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return;

    try {
      await _supabase.from('MPT_memory_round_scores').upsert(
        {
          'game_id': gameId,
          'user_id': uid,
          'display_name': displayName,
          'avatar': avatar,
          'cycle_index': cycleIndex,
          'quadrant_label': quadrantLabel,
          'correct_numbers': correctNumbers,
          'correct_count': correctNumbers.length,
          'wrong_tap_count': wrongTapCount,
          'total_reaction_ms': totalReactionMs,
          'last_recalled_number': lastRecalledNumber,
          'last_reaction_ms': lastReactionMs,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'game_id,user_id,cycle_index',
      );
    } catch (e) {
      debugPrint('MPT_memory_round_scores upsert warning: $e');
    }
  }

  /// Fetches all `MPT_memory_round_scores` rows for a game
  Future<List<MptMemoryRoundScore>> getMemoryRoundScores(String gameId) async {
    try {
      final res = await _supabase
          .from('MPT_memory_round_scores')
          .select()
          .eq('game_id', gameId);
      final list = (res as List)
          .map((e) => MptMemoryRoundScore.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      list.sort(MptMemoryRoundScore.compareStandings);
      return list;
    } catch (e) {
      return const [];
    }
  }

  /// Smart Polling stream for `MPT_memory_round_scores` (1.5s interval for Live TV Board)
  Stream<List<MptMemoryRoundScore>> watchMemoryRoundScores(String gameId) async* {
    while (true) {
      final scores = await getMemoryRoundScores(gameId);
      yield scores;
      await Future.delayed(const Duration(milliseconds: 1500));
    }
  }

  /// Helper to record an approved FlashHousie™ claim + reward row in `MPT_claims` & `MPT_rewards`
  Future<void> _recordFlashHousieWinnerClaim({
    required String gameId,
    required String winnerUserId,
    required String prizeType,
    required List<int> markedNumbers,
  }) async {
    try {
      final existingWins = await _supabase
          .from('MPT_claims')
          .select('id')
          .eq('game_id', gameId)
          .eq('prize_type', prizeType)
          .eq('status', 'APPROVED');

      if ((existingWins as List).isNotEmpty) return;

      final rawHex = const Uuid().v4().replaceAll('-', '').toUpperCase();
      final claimRef =
          'Dab-Housie-${rawHex.substring(0, 4)}-${rawHex.substring(4, 8)}';

      final claimRes = await _supabase
          .from('MPT_claims')
          .insert({
            'game_id': gameId,
            'user_id': winnerUserId,
            'prize_type': prizeType,
            'status': 'APPROVED',
            'marked_numbers': markedNumbers,
          })
          .select()
          .maybeSingle();

      await _supabase.from('MPT_rewards').insert({
        'game_id': gameId,
        'user_id': winnerUserId,
        'prize_type': prizeType,
        'claim_id': claimRes?['id'],
        'claim_reference': claimRef,
        'status': 'AVAILABLE_TO_CLAIM',
      });
    } catch (e) {
      debugPrint('Direct host claim insert deferred to player client: $e');
    }
  }

  /// Crowns the current cycle's `Rx-Qx` Round Winner (`ROUND_x`) based on
  /// Max Correct Recalls -> Fewest Wrong Taps -> Fastest Cumulative Reaction Time,
  /// and optionally advances to the next cycle (`currentCycle + 1`).
  Future<FlashHousieConfig?> finalizeFlashHousieCycleAndAdvance({
    required MptGame game,
    required bool advanceToNextCycle,
  }) async {
    final config = game.flashHousieConfig;
    if (config == null) return null;

    final activeSpec = config.activeCycleSpec;
    final allScores = await getMemoryRoundScores(game.id);
    final cycleScores = allScores
        .where((s) => s.cycleIndex == activeSpec.cycleIndex && s.correctCount > 0)
        .toList()
      ..sort(MptMemoryRoundScore.compareStandings);

    final topScore = cycleScores.isNotEmpty ? cycleScores.first : null;

    final nextWinners = Map<String, String>.from(config.awardedWinners);
    final nextWinnerNames = Map<String, String>.from(config.awardedWinnerNames);

    if (topScore != null) {
      nextWinners[activeSpec.prizeKey] = topScore.userId;
      nextWinnerNames[activeSpec.prizeKey] = topScore.displayName;
      await _recordFlashHousieWinnerClaim(
        gameId: game.id,
        winnerUserId: topScore.userId,
        prizeType: activeSpec.prizeKey,
        markedNumbers: topScore.correctNumbers,
      );
    }

    final nextCycleIndex =
        (advanceToNextCycle && config.currentCycle < config.totalCycles)
            ? config.currentCycle + 1
            : config.currentCycle;
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    final updatedCycles = config.cycles.map((c) {
      if (c.cycleIndex == activeSpec.cycleIndex && topScore != null) {
        return c.copyWith(
          winnerUserId: topScore.userId,
          winnerName: topScore.displayName,
          winnerAvatar: topScore.avatar,
          winnerCorrectCount: topScore.correctCount,
          winnerReactionMs: topScore.totalReactionMs,
        );
      }
      if (advanceToNextCycle && c.cycleIndex == nextCycleIndex) {
        return c.copyWith(startedAtMs: nowMs);
      }
      return c;
    }).toList();

    final updatedConfig = config.copyWith(
      currentCycle: nextCycleIndex,
      cycles: updatedCycles,
      awardedWinners: nextWinners,
      awardedWinnerNames: nextWinnerNames,
    );

    await updateFlashHousieConfig(
      gameId: game.id,
      currentPrizeGiftsConfig: game.prizeGiftsConfig,
      updatedConfig: updatedConfig,
    );

    return updatedConfig;
  }

  /// Finalizes the final cycle AND crowns the Cumulative `FULL_HOUSE` (and `SECOND_FULL_HOUSE`)
  /// winners across all cycles combined.
  Future<FlashHousieConfig?> finalizeFlashHousieGrandWinners(MptGame game) async {
    // 1. First finalize the current cycle winner without advancing
    final afterCycleConfig = await finalizeFlashHousieCycleAndAdvance(
      game: game,
      advanceToNextCycle: false,
    );
    if (afterCycleConfig == null) return null;

    // 2. Aggregate cumulative scores across all cycles per user_id
    final allScores = await getMemoryRoundScores(game.id);
    final Map<String, MptMemoryRoundScore> cumulativeByUser = {};

    for (final s in allScores) {
      final existing = cumulativeByUser[s.userId];
      if (existing == null) {
        cumulativeByUser[s.userId] = s;
      } else {
        final combinedNums = <int>{...existing.correctNumbers, ...s.correctNumbers}.toList();
        cumulativeByUser[s.userId] = MptMemoryRoundScore(
          id: existing.id,
          gameId: existing.gameId,
          userId: existing.userId,
          displayName: s.displayName,
          avatar: s.avatar,
          cycleIndex: 0,
          quadrantLabel: 'CUMULATIVE',
          correctNumbers: combinedNums,
          correctCount: existing.correctCount + s.correctCount,
          wrongTapCount: existing.wrongTapCount + s.wrongTapCount,
          totalReactionMs: existing.totalReactionMs + s.totalReactionMs,
          updatedAt: s.updatedAt,
        );
      }
    }

    final rankedUsers = cumulativeByUser.values
        .where((u) => u.correctCount > 0)
        .toList()
      ..sort(MptMemoryRoundScore.compareStandings);

    final nextWinners = Map<String, String>.from(afterCycleConfig.awardedWinners);
    final nextWinnerNames = Map<String, String>.from(afterCycleConfig.awardedWinnerNames);

    if (rankedUsers.isNotEmpty && game.prizesConfig.contains('FULL_HOUSE')) {
      final firstWinner = rankedUsers[0];
      nextWinners['FULL_HOUSE'] = firstWinner.userId;
      nextWinnerNames['FULL_HOUSE'] = firstWinner.displayName;
      await _recordFlashHousieWinnerClaim(
        gameId: game.id,
        winnerUserId: firstWinner.userId,
        prizeType: 'FULL_HOUSE',
        markedNumbers: firstWinner.correctNumbers,
      );
    }

    if (rankedUsers.length >= 2 && game.prizesConfig.contains('SECOND_FULL_HOUSE')) {
      final secondWinner = rankedUsers[1];
      nextWinners['SECOND_FULL_HOUSE'] = secondWinner.userId;
      nextWinnerNames['SECOND_FULL_HOUSE'] = secondWinner.displayName;
      await _recordFlashHousieWinnerClaim(
        gameId: game.id,
        winnerUserId: secondWinner.userId,
        prizeType: 'SECOND_FULL_HOUSE',
        markedNumbers: secondWinner.correctNumbers,
      );
    }

    final finalConfig = afterCycleConfig.copyWith(
      awardedWinners: nextWinners,
      awardedWinnerNames: nextWinnerNames,
    );

    await updateFlashHousieConfig(
      gameId: game.id,
      currentPrizeGiftsConfig: game.prizeGiftsConfig,
      updatedConfig: finalConfig,
    );

    return finalConfig;
  }
}
