/// P32 Apple-aligned Liquid Glass 令牌。
///
/// 对齐 Apple HIG Materials + iOS/iPadOS 27 UI Kit（Figma）变量：
/// - Liquid Glass/Opacity、Frost - Regular/Medium/Large
/// - Liquid Glass/Light Angle、Refraction、Depth、Splay、Dispersion
///
/// 原则（HIG）：
/// - Liquid Glass **只用于功能层**（顶栏按钮、平台状态条等 chrome）。
/// - 内容层（包裹卡、Hero 数字块、空态、PDD 入口）用 [contentFill] 实心抬升面，
///   **禁止** 把列表卡做成磨砂玻璃板。
/// - 变体：首页 chrome 用 **Regular**（有字可读）；**Clear** 仅适合富媒体底，Parcly 不用。
/// - 真 [BackdropFilter] 只给少量 chrome；列表卡绝不逐行 blur。
library;

import 'package:flutter/material.dart';

/// Apple Liquid Glass ↔ Flutter 映射的唯一真源。
class GlassTokens {
  GlassTokens._();

  // ── 画布（内容滚动其下；非玻璃）──────────────────────────────────────
  /// 柔和多段渐变：淡紫 → 柔蓝 → 暖奶油（环境光，不是 Frost）。
  static const canvasGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFFE8E0F5),
      Color(0xFFD6E8F8),
      Color(0xFFF7EFE4),
    ],
    stops: [0.0, 0.48, 1.0],
  );

  // ── Chrome 填充（≈ Kit: Liquid Glass/Opacity · Regular）──────────────
  /// Regular Medium chrome 填充（~28% 白）。P31 的 55% 乳白过厚，已下调。
  static const fill = Color(0x47FFFFFF); // ≈ 0.28

  /// 略实 chrome（~35%），用于需要稍强可读底的功能条。
  static const fillStrong = Color(0x59FFFFFF); // ≈ 0.35

  /// 状态条正常态（~32%）。单测 `platform_status_bar_test` 认此常量。
  static const fillSoft = Color(0x52FFFFFF); // ≈ 0.32

  /// @Deprecated 语义：P32 列表卡不再用半透玻璃。保留别名避免旧引用崩；
  /// 新代码请用 [contentFill]。
  static const fillListCard = Color(0xF7FFFFFF); // ≈ content，近实心

  // ── 内容层（标准抬升面，非 Liquid Glass）────────────────────────────
  /// 包裹卡 / Hero / 空态 / PDD：近实心白，保证取件码对比度。
  static const contentFill = Color(0xF7FFFFFF); // ≈ 0.97

  /// 内容卡描边（细分割，非折射边）。
  static const contentBorder = Color(0x1A2C2C2E); // ink @ 0.10

  /// 到站卡强调描边（primary @ 0.40）。
  static const arrivedBorder = Color(0x66007AFF);

  // ── Chrome 描边 / 折射（≈ Kit: Refraction + Light Angle）────────────
  /// 统一描边回退（单色）。真 chrome 优先用 [refractionBorder]。
  static const border = Color(0x66FFFFFF); // white @ 0.40

  /// 顶缘高光色（Specular / Light Angle）。
  static const specularTop = Color(0xB3FFFFFF); // white @ 0.70

  /// 底缘软边（折射下沿）。
  static const refractionBottom = Color(0x1AFFFFFF); // white @ 0.10

  /// 顶部镜面高光渐变（叠在 chrome 上沿，高度约 40%）。
  static const specularHighlight = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0x73FFFFFF), // white @ 0.45
      Color(0x00FFFFFF),
    ],
    stops: [0.0, 1.0],
  );

  // ── Frost（≈ Kit: Frost - Regular / Medium）─────────────────────────
  /// Regular Medium 面板（状态条、Hero 若误用 chrome）。
  static const blurSigma = 24.0;

  /// Regular Small / 顶栏圆形按钮。
  static const blurSigmaSoft = 20.0;

  // ── 圆角（≈ Kit: Splay - Medium and Large → 更大同心圆角）──────────
  /// Chrome / 内容面板（P32：28，原 P31 24）。
  static const radius = 28.0;
  static BorderRadius get radiusAll => BorderRadius.circular(radius);

  /// 内容卡（略小于面板，仍大于旧 md=16）。
  static const radiusContent = 22.0;
  static BorderRadius get radiusContentAll =>
      BorderRadius.circular(radiusContent);

  /// 胶囊（平台条外形可用；芯片本身 P32 倾向实心字，不嵌套玻璃）。
  static const radiusCapsule = 999.0;
  static BorderRadius get radiusCapsuleAll =>
      BorderRadius.circular(radiusCapsule);

  // ── 阴影（≈ Kit: Depth - Regular / Medium）──────────────────────────
  /// Chrome 软阴影（内容感知、浅）。
  static final softShadow = <BoxShadow>[
    BoxShadow(
      color: const Color(0xFF2C2C2E).withValues(alpha: 0.08),
      blurRadius: 24,
      offset: const Offset(0, 10),
      spreadRadius: -2,
    ),
  ];

  /// 内容抬升卡阴影（标准 elevated，非玻璃）。
  static final contentShadow = <BoxShadow>[
    BoxShadow(
      color: const Color(0xFF2C2C2E).withValues(alpha: 0.07),
      blurRadius: 16,
      offset: const Offset(0, 6),
    ),
    BoxShadow(
      color: const Color(0xFF2C2C2E).withValues(alpha: 0.03),
      blurRadius: 4,
      offset: const Offset(0, 1),
    ),
  ];

  /// @Deprecated 用 [contentShadow]。
  static final listCardShadow = contentShadow;
}
