import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

class UspGridSection extends StatelessWidget {
  const UspGridSection({super.key});

  static const _uspItems = [
    {
      'icon': Icons.shield_outlined,
      'title': 'Fair Play, Guaranteed',
      'desc':
          'Every prize claim is checked against the official called-numbers list on our server — not the honor system. No more disputed wins.',
      'color': AppTheme.secondaryColor, // Yellow
    },
    {
      'icon': Icons.confirmation_number_outlined,
      'title': 'Every Ticket Truly Unique',
      'desc':
          'Our ticket generator was stress-tested across 200 consecutive tickets with zero duplicates — so no two players ever share a winning pattern.',
      'color': AppTheme.accentDanger, // Red
    },
    {
      'icon': Icons.bolt_outlined,
      'title': 'Join in Seconds',
      'desc':
          'Players never create an account. Pick a name and avatar, enter the invite code, and you\'re playing — on any phone, tablet, or laptop.',
      'color': AppTheme.accentSuccess, // Green
    },
    {
      'icon': Icons.qr_code_rounded,
      'title': 'QR Prize Pickup',
      'desc':
          'Winners get a scannable voucher. Organizers verify it with one tap — perfect for handing out real prizes at in-person parties.',
      'color': AppTheme.accentPartyPurple, // Purple
    },
    {
      'icon': Icons.tv_rounded,
      'title': 'Big-Screen Caller Mode',
      'desc':
          'Cast the live board and number caller to a TV or projector so the whole room follows along together.',
      'color': AppTheme.primaryLight, // Navy
    },
    {
      'icon': Icons.event_seat_rounded,
      'title': 'Never Turn Guests Away',
      'desc':
          'More people show up than planned? Waiting-list players are auto-promoted the moment you add capacity — first come, first served.',
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
            Icon(Icons.stars_rounded, color: AppTheme.secondaryColor, size: 22),
            SizedBox(width: 8),
            Text(
              'Why DebHousie?',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (ctx, constraints) {
            final isDesktop = constraints.maxWidth > 720;
            final crossAxisCount = isDesktop ? 3 : 2;
            final childAspectRatio = isDesktop ? 1.55 : 0.88;

            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _uspItems.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: childAspectRatio,
              ),
              itemBuilder: (ctx, idx) {
                final item = _uspItems[idx];
                final color = item['color'] as Color;

                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.darkCard,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF2E334D)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Accent Top Badge
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.16),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: color.withOpacity(0.35)),
                        ),
                        child: Icon(item['icon'] as IconData, color: color, size: 20),
                      ),
                      const SizedBox(height: 10),

                      // Title
                      Text(
                        item['title'] as String,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          height: 1.2,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),

                      // Description
                      Expanded(
                        child: Text(
                          item['desc'] as String,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFFCBD5E1),
                            height: 1.35,
                          ),
                          overflow: TextOverflow.fade,
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
