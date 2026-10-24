/// 带有弹簧物理触感与按压回弹的现代卡片组件
///
/// P31：`glass: true` 走半透明列表材质（**无** BackdropFilter）；
/// 真模糊请直接用 [GlassSurface]（enableBlur: true）。
library;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../constants/app_constants.dart';
import '../theme/glass_tokens.dart';
import '../theme/motion.dart';
import 'glass_surface.dart';

class SpringCard extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double pressScale;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final BorderRadius? borderRadius;
  final Border? border;
  final List<BoxShadow>? boxShadow;

  /// 半透明玻璃列表卡（无逐行 blur）。
  final bool glass;

  final Color? glassFill;
  final Color? glassBorderColor;

  const SpringCard({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.pressScale = 0.975,
    this.padding = EdgeInsets.zero,
    this.color,
    this.borderRadius,
    this.border,
    this.boxShadow,
    this.glass = false,
    this.glassFill,
    this.glassBorderColor,
  });

  @override
  State<SpringCard> createState() => _SpringCardState();
}

class _SpringCardState extends State<SpringCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late Animation<double> _scaleAnimation;

  final _springDesc = const SpringDescription(
    mass: 1.0,
    stiffness: 520.0,
    damping: 32.0,
  );

  @override
  void initState() {
    super.initState();
    _controller = AnimationController.unbounded(vsync: this);
    _scaleAnimation = _controller.drive(
      Tween<double>(begin: 1.0, end: widget.pressScale),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails details) {
    if (widget.onTap == null && widget.onLongPress == null) return;
    if (Motion.reduce(context)) {
      _controller.value = 1.0;
      return;
    }
    final simulation =
        SpringSimulation(_springDesc, _controller.value, 1.0, 0.0);
    _controller.animateWith(simulation);
  }

  void _handleTapUp(TapUpDetails details) {
    _releaseSpring();
    widget.onTap?.call();
  }

  void _handleTapCancel() => _releaseSpring();

  void _releaseSpring() {
    if (Motion.reduce(context)) {
      _controller.value = 0.0;
      return;
    }
    final simulation =
        SpringSimulation(_springDesc, _controller.value, 0.0, 0.0);
    _controller.animateWith(simulation);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cardBorderRadius = widget.borderRadius ??
        (widget.glass ? GlassTokens.radiusAll : AppRadius.mdAll);

    final Widget body;
    if (widget.glass) {
      body = GlassSurface(
        enableBlur: false, // CTO：列表卡不开逐行 blur
        padding: widget.padding,
        borderRadius: cardBorderRadius,
        fill: widget.glassFill ?? GlassTokens.fillListCard,
        borderColor: widget.border?.top.color ??
            widget.glassBorderColor ??
            GlassTokens.border,
        borderWidth: widget.border?.top.width ?? 1,
        boxShadow: widget.boxShadow ?? GlassTokens.listCardShadow,
        child: widget.child,
      );
    } else {
      body = Container(
        padding: widget.padding,
        decoration: BoxDecoration(
          color: widget.color ?? theme.colorScheme.surface,
          borderRadius: cardBorderRadius,
          border: widget.border,
          boxShadow: widget.boxShadow ??
              [
                BoxShadow(
                  color: const Color(0xFF2C2C2E).withValues(alpha: 0.05),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
        ),
        child: widget.child,
      );
    }

    return RepaintBoundary(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: _handleTapDown,
        onTapUp: _handleTapUp,
        onTapCancel: _handleTapCancel,
        onLongPress: widget.onLongPress,
        child: AnimatedBuilder(
          animation: _scaleAnimation,
          builder: (context, child) => Transform.scale(
            scale: _scaleAnimation.value,
            alignment: Alignment.center,
            child: child,
          ),
          child: body,
        ),
      ),
    );
  }
}
