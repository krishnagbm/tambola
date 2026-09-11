import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

import 'corporate_inquiry_dialog.dart';

class UspGridSection extends StatelessWidget {
  const UspGridSection({super.key});

  static const _uspItems = [
    {
      'icon': Icons.shield_outlined,
      'title': 'Fair Play, Guaranteed',
      'desc': 'Server validates every claim against called numbers automatically. Zero disputes.',
      'color': AppTheme.secondaryColor, // Yellow
      'actionTopic': null,
    },
    {
      'icon': Icons.confirmation_number_outlined,
      'title': '100K+ Unique Tickets',
      'desc': 'Stress-tested across 100,000+ tickets with zero duplicates from an 8.1 Trillion space.',
      'color': AppTheme.accentDanger, // Red
      'actionTopic': null,
    },
    {
      'icon': Icons.corporate_fare_rounded,
      'title': 'Mega-X Enterprise Scale',
      'desc': 'Host up to 250 players standard, or scale to 100,000+ players for enterprise townhalls.',
      'color': AppTheme.accentSuccess, // Green
      'actionTopic': 'Mega-X Event (250+ Players)',
    },
    {
      'icon': Icons.auto_awesome_rounded,
      'title': 'Custom Winning Patterns',
      'desc': 'Standard Jaldi 5, Lines, Full House, or bespoke corporate patterns on demand.',
      'color': AppTheme.accentPartyPurple, // Purple
      'actionTopic': 'Custom Winning Patterns',
    },
    {
      'icon': Icons.tv_rounded,
      'title': 'Big-Screen Caller Cast',
      'desc': 'Cast live board & numbers to TV or projector for room-wide excitement.',
      'color': AppTheme.primaryLight, // Navy
      'actionTopic': null,
    },
    {
      'icon': Icons.bolt_outlined,
      'title': 'Instant Guest Join',
      'desc': 'No app download or account needed. Just enter code & pick an avatar.',
      'color': AppTheme.secondaryColor, // Yellow
      'actionTopic': null,
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: const [
            Icon(Icons.stars_rounded, color: AppTheme.secondaryColor, size: 20),
            SizedBox(width: 8),
            Text(
              'Why DebHousie?',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (ctx, constraints) {
            final isDesktop = constraints.maxWidth > 840;
            final isTablet = constraints.maxWidth > 580;
            final crossAxisCount = isDesktop ? 3 : (isTablet ? 3 : 2);
            final childAspectRatio = isDesktop ? 2.55 : (isTablet ? 2.15 : 1.45);

            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _uspItems.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: childAspectRatio,
              ),
              itemBuilder: (ctx, idx) {
                final item = _uspItems[idx];
                final color = item['color'] as Color;
                final actionTopic = item['actionTopic'] as String?;

                return InkWell(
                  onTap: actionTopic != null
                      ? () => CorporateInquiryDialog.show(context, initialTopic: actionTopic)
                      : null,
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppTheme.darkCard,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: actionTopic != null
                            ? color.withValues(alpha: 0.4)
                            : const Color(0xFF2E334D),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Accent Top Badge
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(5),
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.16),
                                borderRadius: BorderRadius.circular(7),
                                border: Border.all(color: color.withValues(alpha: 0.35)),
                              ),
                              child: Icon(item['icon'] as IconData, color: color, size: 15),
                            ),
                            if (actionTopic != null)
                              const Icon(Icons.arrow_forward_rounded, color: Color(0xFFA0AEC0), size: 13),
                          ],
                        ),
                        const SizedBox(height: 5),

                        // Title
                        Text(
                          item['title'] as String,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            height: 1.15,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),

                        // Description
                        Expanded(
                          child: Text(
                            item['desc'] as String,
                            style: const TextStyle(
                              fontSize: 10.5,
                              color: Color(0xFFCBD5E1),
                              height: 1.2,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ],
    );
  }
}
