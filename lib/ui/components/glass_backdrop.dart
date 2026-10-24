/// 首页液态玻璃画布：柔和多段渐变 + 低透明度光斑（P31）。
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
            top: -80,
            left: -60,
            child: _Orb(
              diameter: 260,
              color: const Color(0xFFB8A6F0).withValues(alpha: 0.28),
            ),
          ),
          Positioned(
            top: 180,
            right: -90,
            child: _Orb(
              diameter: 300,
              color: const Color(0xFF8EC5F8).withValues(alpha: 0.22),
            ),
          ),
          Positioned(
            bottom: -40,
            left: 40,
            child: _Orb(
              diameter: 240,
              color: const Color(0xFFF5D9B8).withValues(alpha: 0.20),
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
