import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';

class OrganizerPlayerSplit extends StatelessWidget {
  const OrganizerPlayerSplit({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final isWide = constraints.maxWidth > 600;

        final card1 = _buildSplitCard(
          context: context,
          icon: Icons.dashboard_customize_rounded,
          iconColor: AppTheme.primaryLight,
          borderColor: AppTheme.primaryLight,
          title: 'Hosting a Party or Event?',
          description:
              'Create a game in 30 seconds, share one invite code or link, and let up to 250 guests join instantly. We handle capacity, waitlists, number calling, and prize verification — you just enjoy the party.',
          ctaText: 'Create Your Game →',
          onTap: () => context.push('/create-game'),
          isPrimaryCta: true,
        );

        final card2 = _buildSplitCard(
          context: context,
          icon: Icons.confirmation_number_rounded,
          iconColor: AppTheme.secondaryColor,
          borderColor: AppTheme.secondaryColor,
          title: 'Got an Invite Code?',
          description:
              'Jump straight in — no downloads, no sign-up, no email. Pick a name and avatar, get your ticket, and start dabbing the moment numbers are called.',
          ctaText: 'Join a Game →',
          onTap: () => context.push('/join'),
          isPrimaryCta: false,
        );

        if (isWide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: card1),
              const SizedBox(width: 14),
              Expanded(child: card2),
            ],
          );
        } else {
          return Column(
            children: [
              card1,
              const SizedBox(height: 14),
              card2,
            ],
          );
        }
      },
    );
  }

  Widget _buildSplitCard({
    required BuildContext context,
    required IconData icon,
    required Color iconColor,
    required Color borderColor,
    required String title,
    required String description,
    required String ctaText,
    required VoidCallback onTap,
    required bool isPrimaryCta,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor.withOpacity(0.5), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            description,
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFFCBD5E1),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: isPrimaryCta
                ? ElevatedButton(
                    onPressed: onTap,
                    child: Text(ctaText),
                  )
                : OutlinedButton(
                    onPressed: onTap,
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: borderColor, width: 1.5),
                    ),
                    child: Text(ctaText),
                  ),
          ),
        ],
      ),
    );
  }
}
