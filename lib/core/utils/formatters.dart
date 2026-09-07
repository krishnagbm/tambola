import 'package:intl/intl.dart';

class Formatters {
  static String formatDate(DateTime date) {
    return DateFormat('MMM d, y • h:mm a').format(date.toLocal());
  }

  static String formatShortDate(DateTime date) {
    return DateFormat('MMM d, h:mm a').format(date.toLocal());
  }

  static String formatCredits(int credits) {
    return NumberFormat('#,###').format(credits);
  }

  static String formatPrizeName(String prizeType) {
    switch (prizeType.toUpperCase()) {
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
