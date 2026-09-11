import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

class PerfectForChipsSection extends StatelessWidget {
  const PerfectForChipsSection({super.key});

  static const _scenarios = [
    {'title': 'Family Get-Togethers', 'icon': '👨‍👩‍👧‍👦'},
    {'title': 'Kitty Parties', 'icon': '💃'},
    {'title': 'Diwali & Festivals', 'icon': '🪔'},
    {'title': 'Housing Societies', 'icon': '🏢'},
    {'title': 'Office Team Nights', 'icon': '💼'},
    {'title': 'Weddings & Sangeet', 'icon': '🎊'},
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: const [
            Icon(Icons.celebration_rounded, color: AppTheme.secondaryColor, size: 20),
            SizedBox(width: 8),
            Text(
              'Perfect For Every Celebration',
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
            final isDesktop = constraints.maxWidth > 600;
            final crossAxisCount = isDesktop ? 3 : 2;
            final childAspectRatio = isDesktop ? 3.8 : 2.8;

            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _scenarios.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: childAspectRatio,
              ),
              itemBuilder: (ctx, idx) {
                final item = _scenarios[idx];
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.darkSurface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF2E334D)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(item['icon']!, style: const TextStyle(fontSize: 15)),
                      const SizedBox(width: 7),
                      Flexible(
                        child: Text(
                          item['title']!,
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
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
