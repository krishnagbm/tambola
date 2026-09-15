import 'package:flutter_test/flutter_test.dart';
import 'package:tambola/models/mpt_game.dart';
import 'package:tambola/models/mpt_registration.dart';
import 'package:tambola/models/mpt_reward.dart';
import 'package:tambola/models/mpt_user.dart';
import 'package:tambola/models/mpt_wallet.dart';

void main() {
  group('Model Serialization & Logic', () {
    test('MptUser serialization and registration status', () {
      final anonymousUser = MptUser(
        id: 'u-123',
        displayName: 'Aarav',
        avatar: 'avatar_2',
        isAnonymous: true,
        createdAt: DateTime.parse('2026-09-01T10:00:00Z'),
        updatedAt: DateTime.parse('2026-09-01T10:00:00Z'),
      );

      expect(anonymousUser.isAnonymous, isTrue);
      expect(anonymousUser.isRegistered, isFalse);
      expect(anonymousUser.email, isNull);

      final registeredUser = MptUser(
        id: 'u-456',
        displayName: 'Priya Sharma',
        avatar: 'avatar_1',
        isAnonymous: false,
        email: 'priya@example.com',
        avatarUrl: 'https://lh3.googleusercontent.com/a/test-avatar',
        provider: 'google',
        createdAt: DateTime.parse('2026-09-01T10:00:00Z'),
        updatedAt: DateTime.parse('2026-09-01T10:00:00Z'),
      );

      final json = registeredUser.toJson();
      final fromJson = MptUser.fromJson(json);

      expect(fromJson.id, 'u-456');
      expect(fromJson.displayName, 'Priya Sharma');
      expect(fromJson.isAnonymous, isFalse);
      expect(fromJson.isRegistered, isTrue);
      expect(fromJson.email, 'priya@example.com');
      expect(fromJson.avatarUrl, 'https://lh3.googleusercontent.com/a/test-avatar');
      expect(fromJson.provider, 'google');
    });

    test('MptGame state logic', () {
      final game = MptGame(
        id: 'g-100',
        adminUserId: 'u-admin',
        name: 'Diwalli Special',
        inviteCode: 'DIW26A',
        status: 'OPEN',
        initialFundedCapacity: 25,
        fundedCapacity: 50,
        prizesConfig: ['EARLY_FIVE', 'FULL_HOUSE'],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(game.isOpen, isTrue);
      expect(game.isInProgress, isFalse);
      expect(game.isCompleted, isFalse);
    });

    test('MptRegistration seat status checks', () {
      final confirmedReg = MptRegistration(
        id: 'reg-1',
        gameId: 'g-100',
        userId: 'u-1',
        displayName: 'Player 1',
        avatar: 'avatar_1',
        registrationSeq: 1,
        seatStatus: 'CONFIRMED',
        joinedAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(confirmedReg.isConfirmed, isTrue);
      expect(confirmedReg.isWaiting, isFalse);

      final waitingReg = MptRegistration(
        id: 'reg-26',
        gameId: 'g-100',
        userId: 'u-26',
        displayName: 'Player 26',
        avatar: 'avatar_1',
        registrationSeq: 26,
        seatStatus: 'WAITING',
        joinedAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(waitingReg.isConfirmed, isFalse);
      expect(waitingReg.isWaiting, isTrue);
    });

    test('MptWallet balance and transactions', () {
      final wallet = MptWallet(
        userId: 'u-admin',
        availableCredits: 500,
        updatedAt: DateTime.now(),
      );

      expect(wallet.availableCredits, 500);

      final tx = MptCreditTransaction(
        id: 'tx-1',
        userId: 'u-admin',
        type: 'MOCK_PURCHASE',
        amount: 200,
        balanceAfter: 500,
        createdAt: DateTime.now(),
      );

      expect(tx.amount, 200);
      expect(tx.balanceAfter, 500);
    });

    test('MptReward voucher reference', () {
      final reward = MptReward(
        id: 'rew-1',
        gameId: 'g-100',
        userId: 'u-1',
        prizeType: 'FULL_HOUSE',
        claimReference: 'MPT-REW-7K9Q-X4M2',
        status: 'AVAILABLE_TO_CLAIM',
        createdAt: DateTime.now(),
      );

      expect(reward.isAvailable, isTrue);
      expect(reward.claimReference, 'MPT-REW-7K9Q-X4M2');
    });
  });
}
