class BrandOffer {
  final String id;
  final String brandName;
  final String brandDomain;
  final String? brandLogoUrl;
  final String? contactName;
  final String contactEmail;
  final String productTitle;
  final String? productDescription;
  final String category;
  final String offerType;
  final String targetRegion;
  final List<String> targetCountries;
  final String? productImageUrl;
  final String productUrl;
  final double retailPrice;
  final double organizerPrice;
  final int discountPercent;
  final String currency;
  final String voucherCodeType;
  final String? promoCode;
  final String emoji;
  final String? badgeText;
  final String status;
  final String? expirationDate;
  final String? redemptionRestrictions;
  final double? minimumPurchase;
  final bool newCustomersOnly;
  final String redemptionChannel;
  final int vouchersTotalCount;
  final int vouchersConsumedCount;
  final int gamesAssignedCount;
  final int clicksCount;
  final int gameViewsCount;
  final int offerViewsCount;
  final int winnerCount;
  final int rewardClaimsCount;
  final int redemptionsCount;
  final DateTime? updatedAt;

  const BrandOffer({
    required this.id,
    required this.brandName,
    required this.brandDomain,
    this.brandLogoUrl,
    this.contactName,
    required this.contactEmail,
    required this.productTitle,
    this.productDescription,
    required this.category,
    this.offerType = 'DIGITAL_GIFT_VOUCHER',
    this.targetRegion = 'Global',
    this.targetCountries = const ['Global'],
    this.productImageUrl,
    required this.productUrl,
    required this.retailPrice,
    required this.organizerPrice,
    this.discountPercent = 0,
    this.currency = 'USD',
    this.voucherCodeType = 'SHARED_PROMO_CODE',
    this.promoCode,
    this.emoji = '🎁',
    this.badgeText,
    this.status = 'ACTIVE',
    this.expirationDate,
    this.redemptionRestrictions,
    this.minimumPurchase,
    this.newCustomersOnly = false,
    this.redemptionChannel = 'ONLINE',
    this.vouchersTotalCount = 10,
    this.vouchersConsumedCount = 0,
    this.gamesAssignedCount = 0,
    this.clicksCount = 0,
    this.gameViewsCount = 0,
    this.offerViewsCount = 0,
    this.winnerCount = 0,
    this.rewardClaimsCount = 0,
    this.redemptionsCount = 0,
    this.updatedAt,
  });

  factory BrandOffer.fromJson(Map<String, dynamic> json) {
    final rawCountries = json['target_countries'];
    final List<String> parsedCountries = rawCountries is List
        ? rawCountries.map((e) => e.toString()).toList()
        : <String>[(json['target_region'] ?? 'Global').toString()];

    return BrandOffer(
      id: (json['id'] ?? '').toString(),
      brandName: (json['brand_name'] ?? '').toString(),
      brandDomain: (json['brand_domain'] ?? '').toString(),
      brandLogoUrl: json['brand_logo_url'] as String?,
      contactName:
          (json['contact_name'] ?? json['marketer_name']) as String?,
      contactEmail:
          ((json['contact_email'] ?? json['marketer_email']) ?? '').toString(),
      productTitle:
          ((json['product_title'] ?? json['gift_title']) ?? '').toString(),
      productDescription:
          (json['product_description'] ??
                  json['gift_description'] ??
                  json['description'])
              as String?,
      category: (json['category'] ?? 'General').toString(),
      offerType: (json['offer_type'] ?? 'DIGITAL_GIFT_VOUCHER').toString(),
      targetRegion: (json['target_region'] ?? 'Global').toString(),
      targetCountries: parsedCountries.isEmpty ? const ['Global'] : parsedCountries,
      productImageUrl: json['product_image_url'] as String?,
      productUrl: (json['product_url'] ?? '').toString(),
      retailPrice:
          ((json['retail_price'] ?? json['retail_value']) as num?)?.toDouble() ??
          0.0,
      organizerPrice: (json['organizer_price'] as num?)?.toDouble() ?? 0.0,
      discountPercent: (json['discount_percent'] as num?)?.toInt() ?? 0,
      currency: (json['currency'] ?? 'USD').toString(),
      voucherCodeType:
          (json['voucher_code_type'] ?? 'SHARED_PROMO_CODE').toString(),
      promoCode: json['promo_code'] as String?,
      emoji: (json['emoji'] ?? '🎁').toString(),
      badgeText: json['badge_text'] as String?,
      status: (json['status'] ?? 'ACTIVE').toString(),
      expirationDate: json['expiration_date']?.toString(),
      redemptionRestrictions: json['redemption_restrictions'] as String?,
      minimumPurchase: (json['minimum_purchase'] as num?)?.toDouble(),
      newCustomersOnly: json['new_customers_only'] == true,
      redemptionChannel: (json['redemption_channel'] ?? 'ONLINE').toString(),
      vouchersTotalCount:
          (json['vouchers_total_count'] as num?)?.toInt() ?? 10,
      vouchersConsumedCount:
          (json['vouchers_consumed_count'] as num?)?.toInt() ?? 0,
      gamesAssignedCount:
          (json['games_assigned_count'] as num?)?.toInt() ?? 0,
      clicksCount: (json['clicks_count'] as num?)?.toInt() ?? 0,
      gameViewsCount: (json['game_views_count'] as num?)?.toInt() ?? 0,
      offerViewsCount: (json['offer_views_count'] as num?)?.toInt() ?? 0,
      winnerCount: (json['winner_count'] as num?)?.toInt() ?? 0,
      rewardClaimsCount: (json['reward_claims_count'] as num?)?.toInt() ?? 0,
      redemptionsCount: (json['redemptions_count'] as num?)?.toInt() ?? 0,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'].toString())
          : null,
    );
  }

  BrandOffer copyWith({
    double? retailPrice,
    double? organizerPrice,
    String? currency,
  }) {
    return BrandOffer(
      id: id,
      brandName: brandName,
      brandDomain: brandDomain,
      brandLogoUrl: brandLogoUrl,
      contactName: contactName,
      contactEmail: contactEmail,
      productTitle: productTitle,
      productDescription: productDescription,
      category: category,
      offerType: offerType,
      targetRegion: targetRegion,
      targetCountries: targetCountries,
      productImageUrl: productImageUrl,
      productUrl: productUrl,
      retailPrice: retailPrice ?? this.retailPrice,
      organizerPrice: organizerPrice ?? this.organizerPrice,
      discountPercent: discountPercent,
      currency: currency ?? this.currency,
      voucherCodeType: voucherCodeType,
      promoCode: promoCode,
      emoji: emoji,
      badgeText: badgeText,
      status: status,
      expirationDate: expirationDate,
      redemptionRestrictions: redemptionRestrictions,
      minimumPurchase: minimumPurchase,
      newCustomersOnly: newCustomersOnly,
      redemptionChannel: redemptionChannel,
      vouchersTotalCount: vouchersTotalCount,
      vouchersConsumedCount: vouchersConsumedCount,
      gamesAssignedCount: gamesAssignedCount,
      clicksCount: clicksCount,
      gameViewsCount: gameViewsCount,
      offerViewsCount: offerViewsCount,
      winnerCount: winnerCount,
      rewardClaimsCount: rewardClaimsCount,
      redemptionsCount: redemptionsCount,
      updatedAt: updatedAt,
    );
  }

  Map<String, dynamic> toPrizeConfigJson({
    double? customPrizeValue,
    String? currencyCode,
    String? currencySymbol,
  }) {
    return {
      'offer_id': id,
      'brand_name': brandName,
      'brand_domain': brandDomain,
      'brand_logo_url': brandLogoUrl,
      'gift_title': productTitle,
      'product_title': productTitle,
      'offer_type': offerType,
      'target_region': targetRegion,
      'product_url': productUrl,
      'product_image_url': productImageUrl,
      'retail_price': retailPrice,
      'organizer_price': organizerPrice,
      'promo_code': promoCode,
      'emoji': emoji,
      'prize_value': customPrizeValue ?? retailPrice,
      'currency': currencyCode ?? currency,
      'currency_symbol': ?currencySymbol,
      'is_custom_host_offer': isCustomHostOffer,
    };
  }

  bool get isCustomHostOffer => id.startsWith('custom_');

  bool get isHostSelfFulfilledTemplate =>
      !isCustomHostOffer &&
      organizerPrice > 0 &&
      (promoCode == null || promoCode!.trim().isEmpty);

  int get vouchersRemaining =>
      (vouchersTotalCount - vouchersConsumedCount).clamp(0, 999999);

  String get offerTypeLabel {
    switch (offerType.toUpperCase()) {
      case 'PERCENTAGE_DISCOUNT':
        return '🏷️ % Discount';
      case 'FIXED_VALUE_OFFER':
        return '💵 Fixed Offer';
      case 'FREE_ITEM_WITH_PURCHASE':
        return '🎁 Free w/ Purchase';
      case 'SUBSCRIPTION_TRIAL':
        return '⚡ App / Trial';
      case 'PRODUCT_BUNDLE':
        return '📦 Bundle Offer';
      case 'EVENT_EXPERIENCE_REWARD':
        return '🎟️ Experience';
      default:
        return '🎟️ Gift Voucher';
    }
  }

  String get categoryEmoji => emoji;
}

