import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

class HowItWorksSection extends StatelessWidget {
  const HowItWorksSection({super.key});

  static const _steps = [
    {
      'num': '1',
      'title': 'Create your game',
      'desc': 'Name it, set capacity, pick prizes, get instant invite code.',
    },
    {
      'num': '2',
      'title': 'Guests join free',
      'desc': 'Code or link, zero app download — ticket ready in 5 seconds.',
    },
    {
      'num': '3',
      'title': 'Call numbers live',
      'desc': 'Wins verified on server instantly. Winners get QR vouchers.',
    },
  ];

  @override
  Widget build(BuildContext context) {
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
          Row(
            children: const [
              Icon(Icons.checklist_rounded, color: AppTheme.secondaryColor, size: 20),
              SizedBox(width: 8),
              Text(
                'How It Works',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (ctx, constraints) {
              final isWide = constraints.maxWidth > 580;

              if (isWide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (int i = 0; i < _steps.length; i++) ...[
                      Expanded(child: _buildStepItem(_steps[i])),
                      if (i < _steps.length - 1)
                        const Padding(
                          padding: EdgeInsets.only(top: 10),
                          child: Icon(Icons.arrow_forward_rounded, color: Color(0xFF718096), size: 16),
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
                          padding: EdgeInsets.symmetric(vertical: 4),
                          child: Icon(Icons.arrow_downward_rounded, color: Color(0xFF718096), size: 14),
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
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: AppTheme.primaryColor,
            shape: BoxShape.circle,
            border: Border.all(color: AppTheme.secondaryColor, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: AppTheme.secondaryColor.withOpacity(0.25),
                blurRadius: 4,
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Text(
            step['num']!,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: AppTheme.secondaryColor,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                step['title']!,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                step['desc']!,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: Color(0xFFCBD5E1),
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
