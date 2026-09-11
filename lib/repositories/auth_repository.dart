import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../core/config/app_config.dart';
import '../models/mpt_user.dart';

class AuthRepository {
  final SupabaseClient _supabase;
  static const String _prefKeyName = 'mpt_player_name';
  static const String _prefKeyAvatar = 'mpt_player_avatar';
  static const String _prefKeyLocalUuid = 'mpt_local_uuid';

  AuthRepository(this._supabase);

  String? get currentUserId => _supabase.auth.currentUser?.id;
  bool get isAuthenticated => _supabase.auth.currentUser != null;

  /// Ensures an anonymous authentication session exists and syncs user profile
  Future<MptUser> initializeAuth() async {
    final prefs = await SharedPreferences.getInstance();
    var cachedName = prefs.getString(_prefKeyName) ?? 'My Name';
    var cachedAvatar = prefs.getString(_prefKeyAvatar) ?? 'avatar_1';

    User? user = _supabase.auth.currentUser;

    if (user == null) {
      try {
        final authResponse = await _supabase.auth.signInAnonymously();
        user = authResponse.user;
      } catch (e) {
        // Fallback for local testing / offline mock session
        var localId = prefs.getString(_prefKeyLocalUuid);
        if (localId == null) {
          localId = const Uuid().v4();
          await prefs.setString(_prefKeyLocalUuid, localId);
        }
        return MptUser(
          id: localId,
          displayName: cachedName,
          avatar: cachedAvatar,
          isAnonymous: true,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
      }
    }

    // Upsert user in MPT_users table via RPC or direct insert
    try {
      final res = await _supabase.rpc('MPT_upsert_user', params: {
        'p_display_name': cachedName,
        'p_avatar': cachedAvatar,
      });
      if (res != null && res is Map<String, dynamic>) {
        return MptUser.fromJson(res);
      }
    } catch (_) {
      // If RPC not available yet, create basic user object
    }

    return MptUser(
      id: user?.id ?? const Uuid().v4(),
      displayName: cachedName,
      avatar: cachedAvatar,
      isAnonymous: true,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  /// Updates player's display name and avatar (gameplay identity)
  Future<MptUser> updateProfile({required String displayName, required String avatar}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKeyName, displayName);
    await prefs.setString(_prefKeyAvatar, avatar);

    final uid = currentUserId;
    if (uid != null) {
      try {
        await _supabase.rpc('MPT_upsert_user', params: {
          'p_display_name': displayName,
          'p_avatar': avatar,
        });
      } catch (_) {}
    }

    return MptUser(
      id: uid ?? const Uuid().v4(),
      displayName: displayName,
      avatar: avatar,
      isAnonymous: true,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  /// Signs in or links with Google OAuth
  Future<void> signInWithGoogle({String? redirectTo}) async {
    await _supabase.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: redirectTo ?? '${AppConfig.appBaseUrl}/#/',
    );
  }

  /// Sends a magic sign-in link (OTP) to the given email
  Future<void> signInWithEmail(String email, {String? redirectTo}) async {
    final cleanEmail = email.trim();
    if (cleanEmail.isEmpty) throw Exception('Please enter a valid email address');
    await _supabase.auth.signInWithOtp(
      email: cleanEmail,
      emailRedirectTo: redirectTo ?? '${AppConfig.appBaseUrl}/#/',
    );
  }

  /// Signs out of current account and starts a fresh session
  Future<void> signOut() async {
    await _supabase.auth.signOut();
  }

  /// Checks if current user has protected identity (email/oauth linked)
  bool isProtectedIdentity() {
    final user = _supabase.auth.currentUser;
    if (user == null) return false;
    final isAnon = user.isAnonymous;
    return !isAnon || (user.email != null && user.email!.isNotEmpty);
  }
}
