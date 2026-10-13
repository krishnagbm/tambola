class MptWallet {
  final String userId;
  final int availableCredits;
  final DateTime? lastPaidGameAt;
  final DateTime? creditsExpireAt;
  final DateTime updatedAt;

  MptWallet({
    required this.userId,
    required this.availableCredits,
    this.lastPaidGameAt,
    this.creditsExpireAt,
    required this.updatedAt,
  });

  factory MptWallet.fromJson(Map<String, dynamic> json) {
    return MptWallet(
      userId: json['user_id'] as String,
      availableCredits: (json['available_credits'] as num?)?.toInt() ?? 0,
      lastPaidGameAt: json['last_paid_game_at'] != null ? DateTime.parse(json['last_paid_game_at']) : null,
      creditsExpireAt: json['credits_expire_at'] != null ? DateTime.parse(json['credits_expire_at']) : null,
      updatedAt: json['updated_at'] != null ? DateTime.parse(json['updated_at']) : DateTime.now(),
    );
  }
}

class MptCreditTransaction {
  final String id;
  final String userId;
  final String type; // PURCHASE, MOCK_PURCHASE, GAME_CHARGE, ADJUSTMENT, EXPIRY
  final int amount;
  final int balanceAfter;
  final String? referenceId;
  final String? description;
  final DateTime? expiresAt;
  final DateTime createdAt;

  MptCreditTransaction({
    required this.id,
    required this.userId,
    required this.type,
    required this.amount,
    required this.balanceAfter,
    this.referenceId,
    this.description,
    this.expiresAt,
    required this.createdAt,
  });

  factory MptCreditTransaction.fromJson(Map<String, dynamic> json) {
    DateTime? exp;
    if (json['expires_at'] != null) {
      exp = DateTime.parse(json['expires_at']);
    } else {
      final created = json['created_at'] != null ? DateTime.parse(json['created_at']) : DateTime.now();
      final ref = json['reference_id']?.toString() ?? '';
      final desc = (json['description']?.toString() ?? '').toLowerCase();

      if (ref.startsWith('ADMIN_GRANT_')) {
        // Fallback for admin promo grants (defaults to 30 days if not set in DB)
        exp = created.add(const Duration(days: 30));
      } else if (json['type'] == 'PURCHASE' || json['type'] == 'MOCK_PURCHASE' || desc.contains('welcome')) {
        // Standard purchases or welcome packs valid for 1 year
        exp = created.add(const Duration(days: 365));
      }
    }

    return MptCreditTransaction(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      type: json['type'] as String,
      amount: (json['amount'] as num).toInt(),
      balanceAfter: (json['balance_after'] as num).toInt(),
      referenceId: json['reference_id'] as String?,
      description: json['description'] as String?,
      expiresAt: exp,
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at']) : DateTime.now(),
    );
  }
}
