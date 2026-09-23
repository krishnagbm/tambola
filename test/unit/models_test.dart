import 'package:flutter_test/flutter_test.dart';
import 'package:tambola/models/mpt_game.dart';
import 'package:tambola/models/mpt_registration.dart';
import 'package:tambola/models/mpt_reward.dart';
import 'package:tambola/models/mpt_user.dart';
import 'package:tambola/models/mpt_wallet.dart';
import 'package:tambola/repositories/auth_repository.dart';

void main() {
  group('Model Serialization & Logic', () {
    test('AuthRepository 625 nickname generator and randomness', () {
      expect(AuthRepository.nicknameAdjectives.length, 25);
      expect(AuthRepository.nicknameNouns.length, 25);
      expect(AuthRepository.defaultNicknames.length, 625);
      expect(AuthRepository.defaultNicknames.toSet().length, 625);

      final sample = AuthRepository.getRandomDefaultNickname();
      expect(sample, isNotEmpty);
      expect(sample.contains(' '), isTrue);
      expect(AuthRepository.defaultNicknames.contains(sample), isTrue);
    });

    test('AuthRepository getUniqueNicknameForSession excludes taken names', () {
      final allNames = AuthRepository.defaultNicknames;

      // 1. Exclude a specific name
      final takenSingle = {'lucky dabber'};
      for (int i = 0; i < 50; i++) {
        final nick = AuthRepository.getUniqueNicknameForSession(takenSingle);
        expect(nick.toLowerCase(), isNot('lucky dabber'));
      }

      // 2. Room with 250 taken names (max game room capacity)
      final taken250 = allNames.take(250).map((n) => n.toLowerCase()).toSet();
      final picked250 = AuthRepository.getUniqueNicknameForSession(taken250);
      expect(taken250.contains(picked250.toLowerCase()), isFalse);
      expect(allNames.contains(picked250), isTrue);

      // 3. Room with all but 1 name taken
      final onlyAvailable = allNames.last;
      final takenAllExceptOne = allNames.take(allNames.length - 1).map((n) => n.toLowerCase()).toSet();
      final pickedLast = AuthRepository.getUniqueNicknameForSession(takenAllExceptOne);
      expect(pickedLast, onlyAvailable);

      // 4. Room where all 625 names are taken (fallback to numeric suffix)
      final takenAll = allNames.map((n) => n.toLowerCase()).toSet();
      final fallbackNick = AuthRepository.getUniqueNicknameForSession(takenAll);
      expect(fallbackNick, isNotEmpty);
      expect(fallbackNick.split(' ').length, 3); // e.g. "Cosmic Dabber 412"
    });
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
