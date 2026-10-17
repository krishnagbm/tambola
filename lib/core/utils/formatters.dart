import 'package:intl/intl.dart';
import '../config/app_config.dart';

class Formatters {
  static String formatDate(DateTime date) {
    return DateFormat('MMM d, y • h:mm a').format(date.toLocal());
  }

  static String formatShortDate(DateTime date) {
    return DateFormat('MMM d, h:mm a').format(date.toLocal());
  }

  /// Builds a player-facing invitation message including scheduled date/time and prize pool if applicable
  static String buildGameInviteMessage({
    required String gameName,
    required String inviteCode,
    DateTime? scheduledAt,
    double? totalPrizeBudget,
    String? currencySymbol,
  }) {
    final link = '${AppConfig.appBaseUrl}/#/join/$inviteCode';
    final prizeLine = (totalPrizeBudget != null && totalPrizeBudget > 0)
        ? '🏆 Prize Pool: ${currencySymbol ?? '\$'}${totalPrizeBudget.toStringAsFixed(totalPrizeBudget.truncateToDouble() == totalPrizeBudget ? 0 : 2)} in Brand Vouchers\n'
        : '';
    if (scheduledAt != null) {
      final timeFormatted = formatDate(scheduledAt);
      return '🎉 You are invited to play DabHousie in "$gameName"!\n\n'
          '📅 Scheduled Time: $timeFormatted\n'
          '🔑 Invite Code: $inviteCode\n'
          '${prizeLine.isNotEmpty ? '$prizeLine\n' : ''}'
          '👉 Tap to reserve your seat & preview tickets:\n$link';
    } else {
      return '🎉 You are invited to play DabHousie in "$gameName"!\n\n'
          '🔑 Invite Code: $inviteCode\n'
          '${prizeLine.isNotEmpty ? '$prizeLine\n' : ''}'
          '👉 Tap the link below to join directly in your browser:\n$link';
    }
  }

  static String formatCredits(int credits) {
    return NumberFormat('#,###').format(credits);
  }

  static String formatPrizeName(String prizeType, {int? cellsPerQuadrant}) {
    final upper = prizeType.toUpperCase();
    if (upper.startsWith('ROUND_')) {
      final numPart = upper.replaceFirst('ROUND_', '');
      if (cellsPerQuadrant != null) {
        return 'Round $numPart (Early $cellsPerQuadrant)';
      }
      return 'Round $numPart Winner';
    }
    switch (upper) {
      case 'EARLY_FIVE':
        return 'Early 5 (Jaldi 5)';
      case 'TOP_LINE':
        return 'Top Line';
      case 'MIDDLE_LINE':
        return 'Middle Line';
      case 'BOTTOM_LINE':
        return 'Bottom Line';
      case 'FOUR_CORNERS':
        return 'Four Corners';
      case 'FULL_HOUSE':
        return 'Full House';
      case 'SECOND_FULL_HOUSE':
        return 'Second Full House';
      default:
        return prizeType.replaceAll('_', ' ');
    }
  }

  static String getAvatarEmoji(String? avatarKey) {
    switch (avatarKey) {
      case 'avatar_lion':
        return '🦁';
      case 'avatar_tiger':
        return '🐯';
      case 'avatar_crown':
        return '👑';
      case 'avatar_wizard':
        return '🧙';
      case 'avatar_rocket':
        return '🚀';
      case 'avatar_fox':
        return '🦊';
      case 'avatar_panda':
        return '🐼';
      case 'avatar_unicorn':
        return '🦄';
      case 'avatar_cowboy':
        return '🤠';
      case 'avatar_star':
        return '🌟';
      case 'avatar_bullseye':
        return '🎯';
      case 'avatar_rocker':
        return '🎸';
      default:
        return '👤';
    }
  }
}
