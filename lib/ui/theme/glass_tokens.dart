/// P33 Control-Center-strength Liquid Glass 令牌。
///
/// ## P32 失败原因（CEO 真机拒收）
/// P32 `GlassChrome` = 弱 Frost（sigma 20–24）+ 偏高白填充（28–35%）+ 平描边，
/// 真机读成「半透明白膜 / 磨砂塑料」，**不是** iOS Control Center 那种厚磨砂。
/// Flutter 做不到系统级实时透镜/色散；P33 用更强 BackdropFilter + 低面洗 +
/// specular / 双层折射边近似。未引入 `liquid_glass_renderer`（需 Flutter GPU /
/// Impeller 开关，Android 风险高；CTO：优先稳妥 Frost）。
///
/// ## Figma iOS/iPadOS 27 UI Kit（CEO 粘贴）
/// - Frost Regular = 6 → Flutter sigma 映射见 [blurSigma]（明显可见磨砂）
/// - Refraction = 70 → 边沿双描边 + 顶缘 specular 近似
/// - Splay Regular = 20 → [radius] / [radiusContent]
/// - Depth Regular = 30 → [softShadow]
/// - Dispersion = 20 → 边沿冷暖双色近似（非真色散）
/// - Light Angle = 0 → 顶缘高光
/// - Opacity → chrome 面洗压到 ~18–22%，避免乳白板
///
/// ## 分层（CTO P33）
/// - **功能层 chrome**：强 Frost + 低 opacity + specular（状态条、顶栏圆钮）
/// - **大块轻玻璃**：一次 BackdropFilter、可读（空态、PDD 横幅）
/// - **列表内容卡**：近实心，无逐行 blur（取件码对比度）
library;

import 'package:flutter/material.dart';

/// Apple Liquid Glass ↔ Flutter 映射的唯一真源（P33）。
class GlassTokens {
  GlassTokens._();

  // ── 画布（内容滚动其下；非玻璃；P33 加浓色斑供磨砂折射）──────────────
  /// 更饱和的多段渐变：紫 → 蓝 → 青 → 暖奶油，让 Frost 有东西可磨。
  static const canvasGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFFD9C8F5),
      Color(0xFFB8D4F8),
      Color(0xFFC5E8F0),
      Color(0xFFF5E6D4),
    ],
    stops: [0.0, 0.35, 0.65, 1.0],
  );

  // ── Chrome 填充（≈ Kit Opacity · Regular；P33 低于 P32 的乳白）────────
  /// Regular chrome 面洗（~18% 白）。P32 的 0.28 过厚 → 白膜。
  static const fill = Color(0x2EFFFFFF); // ≈ 0.18

  /// 略实 chrome（~22%），需要稍强可读底时用。
  static const fillStrong = Color(0x38FFFFFF); // ≈ 0.22

  /// 状态条正常态（~20%）。单测 `platform_status_bar_test` 认此常量。
  static const fillSoft = Color(0x33FFFFFF); // ≈ 0.20

  /// @Deprecated 语义：列表卡近实心。新代码用 [contentFill]。
  static const fillListCard = Color(0xF7FFFFFF);

  // ── 大块轻玻璃（空态 / PDD；一次 blur，可读）────────────────────────
  /// 轻玻璃面洗（~52%）：透出渐变但仍压得住正文。
  static const lightGlassFill = Color(0x85FFFFFF); // ≈ 0.52

  /// 轻玻璃 Frost（低于 chrome，高于「无 blur」）。
  static const lightGlassBlur = 28.0;

  /// 轻玻璃描边。
  static const lightGlassBorder = Color(0x73FFFFFF); // white @ 0.45

  // ── 内容层（标准抬升面，非 Liquid Glass）────────────────────────────
  /// 包裹卡 / Hero：近实心白，保证取件码对比度。
  static const contentFill = Color(0xF7FFFFFF); // ≈ 0.97

  /// 内容卡描边（细分割，非折射边）。
  static const contentBorder = Color(0x1A2C2C2E); // ink @ 0.10

  /// 到站卡强调描边（primary @ 0.40）。
  static const arrivedBorder = Color(0x66007AFF);

  // ── Chrome 描边 / 折射近似（≈ Kit Refraction=70 + Dispersion=20）────
  /// 外轮廓（略深，模拟暗边 / contour）。
  static const borderOuter = Color(0x332C2C2E); // ink @ 0.20

  /// 内高光边（亮，模拟折射亮沿）。
  static const borderInner = Color(0xB3FFFFFF); // white @ 0.70

  /// 统一描边回退。
  static const border = Color(0x88FFFFFF); // white @ 0.53

  /// 顶缘高光色（Specular / Light Angle = 0）。
  static const specularTop = Color(0xE6FFFFFF); // white @ 0.90

  /// 底缘软边。
  static const refractionBottom = Color(0x26FFFFFF); // white @ 0.15

  /// 色散近似：左缘偏冷、右缘偏暖的细线（非真 chromatic aberration）。
  static const dispersionCool = Color(0x6699C9FF); // cool @ 0.40
  static const dispersionWarm = Color(0x66FFD4A8); // warm @ 0.40

  /// 顶部镜面高光渐变（叠在 chrome 上沿；P33 比 P32 更亮更厚）。
  static const specularHighlight = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xB3FFFFFF), // white @ 0.70
      Color(0x40FFFFFF), // white @ 0.25
      Color(0x00FFFFFF),
    ],
    stops: [0.0, 0.45, 1.0],
  );

  // ── Frost（≈ Kit Frost Regular = 6 → 真机必须一眼看出磨砂）──────────
  /// Chrome 面板（状态条）。P32 的 24 太弱 → 白膜；P33 ≥ 40。
  static const blurSigma = 42.0;

  /// 顶栏圆形按钮。
  static const blurSigmaSoft = 34.0;

  // ── 圆角（≈ Kit Splay Regular = 20）────────────────────────────────
  /// Chrome / 大块面板。
  static const radius = 28.0;
  static BorderRadius get radiusAll => BorderRadius.circular(radius);

  /// 内容卡。
  static const radiusContent = 22.0;
  static BorderRadius get radiusContentAll =>
      BorderRadius.circular(radiusContent);

  /// 胶囊（平台状态条外形）。
  static const radiusCapsule = 999.0;
  static BorderRadius get radiusCapsuleAll =>
      BorderRadius.circular(radiusCapsule);

  // ── 阴影（≈ Kit Depth Regular = 30）────────────────────────────────
  /// Chrome 软阴影。
  static final softShadow = <BoxShadow>[
    BoxShadow(
      color: const Color(0xFF2C2C2E).withValues(alpha: 0.10),
      blurRadius: 28,
      offset: const Offset(0, 12),
      spreadRadius: -2,
    ),
    BoxShadow(
      color: const Color(0xFF2C2C2E).withValues(alpha: 0.04),
      blurRadius: 6,
      offset: const Offset(0, 2),
    ),
  ];

  /// 内容抬升卡阴影。
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

  /// 轻玻璃阴影（介于 chrome 与 content）。
  static final lightGlassShadow = <BoxShadow>[
    BoxShadow(
      color: const Color(0xFF2C2C2E).withValues(alpha: 0.08),
      blurRadius: 20,
      offset: const Offset(0, 8),
      spreadRadius: -1,
    ),
  ];

  /// @Deprecated 用 [contentShadow]。
  static final listCardShadow = contentShadow;
}
