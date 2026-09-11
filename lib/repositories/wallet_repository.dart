import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';
import '../core/config/app_config.dart';
import '../models/mpt_capacity_tier.dart';
import '../models/mpt_wallet.dart';

class WalletRepository {
  final SupabaseClient _supabase;

  WalletRepository(this._supabase);

  /// Gets current user wallet
  Future<MptWallet> getWallet() async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) {
      return MptWallet(userId: '', availableCredits: 0, updatedAt: DateTime.now());
    }

    try {
      final rpcRes = await _supabase.rpc('MPT_get_or_create_wallet');
      if (rpcRes is Map<String, dynamic>) {
        return MptWallet.fromJson(rpcRes);
      }
    } catch (_) {}

    try {
      final res = await _supabase
          .from('MPT_admin_wallets')
          .select()
          .eq('user_id', uid)
          .maybeSingle();

      if (res != null) {
        final wallet = MptWallet.fromJson(res);
        if (wallet.availableCredits > 0) return wallet;
      }

      // Create new wallet record with 10 free welcome credits if missing or empty
      final row = await _supabase.from('MPT_admin_wallets').upsert({
        'user_id': uid,
        'available_credits': 10,
        'credits_expire_at': DateTime.now().add(const Duration(days: 365)).toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      }).select().single();

      // Also record initial welcome transaction in ledger
      try {
        await _supabase.from('MPT_credit_transactions').insert({
          'user_id': uid,
          'type': 'PURCHASE',
          'amount': 10,
          'balance_after': 10,
          'description': 'Welcome Bonus: 10 Free Credits',
          'idempotency_key': 'welcome-$uid',
        });
      } catch (_) {}

      return MptWallet.fromJson(row);
    } catch (_) {
      return MptWallet(userId: uid, availableCredits: 10, updatedAt: DateTime.now());
    }
  }

  /// Gets credit ledger transactions
  Future<List<MptCreditTransaction>> getTransactions() async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return [];

    try {
      final res = await _supabase
          .from('MPT_credit_transactions')
          .select()
          .eq('user_id', uid)
          .order('created_at', ascending: false);

      return (res as List).map((e) => MptCreditTransaction.fromJson(e)).toList();
    } catch (_) {
      return [];
    }
  }

  /// Adds mock credits (for development, testing & demo)
  Future<int> addMockCredits(int amount, {String? description}) async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) throw Exception('Auth required');

    final idempotencyKey = const Uuid().v4();
    try {
      final res = await _supabase.rpc('MPT_add_mock_credits', params: {
        'p_amount': amount,
        'p_idempotency_key': idempotencyKey,
        'p_description': description ?? 'Mock credit top-up',
      });

      if (res is Map<String, dynamic> && res['available_credits'] != null) {
        return (res['available_credits'] as num).toInt();
      }
    } catch (_) {
      // Fallback
      final current = await getWallet();
      final newBalance = current.availableCredits + amount;
      await _supabase.from('MPT_admin_wallets').upsert({
        'user_id': uid,
        'available_credits': newBalance,
      });
      await _supabase.from('MPT_credit_transactions').insert({
        'user_id': uid,
        'type': 'MOCK_PURCHASE',
        'amount': amount,
        'balance_after': newBalance,
        'description': description ?? 'Mock credit top-up',
        'idempotency_key': idempotencyKey,
      });
      return newBalance;
    }
    return 0;
  }

  /// Fetches available capacity tiers
  Future<List<MptCapacityTier>> getCapacityTiers() async {
    try {
      final res = await _supabase
          .from('MPT_capacity_tiers')
          .select()
          .eq('is_active', true)
          .order('display_order', ascending: true);

      return (res as List).map((e) => MptCapacityTier.fromJson(e)).toList();
      return [
        MptCapacityTier(id: '1', name: 'Family Pack (1–5 Players)', minPlayers: 1, maxPlayers: 5, creditsRequired: 0),
        MptCapacityTier(id: '2', name: 'Small Party (6–15 Players)', minPlayers: 6, maxPlayers: 15, creditsRequired: 50),
        MptCapacityTier(id: '3', name: 'Standard Event (16–25 Players)', minPlayers: 16, maxPlayers: 25, creditsRequired: 100),
        MptCapacityTier(id: '4', name: 'Large Gala (26–100 Players)', minPlayers: 26, maxPlayers: 100, creditsRequired: 250),
        MptCapacityTier(id: '5', name: 'Mega Event (101–250 Players)', minPlayers: 101, maxPlayers: 250, creditsRequired: 500),
      ];
    }
  }

  /// Launches external web checkout for purchasing credits
  Future<bool> launchWebPurchaseHandoff({String? adminEmail}) async {
    if (!AppConfig.purchaseEnabled) return false;

    final uid = _supabase.auth.currentUser?.id ?? '';
    final uri = Uri.parse(AppConfig.purchaseBaseUrl).replace(queryParameters: {
      'user_id': uid,
      ...?adminEmail == null ? null : {'email': adminEmail},
      'app_env': AppConfig.environment,
    });

    if (await canLaunchUrl(uri)) {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    return false;
  }
}
