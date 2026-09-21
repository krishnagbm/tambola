import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

class HowItWorksSection extends StatelessWidget {
  const HowItWorksSection({super.key});

  static const _steps = [
    {
      'num': '1',
      'title': 'Create your game',
      'desc': 'Name it, set capacity & prizes.\nGet instant invite code.',
    },
    {
      'num': '2',
      'title': 'Guests join free',
      'desc': 'Join on any web browser.\nZero app download needed.',
    },
    {
      'num': '3',
      'title': 'Call numbers live',
      'desc': 'Automated live number caller.\nInstant server win checks.',
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
                          padding: EdgeInsets.only(top: 8, left: 10, right: 10),
                          child: Icon(
                            Icons.arrow_forward_rounded,
                            color: Color(0xFF94A3B8),
                            size: 22,
                          ),
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
                          child: Center(
                            child: Icon(
                              Icons.arrow_downward_rounded,
                              color: Color(0xFF94A3B8),
                              size: 18,
                            ),
                          ),
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
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: AppTheme.primaryColor,
            shape: BoxShape.circle,
            border: Border.all(color: AppTheme.secondaryColor, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: AppTheme.secondaryColor.withValues(alpha: 0.25),
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
                  fontSize: 13.5,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                step['desc']!,
                style: const TextStyle(
                  fontSize: 11.5,
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
