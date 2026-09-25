class MptReward {
  final String id;
  final String gameId;
  final String userId;
  final String prizeType;
  final String? claimId;
  final String claimReference;
  final String status; // AVAILABLE_TO_CLAIM, CLAIMED, VOID
  final String? verifiedByAdminId;
  final DateTime? claimedAt;
  final DateTime createdAt;

  // Enriched game & organizer context (joined from MPT_games / MPT_users)
  final String? gameName;
  final String? inviteCode;
  final DateTime? gameDate;
  final String? organizerName;

  // Enriched winner context (for Organizer claims management)
  final String? winnerName;
  final String? winnerAvatar;
  final String? winnerEmail;
  final bool isGuest;
  final int? ticketNumber;

  // Brand Partner Gift Fulfillment context
  final double? prizeValue;
  final String? brandOfferId;
  final String? fulfilledGiftTitle;
  final String? fulfilledBrandName;
  final String? fulfilledGiftCode;
  final String? fulfilledProductUrl;
  final String? fulfilledProductImageUrl;
  final String? fulfillmentNote;

  MptReward({
    required this.id,
    required this.gameId,
    required this.userId,
    required this.prizeType,
    this.claimId,
    required this.claimReference,
    required this.status,
    this.verifiedByAdminId,
    this.claimedAt,
    required this.createdAt,
    this.gameName,
    this.inviteCode,
    this.gameDate,
    this.organizerName,
    this.winnerName,
    this.winnerAvatar,
    this.winnerEmail,
    this.isGuest = true,
    this.ticketNumber,
    this.prizeValue,
    this.brandOfferId,
    this.fulfilledGiftTitle,
    this.fulfilledBrandName,
    this.fulfilledGiftCode,
    this.fulfilledProductUrl,
    this.fulfilledProductImageUrl,
    this.fulfillmentNote,
  });

  bool get isAvailable => status == 'AVAILABLE_TO_CLAIM';
  bool get isClaimed => status == 'CLAIMED';

  factory MptReward.fromJson(Map<String, dynamic> json) {
    // Game context may be nested under a 'MPT_games' key (Supabase join)
    final gameMap = json['MPT_games'] as Map<String, dynamic>?;
    // Organizer name may be nested under 'MPT_users' inside the game map
    final organizerMap = gameMap?['MPT_users'] as Map<String, dynamic>?;

    DateTime? gameDate;
    if (gameMap != null) {
      final raw =
          gameMap['completed_at'] ??
          gameMap['started_at'] ??
          gameMap['created_at'];
      if (raw != null) gameDate = DateTime.tryParse(raw.toString());
    } else if (json['game_date'] != null) {
      gameDate = DateTime.tryParse(json['game_date'].toString());
    }

    // Parse fallback gift config from joined MPT_games.prize_gifts_config if present
    final prizeTypeStr = json['prize_type']?.toString() ?? '';
    Map<String, dynamic>? configuredGift;
    if (gameMap != null && gameMap['prize_gifts_config'] is Map) {
      final cfg = gameMap['prize_gifts_config'] as Map;
      if (cfg[prizeTypeStr] is Map) {
        configuredGift = Map<String, dynamic>.from(cfg[prizeTypeStr] as Map);
      }
    }

    final rawFulfilledBrand =
        (json['fulfilled_brand_name'] as String?) ??
        (json['fulfilled_brand'] as String?) ??
        (configuredGift?['brand_name'] as String?);
    final rawFulfilledTitle =
        (json['fulfilled_gift_title'] as String?) ??
        (configuredGift?['gift_title'] as String?) ??
        (configuredGift?['product_title'] as String?);

    return MptReward(
      id: json['id'].toString(),
      gameId: json['game_id'].toString(),
      userId: json['user_id'].toString(),
      prizeType: prizeTypeStr,
      claimId: json['claim_id']?.toString(),
      claimReference: json['claim_reference'].toString(),
      status: json['status'] as String? ?? 'AVAILABLE_TO_CLAIM',
      verifiedByAdminId: json['verified_by_admin_id']?.toString(),
      claimedAt: json['claimed_at'] != null
          ? DateTime.tryParse(json['claimed_at'].toString())
          : null,
      createdAt: json['created_at'] != null
          ? (DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now())
          : DateTime.now(),
      gameName:
          (gameMap?['name'] as String?) ?? (json['game_name'] as String?),
      inviteCode:
          (gameMap?['invite_code'] as String?) ??
          (json['invite_code'] as String?),
      gameDate: gameDate,
      organizerName:
          (organizerMap?['display_name'] as String?) ??
          (json['organizer_name'] as String?),
      winnerName: json['winner_name'] as String?,
      winnerAvatar: json['winner_avatar'] as String?,
      winnerEmail: json['winner_email'] as String?,
      isGuest: json['is_guest'] as bool? ?? true,
      ticketNumber: json['ticket_number'] != null
          ? int.tryParse(json['ticket_number'].toString())
          : null,
      prizeValue:
          (json['prize_value'] as num?)?.toDouble() ??
          (configuredGift?['prize_value'] as num?)?.toDouble() ??
          (configuredGift?['retail_price'] as num?)?.toDouble(),
      brandOfferId:
          (json['brand_offer_id']?.toString()) ??
          (configuredGift?['offer_id']?.toString()),
      fulfilledGiftTitle: rawFulfilledTitle,
      fulfilledBrandName: rawFulfilledBrand,
      fulfilledGiftCode:
          (json['fulfilled_gift_code'] as String?) ??
          (json['fulfilled_code'] as String?),
      fulfilledProductUrl:
          (json['fulfilled_product_url'] as String?) ??
          (configuredGift?['product_url'] as String?),
      fulfilledProductImageUrl:
          (json['fulfilled_product_image_url'] as String?) ??
          (configuredGift?['product_image_url'] as String?),
      fulfillmentNote: json['fulfillment_note'] as String?,
    );
  }
}

class OrganizerGameClaimsSummary {
  final String gameId;
  final String name;
  final String inviteCode;
  final String status;
  final int playerCount;
  final int fundedCapacity;
  final String? organizationName;
  final String? organizationLogoUrl;
  final DateTime? gameDate;
  final int unsettledCount;
  final int settledCount;
  final int totalClaimsCount;
  final List<MptReward> rewards;

  OrganizerGameClaimsSummary({
    required this.gameId,
    required this.name,
    required this.inviteCode,
    required this.status,
    required this.playerCount,
    required this.fundedCapacity,
    this.organizationName,
    this.organizationLogoUrl,
    this.gameDate,
    required this.unsettledCount,
    required this.settledCount,
    required this.totalClaimsCount,
    required this.rewards,
  });

  factory OrganizerGameClaimsSummary.fromJson(Map<String, dynamic> json) {
    final rawRewards = json['rewards'] as List? ?? const [];
    final rewardsList = rawRewards
        .map((e) => MptReward.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();

    return OrganizerGameClaimsSummary(
      gameId: json['game_id']?.toString() ?? '',
      name: json['name'] as String? ?? 'Hosted Game',
      inviteCode: json['invite_code'] as String? ?? '------',
      status: json['status'] as String? ?? 'COMPLETED',
      playerCount: (json['player_count'] as num?)?.toInt() ?? 0,
      fundedCapacity: (json['funded_capacity'] as num?)?.toInt() ?? 25,
      organizationName: json['organization_name'] as String?,
      organizationLogoUrl: json['organization_logo_url'] as String?,
      gameDate: json['game_date'] != null
          ? DateTime.tryParse(json['game_date'].toString())
          : null,
      unsettledCount:
          (json['unsettled_count'] as num?)?.toInt() ??
          rewardsList.where((r) => r.isAvailable).length,
      settledCount:
          (json['settled_count'] as num?)?.toInt() ??
          rewardsList.where((r) => r.isClaimed).length,
      totalClaimsCount:
          (json['total_claims_count'] as num?)?.toInt() ?? rewardsList.length,
      rewards: rewardsList,
    );
  }
}
