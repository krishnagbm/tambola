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
  final String? productImageUrl;
  final String productUrl;
  final double retailPrice;
  final double organizerPrice;
  final int discountPercent;
  final String currency;
  final String? promoCode;
  final String emoji;
  final String? badgeText;
  final String status;
  final int gamesAssignedCount;
  final int clicksCount;

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
    this.productImageUrl,
    required this.productUrl,
    required this.retailPrice,
    required this.organizerPrice,
    this.discountPercent = 0,
    this.currency = 'USD',
    this.promoCode,
    this.emoji = '🎁',
    this.badgeText,
    this.status = 'ACTIVE',
    this.gamesAssignedCount = 0,
    this.clicksCount = 0,
  });

  factory BrandOffer.fromJson(Map<String, dynamic> json) {
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
          (json['product_description'] ?? json['gift_description']) as String?,
      category: (json['category'] ?? 'General').toString(),
      productImageUrl: json['product_image_url'] as String?,
      productUrl: (json['product_url'] ?? '').toString(),
      retailPrice:
          ((json['retail_price'] ?? json['retail_value']) as num?)?.toDouble() ??
          0.0,
      organizerPrice: (json['organizer_price'] as num?)?.toDouble() ?? 0.0,
      discountPercent: (json['discount_percent'] as num?)?.toInt() ?? 0,
      currency: (json['currency'] ?? 'USD').toString(),
      promoCode: json['promo_code'] as String?,
      emoji: (json['emoji'] ?? '🎁').toString(),
      badgeText: json['badge_text'] as String?,
      status: (json['status'] ?? 'ACTIVE').toString(),
      gamesAssignedCount:
          (json['games_assigned_count'] as num?)?.toInt() ?? 0,
      clicksCount: (json['clicks_count'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toPrizeConfigJson({double? customPrizeValue}) {
    return {
      'offer_id': id,
      'brand_name': brandName,
      'brand_domain': brandDomain,
      'brand_logo_url': brandLogoUrl,
      'gift_title': productTitle,
      'product_title': productTitle,
      'product_url': productUrl,
      'product_image_url': productImageUrl,
      'retail_price': retailPrice,
      'organizer_price': organizerPrice,
      'promo_code': promoCode,
      'emoji': emoji,
      'prize_value': customPrizeValue ?? retailPrice,
    };
  }

  String get categoryEmoji => emoji;
}
