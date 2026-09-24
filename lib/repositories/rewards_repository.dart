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

    return (res as List).map((e) => MptReward.fromJson(e)).toList();
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
