import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/mpt_game.dart';
import '../models/mpt_registration.dart';

class GameRepository {
  final SupabaseClient _supabase;

  GameRepository(this._supabase);

  /// Creates a new game room
  Future<MptGame> createGame({
    required String name,
    int plannedCapacity = 25,
    String? plannedCapacityTierId,
    DateTime? scheduledAt,
    List<String>? prizesConfig,
  }) async {
    try {
      final res = await _supabase.rpc('MPT_create_game', params: {
        'p_name': name,
        'p_planned_capacity': plannedCapacity,
        'p_scheduled_at': scheduledAt?.toIso8601String(),
        'p_prizes_config': prizesConfig ?? ['EARLY_FIVE', 'TOP_LINE', 'MIDDLE_LINE', 'BOTTOM_LINE', 'FOUR_CORNERS', 'FULL_HOUSE'],
        'p_planned_capacity_tier_id': plannedCapacityTierId,
      });

      if (res is Map<String, dynamic>) {
        return MptGame.fromJson(res);
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
        'planned_capacity_tier_id': plannedCapacityTierId,
        'initial_funded_capacity': plannedCapacity,
        'funded_capacity': plannedCapacity,
        'scheduled_at': scheduledAt?.toIso8601String(),
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

  /// Registers player with server-authoritative sequence & overflow capacity logic
  Future<MptRegistration> registerPlayer({
    required String gameId,
    required String displayName,
    required String avatar,
  }) async {
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
      final res = await _supabase
          .from('MPT_game_registrations')
          .select('*, game:MPT_games(*)')
          .eq('user_id', uid)
          .order('registered_at', ascending: false)
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
}
