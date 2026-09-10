import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';

class OrganizerPlayerSplit extends StatelessWidget {
  const OrganizerPlayerSplit({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final isWide = constraints.maxWidth > 580;

        final card1 = _buildSplitCard(
          context: context,
          icon: Icons.dashboard_customize_rounded,
          iconColor: AppTheme.primaryLight,
          borderColor: AppTheme.primaryLight,
          title: 'Hosting a Party or Event?',
          description: 'Host up to 250 guests in 30 seconds. We manage capacity, number calling & automated prize validation.',
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
          description: 'Instant guest access — zero app download or sign-up. Grab a ticket and dab numbers live.',
          ctaText: 'Join a Game →',
          onTap: () => context.push('/join'),
          isPrimaryCta: false,
        );

        if (isWide) {
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: card1),
                const SizedBox(width: 12),
                Expanded(child: card2),
              ],
            ),
          );
        } else {
          return Column(
            children: [
              card1,
              const SizedBox(height: 10),
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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor.withValues(alpha: 0.5), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFFCBD5E1),
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: isPrimaryCta
                ? ElevatedButton(
                    onPressed: onTap,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                    ),
                    child: Text(ctaText),
                  )
                : OutlinedButton(
                    onPressed: onTap,
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: borderColor, width: 1.5),
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                    ),
                    child: Text(ctaText),
                  ),
          ),
        ],
      ),
    );
  }
}
