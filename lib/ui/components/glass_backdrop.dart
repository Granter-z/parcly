/// 首页环境画布：更饱和渐变 + 色斑，给功能层强 Frost 提供可磨内容（P33）。
///
/// P32 画布偏淡，磨砂后几乎看不见色差 → 更像白膜。P33 加浓色斑。
library;

import 'package:flutter/material.dart';

import '../theme/glass_tokens.dart';

class GlassBackdrop extends StatelessWidget {
  const GlassBackdrop({super.key});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(gradient: GlassTokens.canvasGradient),
          ),
          Positioned(
            top: -100,
            left: -80,
            child: _Orb(
              diameter: 320,
              color: const Color(0xFFA78BFA).withValues(alpha: 0.42),
            ),
          ),
          Positioned(
            top: 140,
            right: -100,
            child: _Orb(
              diameter: 340,
              color: const Color(0xFF60A5FA).withValues(alpha: 0.38),
            ),
          ),
          Positioned(
            bottom: 80,
            left: -40,
            child: _Orb(
              diameter: 280,
              color: const Color(0xFF34D399).withValues(alpha: 0.22),
            ),
          ),
          Positioned(
            bottom: -60,
            right: 20,
            child: _Orb(
              diameter: 260,
              color: const Color(0xFFFBBF24).withValues(alpha: 0.28),
            ),
          ),
        ],
      ),
    );
  }
}

class _Orb extends StatelessWidget {
  final double diameter;
  final Color color;

  const _Orb({required this.diameter, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color, color.withValues(alpha: 0)],
        ),
      ),
    );
  }
}
