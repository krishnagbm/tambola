import 'package:supabase_flutter/supabase_flutter.dart';

class AdminReportsRepository {
  final SupabaseClient _supabase;

  AdminReportsRepository(this._supabase);

  /// Check if the currently authenticated user has the 'ADMIN' role
  Future<Map<String, dynamic>> checkAdminRole() async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      return {'is_admin': false, 'role': 'ANONYMOUS', 'email': null};
    }

    try {
      final res = await _supabase.rpc('MPT_check_my_admin_role');
      if (res is Map<String, dynamic>) {
        return res;
      }
      return {'is_admin': false, 'role': 'HOST', 'email': user.email};
    } catch (_) {
      // Fallback direct check against MPT_admin_profiles if RPC is pending
      try {
        final profile = await _supabase
            .from('MPT_admin_profiles')
            .select('role, email')
            .eq('user_id', user.id)
            .maybeSingle();

        if (profile != null) {
          final role = profile['role'] as String? ?? 'HOST';
          return {
            'is_admin': role.toUpperCase() == 'ADMIN',
            'role': role,
            'email': profile['email'] ?? user.email,
          };
        }
      } catch (_) {}

      return {'is_admin': false, 'role': 'HOST', 'email': user.email};
    }
  }

  /// Fetch full executive KPI metrics and reports data
  Future<Map<String, dynamic>> getReportsOverview() async {
    try {
      final res = await _supabase.rpc('MPT_get_admin_reports_overview');
      if (res is Map<String, dynamic>) {
        return res;
      }
      return {};
    } catch (e) {
      rethrow;
    }
  }

  /// Toggle public visibility of a game in Recent Games / Hall of Fame
  Future<bool> setGamePublicVisibility(String gameId, bool isVisible) async {
    try {
      final res = await _supabase.rpc('MPT_set_game_public_visibility', params: {
        'p_game_id': gameId,
        'p_is_visible': isVisible,
      });
      if (res is Map && res['success'] == true) {
        return true;
      }
    } catch (_) {
      try {
        final res = await _supabase.rpc('mpt_set_game_public_visibility', params: {
          'p_game_id': gameId,
          'p_is_visible': isVisible,
        });
        if (res is Map && res['success'] == true) {
          return true;
        }
      } catch (_) {}
    }

    // Direct update fallback if user has direct permission
    try {
      await _supabase
          .from('MPT_games')
          .update({'is_publicly_visible': isVisible})
          .eq('id', gameId);
      await _supabase
          .from('MPT_game_archives')
          .update({'is_publicly_visible': isVisible})
          .eq('game_id', gameId);
      return true;
    } catch (e2) {
      rethrow;
    }
  }

  /// Bulk auto-hide all games that did not meet minimum quorum
  Future<int> autoHideBelowQuorumGames({int minQuorum = 2}) async {
    try {
      final res = await _supabase.rpc('MPT_auto_hide_below_quorum_games', params: {
        'p_min_quorum': minQuorum,
      });
      if (res is Map && res['hidden_games_count'] != null) {
        return res['hidden_games_count'] as int;
      }
    } catch (_) {
      try {
        final res = await _supabase.rpc('mpt_auto_hide_below_quorum_games', params: {
          'p_min_quorum': minQuorum,
        });
        if (res is Map && res['hidden_games_count'] != null) {
          return res['hidden_games_count'] as int;
        }
      } catch (_) {}
    }
    return 0;
  }

  /// Fetch detailed game inspection statistics (players, claims, draws)
  Future<Map<String, dynamic>> getAdminGameDetails(String gameId) async {
    // 1. Try uppercase RPC
    try {
      final res = await _supabase.rpc('MPT_get_admin_game_details', params: {
        'p_game_id': gameId,
      });
      if (res is Map<String, dynamic>) {
        return res;
      }
    } catch (_) {}

    // 2. Try lowercase RPC
    try {
      final res = await _supabase.rpc('mpt_get_admin_game_details', params: {
        'p_game_id': gameId,
      });
      if (res is Map<String, dynamic>) {
        return res;
      }
    } catch (_) {}

    // 3. Resilient Direct Table Queries Fallback
    try {
      final gameData = await _supabase
          .from('MPT_games')
          .select()
          .eq('id', gameId)
          .maybeSingle();

      final playersData = await _supabase
          .from('MPT_game_registrations')
          .select('user_id, display_name, avatar, registration_seq, seat_status, joined_at')
          .eq('game_id', gameId)
          .order('registration_seq', ascending: true);

      final claimsData = await _supabase
          .from('MPT_claims')
          .select('id, prize_type, status, rejection_reason, submitted_at, processed_at, marked_numbers, user_id')
          .eq('game_id', gameId)
          .order('submitted_at', ascending: false);

      final numbersData = await _supabase
          .from('MPT_called_numbers')
          .select('number, call_seq, called_at')
          .eq('game_id', gameId)
          .order('call_seq', ascending: true);

      return {
        'game': gameData ?? {'id': gameId},
        'players': playersData,
        'claims': claimsData,
        'called_numbers': numbersData,
      };
    } catch (e) {
      rethrow;
    }
  }
}
