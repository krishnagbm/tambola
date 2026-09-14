import 'package:flutter_test/flutter_test.dart';
import 'package:tambola/models/mpt_capacity_tier.dart';

void main() {
  group('Capacity Tiers & Credit Pricing Tests', () {
    test('Default capacity tiers contain all 6 confirmed tiers with exact credit costs', () {
      final tiers = MptCapacityTier.defaultTiers;
      expect(tiers.length, 6);

      // Tier 1: Family Pack (1–5) -> 0 credits
      expect(tiers[0].minPlayers, 1);
      expect(tiers[0].maxPlayers, 5);
      expect(tiers[0].creditsRequired, 0);

      // Tier 2: Small Party (6–15) -> 15 credits
      expect(tiers[1].minPlayers, 6);
      expect(tiers[1].maxPlayers, 15);
      expect(tiers[1].creditsRequired, 15);

      // Tier 3: Medium Group (16–25) -> 25 credits
      expect(tiers[2].minPlayers, 16);
      expect(tiers[2].maxPlayers, 25);
      expect(tiers[2].creditsRequired, 25);

      // Tier 4: Large Group (26–50) -> 50 credits
      expect(tiers[3].minPlayers, 26);
      expect(tiers[3].maxPlayers, 50);
      expect(tiers[3].creditsRequired, 50);

      // Tier 5: Club Event (51–100) -> 100 credits
      expect(tiers[4].minPlayers, 51);
      expect(tiers[4].maxPlayers, 100);
      expect(tiers[4].creditsRequired, 100);

      // Tier 6: Mega Event (101–250) -> 250 credits
      expect(tiers[5].minPlayers, 101);
      expect(tiers[5].maxPlayers, 250);
      expect(tiers[5].creditsRequired, 250);
    });

    test('Tier resolution matches player counts accurately', () {
      final tiers = MptCapacityTier.defaultTiers;

      int getCreditsForCount(int confirmedCount) {
        final matchingTier = tiers.firstWhere(
          (t) => (confirmedCount == 0 && t.minPlayers <= 1) || (confirmedCount > 0 && confirmedCount >= t.minPlayers && confirmedCount <= t.maxPlayers),
          orElse: () => tiers.firstWhere((t) => t.maxPlayers >= confirmedCount, orElse: () => tiers.last),
        );
        return matchingTier.creditsRequired;
      }

      expect(getCreditsForCount(0), 0);
      expect(getCreditsForCount(1), 0);
      expect(getCreditsForCount(5), 0);
      expect(getCreditsForCount(6), 15);
      expect(getCreditsForCount(15), 15);
      expect(getCreditsForCount(16), 25);
      expect(getCreditsForCount(25), 25);
      expect(getCreditsForCount(26), 50);
      expect(getCreditsForCount(50), 50);
      expect(getCreditsForCount(51), 100);
      expect(getCreditsForCount(100), 100);
      expect(getCreditsForCount(101), 250);
      expect(getCreditsForCount(250), 250);
    });

    test('MptCapacityTier.fromJson parses valid JSON data with fallbacks', () {
      final tier = MptCapacityTier.fromJson({
        'id': 'abc-123',
        'name': 'Custom Tier',
        'min_players': 10,
        'max_players': 30,
        'credits_required': 30,
        'display_order': 2,
      });

      expect(tier.id, 'abc-123');
      expect(tier.name, 'Custom Tier');
      expect(tier.minPlayers, 10);
      expect(tier.maxPlayers, 30);
      expect(tier.creditsRequired, 30);
      expect(tier.displayOrder, 2);
      expect(tier.isActive, isTrue);
    });
  });
}
