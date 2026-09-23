import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/mpt_game.dart';
import '../models/mpt_registration.dart';
import '../models/mpt_seat_otp.dart';

class GameRepository {
  final SupabaseClient _supabase;

  GameRepository(this._supabase);

  /// Creates a new game room
  Future<MptGame> createGame({
    required String name,
    int plannedCapacity = 10,
    String? plannedCapacityTierId,
    DateTime? scheduledAt,
    List<String>? prizesConfig,
    bool isPrivate = false,
  }) async {
    // Validate UUID format; pass null if not a valid UUID string
    String? effectiveTierId = plannedCapacityTierId;
    if (effectiveTierId != null &&
        !RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')
            .hasMatch(effectiveTierId)) {
      effectiveTierId = null;
    }

    try {
      final res = await _supabase.rpc('MPT_create_game', params: {
        'p_name': name,
        'p_planned_capacity': plannedCapacity,
        'p_scheduled_at': scheduledAt?.toIso8601String(),
        'p_prizes_config': prizesConfig ?? ['EARLY_FIVE', 'TOP_LINE', 'MIDDLE_LINE', 'BOTTOM_LINE', 'FOUR_CORNERS', 'FULL_HOUSE'],
        'p_is_private': isPrivate,
      });

      if (res is Map<String, dynamic>) {
        final game = MptGame.fromJson(res);
        // If private, trigger organizer email in background
        if (isPrivate) {
          sendPrivatePartyEmail(gameId: game.id).catchError((_) => <String, dynamic>{'success': false});
        }
        return game;
      }
      throw Exception('Invalid response format when creating game');
    } catch (e) {
      // Fallback direct table insert if RPC is missing
      final uid = _supabase.auth.currentUser?.id;
      final inviteCode = 'TAMB${(DateTime.now().millisecondsSinceEpoch % 90000) + 10000}';
      final row = await _supabase.from('MPT_games').insert({
        'admin_user_id': uid,
        'name': name,
        'invite_code': inviteCode,
        'status': 'OPEN',
        'planned_capacity_tier_id': effectiveTierId,
        'initial_funded_capacity': plannedCapacity,
        'funded_capacity': plannedCapacity,
        'scheduled_at': scheduledAt?.toIso8601String(),
        'is_private': isPrivate,
        'prizes_config': prizesConfig ?? ['EARLY_FIVE', 'TOP_LINE', 'MIDDLE_LINE', 'BOTTOM_LINE', 'FOUR_CORNERS', 'FULL_HOUSE'],
      }).select().single();
      return MptGame.fromJson(row);
    }
  }

  /// Looks up a game by its alphanumeric invite code
  Future<MptGame?> getGameByInviteCode(String code) async {
    final cleanCode = code.trim().toUpperCase();
    final res = await _supabase
        .from('MPT_games')
        .select()
        .eq('invite_code', cleanCode)
        .maybeSingle();

    if (res == null) return null;
    return MptGame.fromJson(res);
  }

  /// Fetches game details by ID
  Future<MptGame> getGame(String gameId) async {
    final res = await _supabase
        .from('MPT_games')
        .select()
        .eq('id', gameId)
        .single();
    return MptGame.fromJson(res);
  }

  /// Updates the event name of a game
  Future<void> updateGameName(String gameId, String newName) async {
    final cleanName = newName.trim();
    if (cleanName.isEmpty) return;
    await _supabase
        .from('MPT_games')
        .update({'name': cleanName})
        .eq('id', gameId);
  }

  /// Cancels an open or scheduled game
  Future<void> cancelGame(String gameId) async {
    await _supabase
        .from('MPT_games')
        .update({
          'status': 'CANCELLED',
          'completed_at': DateTime.now().toIso8601String(),
        })
        .eq('id', gameId);
  }

  /// Registers player with server-authoritative sequence & overflow capacity logic
  Future<MptRegistration> registerPlayer({
    required String gameId,
    required String displayName,
    required String avatar,
  }) async {
    final game = await getGame(gameId);
    if (game.isCancelled) {
      throw Exception('This game event has been cancelled by the host.');
    }
    if (game.isCompleted) {
      throw Exception('This game event has already concluded.');
    }

    try {
      final res = await _supabase.rpc('MPT_register_player', params: {
        'p_game_id': gameId,
        'p_display_name': displayName,
        'p_avatar': avatar,
      });

      if (res is Map<String, dynamic> && res['registration'] != null) {
        return MptRegistration.fromJson(res['registration'] as Map<String, dynamic>);
      }
      throw Exception('Failed to register player');
    } catch (e) {
      // Fallback direct registration
      final uid = _supabase.auth.currentUser?.id;
      final existing = await _supabase
          .from('MPT_game_registrations')
          .select()
          .eq('game_id', gameId)
          .eq('user_id', uid ?? '')
          .maybeSingle();

      if (existing != null) {
        return MptRegistration.fromJson(existing);
      }

      final countRes = await _supabase
          .from('MPT_game_registrations')
          .select('registration_seq')
          .eq('game_id', gameId);
      
      final nextSeq = (countRes as List).length + 1;
      final game = await getGame(gameId);
      final status = nextSeq <= game.fundedCapacity ? 'CONFIRMED' : 'WAITING';

      final row = await _supabase.from('MPT_game_registrations').insert({
        'game_id': gameId,
        'user_id': uid,
        'display_name': displayName,
        'avatar': avatar,
        'registration_seq': nextSeq,
        'seat_status': status,
      }).select().single();

      return MptRegistration.fromJson(row);
    }
  }

  /// Allows a player to leave / cancel their game registration
  Future<void> leaveGame(String gameId) async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return;
    try {
      await _supabase.rpc('MPT_leave_game', params: {
        'p_game_id': gameId,
      });
    } catch (_) {
      await _supabase
          .from('MPT_game_registrations')
          .delete()
          .eq('game_id', gameId)
          .eq('user_id', uid);
    }
  }

  /// Admin increases funded capacity and triggers automatic waiting player promotion
  Future<void> increaseCapacity({
    required String gameId,
    required int additionalCapacity,
  }) async {
    try {
      await _supabase.rpc('MPT_increase_game_capacity', params: {
        'p_game_id': gameId,
        'p_additional_capacity': additionalCapacity,
      });
    } catch (e) {
      final game = await getGame(gameId);
      await _supabase.from('MPT_games').update({
        'funded_capacity': game.fundedCapacity + additionalCapacity,
      }).eq('id', gameId);
    }
  }

  /// Fetches player registration status for a game
  Future<MptRegistration?> getMyRegistration(String gameId) async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return null;

    final res = await _supabase
        .from('MPT_game_registrations')
        .select()
        .eq('game_id', gameId)
        .eq('user_id', uid)
        .maybeSingle();

    if (res == null) return null;
    return MptRegistration.fromJson(res);
  }

  /// Fetches all active/recent games hosted by the current user
  Future<List<MptGame>> getMyHostedGames() async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return [];

    try {
      final res = await _supabase
          .from('MPT_games')
          .select()
          .eq('admin_user_id', uid)
          .order('created_at', ascending: false)
          .limit(20);

      return (res as List).map((e) => MptGame.fromJson(e)).toList();
    } catch (_) {
      return [];
    }
  }

  /// Fetches all active games the current user has registered to play
  Future<List<Map<String, dynamic>>> getMyJoinedGames() async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return [];
    try {
      // Fix 2026-09-05: MPT_game_registrations defines joined_at, not registered_at.
      final res = await _supabase
          .from('MPT_game_registrations')
          .select('*, game:MPT_games(*)')
          .eq('user_id', uid)
          .order('joined_at', ascending: false)
          .limit(20);

      return List<Map<String, dynamic>>.from(res as List);
    } catch (_) {
      return [];
    }
  }

  /// Fetches all registrations for a game
  Future<List<MptRegistration>> getGameRegistrations(String gameId) async {
    try {
      final res = await _supabase
          .from('MPT_game_registrations')
          .select()
          .eq('game_id', gameId)
          .order('registration_seq', ascending: true);

      return (res as List).map((e) => MptRegistration.fromJson(e)).toList();
    } catch (_) {
      return [];
    }
  }

  /// Fetches the set of taken lowercased display names for a game session
  Future<Set<String>> getSessionTakenNicknames(String gameId) async {
    try {
      final res = await _supabase
          .from('MPT_game_registrations')
          .select('display_name')
          .eq('game_id', gameId);

      return (res as List)
          .map((e) => (e['display_name'] as String? ?? '').trim().toLowerCase())
          .where((name) => name.isNotEmpty)
          .toSet();
    } catch (_) {
      return {};
    }
  }

  /// Smart Polling stream for live game state changes (2s interval, 0 WebSocket connections)
  Stream<MptGame> watchGame(String gameId) async* {
    while (true) {
      try {
        final game = await getGame(gameId);
        yield game;
      } catch (_) {}
      await Future.delayed(const Duration(seconds: 2));
    }
  }

  /// Smart Polling stream for live registrations list (2s interval, 0 WebSocket connections)
  Stream<List<MptRegistration>> watchRegistrations(String gameId) async* {
    while (true) {
      try {
        final list = await getGameRegistrations(gameId);
        yield list;
      } catch (_) {}
      await Future.delayed(const Duration(seconds: 2));
    }
  }

  /// Claims a single-use seat OTP for the current user
  Future<Map<String, dynamic>> claimSeatOtp({
    required String gameId,
    required String otpCode,
  }) async {
    final res = await _supabase.rpc('MPT_claim_seat_otp', params: {
      'p_game_id': gameId,
      'p_otp_code': otpCode.trim().toUpperCase(),
    });
    if (res is Map<String, dynamic>) {
      return res;
    }
    return {'success': true};
  }

  /// Fetches all seat OTPs for a private game (Admin only)
  Future<List<MptSeatOtp>> getGameSeatOtps(String gameId) async {
    try {
      final res = await _supabase
          .from('MPT_game_seat_otps')
          .select()
          .eq('game_id', gameId)
          .order('seat_number', ascending: true);

      return (res as List).map((e) => MptSeatOtp.fromJson(e)).toList();
    } catch (_) {
      return [];
    }
  }

  /// Smart polling stream for seat OTPs in Admin Lobby (2s interval)
  Stream<List<MptSeatOtp>> watchGameSeatOtps(String gameId) async* {
    while (true) {
      try {
        final list = await getGameSeatOtps(gameId);
        yield list;
      } catch (_) {}
      await Future.delayed(const Duration(seconds: 2));
    }
  }

  /// Reissues a fresh single-use OTP for a seat
  Future<void> reissueSeatOtp({
    required String gameId,
    required String seatId,
  }) async {
    await _supabase.rpc('MPT_reissue_seat_otp', params: {
      'p_game_id': gameId,
      'p_seat_id': seatId,
    });
  }

  /// Adds additional seat OTPs to a private party
  Future<void> addSeatOtps({
    required String gameId,
    required int additionalSeats,
  }) async {
    await _supabase.rpc('MPT_add_seat_otps', params: {
      'p_game_id': gameId,
      'p_additional_seats': additionalSeats,
    });
  }

  /// Revokes a seat OTP
  Future<void> revokeSeatOtp({
    required String gameId,
    required String seatId,
  }) async {
    await _supabase.rpc('MPT_revoke_seat_otp', params: {
      'p_game_id': gameId,
      'p_seat_id': seatId,
    });
  }

  /// Triggers email delivery of OTP passcodes to the organizer
  Future<Map<String, dynamic>> sendPrivatePartyEmail({required String gameId, String? targetEmail}) async {
    try {
      final game = await getGame(gameId);
      final otps = await getGameSeatOtps(gameId);
      
      String? email = targetEmail;
      if (email == null || email.isEmpty) {
        final adminProfile = await _supabase
            .from('MPT_admin_profiles')
            .select('email')
            .eq('user_id', game.adminUserId)
            .maybeSingle();

        email = adminProfile?['email'] as String? ?? _supabase.auth.currentUser?.email;
      }

      if (email == null || email.isEmpty) {
        return {
          'success': false,
          'email': null,
          'message': 'No organizer email address found for this account.',
        };
      }

      final payload = {
        'to_email': email,
        'game_name': game.name,
        'invite_code': game.inviteCode,
        'otps': otps.map((o) => {'seat_number': o.seatNumber, 'otp_code': o.otpCode}).toList(),
        'scheduled_at': game.scheduledAt?.toIso8601String(),
      };

      // 1. Try AWS API Gateway Lambda endpoint
      try {
        final uri = Uri.parse('https://6uvajebdr2.execute-api.us-east-2.amazonaws.com/Prod/email/private-party');
        final response = await http.post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(payload),
        );
        if (response.statusCode == 200) {
          return {
            'success': true,
            'email': email,
            'message': 'Passcodes successfully emailed to $email',
          };
        }
      } catch (_) {
        // Fallback to Supabase functions
      }

      // 2. Try Supabase Edge function invocation
      try {
        final res = await _supabase.functions.invoke('send-private-party-email', body: payload);
        if (res.status == 200) {
          return {
            'success': true,
            'email': email,
            'message': 'Passcodes successfully emailed to $email',
          };
        }
      } catch (_) {}

      return {
        'success': false,
        'email': email,
        'message': 'Sent request to $email. (Note: In AWS SES Sandbox mode, the destination email must be verified in AWS SES Console).',
      };
    } catch (e) {
      return {
        'success': false,
        'email': null,
        'message': e.toString(),
      };
    }
  }

  /// Submits brand approval request (DVAA) for corporate events and triggers automated SES email
  Future<Map<String, dynamic>> submitBrandApproval({
    required String gameId,
    required String organizationName,
    required String organizationLogoUrl,
    required String approverEmail,
    String? gameName,
    int? capacity,
  }) async {
    try {
      final res = await _supabase.rpc('MPT_submit_brand_approval', params: {
        'p_game_id': gameId,
        'p_organization_name': organizationName,
        'p_organization_logo_url': organizationLogoUrl,
        'p_approver_email': approverEmail,
      });

      if (res is Map<String, dynamic>) {
        if (res['success'] == true) {
          final token = res['approval_token'] as String?;
          if (token != null && token.isNotEmpty) {
            // Trigger automated email delivery to corporate approver
            await _dispatchBrandApprovalEmail(
              gameId: gameId,
              toEmail: approverEmail,
              organizationName: organizationName,
              organizationLogoUrl: organizationLogoUrl,
              approvalToken: token,
              fallbackGameName: gameName,
              fallbackCapacity: capacity,
            );
          }
        }
        return res;
      }
      return {'success': true};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  /// Triggers automated SES email to corporate approver via AWS API Gateway
  Future<void> _dispatchBrandApprovalEmail({
    required String gameId,
    required String toEmail,
    required String organizationName,
    required String organizationLogoUrl,
    required String approvalToken,
    String? fallbackGameName,
    int? fallbackCapacity,
  }) async {
    try {
      String resolvedGameName = fallbackGameName ?? 'Tambola Event';
      int? resolvedCapacity = fallbackCapacity;
      try {
        final g = await getGame(gameId);
        resolvedGameName = g.name;
        resolvedCapacity = g.plannedCapacity;
      } catch (_) {}

      final currentProfile = _supabase.auth.currentUser;
      final organizerName = currentProfile?.userMetadata?['name'] as String? ??
          currentProfile?.userMetadata?['display_name'] as String? ??
          'Event Organizer';

      final payload = {
        'action': 'brand_approval',
        'type': 'brand_approval',
        'to_email': toEmail,
        'organization_name': organizationName,
        'organization_logo_url': organizationLogoUrl,
        'approval_token': approvalToken,
        'game_name': resolvedGameName,
        'organizer_name': organizerName,
        'capacity': resolvedCapacity,
      };

      // 1. Try dedicated brand-approval endpoint
      try {
        final uri = Uri.parse('https://6uvajebdr2.execute-api.us-east-2.amazonaws.com/Prod/email/brand-approval');
        final response = await http.post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(payload),
        );
        if (response.statusCode == 200) return;
      } catch (_) {}

      // 2. Fallback to existing active email endpoint with action: brand_approval
      try {
        final uri = Uri.parse('https://6uvajebdr2.execute-api.us-east-2.amazonaws.com/Prod/email/private-party');
        await http.post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(payload),
        );
      } catch (_) {}
    } catch (_) {
      // Best-effort email dispatch; token is safely persisted in DB
    }
  }
}

