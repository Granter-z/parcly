/// 带有弹簧物理触感与按压回弹的现代卡片组件
///
/// P33：`glass: true` → **内容抬升面**（无 BackdropFilter）。
/// 功能层用 [GlassChrome]；空态/PDD 用 [LightGlassSurface]。
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

  /// 历史名：现为内容抬升面（近实心），**不是** Liquid Glass。
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

  bool _reduced = false;
  int _generation = 0;

  bool get _enabled => widget.onTap != null || widget.onLongPress != null;

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
    _generation++;
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = Motion.reduce(context);
    if (reduced != _reduced) {
      _reduced = reduced;
      _settle();
    }
  }

  @override
  void didUpdateWidget(covariant SpringCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pressScale != widget.pressScale) {
      _scaleAnimation = _controller.drive(
        Tween<double>(begin: 1.0, end: widget.pressScale),
      );
    }
    if (!_enabled) _settle();
  }

  void _settle() {
    _generation++;
    _controller.value = 0;
  }

  void _retarget(double target) {
    if (_reduced || !_enabled) {
      _settle();
      return;
    }
    // q 无量纲，v 为有符号 q/秒；stop 后 velocity 会归零，必须先采样。
    final q = _controller.value;
    final v = _controller.velocity;
    final generation = ++_generation;
    _controller.stop();
    _controller
        .animateWith(SpringSimulation(
      _springDesc,
      q,
      target,
      v,
      tolerance: const Tolerance(distance: 1e-3, velocity: 1e-3),
    ))
        .whenCompleteOrCancel(() {
      if (mounted && generation == _generation) _controller.value = target;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cardBorderRadius = widget.borderRadius ??
        (widget.glass ? GlassTokens.radiusContentAll : AppRadius.mdAll);

    final Widget body;
    if (widget.glass) {
      // P32：内容抬升面，禁止逐行 BackdropFilter
      body = ContentSurface(
        padding: widget.padding,
        borderRadius: cardBorderRadius,
        fill: widget.glassFill ?? GlassTokens.contentFill,
        borderColor: widget.border?.top.color ??
            widget.glassBorderColor ??
            GlassTokens.contentBorder,
        borderWidth: widget.border?.top.width ?? 1,
        boxShadow: widget.boxShadow ?? GlassTokens.contentShadow,
        child: widget.child,
      );
    } else {
      body = Container(
        padding: widget.padding,
        decoration: BoxDecoration(
          color: widget.color ?? theme.colorScheme.surface,
          borderRadius: cardBorderRadius,
          border: widget.border,
          boxShadow: widget.boxShadow ?? GlassTokens.contentShadow,
        ),
        child: widget.child,
      );
    }

    return RepaintBoundary(
      child: Semantics(
        onLongPress: widget.onTap == null ? widget.onLongPress : null,
        child: GestureDetector(
          excludeFromSemantics: widget.onTap == null,
          behavior: HitTestBehavior.opaque,
          onTapDown: _enabled ? (_) => _retarget(1) : null,
          onTapUp: _enabled ? (_) => _retarget(0) : null,
          onTapCancel: _enabled ? () => _retarget(0) : null,
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          onLongPressStart:
              widget.onLongPress != null ? (_) => _retarget(0) : null,
          onLongPressEnd:
              widget.onLongPress != null ? (_) => _retarget(0) : null,
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
      ),
    );
  }
}
