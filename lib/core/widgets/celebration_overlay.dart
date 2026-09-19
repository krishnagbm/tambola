import 'dart:math';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class CelebrationOverlay extends StatefulWidget {
  final Widget child;
  final bool isCelebrating;
  final String? winnerTitle;
  final String? winnerSubtitle;
  final VoidCallback? onDismiss;

  const CelebrationOverlay({
    super.key,
    required this.child,
    required this.isCelebrating,
    this.winnerTitle,
    this.winnerSubtitle,
    this.onDismiss,
  });

  @override
  State<CelebrationOverlay> createState() => _CelebrationOverlayState();
}

class _CelebrationOverlayState extends State<CelebrationOverlay> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<_Particle> _particles = [];
  final Random _rng = Random();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    );

    if (widget.isCelebrating) {
      _startCelebration();
    }
  }

  @override
  void didUpdateWidget(covariant CelebrationOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isCelebrating && !oldWidget.isCelebrating) {
      _startCelebration();
    }
  }

  void _startCelebration() {
    _particles.clear();
    for (int i = 0; i < 60; i++) {
      _particles.add(_Particle(
        x: _rng.nextDouble(),
        y: -_rng.nextDouble() * 0.5,
        speed: 0.15 + _rng.nextDouble() * 0.35,
        size: 6.0 + _rng.nextDouble() * 8.0,
        color: [
          const Color(0xFFFFD700), // Gold
          const Color(0xFF10B981), // Emerald
          const Color(0xFF6366F1), // Indigo
          const Color(0xFFF43F5E), // Rose
          const Color(0xFF38BDF8), // Sky Blue
        ][_rng.nextInt(5)],
        angle: _rng.nextDouble() * 2 * pi,
        rotationSpeed: (_rng.nextDouble() - 0.5) * 6,
      ));
    }
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (widget.isCelebrating)
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  return CustomPaint(
                    painter: _ConfettiPainter(
                      particles: _particles,
                      progress: _controller.value,
                    ),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }
}

class _Particle {
  double x;
  double y;
  double speed;
  double size;
  Color color;
  double angle;
  double rotationSpeed;

  _Particle({
    required this.x,
    required this.y,
    required this.speed,
    required this.size,
    required this.color,
    required this.angle,
    required this.rotationSpeed,
  });
}

class _ConfettiPainter extends CustomPainter {
  final List<_Particle> particles;
  final double progress;

  _ConfettiPainter({required this.particles, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;

    for (final p in particles) {
      final currentY = (p.y + p.speed * progress) * size.height;
      if (currentY > size.height) continue;

      final currentX = p.x * size.width + sin(progress * 8 + p.angle) * 20;
      final currentAngle = p.angle + p.rotationSpeed * progress;

      canvas.save();
      canvas.translate(currentX, currentY);
      canvas.rotate(currentAngle);

      paint.color = p.color.withOpacity((1.0 - (progress * 0.4)).clamp(0.0, 1.0));
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size * 0.6),
          const Radius.circular(2),
        ),
        paint,
      );

      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) => true;
}
