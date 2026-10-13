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
      // If RPC fails (e.g. migration pending execution or access denied),
      // rethrow with clear error
      rethrow;
    }
  }
}
