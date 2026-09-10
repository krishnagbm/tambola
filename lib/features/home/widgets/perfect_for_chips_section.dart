import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

class PerfectForChipsSection extends StatelessWidget {
  const PerfectForChipsSection({super.key});

  static const _scenarios = [
    {'title': 'Family Get-Togethers', 'icon': '👨‍👩‍👧‍👦'},
    {'title': 'Kitty Parties', 'icon': '💃'},
    {'title': 'Diwali & Festival Nights', 'icon': '🪔'},
    {'title': 'Housing Society Events', 'icon': '🏢'},
    {'title': 'Office Team Nights', 'icon': '💼'},
    {'title': 'Wedding Sangeet Games', 'icon': '🎊'},
    {'title': 'School & College Fests', 'icon': '🎓'},
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
        const SizedBox(height: 12),
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _scenarios.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (ctx, idx) {
              final item = _scenarios[idx];
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.darkSurface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF2E334D)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(item['icon']!, style: const TextStyle(fontSize: 14)),
                    const SizedBox(width: 8),
                    Text(
                      item['title']!,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
