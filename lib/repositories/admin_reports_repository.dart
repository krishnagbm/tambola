import 'dart:convert';
import 'package:http/http.dart' as http;
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

  /// Fetch full executive KPI metrics and reports data with automatic direct-table fallback
  Future<Map<String, dynamic>> getReportsOverview() async {
    try {
      final res = await _supabase.rpc('MPT_get_admin_reports_overview');
      if (res is Map<String, dynamic> && res.isNotEmpty) {
        return res;
      }
    } catch (e) {
      // If RPC fails (e.g. migration pending, column mismatch, or permissions),
      // we gracefully fall back to direct Supabase table queries so the dashboard never crashes!
      try {
        return await _getReportsOverviewFallback(e);
      } catch (fallbackError) {
        // If even direct table query fails, rethrow the original RPC error
        rethrow;
      }
    }
    return await _getReportsOverviewFallback(null);
  }

  /// Direct table query fallback when MPT_get_admin_reports_overview RPC is unavailable or encounters an error
  Future<Map<String, dynamic>> _getReportsOverviewFallback([Object? rpcError]) async {
    // 1. Fetch recent games
    List<Map<String, dynamic>> recentGames = [];
    int totalGamesCount = 0;
    int activeGamesCount = 0;
    int completedGamesCount = 0;
    try {
      final gamesRes = await _supabase
          .from('MPT_games')
          .select('*, MPT_admin_profiles(email), MPT_users(display_name)')
          .order('created_at', ascending: false)
          .limit(50);

      recentGames = (gamesRes as List).map((row) {
        final m = Map<String, dynamic>.from(row as Map);
        final adminProfile = m['MPT_admin_profiles'] as Map?;
        final userProfile = m['MPT_users'] as Map?;
        m['host_identifier'] = adminProfile?['email'] ?? userProfile?['display_name'] ?? 'Unknown Host';
        final cap = m['initial_funded_capacity'] as int? ?? 5;
        if (cap <= 5) {
          m['capacity_tier_name'] = 'Family Pack (1–5)';
        } else if (cap <= 25) {
          m['capacity_tier_name'] = 'Small Party (6–25)';
        } else if (cap <= 50) {
          m['capacity_tier_name'] = 'Standard Event (26–50)';
        } else if (cap <= 100) {
          m['capacity_tier_name'] = 'Large Gala (51–100)';
        } else {
          m['capacity_tier_name'] = 'Mega Event (101–250+)';
        }
        return m;
      }).toList();

      totalGamesCount = recentGames.length;
      for (final g in recentGames) {
        final s = (g['status'] as String? ?? '').toUpperCase();
        if (s == 'COMPLETED') completedGamesCount++;
        if (['OPEN', 'READY_TO_START', 'STARTING', 'IN_PROGRESS'].contains(s)) activeGamesCount++;
      }
    } catch (_) {
      try {
        final simpleGames = await _supabase.from('MPT_games').select().order('created_at', ascending: false).limit(50);
        recentGames = List<Map<String, dynamic>>.from(simpleGames as List);
        totalGamesCount = recentGames.length;
      } catch (_) {}
    }

    // 2. Fetch recent hosts
    List<Map<String, dynamic>> recentHosts = [];
    try {
      final hostsRes = await _supabase
          .from('MPT_admin_profiles')
          .select('*, MPT_admin_wallets(available_credits, credits_expire_at)')
          .order('created_at', ascending: false)
          .limit(50);
      recentHosts = (hostsRes as List).map((row) {
        final m = Map<String, dynamic>.from(row as Map);
        final wallet = m['MPT_admin_wallets'] as Map?;
        m['available_credits'] = wallet?['available_credits'] ?? 0;
        m['credits_expire_at'] = wallet?['credits_expire_at'];
        return m;
      }).toList();
    } catch (_) {
      try {
        final simpleHosts = await _supabase.from('MPT_admin_profiles').select().order('created_at', ascending: false).limit(50);
        recentHosts = List<Map<String, dynamic>>.from(simpleHosts as List);
      } catch (_) {}
    }

    // 3. Fetch Stripe Payments Ledger
    List<Map<String, dynamic>> recentPayments = await getPaymentsLedger();
    num totalRevenue = 0;
    for (final p in recentPayments) {
      final st = (p['status']?.toString() ?? '').toLowerCase();
      if (st == 'succeeded' || st == 'completed') {
        final amt = p['amount_usd'];
        if (amt is num) {
          totalRevenue += amt;
        } else if (amt != null) {
          totalRevenue += num.tryParse(amt.toString()) ?? 0;
        }
      }
    }

    // 4. Fetch Users List
    List<Map<String, dynamic>> recentUsers = await getRegisteredUsersList();

    // 5. Fetch Brand Offers & Approvals
    List<Map<String, dynamic>> brandOffers = [];
    try {
      final boRes = await _supabase.from('MPT_brand_offers').select().order('created_at', ascending: false).limit(40);
      brandOffers = List<Map<String, dynamic>>.from(boRes as List);
    } catch (_) {}

    List<Map<String, dynamic>> brandApprovals = [];
    try {
      final baRes = await _supabase.from('MPT_brand_approvals').select().order('created_at', ascending: false).limit(40);
      brandApprovals = List<Map<String, dynamic>>.from(baRes as List);
    } catch (_) {}

    // 6. Counts for tickets & claims
    int totalTickets = 0;
    try {
      final ticketsRes = await _supabase.from('MPT_player_tickets').select('id').limit(1000);
      totalTickets = (ticketsRes as List).length;
    } catch (_) {}

    int totalClaims = 0;
    int approvedClaims = 0;
    try {
      final claimsRes = await _supabase.from('MPT_claims').select('id, status, prize_type').limit(100);
      totalClaims = (claimsRes as List).length;
      for (final c in claimsRes) {
        if ((c['status'] as String? ?? '').toUpperCase() == 'APPROVED') approvedClaims++;
      }
    } catch (_) {}

    return {
      'is_fallback_mode': true,
      'rpc_error': rpcError?.toString(),
      'metrics': {
        'total_registered_users': recentUsers.where((u) => u['is_anonymous'] != true).length,
        'total_users': recentUsers.length,
        'total_games': totalGamesCount,
        'active_games': activeGamesCount,
        'completed_games': completedGamesCount,
        'total_tickets': totalTickets,
        'total_claims': totalClaims,
        'total_brand_offers': brandOffers.length,
        'active_brand_offers': brandOffers.where((b) => (b['status'] as String? ?? '').toUpperCase() == 'ACTIVE').length,
        'total_brand_approvals': brandApprovals.length,
        'pending_brand_approvals': brandApprovals.where((a) => (a['status'] as String? ?? '').toUpperCase() == 'PENDING').length,
        'total_payments_count': recentPayments.where((p) => ['succeeded', 'completed'].contains((p['status']?.toString() ?? '').toLowerCase())).length,
        'total_revenue_amount': totalRevenue,
      },
      'recent_games': recentGames,
      'recent_hosts': recentHosts,
      'recent_payments': recentPayments,
      'recent_users': recentUsers,
      'tickets_claims_summary': {
        'total_tickets': totalTickets,
        'total_claims': totalClaims,
        'approved_claims': approvedClaims,
        'rejected_claims': 0,
        'pending_claims': 0,
        'claims_by_prize': [],
        'top_games_by_tickets': [],
      },
      'brand_offers': brandOffers,
      'brand_approvals': brandApprovals,
    };
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

  /// Grant promotional or marketing free credits to a selected host
  Future<Map<String, dynamic>> grantCreditsToHost({
    String? targetUserId,
    String? targetEmail,
    int credits = 300,
    int validityDays = 30,
    String reason = 'Marketing Promo (30 Days)',
  }) async {
    final params = {
      if (targetUserId != null && targetUserId.isNotEmpty) 'p_target_user_id': targetUserId,
      if (targetEmail != null && targetEmail.isNotEmpty) 'p_target_email': targetEmail,
      'p_credits': credits,
      'p_validity_days': validityDays,
      'p_reason': reason,
    };

    try {
      final res = await _supabase.rpc('MPT_admin_grant_credits', params: params);
      if (res is Map<String, dynamic>) return res;
    } catch (_) {}

    try {
      final res = await _supabase.rpc('mpt_admin_grant_credits', params: params);
      if (res is Map<String, dynamic>) return res;
    } catch (e) {
      rethrow;
    }

    return {'success': false};
  }

  /// Direct query fallback for Stripe payments ledger
  Future<List<Map<String, dynamic>>> getPaymentsLedger() async {
    try {
      final res = await _supabase
          .from('MPT_payments')
          .select()
          .order('created_at', ascending: false)
          .limit(50);
      return (res as List).map((row) {
        final m = Map<String, dynamic>.from(row as Map);
        final ref = m['provider_ref']?.toString().toLowerCase() ?? '';
        m['is_test_mode'] = ref.contains('_test_') || ref.startsWith('cs_test_') || ref.startsWith('pi_test_');
        return m;
      }).toList();
    } catch (_) {
      return [];
    }
  }

  /// Direct query fallback for registered users & players
  Future<List<Map<String, dynamic>>> getRegisteredUsersList() async {
    try {
      final res = await _supabase
          .from('MPT_users')
          .select()
          .order('created_at', ascending: false)
          .limit(50);
      return List<Map<String, dynamic>>.from(res as List);
    } catch (_) {
      return [];
    }
  }

  /// Notify super admin (contact@dabhousie.com) of new host registration or first game creation
  Future<bool> notifyHostRegistration({
    required String hostEmail,
    String? hostName,
    String? gameName,
    String? inviteCode,
    String? userId,
    String? provider,
    String? actionType,
  }) async {
    final payload = <String, dynamic>{
      'action': 'notify_host_registration',
      'host_email': hostEmail,
    };
    if (hostName != null) payload['host_name'] = hostName;
    if (gameName != null) payload['game_name'] = gameName;
    if (inviteCode != null) payload['invite_code'] = inviteCode;
    if (userId != null) payload['user_id'] = userId;
    if (provider != null) payload['provider'] = provider;
    if (actionType != null) payload['action_type'] = actionType;

    try {
      final uri = Uri.parse(
        'https://6uvajebdr2.execute-api.us-east-2.amazonaws.com/Prod/email/brand-approval',
      );
      final res = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
