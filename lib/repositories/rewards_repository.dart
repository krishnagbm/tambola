import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/mpt_reward.dart';

class RewardsRepository {
  final SupabaseClient _supabase;

  RewardsRepository(this._supabase);

  static const String _rewardSelectQuery =
      '*, MPT_games(name, invite_code, started_at, completed_at, created_at, MPT_users(display_name))';

  /// Gets all rewards won by the current player, enriched with game & organizer context.
  /// Also self-heals any APPROVED claims for this user that may be missing a row in MPT_rewards.
  Future<List<MptReward>> getMyRewards() async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return [];

    // 1. Self-heal: check if user has any APPROVED claims without a reward record
    try {
      final approvedClaims = await _supabase
          .from('MPT_claims')
          .select('id, game_id, user_id, prize_type')
          .eq('user_id', uid)
          .eq('status', 'APPROVED');

      final existingRewards = await _supabase
          .from('MPT_rewards')
          .select('id, claim_id, game_id, prize_type')
          .eq('user_id', uid);

      final existingClaimIds = (existingRewards as List)
          .map((r) => r['claim_id'] as String?)
          .whereType<String>()
          .toSet();
      final existingGamePrizes = (existingRewards)
          .map((r) => '${r['game_id']}_${r['prize_type']}')
          .toSet();

      for (final c in (approvedClaims as List)) {
        final claimId = c['id'] as String;
        final gameId = c['game_id'] as String;
        final prizeType = c['prize_type'] as String;
        if (!existingClaimIds.contains(claimId) &&
            !existingGamePrizes.contains('${gameId}_$prizeType')) {
          final cleanHex = claimId.replaceAll('-', '').toUpperCase();
          final fallbackRef =
              'Dab-Housie-${cleanHex.substring(0, 4)}-${cleanHex.substring(4, 8)}';
          try {
            await _supabase.from('MPT_rewards').insert({
              'game_id': gameId,
              'user_id': uid,
              'prize_type': prizeType,
              'claim_id': claimId,
              'claim_reference': fallbackRef,
              'status': 'AVAILABLE_TO_CLAIM',
            });
          } catch (_) {}
        }
      }
    } catch (_) {}

    // 2. Join MPT_games -> MPT_users (organizer) in one query
    final res = await _supabase
        .from('MPT_rewards')
        .select(_rewardSelectQuery)
        .eq('user_id', uid)
        .order('created_at', ascending: false);

    final list = (res as List).map((e) => MptReward.fromJson(e)).toList();

    // 3. Enrich any rewards whose game was archived into MPT_game_archives
    final missingGameIds = list
        .where((r) => r.gameName == null || r.inviteCode == null)
        .map((r) => r.gameId)
        .toSet()
        .toList();

    if (missingGameIds.isNotEmpty) {
      try {
        final archives = await _supabase
            .from('MPT_game_archives')
            .select(
              'game_id, game_name, invite_code, host_name, org_name, concluded_at',
            )
            .inFilter('game_id', missingGameIds);
        final archiveMap = <String, Map<String, dynamic>>{};
        for (final row in (archives as List)) {
          final gid = row['game_id']?.toString();
          if (gid != null) {
            archiveMap[gid] = Map<String, dynamic>.from(row as Map);
          }
        }
        return list.map((r) {
          final arch = archiveMap[r.gameId];
          if (arch == null) return r;
          return MptReward(
            id: r.id,
            gameId: r.gameId,
            userId: r.userId,
            prizeType: r.prizeType,
            claimId: r.claimId,
            claimReference: r.claimReference,
            status: r.status,
            verifiedByAdminId: r.verifiedByAdminId,
            claimedAt: r.claimedAt,
            createdAt: r.createdAt,
            gameName: r.gameName ?? (arch['game_name'] as String?),
            inviteCode: r.inviteCode ?? (arch['invite_code'] as String?),
            gameDate:
                r.gameDate ??
                (arch['concluded_at'] != null
                    ? DateTime.tryParse(arch['concluded_at'].toString())
                    : null),
            organizerName:
                r.organizerName ??
                (arch['org_name'] as String?) ??
                (arch['host_name'] as String?),
            winnerName: r.winnerName,
            winnerAvatar: r.winnerAvatar,
          );
        }).toList();
      } catch (_) {}
    }

    return list;
  }

  /// Searches rewards by voucher reference code (case-insensitive) across MPT_rewards
  /// so players can look up a voucher code even if won in another tab/guest session.
  Future<List<MptReward>> searchRewardsByCode(String query) async {
    final trimmed = query.trim();
    if (trimmed.length < 3) return [];
    final normalized = trimmed.replaceFirst(
      RegExp(r'^mpt-(rew-)?', caseSensitive: false),
      'Dab-Housie-',
    );

    try {
      final res = await _supabase
          .from('MPT_rewards')
          .select(_rewardSelectQuery)
          .ilike('claim_reference', '%$normalized%')
          .order('created_at', ascending: false)
          .limit(20);

      return (res as List).map((e) => MptReward.fromJson(e)).toList();
    } catch (_) {
      return [];
    }
  }

  /// Fetches all prize rewards/claims for a hosted game (for the Organizer).
  Future<List<MptReward>> getGameRewardsForHost(String gameId) async {
    try {
      final res = await _supabase.rpc(
        'MPT_get_game_rewards_for_host',
        params: {'p_game_id': gameId},
      );
      if (res is List) {
        return res
            .map(
              (e) => MptReward.fromJson(Map<String, dynamic>.from(e as Map)),
            )
            .toList();
      }
    } catch (_) {}

    // Fallback direct query
    try {
      final rows = await _supabase
          .from('MPT_rewards')
          .select(_rewardSelectQuery)
          .eq('game_id', gameId)
          .order('created_at', ascending: true);
      return (rows as List).map((e) => MptReward.fromJson(e)).toList();
    } catch (_) {
      return [];
    }
  }

  /// Allows the Game Organizer to close/mark a single claim or all claims in a game as CLAIMED.
  Future<List<MptReward>> closeGameClaim({
    required String gameId,
    String? rewardId,
    String? claimId,
    bool closeAll = false,
  }) async {
    try {
      final res = await _supabase.rpc(
        'MPT_close_game_claim',
        params: {
          'p_game_id': gameId,
          'p_reward_id': rewardId,
          'p_claim_id': claimId,
          'p_close_all': closeAll,
        },
      );
      if (res is Map && res['rewards'] is List) {
        return (res['rewards'] as List)
            .map(
              (e) => MptReward.fromJson(Map<String, dynamic>.from(e as Map)),
            )
            .toList();
      }
    } catch (_) {
      // Fallback direct update
      final uid = _supabase.auth.currentUser?.id;
      var query = _supabase
          .from('MPT_rewards')
          .update({
            'status': 'CLAIMED',
            'verified_by_admin_id': uid,
            'claimed_at': DateTime.now().toIso8601String(),
          })
          .eq('game_id', gameId);

      if (!closeAll) {
        if (rewardId != null) {
          query = query.eq('id', rewardId);
        } else if (claimId != null) {
          query = query.eq('claim_id', claimId);
        }
      }
      await query;
    }
    return getGameRewardsForHost(gameId);
  }

  /// Admin verifies a claim reference code presented by a player
  Future<Map<String, dynamic>> verifyReward(String claimReference) async {
    try {
      final normalized = claimReference.trim().replaceFirst(
        RegExp(r'^mpt-(rew-)?', caseSensitive: false),
        'Dab-Housie-',
      );
      final res = await _supabase.rpc('MPT_verify_reward', params: {
        'p_claim_reference': normalized.toUpperCase(),
      });
      return res as Map<String, dynamic>;
    } catch (e) {
      return {
        'status': 'ERROR',
        'message': e.toString(),
      };
    }
  }
}
