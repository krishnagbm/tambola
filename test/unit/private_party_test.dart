import 'package:flutter_test/flutter_test.dart';
import 'package:tambola/models/mpt_game.dart';
import 'package:tambola/models/mpt_seat_otp.dart';

void main() {
  group('Private Parties & Seat OTPs Model Tests', () {
    test('MptGame parses is_private correctly', () {
      final json = {
        'id': 'd9e0340b-465d-4f1e-8e8e-d903f8c85c21',
        'admin_user_id': '88e5d3c1-01f7-41ab-8e01-c8b9d3e8e190',
        'name': 'Corporate Team Gala',
        'invite_code': 'CORP99',
        'status': 'OPEN',
        'is_private': true,
        'initial_funded_capacity': 20,
        'funded_capacity': 20,
        'prizes_config': ['EARLY_FIVE', 'FULL_HOUSE'],
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      };

      final game = MptGame.fromJson(json);
      expect(game.isPrivate, isTrue);
      expect(game.inviteCode, equals('CORP99'));
      expect(game.fundedCapacity, equals(20));

      final serialized = game.toJson();
      expect(serialized['is_private'], isTrue);
    });

    test('MptSeatOtp model handles status properties correctly', () {
      final unclaimed = MptSeatOtp(
        id: 'seat-1',
        gameId: 'game-1',
        seatNumber: 1,
        otpCode: '581924',
        status: 'UNCLAIMED',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(unclaimed.isUnclaimed, isTrue);
      expect(unclaimed.isClaimed, isFalse);
      expect(unclaimed.isRevoked, isFalse);

      final claimedJson = {
        'id': 'seat-2',
        'game_id': 'game-1',
        'seat_number': 2,
        'otp_code': '918231',
        'status': 'CLAIMED',
        'claimed_by_user_id': 'user-123',
        'claimed_at': DateTime.now().toIso8601String(),
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      };

      final claimed = MptSeatOtp.fromJson(claimedJson);
      expect(claimed.isClaimed, isTrue);
      expect(claimed.isUnclaimed, isFalse);
      expect(claimed.claimedByUserId, equals('user-123'));
    });

    test('Private Party Option A credit schedule calculations', () {
      int getPrivateCredits(int maxPlayers) {
        if (maxPlayers <= 5) return 5;
        if (maxPlayers <= 15) return 20;
        if (maxPlayers <= 25) return 35;
        if (maxPlayers <= 50) return 70;
        if (maxPlayers <= 100) return 135;
        return 325;
      }

      expect(getPrivateCredits(5), equals(5));
      expect(getPrivateCredits(15), equals(20));
      expect(getPrivateCredits(25), equals(35));
      expect(getPrivateCredits(50), equals(70));
      expect(getPrivateCredits(100), equals(135));
      expect(getPrivateCredits(250), equals(325));
    });
  });
}
