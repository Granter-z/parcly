/// P32 表面组件：功能层 Liquid Glass vs 内容层标准抬升面。
///
/// - [GlassChrome]：真 BackdropFilter + 镜面高光 + 折射双描边（仅 chrome）。
/// - [ContentSurface]：近实心抬升面（包裹卡 / Hero / 空态 / PDD），**无** blur。
/// - [GlassSurface]：保留兼容；新代码 chrome 用 [GlassChrome]，内容用 [ContentSurface]。
/// - [GlassListCard]：已改为 [ContentSurface] 语义（无 blur、近实心）。
library;

import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/glass_tokens.dart';

/// 功能层 Liquid Glass（Regular Medium）。
///
/// 叠层：ClipRRect → BackdropFilter(Frost) → 半透填充 → 顶缘 specular →
/// 折射双描边（顶亮底软）。禁止在内容列表里逐行使用。
class GlassChrome extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final BorderRadius borderRadius;
  final Color? fill;
  final double? blurSigma;
  final List<BoxShadow>? boxShadow;
  final bool showSpecular;
  final Clip clipBehavior;

  const GlassChrome({
    super.key,
    required this.child,
    this.padding,
    this.borderRadius =
        const BorderRadius.all(Radius.circular(GlassTokens.radius)),
    this.fill,
    this.blurSigma,
    this.boxShadow,
    this.showSpecular = true,
    this.clipBehavior = Clip.antiAlias,
  });

  @override
  Widget build(BuildContext context) {
    final resolvedFill = fill ?? GlassTokens.fill;
    final sigma = blurSigma ?? GlassTokens.blurSigma;
    final shadows = boxShadow ?? GlassTokens.softShadow;

    return RepaintBoundary(
      child: Container(
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          boxShadow: shadows,
        ),
        child: ClipRRect(
          borderRadius: borderRadius,
          clipBehavior: clipBehavior,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
            child: Stack(
              children: [
                // 半透填充（Opacity）
                Positioned.fill(
                  child: ColoredBox(color: resolvedFill),
                ),
                // Specular / Light Angle：顶缘白→透明
                if (showSpecular)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: 28,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.only(
                            topLeft: borderRadius.topLeft,
                            topRight: borderRadius.topRight,
                          ),
                          gradient: GlassTokens.specularHighlight,
                        ),
                      ),
                    ),
                  ),
                // 折射边：均匀描边（Flutter 圆角不支持非均匀 Border）+ 顶缘 specular 已近似 Light Angle
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: borderRadius,
                        border: Border.all(
                          color: GlassTokens.border,
                          width: 1,
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: padding ?? EdgeInsets.zero,
                  child: child,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 内容层标准抬升面（**不是** Liquid Glass）。
class ContentSurface extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final BorderRadius borderRadius;
  final Color? fill;
  final Color? borderColor;
  final double borderWidth;
  final List<BoxShadow>? boxShadow;

  const ContentSurface({
    super.key,
    required this.child,
    this.padding,
    this.borderRadius =
        const BorderRadius.all(Radius.circular(GlassTokens.radiusContent)),
    this.fill,
    this.borderColor,
    this.borderWidth = 1,
    this.boxShadow,
  });

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          color: fill ?? GlassTokens.contentFill,
          borderRadius: borderRadius,
          border: Border.all(
            color: borderColor ?? GlassTokens.contentBorder,
            width: borderWidth,
          ),
          boxShadow: boxShadow ?? GlassTokens.contentShadow,
        ),
        child: child,
      ),
    );
  }
}

/// 兼容旧调用：默认走 chrome 真 blur。新代码请显式用 [GlassChrome] / [ContentSurface]。
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

  /// false → 内容抬升面（无 blur）；true → [GlassChrome]。
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
    if (enableBlur) {
      return GlassChrome(
        padding: padding,
        borderRadius: borderRadius,
        fill: fill,
        blurSigma: blurSigma,
        boxShadow: boxShadow,
        clipBehavior: clipBehavior,
        child: child,
      );
    }
    return ContentSurface(
      padding: padding,
      borderRadius: borderRadius,
      fill: fill ?? GlassTokens.contentFill,
      borderColor: borderColor ?? GlassTokens.contentBorder,
      borderWidth: borderWidth,
      boxShadow: boxShadow ?? GlassTokens.contentShadow,
      child: child,
    );
  }
}

/// 列表卡快捷构造 → 内容抬升面（强制无 blur）。
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
        const BorderRadius.all(Radius.circular(GlassTokens.radiusContent)),
    this.fill,
    this.borderColor,
    this.borderWidth = 1,
  });

  @override
  Widget build(BuildContext context) {
    return ContentSurface(
      padding: padding,
      borderRadius: borderRadius,
      fill: fill ?? GlassTokens.contentFill,
      borderColor: borderColor ?? GlassTokens.contentBorder,
      borderWidth: borderWidth,
      child: child,
    );
  }
}
