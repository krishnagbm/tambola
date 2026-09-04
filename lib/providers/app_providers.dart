import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/mpt_called_number.dart';
import '../models/mpt_capacity_tier.dart';
import '../models/mpt_claim.dart';
import '../models/mpt_game.dart';
import '../models/mpt_registration.dart';
import '../models/mpt_reward.dart';
import '../models/mpt_ticket.dart';
import '../models/mpt_user.dart';
import '../models/mpt_wallet.dart';
import '../repositories/auth_repository.dart';
import '../repositories/game_repository.dart';
import '../repositories/gameplay_repository.dart';
import '../repositories/rewards_repository.dart';
import '../repositories/wallet_repository.dart';

// Supabase Client Provider
final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

// Repositories
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.watch(supabaseClientProvider));
});

final gameRepositoryProvider = Provider<GameRepository>((ref) {
  return GameRepository(ref.watch(supabaseClientProvider));
});

final walletRepositoryProvider = Provider<WalletRepository>((ref) {
  return WalletRepository(ref.watch(supabaseClientProvider));
});

final gameplayRepositoryProvider = Provider<GameplayRepository>((ref) {
  return GameplayRepository(ref.watch(supabaseClientProvider));
});

final rewardsRepositoryProvider = Provider<RewardsRepository>((ref) {
  return RewardsRepository(ref.watch(supabaseClientProvider));
});

// Current User State Notifier
class CurrentUserNotifier extends StateNotifier<AsyncValue<MptUser>> {
  final AuthRepository _authRepo;

  CurrentUserNotifier(this._authRepo) : super(const AsyncValue.loading()) {
    init();
  }

  Future<void> init() async {
    state = const AsyncValue.loading();
    try {
      final user = await _authRepo.initializeAuth();
      state = AsyncValue.data(user);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> updateProfile({required String displayName, required String avatar}) async {
    try {
      final updated = await _authRepo.updateProfile(displayName: displayName, avatar: avatar);
      state = AsyncValue.data(updated);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

final currentUserProvider = StateNotifierProvider<CurrentUserNotifier, AsyncValue<MptUser>>((ref) {
  return CurrentUserNotifier(ref.watch(authRepositoryProvider));
});

// Wallet Provider
final walletProvider = FutureProvider.autoDispose<MptWallet>((ref) async {
  return ref.watch(walletRepositoryProvider).getWallet();
});

// Credit Transactions Provider
final creditTransactionsProvider = FutureProvider.autoDispose<List<MptCreditTransaction>>((ref) async {
  return ref.watch(walletRepositoryProvider).getTransactions();
});

// Capacity Tiers Provider
final capacityTiersProvider = FutureProvider.autoDispose<List<MptCapacityTier>>((ref) async {
  return ref.watch(walletRepositoryProvider).getCapacityTiers();
});

// Live Game Stream Provider
final gameStreamProvider = StreamProvider.autoDispose.family<MptGame, String>((ref, gameId) {
  return ref.watch(gameRepositoryProvider).watchGame(gameId);
});

// Live Registrations Stream Provider
final registrationsStreamProvider = StreamProvider.autoDispose.family<List<MptRegistration>, String>((ref, gameId) {
  return ref.watch(gameRepositoryProvider).watchRegistrations(gameId);
});

// My Registration Provider
final myRegistrationProvider = FutureProvider.autoDispose.family<MptRegistration?, String>((ref, gameId) async {
  return ref.watch(gameRepositoryProvider).getMyRegistration(gameId);
});

// Live Called Numbers Stream Provider
final calledNumbersStreamProvider = StreamProvider.autoDispose.family<List<MptCalledNumber>, String>((ref, gameId) {
  return ref.watch(gameplayRepositoryProvider).watchCalledNumbers(gameId);
});

// Live Claims Stream Provider
final claimsStreamProvider = StreamProvider.autoDispose.family<List<MptClaim>, String>((ref, gameId) {
  return ref.watch(gameplayRepositoryProvider).watchClaims(gameId);
});

// Player Ticket Provider
final playerTicketProvider = FutureProvider.autoDispose.family<MptTicket, String>((ref, gameId) async {
  return ref.watch(gameplayRepositoryProvider).getOrCreatePlayerTicket(gameId);
});

// My Rewards Provider
final myRewardsProvider = FutureProvider.autoDispose<List<MptReward>>((ref) async {
  return ref.watch(rewardsRepositoryProvider).getMyRewards();
});

// My Hosted Games Provider (Organizer Dashboard)
final myHostedGamesProvider = FutureProvider.autoDispose<List<MptGame>>((ref) async {
  return ref.watch(gameRepositoryProvider).getMyHostedGames();
});

// My Joined Games Provider (Player Dashboard)
final myJoinedGamesProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  return ref.watch(gameRepositoryProvider).getMyJoinedGames();
});

