import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

class UspGridSection extends StatelessWidget {
  const UspGridSection({super.key});

  static const _uspItems = [
    {
      'icon': Icons.shield_outlined,
      'title': 'Fair Play, Guaranteed',
      'desc': 'Server validates every claim against called numbers automatically. Zero disputes.',
      'color': AppTheme.secondaryColor, // Yellow
    },
    {
      'icon': Icons.confirmation_number_outlined,
      'title': '100% Unique Tickets',
      'desc': 'Stress-tested across 200 tickets with zero duplicate winning combinations.',
      'color': AppTheme.accentDanger, // Red
    },
    {
      'icon': Icons.bolt_outlined,
      'title': 'Instant Guest Join',
      'desc': 'No app download or account needed. Just enter code & pick an avatar.',
      'color': AppTheme.accentSuccess, // Green
    },
    {
      'icon': Icons.qr_code_rounded,
      'title': 'QR Prize Vouchers',
      'desc': 'Winners get instant scannable claims for easy organizer prize payout.',
      'color': AppTheme.accentPartyPurple, // Purple
    },
    {
      'icon': Icons.tv_rounded,
      'title': 'Big-Screen Caller Cast',
      'desc': 'Cast live board & numbers to TV or projector for room-wide excitement.',
      'color': AppTheme.primaryLight, // Navy
    },
    {
      'icon': Icons.event_seat_rounded,
      'title': 'Smart Auto-Waitlist',
      'desc': 'Late arrivals auto-promote to active seats as soon as capacity is added.',
      'color': AppTheme.secondaryColor, // Yellow
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
            final childAspectRatio = isDesktop ? 1.85 : (isTablet ? 1.55 : 1.35);

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

                return Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.darkCard,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFF2E334D)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Accent Top Badge
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.16),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: color.withOpacity(0.35)),
                        ),
                        child: Icon(item['icon'] as IconData, color: color, size: 16),
                      ),
                      const SizedBox(height: 6),

                      // Title
                      Text(
                        item['title'] as String,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          height: 1.2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),

                      // Description
                      Expanded(
                        child: Text(
                          item['desc'] as String,
                          style: const TextStyle(
                            fontSize: 10.5,
                            color: Color(0xFFCBD5E1),
                            height: 1.25,
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
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
