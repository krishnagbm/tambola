import 'dart:convert';
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
    final uid = _supabase.auth.currentUser?.id;

    // Special path for FlashHousie™ 5 / 10 / 15 auto-scored & player-claimed prizes
    try {
      final gameRow = await _supabase
          .from('MPT_games')
          .select('prize_gifts_config')
          .eq('id', gameId)
          .maybeSingle();
      if (gameRow != null && gameRow['prize_gifts_config'] is Map) {
        final prizeGifts =
            Map<String, dynamic>.from(gameRow['prize_gifts_config'] as Map);
        final flashCfg = FlashHousieConfig.fromPrizeGiftsConfig(prizeGifts);
        if (flashCfg != null && uid != null) {
          final existingWins = await _supabase
              .from('MPT_claims')
              .select()
              .eq('game_id', gameId)
              .eq('prize_type', prizeType)
              .eq('status', 'APPROVED');
          final winList = List<Map<String, dynamic>>.from(existingWins as List);
          if (winList.isNotEmpty) {
            final myWin = winList.where((w) => w['user_id'] == uid).firstOrNull;
            if (myWin != null) {
              final existingReward = await _supabase
                  .from('MPT_rewards')
                  .select('claim_reference')
                  .eq('game_id', gameId)
                  .eq('prize_type', prizeType)
                  .eq('user_id', uid)
                  .maybeSingle();
              return {
                'status': 'APPROVED',
                'prize_type': prizeType,
                'claim_reference':
                    existingReward?['claim_reference'] as String? ?? 'FLASH-WIN',
              };
            }
            return {
              'status': 'REJECTED',
              'reason': 'Prize already won by another player',
            };
          }

          final awardedUid = flashCfg.awardedWinners[prizeType];
          if (awardedUid != null && awardedUid.isNotEmpty && awardedUid != uid) {
            return {
              'status': 'REJECTED',
              'reason': 'Prize already won by another player',
            };
          }

          final allScores = await getMemoryRoundScores(gameId);
          String scoreSummary =
              flashCfg.awardedWinnerScoreSummaries[prizeType] ?? '';
          String winnerDisplayName =
              flashCfg.awardedWinnerNames[prizeType] ?? 'Player';
          List<int> numbersToRecord = List<int>.from(markedNumbers);

          if (prizeType.startsWith('ROUND_')) {
            final rNum = int.tryParse(prizeType.replaceFirst('ROUND_', '')) ??
                flashCfg.currentCycle;
            final cSpec = flashCfg.cycleAt(rNum) ?? flashCfg.activeCycleSpec;
            final myScore = allScores
                .where((s) => s.cycleIndex == rNum && s.userId == uid)
                .firstOrNull;
            if (myScore != null && myScore.displayName.isNotEmpty) {
              winnerDisplayName = myScore.displayName;
            }
            final calledInCycle = cSpec.calledNumbers.toSet();
            final trueInCycle = cSpec.trueNumbers.toSet();
            final validMarked = markedNumbers
                .where((n) => trueInCycle.contains(n) && calledInCycle.contains(n))
                .toSet();
            if (myScore != null) {
              validMarked.addAll(myScore.correctNumbers);
            }
            numbersToRecord = validMarked.toList();

            if (awardedUid != uid) {
              if (validMarked.isEmpty) {
                return {
                  'status': 'REJECTED',
                  'reason': 'Recall at least 1 called number in Round $rNum to claim.',
                };
              }
              if (!cSpec.isCompleted &&
                  validMarked.length < cSpec.trueNumbers.length) {
                return {
                  'status': 'REJECTED',
                  'reason':
                      'Recall all ${cSpec.trueNumbers.length} numbers (${validMarked.length}/${cSpec.trueNumbers.length}) or wait for all ${cSpec.drawPool.length} round balls to be called.',
                };
              }
              if (cSpec.isCompleted &&
                  validMarked.length < cSpec.trueNumbers.length) {
                final cycleScores = allScores
                    .where((s) => s.cycleIndex == rNum && s.correctCount > 0)
                    .toList()
                  ..sort(MptMemoryRoundScore.compareStandings);
                if (cycleScores.isNotEmpty &&
                    cycleScores.first.userId != uid &&
                    cycleScores.first.correctCount > validMarked.length) {
                  return {
                    'status': 'REJECTED',
                    'reason':
                        '${cycleScores.first.displayName} won Round $rNum with ${cycleScores.first.correctCount}/${cSpec.trueNumbers.length} recalls.',
                  };
                }
              }
            }

            final wrongCount = myScore?.wrongTapCount ?? 0;
            final netScore =
                (validMarked.length *
                    MptMemoryRoundScore.pointsPerCorrectRecall) -
                (wrongCount * MptMemoryRoundScore.penaltyPerWrongTap);
            final reactMs =
                myScore?.totalReactionMs ?? (validMarked.length * 2200);
            final reactSec = (reactMs / 1000).toStringAsFixed(1);
            if (scoreSummary.isEmpty) {
              scoreSummary =
                  '⭐ $netScore pts • ✓ ${validMarked.length}/${cSpec.trueNumbers.length}${wrongCount > 0 ? ' • ✗ $wrongCount (-${wrongCount * MptMemoryRoundScore.penaltyPerWrongTap})' : ''} • ⚡ ${reactSec}s';
            }
          } else {
            // FULL_HOUSE or SECOND_FULL_HOUSE
            final myScores = allScores.where((s) => s.userId == uid).toList();
            if (myScores.isNotEmpty && myScores.first.displayName.isNotEmpty) {
              winnerDisplayName = myScores.first.displayName;
            }
            final totalTargets = flashCfg.totalTargetNumbersAcrossAllCycles;
            final allCalledTrueNums = <int>{
              for (final c in flashCfg.cycles)
                ...c.trueNumbers.where((n) => c.calledNumbers.contains(n)),
            };
            final validMarkedAll = markedNumbers
                .where((n) => allCalledTrueNums.contains(n))
                .toSet();
            for (final s in myScores) {
              validMarkedAll.addAll(s.correctNumbers);
            }
            numbersToRecord = validMarkedAll.toList();

            final scoreSum =
                myScores.fold<int>(0, (sum, s) => sum + s.correctCount);
            final totalRecalled = scoreSum >= validMarkedAll.length
                ? scoreSum
                : validMarkedAll.length;
            final totalWrong =
                myScores.fold<int>(0, (sum, s) => sum + s.wrongTapCount);
            final netScore =
                (totalRecalled * MptMemoryRoundScore.pointsPerCorrectRecall) -
                (totalWrong * MptMemoryRoundScore.penaltyPerWrongTap);
            final totalReactMs = myScores.isNotEmpty
                ? myScores.fold<int>(0, (sum, s) => sum + s.totalReactionMs)
                : (totalRecalled * 2200);
            final lastRoundKey = 'ROUND_${flashCfg.totalCycles}';
            final lastRoundWins = await _supabase
                .from('MPT_claims')
                .select('id')
                .eq('game_id', gameId)
                .eq('prize_type', lastRoundKey)
                .eq('status', 'APPROVED');
            final isLastRoundDone =
                flashCfg.cycles.last.isCompleted ||
                flashCfg.awardedWinners.containsKey(lastRoundKey) ||
                (lastRoundWins as List).isNotEmpty;
            if (awardedUid != uid &&
                !isLastRoundDone &&
                totalRecalled < totalTargets) {
              return {
                'status': 'REJECTED',
                'reason':
                    'Recall all $totalTargets numbers ($totalRecalled/$totalTargets) or complete the final round to claim Full House.',
              };
            }
            final reactSec = (totalReactMs / 1000).toStringAsFixed(1);
            if (scoreSummary.isEmpty) {
              scoreSummary =
                  '⭐ $netScore pts • ✓ $totalRecalled/$totalTargets${totalWrong > 0 ? ' • ✗ $totalWrong (-${totalWrong * MptMemoryRoundScore.penaltyPerWrongTap})' : ''} • ⚡ ${reactSec}s';
            }
          }

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
                'marked_numbers': numbersToRecord,
                'rejection_reason': scoreSummary,
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
          } catch (_) {}

          final nextWinners = Map<String, String>.from(flashCfg.awardedWinners)
            ..[prizeType] = uid;
          final nextNames =
              Map<String, String>.from(flashCfg.awardedWinnerNames)
                ..[prizeType] = winnerDisplayName;
          final nextSummaries =
              Map<String, String>.from(flashCfg.awardedWinnerScoreSummaries)
                ..[prizeType] = scoreSummary;

          // If the final round (e.g. ROUND_3 of 3) was just won, automatically crown FULL_HOUSE immediately!
          if (prizeType == 'ROUND_${flashCfg.totalCycles}') {
            try {
              final fhWins = await _supabase
                  .from('MPT_claims')
                  .select('id')
                  .eq('game_id', gameId)
                  .eq('prize_type', 'FULL_HOUSE')
                  .eq('status', 'APPROVED');
              if ((fhWins as List).isEmpty) {
                final updatedAllScores = await getMemoryRoundScores(gameId);
                final Map<String, MptMemoryRoundScore> cumByUser = {};
                for (final s in updatedAllScores) {
                  final ex = cumByUser[s.userId];
                  if (ex == null) {
                    cumByUser[s.userId] = s;
                  } else {
                    final comb = <int>{
                      ...ex.correctNumbers,
                      ...s.correctNumbers,
                    }.toList();
                    cumByUser[s.userId] = MptMemoryRoundScore(
                      id: ex.id,
                      gameId: ex.gameId,
                      userId: ex.userId,
                      displayName: s.displayName,
                      avatar: s.avatar,
                      cycleIndex: 0,
                      quadrantLabel: 'CUMULATIVE',
                      correctNumbers: comb,
                      correctCount: ex.correctCount + s.correctCount,
                      wrongTapCount: ex.wrongTapCount + s.wrongTapCount,
                      totalReactionMs: ex.totalReactionMs + s.totalReactionMs,
                      updatedAt: s.updatedAt,
                    );
                  }
                }
                final ranked = cumByUser.values
                    .where((u) => u.correctCount > 0)
                    .toList()
                  ..sort(MptMemoryRoundScore.compareStandings);
                final fhWinner = ranked.isNotEmpty ? ranked.first : null;
                final fhUid = fhWinner?.userId ?? uid;
                final fhName = fhWinner?.displayName ?? winnerDisplayName;
                final totalTargets = flashCfg.totalTargetNumbersAcrossAllCycles;
                final fhCount = fhWinner?.correctCount ?? numbersToRecord.length;
                final fhReactSec =
                    (((fhWinner?.totalReactionMs ?? 15000) / 1000))
                        .toStringAsFixed(1);
                final fhSummary =
                    '✓ $fhCount/$totalTargets Total Recalls • ⚡ ${fhReactSec}s';
                nextWinners['FULL_HOUSE'] = fhUid;
                nextNames['FULL_HOUSE'] = fhName;
                nextSummaries['FULL_HOUSE'] = fhSummary;
                await _recordFlashHousieWinnerClaim(
                  gameId: gameId,
                  winnerUserId: fhUid,
                  prizeType: 'FULL_HOUSE',
                  markedNumbers: fhWinner?.correctNumbers ?? numbersToRecord,
                  scoreSummary: fhSummary,
                );
              }
            } catch (_) {}
          }

          // Best-effort sync into MPT_games.prize_gifts_config['_flash_housie']
          try {
            await updateFlashHousieConfig(
              gameId: gameId,
              currentPrizeGiftsConfig: prizeGifts,
              updatedConfig: flashCfg.copyWith(
                awardedWinners: nextWinners,
                awardedWinnerNames: nextNames,
                awardedWinnerScoreSummaries: nextSummaries,
              ),
            );
          } catch (_) {}

          // If FULL_HOUSE (or final round) was just won, immediately mark game COMPLETED & archive!
          if (prizeType == 'FULL_HOUSE' ||
              prizeType == 'ROUND_${flashCfg.totalCycles}' ||
              nextWinners.containsKey('FULL_HOUSE')) {
            try {
              await endGame(gameId);
            } catch (_) {}
          }

          return {
            'status': 'APPROVED',
            'prize_type': prizeType,
            'claim_reference': claimRef,
            'score_summary': scoreSummary,
          };
        }
      }
    } catch (e) {
      debugPrint('FlashHousie submitClaim path warning: $e');
    }

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
    final nowIso = DateTime.now().toUtc().toIso8601String();
    try {
      await _supabase
          .from('MPT_games')
          .update({
            'status': 'COMPLETED',
            'completed_at': nowIso,
            'updated_at': nowIso,
          })
          .eq('id', gameId);
    } catch (e) {
      debugPrint('Direct MPT_games COMPLETED update warning: $e');
    }

    try {
      await _supabase.rpc('MPT_archive_concluded_game', params: {
        'p_game_id': gameId,
      });
    } catch (e) {
      debugPrint('MPT_archive_concluded_game RPC warning: $e');
    }
  }

  /// Smart Polling stream for game claims (2s interval, 0 WebSocket connections)
  Stream<List<MptClaim>> watchClaims(String gameId) async* {
    while (true) {
      try {
        final rpcRes = await _supabase.rpc('MPT_get_game_claims', params: {'p_game_id': gameId});
        if (rpcRes is List) {
          yield (rpcRes)
              .map((e) => MptClaim.fromJson(Map<String, dynamic>.from(e as Map)))
              .where((c) => !c.prizeType.startsWith('FLASH_SCORE_'))
              .toList();
        } else {
          final res = await _supabase
              .from('MPT_claims')
              .select('*, user:MPT_users(display_name, avatar)')
              .eq('game_id', gameId)
              .order('submitted_at', ascending: false);
          yield (res as List)
              .map((e) => MptClaim.fromJson(e))
              .where((c) => !c.prizeType.startsWith('FLASH_SCORE_'))
              .toList();
        }
      } catch (_) {
        try {
          final res = await _supabase
              .from('MPT_claims')
              .select('*')
              .eq('game_id', gameId)
              .order('submitted_at', ascending: false);
          yield (res as List)
              .map((e) => MptClaim.fromJson(e))
              .where((c) => !c.prizeType.startsWith('FLASH_SCORE_'))
              .toList();
        } catch (_) {}
      }
      await Future.delayed(const Duration(seconds: 2));
    }
  }

  // ===========================================================================
  // FLASHHOUSIE™ 5 / 10 / 15 & NEUROWAVE™ SPOTLIGHT ENGINE
  // ===========================================================================

  /// In-memory score cache per gameId -> '${cycleIndex}_$userId' so local/same-browser
  /// sessions and hosts have zero-latency score visibility even before DB migration.
  static final Map<String, Map<String, MptMemoryRoundScore>>
      _localMemoryScoreCache = {};

  /// Persists an updated [FlashHousieConfig] into `MPT_games.prize_gifts_config['_flash_housie']`
  Future<void> updateFlashHousieConfig({
    required String gameId,
    required Map<String, dynamic> currentPrizeGiftsConfig,
    required FlashHousieConfig updatedConfig,
  }) async {
    final mergedEmbedded = <String, MptMemoryRoundScore>{
      ...updatedConfig.embeddedScores,
      ...?_localMemoryScoreCache[gameId],
    };
    final configToSave = updatedConfig.copyWith(embeddedScores: mergedEmbedded);
    final nextPrizeGifts = Map<String, dynamic>.from(currentPrizeGiftsConfig);
    nextPrizeGifts['_flash_housie'] = configToSave.toJson();
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

  /// Upserts a player's live memory recall score into `MPT_memory_round_scores`
  /// AND persists a backup into `MPT_games.prize_gifts_config['_flash_housie']['embedded_scores']`
  /// plus the in-memory `_localMemoryScoreCache`.
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

    final scoreKey = '${cycleIndex}_$uid';
    final now = DateTime.now().toUtc();
    final scoreObj = MptMemoryRoundScore(
      id: scoreKey,
      gameId: gameId,
      userId: uid,
      displayName: displayName,
      avatar: avatar,
      cycleIndex: cycleIndex,
      quadrantLabel: quadrantLabel,
      correctNumbers: List<int>.from(correctNumbers),
      correctCount: correctNumbers.length,
      wrongTapCount: wrongTapCount,
      totalReactionMs: totalReactionMs,
      lastRecalledNumber: lastRecalledNumber,
      lastReactionMs: lastReactionMs,
      updatedAt: now,
    );

    // 1. Always store in local memory cache immediately
    _localMemoryScoreCache.putIfAbsent(gameId, () => {})[scoreKey] = scoreObj;

    // 2. Try upserting into dedicated MPT_memory_round_scores table
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
          'updated_at': now.toIso8601String(),
        },
        onConflict: 'game_id,user_id,cycle_index',
      );
    } catch (e) {
      debugPrint('MPT_memory_round_scores upsert fallback to embedded_scores: $e');
    }

    // 3. Persist into player-writable MPT_claims telemetry row ('FLASH_SCORE_R$cycleIndex')
    // so non-host player scores sync across browsers/devices with 100% RLS compatibility
    try {
      final telemetryPrizeType = 'FLASH_SCORE_R$cycleIndex';
      final encodedScore = jsonEncode(scoreObj.toJson());
      final existingRow = await _supabase
          .from('MPT_claims')
          .select('id')
          .eq('game_id', gameId)
          .eq('user_id', uid)
          .eq('prize_type', telemetryPrizeType)
          .maybeSingle();
      if (existingRow != null && existingRow['id'] != null) {
        await _supabase
            .from('MPT_claims')
            .update({
              'marked_numbers': correctNumbers,
              'rejection_reason': encodedScore,
            })
            .eq('id', existingRow['id']);
      } else {
        await _supabase.from('MPT_claims').insert({
          'game_id': gameId,
          'user_id': uid,
          'prize_type': telemetryPrizeType,
          'status': 'SUBMITTED',
          'marked_numbers': correctNumbers,
          'rejection_reason': encodedScore,
        });
      }
    } catch (_) {}

    // 4. Also persist into MPT_games.prize_gifts_config['_flash_housie']['embedded_scores']
    try {
      final gameRow = await _supabase
          .from('MPT_games')
          .select('prize_gifts_config')
          .eq('id', gameId)
          .maybeSingle();
      if (gameRow != null && gameRow['prize_gifts_config'] is Map) {
        final prizeGifts =
            Map<String, dynamic>.from(gameRow['prize_gifts_config'] as Map);
        final flashCfg = FlashHousieConfig.fromPrizeGiftsConfig(prizeGifts);
        if (flashCfg != null) {
          final nextEmbedded = Map<String, MptMemoryRoundScore>.from(
            flashCfg.embeddedScores,
          );
          nextEmbedded[scoreKey] = scoreObj;
          await updateFlashHousieConfig(
            gameId: gameId,
            currentPrizeGiftsConfig: prizeGifts,
            updatedConfig: flashCfg.copyWith(embeddedScores: nextEmbedded),
          );
        }
      }
    } catch (_) {}
  }

  /// Helper to pick the more complete / newer score between two snapshots
  MptMemoryRoundScore _pickBetterScore(
    MptMemoryRoundScore a,
    MptMemoryRoundScore b,
  ) {
    if (b.correctCount != a.correctCount) {
      return b.correctCount > a.correctCount ? b : a;
    }
    if (b.wrongTapCount != a.wrongTapCount) {
      return b.wrongTapCount > a.wrongTapCount ? b : a;
    }
    return b.updatedAt.isAfter(a.updatedAt) ? b : a;
  }

  /// Fetches and merges all `MPT_memory_round_scores` rows, `MPT_claims` telemetry rows,
  /// `embeddedScores`, and `_localMemoryScoreCache` for a game
  Future<List<MptMemoryRoundScore>> getMemoryRoundScores(String gameId) async {
    final merged = <String, MptMemoryRoundScore>{};

    // 1. Local memory cache
    final localMap = _localMemoryScoreCache[gameId];
    if (localMap != null) {
      merged.addAll(localMap);
    }

    // 2. Embedded scores inside MPT_games.prize_gifts_config['_flash_housie']
    try {
      final gameRow = await _supabase
          .from('MPT_games')
          .select('prize_gifts_config')
          .eq('id', gameId)
          .maybeSingle();
      if (gameRow != null && gameRow['prize_gifts_config'] is Map) {
        final prizeGifts =
            Map<String, dynamic>.from(gameRow['prize_gifts_config'] as Map);
        final flashCfg = FlashHousieConfig.fromPrizeGiftsConfig(prizeGifts);
        if (flashCfg != null) {
          flashCfg.embeddedScores.forEach((k, v) {
            final existing = merged[k];
            merged[k] = existing == null ? v : _pickBetterScore(existing, v);
          });
        }
      }
    } catch (_) {}

    // 3. Player-writable MPT_claims telemetry rows ('FLASH_SCORE_R%')
    try {
      final claimRows = await _supabase
          .from('MPT_claims')
          .select('user_id, prize_type, marked_numbers, rejection_reason, submitted_at')
          .eq('game_id', gameId)
          .like('prize_type', 'FLASH_SCORE_R%');
      for (final raw in (claimRows as List)) {
        final rowMap = Map<String, dynamic>.from(raw as Map);
        final payloadStr = rowMap['rejection_reason'] as String?;
        if (payloadStr != null && payloadStr.trim().startsWith('{')) {
          final decoded = jsonDecode(payloadStr);
          if (decoded is Map) {
            final s = MptMemoryRoundScore.fromJson(
              Map<String, dynamic>.from(decoded),
            );
            final key = '${s.cycleIndex}_${s.userId}';
            final existing = merged[key];
            merged[key] = existing == null ? s : _pickBetterScore(existing, s);
          }
        }
      }
    } catch (_) {}

    // 3b. Reconstruct round scores from APPROVED 'ROUND_%' claims in MPT_claims
    try {
      final roundWinRows = await _supabase
          .from('MPT_claims')
          .select('user_id, prize_type, marked_numbers, rejection_reason, submitted_at')
          .eq('game_id', gameId)
          .eq('status', 'APPROVED')
          .like('prize_type', 'ROUND_%');
      for (final raw in (roundWinRows as List)) {
        final rowMap = Map<String, dynamic>.from(raw as Map);
        final userId = rowMap['user_id'] as String?;
        final prizeType = rowMap['prize_type'] as String?;
        if (userId == null || prizeType == null) continue;
        final cycleNum = int.tryParse(prizeType.replaceFirst('ROUND_', ''));
        if (cycleNum == null) continue;
        final markedRaw = rowMap['marked_numbers'];
        final markedList = markedRaw is List
            ? markedRaw.map((e) => (e as num).toInt()).toList()
            : <int>[];
        final reasonStr = rowMap['rejection_reason'] as String? ?? '';
        int reactionMs = 0;
        final match = RegExp(r'⚡\s*([\d.]+)s').firstMatch(reasonStr);
        if (match != null) {
          final secs = double.tryParse(match.group(1) ?? '');
          if (secs != null) reactionMs = (secs * 1000).round();
        }
        final key = '${cycleNum}_$userId';
        final existing = merged[key];
        final s = MptMemoryRoundScore(
          id: 'claim_${gameId}_r${cycleNum}_$userId',
          gameId: gameId,
          userId: userId,
          displayName: existing?.displayName ?? 'Player',
          avatar: existing?.avatar ?? '🎯',
          cycleIndex: cycleNum,
          quadrantLabel: 'R$cycleNum-Q$cycleNum',
          correctNumbers: markedList,
          correctCount: markedList.length,
          wrongTapCount: existing?.wrongTapCount ?? 0,
          totalReactionMs: reactionMs > 0
              ? reactionMs
              : (existing?.totalReactionMs ?? 0),
          updatedAt: DateTime.tryParse(rowMap['submitted_at']?.toString() ?? '') ??
              DateTime.now(),
        );
        if (existing == null || s.correctCount > existing.correctCount) {
          merged[key] = s;
        }
      }
    } catch (_) {}

    // 4. Dedicated MPT_memory_round_scores table (if migrated)
    try {
      final res = await _supabase
          .from('MPT_memory_round_scores')
          .select()
          .eq('game_id', gameId);
      for (final raw in (res as List)) {
        final s = MptMemoryRoundScore.fromJson(
          Map<String, dynamic>.from(raw as Map),
        );
        final key = '${s.cycleIndex}_${s.userId}';
        final existing = merged[key];
        merged[key] = existing == null ? s : _pickBetterScore(existing, s);
      }
    } catch (_) {}

    final list = merged.values.toList()
      ..sort(MptMemoryRoundScore.compareStandings);
    return list;
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
    String? scoreSummary,
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
            if (scoreSummary != null && scoreSummary.isNotEmpty)
              'rejection_reason': scoreSummary,
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
    // Always fetch latest game snapshot from DB so we don't overwrite recent embeddedScores
    MptGame latestGame = game;
    try {
      final row = await _supabase
          .from('MPT_games')
          .select()
          .eq('id', game.id)
          .maybeSingle();
      if (row != null) {
        latestGame = MptGame.fromJson(row);
      }
    } catch (_) {}

    final config = latestGame.flashHousieConfig ?? game.flashHousieConfig;
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
    final nextWinnerSummaries =
        Map<String, String>.from(config.awardedWinnerScoreSummaries);

    if (topScore != null && !nextWinners.containsKey(activeSpec.prizeKey)) {
      final wrongPart = topScore.wrongTapCount > 0
          ? ' • ✗ ${topScore.wrongTapCount} (-${topScore.wrongTapCount * MptMemoryRoundScore.penaltyPerWrongTap})'
          : '';
      final summaryStr =
          '⭐ ${topScore.netScore} pts • ✓ ${topScore.correctCount}/${activeSpec.trueNumbers.length}$wrongPart • ⚡ ${(topScore.totalReactionMs / 1000).toStringAsFixed(1)}s';
      nextWinners[activeSpec.prizeKey] = topScore.userId;
      nextWinnerNames[activeSpec.prizeKey] = topScore.displayName;
      nextWinnerSummaries[activeSpec.prizeKey] = summaryStr;
      await _recordFlashHousieWinnerClaim(
        gameId: game.id,
        winnerUserId: topScore.userId,
        prizeType: activeSpec.prizeKey,
        markedNumbers: topScore.correctNumbers,
        scoreSummary: summaryStr,
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
      awardedWinnerScoreSummaries: nextWinnerSummaries,
    );

    await updateFlashHousieConfig(
      gameId: game.id,
      currentPrizeGiftsConfig: latestGame.prizeGiftsConfig,
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
    final nextWinnerSummaries =
        Map<String, String>.from(afterCycleConfig.awardedWinnerScoreSummaries);
    final totalTargets = afterCycleConfig.totalTargetNumbersAcrossAllCycles;

    if (rankedUsers.isNotEmpty &&
        game.prizesConfig.contains('FULL_HOUSE') &&
        !nextWinners.containsKey('FULL_HOUSE')) {
      final firstWinner = rankedUsers[0];
      final wrongPart = firstWinner.wrongTapCount > 0
          ? ' • ✗ ${firstWinner.wrongTapCount} (-${firstWinner.wrongTapCount * MptMemoryRoundScore.penaltyPerWrongTap})'
          : '';
      final summaryStr =
          '⭐ ${firstWinner.netScore} pts • ✓ ${firstWinner.correctCount}/$totalTargets$wrongPart • ⚡ ${(firstWinner.totalReactionMs / 1000).toStringAsFixed(1)}s';
      nextWinners['FULL_HOUSE'] = firstWinner.userId;
      nextWinnerNames['FULL_HOUSE'] = firstWinner.displayName;
      nextWinnerSummaries['FULL_HOUSE'] = summaryStr;
      await _recordFlashHousieWinnerClaim(
        gameId: game.id,
        winnerUserId: firstWinner.userId,
        prizeType: 'FULL_HOUSE',
        markedNumbers: firstWinner.correctNumbers,
        scoreSummary: summaryStr,
      );
    }

    if (rankedUsers.length >= 2 &&
        game.prizesConfig.contains('SECOND_FULL_HOUSE') &&
        !nextWinners.containsKey('SECOND_FULL_HOUSE')) {
      final secondWinner = rankedUsers[1];
      final wrongPart = secondWinner.wrongTapCount > 0
          ? ' • ✗ ${secondWinner.wrongTapCount} (-${secondWinner.wrongTapCount * MptMemoryRoundScore.penaltyPerWrongTap})'
          : '';
      final summaryStr =
          '⭐ ${secondWinner.netScore} pts • ✓ ${secondWinner.correctCount}/$totalTargets$wrongPart • ⚡ ${(secondWinner.totalReactionMs / 1000).toStringAsFixed(1)}s';
      nextWinners['SECOND_FULL_HOUSE'] = secondWinner.userId;
      nextWinnerNames['SECOND_FULL_HOUSE'] = secondWinner.displayName;
      nextWinnerSummaries['SECOND_FULL_HOUSE'] = summaryStr;
      await _recordFlashHousieWinnerClaim(
        gameId: game.id,
        winnerUserId: secondWinner.userId,
        prizeType: 'SECOND_FULL_HOUSE',
        markedNumbers: secondWinner.correctNumbers,
        scoreSummary: summaryStr,
      );
    }

    final finalConfig = afterCycleConfig.copyWith(
      awardedWinners: nextWinners,
      awardedWinnerNames: nextWinnerNames,
      awardedWinnerScoreSummaries: nextWinnerSummaries,
    );

    // Fetch latest prizeGiftsConfig before saving
    Map<String, dynamic> latestPrizeGifts = game.prizeGiftsConfig;
    try {
      final row = await _supabase
          .from('MPT_games')
          .select('prize_gifts_config')
          .eq('id', game.id)
          .maybeSingle();
      if (row != null && row['prize_gifts_config'] is Map) {
        latestPrizeGifts =
            Map<String, dynamic>.from(row['prize_gifts_config'] as Map);
      }
    } catch (_) {}

    await updateFlashHousieConfig(
      gameId: game.id,
      currentPrizeGiftsConfig: latestPrizeGifts,
      updatedConfig: finalConfig,
    );

    if (finalConfig.awardedWinners.containsKey('FULL_HOUSE')) {
      try {
        await endGame(game.id);
      } catch (_) {}
    }

    return finalConfig;
  }
}
