import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../game/race.dart';

class VictoryCelebration extends StatelessWidget {
  const VictoryCelebration({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => SizedBox.expand(
    child: TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 1800),
      child: child,
      builder: (context, progress, panel) => Stack(
        fit: StackFit.expand,
        children: [
          IgnorePointer(child: CustomPaint(painter: _Confetti(progress))),
          Center(
            child: Opacity(
              opacity: (progress * 5).clamp(0, 1),
              child: Transform.scale(
                scale: .9 + .1 * Curves.easeOutBack.transform(progress),
                child: panel,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _Confetti extends CustomPainter {
  _Confetti(this.progress);
  final double progress;
  @override
  void paint(Canvas canvas, Size size) {
    if (progress >= 1) return;
    for (var i = 0; i < 48; i++) {
      final x =
          ((i * .6180339) % 1) * size.width + math.sin(i + progress * 5) * 45;
      final y = -40 + progress * (size.height + 100) - (i % 7) * 28;
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(i + progress * 8);
      canvas.drawRect(
        const Rect.fromLTWH(-4, -7, 8, 14),
        Paint()
          ..color = Color(playerColors[i % playerColors.length])
              .withValues(alpha: 1 - progress),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_Confetti oldDelegate) => oldDelegate.progress != progress;
}
