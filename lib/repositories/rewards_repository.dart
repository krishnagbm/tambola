import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/mpt_reward.dart';

class RewardsRepository {
  final SupabaseClient _supabase;

  RewardsRepository(this._supabase);

  /// Gets all rewards won by the current player
  Future<List<MptReward>> getMyRewards() async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return [];

    final res = await _supabase
        .from('MPT_rewards')
        .select()
        .eq('user_id', uid)
        .order('created_at', ascending: false);

    return (res as List).map((e) => MptReward.fromJson(e)).toList();
  }

  /// Admin verifies a claim reference code presented by a player
  Future<Map<String, dynamic>> verifyReward(String claimReference) async {
    try {
      final res = await _supabase.rpc('MPT_verify_reward', params: {
        'p_claim_reference': claimReference.trim().toUpperCase(),
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
