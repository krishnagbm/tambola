import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/mpt_reward.dart';

class RewardsRepository {
  final SupabaseClient _supabase;

  RewardsRepository(this._supabase);

  static const String _rewardSelectQuery =
      '*, MPT_games(name, invite_code, started_at, completed_at, created_at, prize_gifts_config, MPT_users(display_name))';

  /// Gets all rewards won by the current player, enriched with game & organizer context.
  /// Also self-heals any APPROVED claims for this user that may be missing a row in MPT_rewards.
  Future<List<MptReward>> getMyRewards() async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return [];

    // 1. Self-heal: check if user has any APPROVED claims without a reward record
    try {
      final approvedClaims = await _supabase
          .from('MPT_claims')
          .select('id, game_id, user_id, prize_type')
          .eq('user_id', uid)
          .eq('status', 'APPROVED');

      final existingRewards = await _supabase
          .from('MPT_rewards')
          .select('id, claim_id, game_id, prize_type')
          .eq('user_id', uid);

      final existingClaimIds = (existingRewards as List)
          .map((r) => r['claim_id'] as String?)
          .whereType<String>()
          .toSet();
      final existingGamePrizes = (existingRewards)
          .map((r) => '${r['game_id']}_${r['prize_type']}')
          .toSet();

      for (final c in (approvedClaims as List)) {
        final claimId = c['id'] as String;
        final gameId = c['game_id'] as String;
        final prizeType = c['prize_type'] as String;
        if (!existingClaimIds.contains(claimId) &&
            !existingGamePrizes.contains('${gameId}_$prizeType')) {
          final cleanHex = claimId.replaceAll('-', '').toUpperCase();
          final fallbackRef =
              'Dab-Housie-${cleanHex.substring(0, 4)}-${cleanHex.substring(4, 8)}';
          try {
            await _supabase.from('MPT_rewards').insert({
              'game_id': gameId,
              'user_id': uid,
              'prize_type': prizeType,
              'claim_id': claimId,
              'claim_reference': fallbackRef,
              'status': 'AVAILABLE_TO_CLAIM',
            });
          } catch (_) {}
        }
      }
    } catch (_) {}

    // 2. Join MPT_games -> MPT_users (organizer) in one query
    final res = await _supabase
        .from('MPT_rewards')
        .select(_rewardSelectQuery)
        .eq('user_id', uid)
        .order('created_at', ascending: false);

    final list = (res as List).map((e) => MptReward.fromJson(e)).toList();

    // 3. Enrich any rewards whose game was archived into MPT_game_archives
    final missingGameIds = list
        .where((r) => r.gameName == null || r.inviteCode == null)
        .map((r) => r.gameId)
        .toSet()
        .toList();

    if (missingGameIds.isNotEmpty) {
      try {
        final archives = await _supabase
            .from('MPT_game_archives')
            .select(
              'game_id, name, invite_code, organization_name, completed_at',
            )
            .inFilter('game_id', missingGameIds);
        final archiveMap = <String, Map<String, dynamic>>{};
        for (final row in (archives as List)) {
          final gid = row['game_id']?.toString();
          if (gid != null) {
            archiveMap[gid] = Map<String, dynamic>.from(row as Map);
          }
        }
        return list.map((r) {
          final arch = archiveMap[r.gameId];
          if (arch == null) return r;
          return MptReward(
            id: r.id,
            gameId: r.gameId,
            userId: r.userId,
            prizeType: r.prizeType,
            claimId: r.claimId,
            claimReference: r.claimReference,
            status: r.status,
            verifiedByAdminId: r.verifiedByAdminId,
            claimedAt: r.claimedAt,
            createdAt: r.createdAt,
            gameName: r.gameName ?? (arch['name'] as String?),
            inviteCode: r.inviteCode ?? (arch['invite_code'] as String?),
            gameDate:
                r.gameDate ??
                (arch['completed_at'] != null
                    ? DateTime.tryParse(arch['completed_at'].toString())
                    : null),
            organizerName:
                r.organizerName ?? (arch['organization_name'] as String?),
            winnerName: r.winnerName,
            winnerAvatar: r.winnerAvatar,
            winnerEmail: r.winnerEmail,
            isGuest: r.isGuest,
            ticketNumber: r.ticketNumber,
            prizeValue: r.prizeValue,
            brandOfferId: r.brandOfferId,
            fulfilledGiftTitle: r.fulfilledGiftTitle,
            fulfilledBrandName: r.fulfilledBrandName,
            fulfilledGiftCode: r.fulfilledGiftCode,
            fulfilledProductUrl: r.fulfilledProductUrl,
            fulfilledProductImageUrl: r.fulfilledProductImageUrl,
            fulfillmentNote: r.fulfillmentNote,
          );
        }).toList();
      } catch (_) {}
    }

    return list;
  }

  /// Searches rewards by voucher reference code (case-insensitive) across MPT_rewards
  /// so players can look up a voucher code even if won in another tab/guest session.
  Future<List<MptReward>> searchRewardsByCode(String query) async {
    final trimmed = query.trim();
    if (trimmed.length < 3) return [];
    final normalized = trimmed.replaceFirst(
      RegExp(r'^mpt-(rew-)?', caseSensitive: false),
      'Dab-Housie-',
    );

    try {
      final res = await _supabase
          .from('MPT_rewards')
          .select(_rewardSelectQuery)
          .ilike('claim_reference', '%$normalized%')
          .order('created_at', ascending: false)
          .limit(20);

      return (res as List).map((e) => MptReward.fromJson(e)).toList();
    } catch (_) {
      return [];
    }
  }

  /// Fetches all prize rewards/claims for a hosted game (for the Organizer).
  Future<List<MptReward>> getGameRewardsForHost(String gameId) async {
    try {
      final res = await _supabase.rpc(
        'MPT_get_game_rewards_for_host',
        params: {'p_game_id': gameId},
      );
      if (res is List) {
        return res
            .map(
              (e) => MptReward.fromJson(Map<String, dynamic>.from(e as Map)),
            )
            .toList();
      }
    } catch (_) {}

    // Fallback direct query with manual registration & archive enrichment
    try {
      final rows = await _supabase
          .from('MPT_rewards')
          .select(_rewardSelectQuery)
          .eq('game_id', gameId)
          .order('created_at', ascending: true);

      final regRows = await _supabase
          .from('MPT_game_registrations')
          .select('user_id, display_name, avatar, registration_seq')
          .eq('game_id', gameId);
      final regByUser = <String, Map<String, dynamic>>{};
      for (final reg in (regRows as List)) {
        final uid = reg['user_id']?.toString();
        if (uid != null) {
          regByUser[uid] = Map<String, dynamic>.from(reg as Map);
        }
      }

      return (rows as List).map((e) {
        final map = Map<String, dynamic>.from(e as Map);
        final uid = map['user_id']?.toString();
        final reg = uid != null ? regByUser[uid] : null;
        if (reg != null) {
          map['winner_name'] ??= reg['display_name'];
          map['winner_avatar'] ??= reg['avatar'];
          map['ticket_number'] ??= reg['registration_seq'];
        }
        return MptReward.fromJson(map);
      }).toList();
    } catch (_) {
      return [];
    }
  }

  /// Fetches all games conducted by the current Organizer along with unsettled/settled
  /// claim counts and full player-enriched claims for each game.
  Future<List<OrganizerGameClaimsSummary>> getOrganizerAllGamesClaims() async {
    try {
      final res = await _supabase.rpc('MPT_get_organizer_all_games_claims');
      if (res is List) {
        return res
            .map(
              (e) => OrganizerGameClaimsSummary.fromJson(
                Map<String, dynamic>.from(e as Map),
              ),
            )
            .toList();
      }
    } catch (_) {}

    // Fallback if RPC unavailable
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return [];
    try {
      final games = await _supabase
          .from('MPT_games')
          .select()
          .eq('admin_user_id', uid)
          .order('created_at', ascending: false);

      final summaries = <OrganizerGameClaimsSummary>[];
      for (final rawGame in (games as List)) {
        final g = Map<String, dynamic>.from(rawGame as Map);
        final gid = g['id'].toString();
        final rewards = await getGameRewardsForHost(gid);
        final unsettled = rewards.where((r) => r.isAvailable).length;
        final settled = rewards.where((r) => r.isClaimed).length;
        summaries.add(
          OrganizerGameClaimsSummary(
            gameId: gid,
            name: g['name'] as String? ?? 'Hosted Game',
            inviteCode: g['invite_code'] as String? ?? '------',
            status: g['status'] as String? ?? 'COMPLETED',
            playerCount: (g['final_capacity'] as num?)?.toInt() ?? 0,
            fundedCapacity: (g['funded_capacity'] as num?)?.toInt() ?? 25,
            organizationName: g['organization_name'] as String?,
            organizationLogoUrl: g['organization_logo_url'] as String?,
            gameDate: DateTime.tryParse(
              (g['completed_at'] ?? g['started_at'] ?? g['created_at'] ?? '')
                  .toString(),
            ),
            unsettledCount: unsettled,
            settledCount: settled,
            totalClaimsCount: rewards.length,
            rewards: rewards,
          ),
        );
      }
      return summaries;
    } catch (_) {
      return [];
    }
  }

  /// Allows the Game Organizer to close/mark a single claim or all claims in a game as CLAIMED,
  /// optionally attaching Brand Partner Gift / Voucher fulfillment details.
  Future<List<MptReward>> closeGameClaim({
    required String gameId,
    String? rewardId,
    String? claimId,
    bool closeAll = false,
    String? giftTitle,
    String? brandName,
    String? giftCode,
    String? productUrl,
    String? brandOfferId,
    double? prizeValue,
    String? fulfillmentNote,
  }) async {
    try {
      final res = await _supabase.rpc(
        'MPT_close_game_claim',
        params: {
          'p_game_id': gameId,
          'p_reward_id': rewardId,
          'p_claim_id': claimId,
          'p_close_all': closeAll,
          'p_fulfilled_brand': brandName != null && giftTitle != null
              ? '$brandName — $giftTitle'
              : (brandName ?? giftTitle),
          'p_fulfilled_code': giftCode,
          'p_fulfilled_product_url': productUrl,
          'p_brand_offer_id': brandOfferId,
          'p_prize_value': prizeValue,
        },
      );
      if (res is Map && res['rewards'] is List) {
        return (res['rewards'] as List)
            .map(
              (e) => MptReward.fromJson(Map<String, dynamic>.from(e as Map)),
            )
            .toList();
      }
    } catch (_) {
      // Fallback direct update
      final uid = _supabase.auth.currentUser?.id;
      final updateMap = <String, dynamic>{
        'status': 'CLAIMED',
        'verified_by_admin_id': uid,
        'claimed_at': DateTime.now().toIso8601String(),
      };
      if (giftTitle != null) updateMap['fulfilled_gift_title'] = giftTitle;
      if (brandName != null) updateMap['fulfilled_brand_name'] = brandName;
      if (giftCode != null) updateMap['fulfilled_gift_code'] = giftCode;
      if (productUrl != null) updateMap['fulfilled_product_url'] = productUrl;
      if (brandOfferId != null) updateMap['brand_offer_id'] = brandOfferId;
      if (prizeValue != null) updateMap['prize_value'] = prizeValue;
      if (fulfillmentNote != null) {
        updateMap['fulfillment_note'] = fulfillmentNote;
      }

      var query = _supabase
          .from('MPT_rewards')
          .update(updateMap)
          .eq('game_id', gameId);

      if (!closeAll) {
        if (rewardId != null) {
          query = query.eq('id', rewardId);
        } else if (claimId != null) {
          query = query.eq('claim_id', claimId);
        }
      }
      await query;
    }
    return getGameRewardsForHost(gameId);
  }

  /// Dispatches a rich HTML Prize & Brand Gift Voucher email via AWS SES
  Future<bool> sendWinnerGiftEmail({
    required String toEmail,
    required MptReward reward,
  }) async {
    try {
      final uri = Uri.parse(
        'https://6uvajebdr2.execute-api.us-east-2.amazonaws.com/Prod/email/private-party',
      );
      final resp = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': 'send_winner_gift_email',
          'to_email': toEmail.trim(),
          'player_name': reward.winnerName ?? 'DabHousie Winner',
          'game_name': reward.gameName ?? 'DabHousie Event',
          'invite_code': reward.inviteCode ?? '------',
          'prize_type': reward.prizeType,
          'verification_code': reward.claimReference,
          'prize_value': reward.prizeValue,
          'brand_name': reward.fulfilledBrandName,
          'gift_title': reward.fulfilledGiftTitle,
          'product_url': reward.fulfilledProductUrl,
          'fulfilled_code': reward.fulfilledGiftCode,
        }),
      );
      if (resp.statusCode == 200) {
        final decoded = jsonDecode(resp.body);
        return decoded is Map && decoded['success'] == true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Admin verifies a claim reference code presented by a player
  Future<Map<String, dynamic>> verifyReward(String claimReference) async {
    try {
      final normalized = claimReference.trim().replaceFirst(
        RegExp(r'^mpt-(rew-)?', caseSensitive: false),
        'Dab-Housie-',
      );
      final res = await _supabase.rpc('MPT_verify_reward', params: {
        'p_claim_reference': normalized.toUpperCase(),
      });
      return res as Map<String, dynamic>;
    } catch (e) {
      return {
        'status': 'ERROR',
        'message': e.toString(),
      };
    }
  }
}

