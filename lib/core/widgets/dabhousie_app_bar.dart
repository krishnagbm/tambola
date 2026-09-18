import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/app_config.dart';
import '../constants/app_assets.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import '../../providers/app_providers.dart';
import '../../features/auth/widgets/auth_dialog.dart';

class DabHousieAppBar extends ConsumerWidget implements PreferredSizeWidget {
  final String? badgeText;
  final bool showBackButton;
  final VoidCallback? onBack;
  final VoidCallback? onRefresh;
  final bool showDesktopNav;
  final bool showWallet;
  final bool showRewards;
  final bool showAuth;
  final List<Widget>? extraActions;

  const DabHousieAppBar({
    super.key,
    this.badgeText,
    this.showBackButton = false,
    this.onBack,
    this.onRefresh,
    this.showDesktopNav = true,
    this.showWallet = true,
    this.showRewards = true,
    this.showAuth = true,
    this.extraActions,
  });

  @override
  Size get preferredSize => const Size.fromHeight(64);

  Future<void> _handleSignOut(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.darkCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Sign Out?', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text(
          'Are you sure you want to sign out? You will return to a guest session, and will need to sign in again to host games.',
          style: TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accentDanger,
              foregroundColor: Colors.white,
            ),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await ref.read(authRepositoryProvider).signOut();
      ref.invalidate(currentUserProvider);
      ref.invalidate(walletProvider);
      ref.invalidate(creditTransactionsProvider);
      ref.invalidate(myHostedGamesProvider);
      ref.invalidate(myJoinedGamesProvider);
      if (context.mounted) {
        context.go('/');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Signed out successfully')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error signing out: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userState = ref.watch(currentUserProvider);
    final walletState = ref.watch(walletProvider);
    final user = userState.value;
    final screenWidth = MediaQuery.of(context).size.width;

    return AppBar(
      toolbarHeight: 64,
      centerTitle: false,
      titleSpacing: showBackButton ? 0 : 16,
      leading: showBackButton
          ? IconButton(
              icon: const Icon(Icons.arrow_back),
              tooltip: 'Back',
              onPressed: onBack ??
                  () {
                    if (context.canPop()) {
                      context.pop();
                    } else {
                      context.go('/');
                    }
                  },
            )
          : null,
      title: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          InkWell(
            onTap: () => context.go('/'),
            borderRadius: BorderRadius.circular(8),
            child: Image.asset(
              AppAssets.horizontalLogo,
              height: 42,
              fit: BoxFit.contain,
            ),
          ),
          if (badgeText != null) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: AppTheme.primaryLight.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.primaryLight.withValues(alpha: 0.6)),
              ),
              child: Text(
                badgeText!,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.secondaryColor,
                ),
              ),
            ),
          ],
        ],
      ),
      actions: [
        if (showDesktopNav && screenWidth > 768) ...[
          TextButton(
            onPressed: () => launchUrl(
              Uri.parse('${AppConfig.appBaseUrl}/how-it-works.html'),
              webOnlyWindowName: '_self',
            ),
            child: const Text(
              'How It Works',
              style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          TextButton(
            onPressed: () => launchUrl(
              Uri.parse('${AppConfig.appBaseUrl}/90-ball-bingo.html'),
              webOnlyWindowName: '_self',
            ),
            child: const Text(
              '90-Ball Bingo Guide',
              style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          TextButton(
            onPressed: () => launchUrl(
              Uri.parse('${AppConfig.appBaseUrl}/pricing.html'),
              webOnlyWindowName: '_self',
            ),
            child: const Text(
              'Pricing',
              style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 8),
        ],
        if (onRefresh != null)
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: onRefresh,
          ),
        if (showRewards)
          IconButton(
            icon: const Icon(Icons.emoji_events_outlined, color: AppTheme.secondaryColor),
            tooltip: 'My Rewards',
            onPressed: () => context.push('/rewards'),
          ),
        if (showWallet)
          walletState.when(
            data: (w) {
              final credits = w.availableCredits;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
                child: InkWell(
                  onTap: () => context.push('/wallet'),
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.secondaryColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: AppTheme.secondaryColor.withValues(alpha: 0.5),
                        width: 1.2,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('🪙', style: TextStyle(fontSize: 13)),
                        const SizedBox(width: 4),
                        Text(
                          '$credits C',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            color: AppTheme.secondaryColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
            loading: () => IconButton(
              icon: const Icon(Icons.account_balance_wallet_outlined),
              tooltip: 'Organizer Wallet',
              onPressed: () => context.push('/wallet'),
            ),
            error: (e, st) => IconButton(
              icon: const Icon(Icons.account_balance_wallet_outlined),
              tooltip: 'Organizer Wallet',
              onPressed: () => context.push('/wallet'),
            ),
          ),
        if (extraActions != null) ...extraActions!,
        if (showAuth) ...[
          if (user != null && user.isRegistered)
            Padding(
              padding: const EdgeInsets.only(right: 8, left: 4),
              child: PopupMenuButton<String>(
                tooltip: 'Account Menu',
                offset: const Offset(0, 48),
                color: AppTheme.darkCard,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: const BorderSide(color: Color(0xFF2E334D)),
                ),
                icon: CircleAvatar(
                  radius: 16,
                  backgroundColor: AppTheme.primaryLight.withValues(alpha: 0.3),
                  backgroundImage: (user.avatarUrl != null && user.avatarUrl!.isNotEmpty)
                      ? NetworkImage(user.avatarUrl!)
                      : null,
                  child: (user.avatarUrl == null || user.avatarUrl!.isEmpty)
                      ? Text(Formatters.getAvatarEmoji(user.avatar), style: const TextStyle(fontSize: 16))
                      : null,
                ),
                itemBuilder: (ctx) => [
                  PopupMenuItem(
                    value: 'profile',
                    child: Row(
                      children: [
                        const Icon(Icons.person, size: 18, color: AppTheme.secondaryColor),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(user.displayName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                              if (user.email != null)
                                Text(user.email!, style: const TextStyle(fontSize: 10.5, color: Color(0xFFA0AEC0))),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const PopupMenuDivider(),
                  const PopupMenuItem(
                    value: 'wallet',
                    child: Row(
                      children: [
                        Icon(Icons.account_balance_wallet_outlined, size: 18),
                        SizedBox(width: 8),
                        Text('Organizer Wallet', style: TextStyle(fontSize: 13)),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'signout',
                    child: Row(
                      children: [
                        Icon(Icons.logout, size: 18, color: AppTheme.accentDanger),
                        SizedBox(width: 8),
                        Text('Sign Out', style: TextStyle(fontSize: 13, color: AppTheme.accentDanger)),
                      ],
                    ),
                  ),
                ],
                onSelected: (val) {
                  if (val == 'profile') {
                    context.go('/profile');
                  } else if (val == 'wallet') {
                    context.push('/wallet');
                  } else if (val == 'signout') {
                    _handleSignOut(context, ref);
                  }
                },
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(right: 8, left: 4),
              child: TextButton.icon(
                onPressed: () => AuthDialog.show(context),
                icon: Container(
                  width: 18,
                  height: 18,
                  decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                  child: const Center(
                    child: Text(
                      'G',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        fontFamily: 'Roboto',
                        color: Color(0xFF4285F4),
                      ),
                    ),
                  ),
                ),
                label: const Text(
                  'Sign In',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                style: TextButton.styleFrom(
                  backgroundColor: AppTheme.primaryLight.withValues(alpha: 0.25),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(color: AppTheme.primaryLight.withValues(alpha: 0.5)),
                  ),
                ),
              ),
            ),
        ],
      ],
    );
  }
}
