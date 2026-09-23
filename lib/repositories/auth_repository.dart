import 'package:flutter/foundation.dart';
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

  static const List<String> defaultNicknames = [
    'Lucky Dabber',
    'Tiger King',
    'Party Star',
    'Speedy Housie',
    'Golden Ticket',
    'Housie Hero',
    'Tambola Champ',
  ];

  static String getRandomDefaultNickname() {
    return defaultNicknames[DateTime.now().microsecond % defaultNicknames.length];
  }

  AuthRepository(this._supabase);

  String? get currentUserId => _supabase.auth.currentUser?.id;
  bool get isAuthenticated => _supabase.auth.currentUser != null;
  User? get currentAuthUser => _supabase.auth.currentUser;

  /// Stream of Supabase auth state changes for real-time reactivity
  Stream<AuthState> get onAuthStateChange => _supabase.auth.onAuthStateChange;

  String _getEffectiveRedirectUrl(String? customRedirect) {
    if (customRedirect != null && customRedirect.isNotEmpty) {
      return customRedirect;
    }
    if (kIsWeb) {
      try {
        final origin = Uri.base.origin;
        if (origin.isNotEmpty && origin != 'null') {
          return origin;
        }
      } catch (_) {}
    }
    return AppConfig.appBaseUrl;
  }

  /// Signs in or links with Google OAuth
  Future<void> signInWithGoogle({String? redirectTo}) async {
    await _supabase.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: _getEffectiveRedirectUrl(redirectTo),
    );
  }

  /// Signs in or links with Apple OAuth
  Future<void> signInWithApple({String? redirectTo}) async {
    await _supabase.auth.signInWithOAuth(
      OAuthProvider.apple,
      redirectTo: _getEffectiveRedirectUrl(redirectTo),
    );
  }

  /// Signs in or links with Microsoft (Azure) OAuth
  Future<void> signInWithMicrosoft({String? redirectTo}) async {
    await _supabase.auth.signInWithOAuth(
      OAuthProvider.azure,
      redirectTo: _getEffectiveRedirectUrl(redirectTo),
    );
  }

  /// Sends a 6-digit OTP code to the given email
  Future<void> sendEmailOtp(String email) async {
    final cleanEmail = email.trim();
    if (cleanEmail.isEmpty || !cleanEmail.contains('@')) {
      throw Exception('Please enter a valid email address');
    }
    await _supabase.auth.signInWithOtp(
      email: cleanEmail,
      shouldCreateUser: true,
    );
  }

  /// Verifies the 6-digit OTP token entered by the user
  Future<AuthResponse> verifyEmailOtp({
    required String email,
    required String token,
  }) async {
    final cleanEmail = email.trim();
    final cleanToken = token.trim();
    if (cleanEmail.isEmpty) throw Exception('Email address is required');
    if (cleanToken.isEmpty || cleanToken.length < 6) {
      throw Exception('Please enter a valid 6-digit verification code');
    }

    final response = await _supabase.auth.verifyOTP(
      email: cleanEmail,
      token: cleanToken,
      type: OtpType.email,
    );

    // Sync profile after OTP verification
    try {
      await initializeAuth();
    } catch (_) {}

    return response;
  }

  /// Sends a magic sign-in link (OTP) to the given email
  Future<void> signInWithEmail(String email, {String? redirectTo}) async {
    final cleanEmail = email.trim();
    if (cleanEmail.isEmpty) throw Exception('Please enter a valid email address');
    await _supabase.auth.signInWithOtp(
      email: cleanEmail,
      emailRedirectTo: _getEffectiveRedirectUrl(redirectTo),
    );
  }

  /// Ensures an authentication session exists and syncs user profile
  Future<MptUser> initializeAuth() async {
    final prefs = await SharedPreferences.getInstance();
    var cachedName = prefs.getString(_prefKeyName);
    if (cachedName == null || cachedName.trim().isEmpty || cachedName == 'My Name') {
      cachedName = getRandomDefaultNickname();
      await prefs.setString(_prefKeyName, cachedName);
    }
    var cachedAvatar = prefs.getString(_prefKeyAvatar) ?? 'avatar_lion';

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

    final isAnon = user?.isAnonymous ?? true;
    final email = user?.email;
    final metadata = user?.userMetadata ?? {};
    
    String? resolvedName;
    if (metadata['full_name'] is String) {
      resolvedName = metadata['full_name'] as String;
    } else if (metadata['full_name'] is Map) {
      final nameMap = metadata['full_name'] as Map;
      final first = nameMap['firstName'] ?? '';
      final last = nameMap['lastName'] ?? '';
      resolvedName = '$first $last'.trim();
    } else if (metadata['name'] is String) {
      resolvedName = metadata['name'] as String;
    } else if (metadata['custom_claims'] is Map && (metadata['custom_claims'] as Map)['name'] is String) {
      resolvedName = (metadata['custom_claims'] as Map)['name'] as String;
    }

    if ((resolvedName == null || resolvedName.isEmpty) && email != null && email.isNotEmpty) {
      resolvedName = email.split('@').first;
    }

    final avatarUrl = metadata['avatar_url'] as String? ?? metadata['picture'] as String?;
    final provider = user?.appMetadata['provider'] as String? ?? (isAnon ? 'anonymous' : 'email');

    if (!isAnon && resolvedName != null && resolvedName.isNotEmpty && (cachedName == 'My Name' || cachedName.isEmpty)) {
      cachedName = resolvedName;
      await prefs.setString(_prefKeyName, cachedName);
    }

    // Upsert user in MPT_users table via RPC or direct insert
    try {
      final res = await _supabase.rpc('MPT_upsert_user', params: {
        'p_display_name': cachedName,
        'p_avatar': cachedAvatar,
      });
      if (res != null && res is Map<String, dynamic>) {
        return MptUser.fromJson({
          ...res,
          'email': email,
          'avatar_url': avatarUrl,
          'provider': provider,
          'is_anonymous': isAnon,
        });
      }
    } catch (_) {
      // If RPC not available yet, create basic user object
    }

    return MptUser(
      id: user?.id ?? const Uuid().v4(),
      displayName: cachedName,
      avatar: cachedAvatar,
      avatarUrl: avatarUrl,
      email: email,
      provider: provider,
      isAnonymous: isAnon,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  /// Updates player's display name and avatar (gameplay identity)
  Future<MptUser> updateProfile({required String displayName, required String avatar}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKeyName, displayName);
    await prefs.setString(_prefKeyAvatar, avatar);

    final user = _supabase.auth.currentUser;
    final uid = user?.id;
    final isAnon = user?.isAnonymous ?? true;
    final email = user?.email;
    final metadata = user?.userMetadata ?? {};
    final avatarUrl = metadata['avatar_url'] as String? ?? metadata['picture'] as String?;
    final provider = user?.appMetadata['provider'] as String? ?? (isAnon ? 'anonymous' : 'email');

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
      avatarUrl: avatarUrl,
      email: email,
      provider: provider,
      isAnonymous: isAnon,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  /// Signs out of current account and starts a fresh guest session
  Future<void> signOut() async {
    await _supabase.auth.signOut();
    try {
      await _supabase.auth.signInAnonymously();
    } catch (_) {}
  }

  /// Checks if current user has protected identity (email/oauth linked)
  bool isProtectedIdentity() {
    final user = _supabase.auth.currentUser;
    if (user == null) return false;
    final isAnon = user.isAnonymous;
    return !isAnon || (user.email != null && user.email!.isNotEmpty);
  }
}

