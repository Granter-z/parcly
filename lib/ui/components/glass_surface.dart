/// P34 表面组件：更透 chrome + 突起折射边 / 轻玻璃 / 实心内容卡。
///
/// P34：面洗再降；外暗内亮双描边加粗；顶缘 specular 更高，读成玻璃药片突起。
///
/// - [GlassChrome]：功能层（状态条、顶栏圆钮）— 强 Frost + 厚 bevel。
/// - [LightGlassSurface]：空态 / PDD / 已完成胶囊 — 一次可读轻玻璃。
/// - [ContentSurface]：列表包裹卡 / Hero — 近实心，无 blur。
/// - [GlassSurface] / [GlassListCard]：兼容转发。
library;

import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/glass_tokens.dart';

/// 功能层 Liquid Glass（Control Center 强度 Frost）。
///
/// 叠层：ClipRRect → BackdropFilter(强 Frost) → 低面洗 → 厚 specular →
/// 双层折射边（外暗内亮）+ 冷暖色散细线。禁止在内容列表里逐行使用。
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
                // 低面洗（Opacity）— 让强 Frost 透出来，避免 P32 白膜
                Positioned.fill(
                  child: ColoredBox(color: resolvedFill),
                ),
                // Specular / Light Angle：顶缘更亮更厚（P34 突起顶面）
                if (showSpecular)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: 44,
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
                // 色散近似：左右细冷暖条（不用非均匀 Border，避免圆角断言）
                Positioned(
                  left: 0,
                  top: 8,
                  bottom: 8,
                  width: 1.5,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: GlassTokens.dispersionCool,
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 0,
                  top: 8,
                  bottom: 8,
                  width: 1.5,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: GlassTokens.dispersionWarm,
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
                ),
                // 折射边：外暗轮廓（P34 加粗 → 突起侧面）
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: borderRadius,
                        border: Border.all(
                          color: GlassTokens.borderOuter,
                          width: 1.4,
                        ),
                      ),
                    ),
                  ),
                ),
                // 折射边：内高光（P34 加亮加宽 → 顶面亮沿）
                Positioned.fill(
                  child: IgnorePointer(
                    child: Padding(
                      padding: const EdgeInsets.all(1.4),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: borderRadius,
                          border: Border.all(
                            color: GlassTokens.borderInner,
                            width: 1.15,
                          ),
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

/// 大块轻玻璃（空态 / PDD）。一次 BackdropFilter，面洗更高以保可读。
///
/// CTO P33：大块非列表块可用轻玻璃，**不是**纯实心白；列表卡仍用
/// [ContentSurface]。
class LightGlassSurface extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final BorderRadius borderRadius;
  final Color? fill;
  final Color? borderColor;
  final double? blurSigma;
  final List<BoxShadow>? boxShadow;

  const LightGlassSurface({
    super.key,
    required this.child,
    this.padding,
    this.borderRadius =
        const BorderRadius.all(Radius.circular(GlassTokens.radius)),
    this.fill,
    this.borderColor,
    this.blurSigma,
    this.boxShadow,
  });

  @override
  Widget build(BuildContext context) {
    final resolvedFill = fill ?? GlassTokens.lightGlassFill;
    final sigma = blurSigma ?? GlassTokens.lightGlassBlur;
    final shadows = boxShadow ?? GlassTokens.lightGlassShadow;

    return RepaintBoundary(
      child: Container(
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          boxShadow: shadows,
        ),
        child: ClipRRect(
          borderRadius: borderRadius,
          clipBehavior: Clip.antiAlias,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
            child: Stack(
              children: [
                Positioned.fill(
                  child: ColoredBox(color: resolvedFill),
                ),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: 24,
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
                // 外暗
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: borderRadius,
                        border: Border.all(
                          color: GlassTokens.borderOuter,
                          width: 1.2,
                        ),
                      ),
                    ),
                  ),
                ),
                // 内亮 / 自定义边
                Positioned.fill(
                  child: IgnorePointer(
                    child: Padding(
                      padding: const EdgeInsets.all(1.2),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: borderRadius,
                          border: Border.all(
                            color: borderColor ?? GlassTokens.lightGlassBorder,
                            width: 1.0,
                          ),
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

/// 兼容旧调用：默认走 chrome 真 blur。新代码请显式用分层组件。
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
