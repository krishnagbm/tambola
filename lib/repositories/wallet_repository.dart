import 'dart:convert';
import 'package:http/http.dart' as http;
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

  static List<MptCapacityTier> _cachedTiers = MptCapacityTier.defaultTiers;

  /// Fetches available capacity tiers with instant fallback and in-memory cache
  Future<List<MptCapacityTier>> getCapacityTiers() async {
    try {
      final res = await _supabase
          .from('MPT_capacity_tiers')
          .select()
          .eq('is_active', true)
          .order('display_order', ascending: true);

      final remoteTiers = (res as List).map((e) => MptCapacityTier.fromJson(e)).toList();
      if (remoteTiers.isNotEmpty) {
        _cachedTiers = remoteTiers;
        return remoteTiers;
      }
    } catch (_) {
      // Fallback to cache or defaults
    }
    return _cachedTiers;
  }


  /// Directly requests a Stripe Hosted Checkout session from the backend API
  /// and opens the Stripe checkout page directly for logged-in hosts
  Future<bool> startDirectStripeCheckout({required String plan}) async {
    final user = _supabase.auth.currentUser;
    final uid = user?.id;
    final email = user?.email;

    if (uid == null || email == null || email.isEmpty) {
      // If user session is unverified or missing email, hand off to web store
      return await launchWebPurchaseHandoff(plan: plan);
    }

    try {
      final apiUrl = Uri.parse(AppConfig.checkoutApiUrl);
      final response = await http.post(
        apiUrl,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'user_id': uid,
          'email': email,
          'plan': plan,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final checkoutUrl = data['checkout_url'] as String?;
        if (checkoutUrl != null && checkoutUrl.isNotEmpty) {
          final uri = Uri.parse(checkoutUrl);
          if (await canLaunchUrl(uri)) {
            return await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        }
      }
    } catch (_) {
      // Fall back to web purchase page if direct API call encounters network error
    }

    return await launchWebPurchaseHandoff(plan: plan, adminEmail: email);
  }

  /// Launches external web checkout for purchasing credits
  Future<bool> launchWebPurchaseHandoff({
    String? plan,
    String? adminEmail,
    String? userId,
    String? displayName,
    String? avatar,
    int? balance,
  }) async {
    if (!AppConfig.purchaseEnabled) return false;

    final user = _supabase.auth.currentUser;
    final uid = (userId != null && userId.isNotEmpty) ? userId : (user?.id ?? '');
    final email = (adminEmail != null && adminEmail.isNotEmpty) ? adminEmail : (user?.email ?? '');

    final queryParams = <String, String>{
      if (uid.isNotEmpty) 'user_id': uid,
      if (email.isNotEmpty) 'email': email,
      if (displayName != null && displayName.isNotEmpty) 'name': displayName,
      if (avatar != null && avatar.isNotEmpty) 'avatar': avatar,
      if (balance != null) 'balance': balance.toString(),
      if (plan != null && plan.isNotEmpty) 'plan': plan,
      'app_env': AppConfig.environment,
    };

    final uri = Uri.parse(AppConfig.purchaseBaseUrl).replace(queryParameters: queryParams);

    if (await canLaunchUrl(uri)) {
      return await launchUrl(uri, mode: LaunchMode.platformDefault);
    }
    return false;
  }
}
