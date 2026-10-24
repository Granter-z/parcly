/// 液态玻璃表面（P31）。
///
/// - [enableBlur] == true：ClipRRect + BackdropFilter（仅 Hero / 状态条等少量表面）。
/// - [enableBlur] == false：半透明填充 + 描边，**不开** blur（滚动列表卡必须走这条）。
library;

import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/glass_tokens.dart';

class GlassSurface extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final BorderRadius borderRadius;
  final Color? fill;
  final Color? borderColor;
  final double borderWidth;
  final double? blurSigma;
  final List<BoxShadow>? boxShadow;
  final Clip clipBehavior;

  /// 为 false 时只做半透明材质，避免列表逐行 BackdropFilter。
  final bool enableBlur;

  const GlassSurface({
    super.key,
    required this.child,
    this.padding,
    this.borderRadius =
        const BorderRadius.all(Radius.circular(GlassTokens.radius)),
    this.fill,
    this.borderColor,
    this.borderWidth = 1,
    this.blurSigma,
    this.boxShadow,
    this.clipBehavior = Clip.antiAlias,
    this.enableBlur = true,
  });

  @override
  Widget build(BuildContext context) {
    final resolvedFill = fill ?? GlassTokens.fill;
    final resolvedBorder = borderColor ?? GlassTokens.border;
    final shadows = boxShadow ?? GlassTokens.softShadow;
    final sigma = blurSigma ?? GlassTokens.blurSigma;

    final painted = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: resolvedFill,
        borderRadius: borderRadius,
        border: Border.all(color: resolvedBorder, width: borderWidth),
      ),
      child: child,
    );

    final Widget clipped;
    if (enableBlur) {
      clipped = ClipRRect(
        borderRadius: borderRadius,
        clipBehavior: clipBehavior,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
          child: painted,
        ),
      );
    } else {
      clipped = ClipRRect(
        borderRadius: borderRadius,
        clipBehavior: clipBehavior,
        child: painted,
      );
    }

    return RepaintBoundary(
      child: Container(
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          boxShadow: shadows,
        ),
        child: clipped,
      ),
    );
  }
}

/// 半透明列表卡快捷构造（强制无 blur）。
class GlassListCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final BorderRadius borderRadius;
  final Color? fill;
  final Color? borderColor;
  final double borderWidth;

  const GlassListCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.borderRadius =
        const BorderRadius.all(Radius.circular(GlassTokens.radius)),
    this.fill,
    this.borderColor,
    this.borderWidth = 1,
  });

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      enableBlur: false,
      padding: padding,
      borderRadius: borderRadius,
      fill: fill ?? GlassTokens.fillListCard,
      borderColor: borderColor ?? GlassTokens.border,
      borderWidth: borderWidth,
      boxShadow: GlassTokens.listCardShadow,
      child: child,
    );
  }
}
