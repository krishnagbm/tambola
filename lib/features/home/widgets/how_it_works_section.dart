import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

class HowItWorksSection extends StatelessWidget {
  const HowItWorksSection({super.key});

  static const _steps = [
    {
      'num': '1',
      'title': 'Create your game',
      'desc': 'Name it, set capacity, pick your prizes, get an invite code.',
    },
    {
      'num': '2',
      'title': 'Guests join free',
      'desc': 'Code or link, no app, no account — ticket in hand instantly.',
    },
    {
      'num': '3',
      'title': 'Call numbers live',
      'desc': 'Claims are verified automatically. Winners get their voucher on the spot.',
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF2E334D)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.checklist_rounded, color: AppTheme.secondaryColor, size: 22),
              SizedBox(width: 8),
              Text(
                'How It Works',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (ctx, constraints) {
              final isWide = constraints.maxWidth > 600;

              if (isWide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (int i = 0; i < _steps.length; i++) ...[
                      Expanded(child: _buildStepItem(_steps[i])),
                      if (i < _steps.length - 1)
                        const Padding(
                          padding: EdgeInsets.only(top: 14),
                          child: Icon(Icons.arrow_forward_rounded, color: Color(0xFF718096), size: 18),
                        ),
                    ],
                  ],
                );
              } else {
                return Column(
                  children: [
                    for (int i = 0; i < _steps.length; i++) ...[
                      _buildStepItem(_steps[i]),
                      if (i < _steps.length - 1)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Icon(Icons.arrow_downward_rounded, color: Color(0xFF718096), size: 16),
                        ),
                    ],
                  ],
                );
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildStepItem(Map<String, String> step) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: AppTheme.primaryColor,
            shape: BoxShape.circle,
            border: Border.all(color: AppTheme.secondaryColor, width: 2),
            boxShadow: [
              BoxShadow(
                color: AppTheme.secondaryColor.withOpacity(0.3),
                blurRadius: 6,
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Text(
            step['num']!,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              color: AppTheme.secondaryColor,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                step['title']!,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                step['desc']!,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFFCBD5E1),
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
