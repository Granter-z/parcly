/// P34 Liquid Glass polish（在 P33 Frost 上拧透度 + 突起）。
///
/// ## P33 → P34（CEO 真机）
/// - 仍「不够透」→ chrome / 轻玻璃面洗再降一档
/// - 「玻璃突起」没体现 → 外暗内亮双描边加粗 + 外缘软辉光/抬升阴影
/// - 列表内容卡仍近实心；设置页不动
///
/// ## 分层
/// - **功能层 chrome**：更低 opacity + 强 Frost + 厚折射边（状态条、顶栏圆钮）
/// - **大块轻玻璃**：一次 BackdropFilter、可读（空态、PDD、已完成胶囊）
/// - **列表内容卡**：近实心，无逐行 blur
library;

import 'package:flutter/material.dart';

/// Apple Liquid Glass ↔ Flutter 映射的唯一真源（P34）。
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

  // ── Chrome 填充（P34：再降一档，更透出渐变）────────────────────────
  /// Regular chrome 面洗（~11% 白）。P33 的 0.18 仍偏实。
  static const fill = Color(0x1CFFFFFF); // ≈ 0.11

  /// 略实 chrome（~15%），需要稍强可读底时用。
  static const fillStrong = Color(0x26FFFFFF); // ≈ 0.15

  /// 状态条正常态（~12%）。单测 `platform_status_bar_test` 认此常量。
  static const fillSoft = Color(0x1FFFFFFF); // ≈ 0.12

  /// @Deprecated 语义：列表卡近实心。新代码用 [contentFill]。
  static const fillListCard = Color(0xF7FFFFFF);

  // ── 大块轻玻璃（空态 / PDD / 已完成胶囊；一次 blur，可读）──────────
  /// 轻玻璃面洗（~36%）：比 P33 更透，正文仍可读。
  static const lightGlassFill = Color(0x5CFFFFFF); // ≈ 0.36

  /// 轻玻璃 Frost（低于 chrome，高于「无 blur」）。
  static const lightGlassBlur = 28.0;

  /// 轻玻璃描边。
  static const lightGlassBorder = Color(0x99FFFFFF); // white @ 0.60

  // ── 内容层（标准抬升面，非 Liquid Glass）────────────────────────────
  /// 包裹卡 / Hero：近实心白，保证取件码对比度。
  static const contentFill = Color(0xF7FFFFFF); // ≈ 0.97

  /// 内容卡描边（细分割，非折射边）。
  static const contentBorder = Color(0x1A2C2C2E); // ink @ 0.10

  /// 到站卡强调描边（primary @ 0.40）。
  static const arrivedBorder = Color(0x66007AFF);

  // ── Chrome 描边 / 折射近似（P34：突起 bevel 加强）──────────────────
  /// 外轮廓（更深，模拟玻璃药片暗边 / contour）。
  static const borderOuter = Color(0x592C2C2E); // ink @ 0.35

  /// 内高光边（更亮，模拟折射亮沿 / 突起上沿）。
  static const borderInner = Color(0xE6FFFFFF); // white @ 0.90

  /// 统一描边回退。
  static const border = Color(0xA6FFFFFF); // white @ 0.65

  /// 顶缘高光色（Specular / Light Angle = 0）。
  static const specularTop = Color(0xF2FFFFFF); // white @ 0.95

  /// 底缘软边。
  static const refractionBottom = Color(0x33FFFFFF); // white @ 0.20

  /// 色散近似：左缘偏冷、右缘偏暖的细线（非真 chromatic aberration）。
  static const dispersionCool = Color(0x8099C9FF); // cool @ 0.50
  static const dispersionWarm = Color(0x80FFD4A8); // warm @ 0.50

  /// 顶部镜面高光渐变（P34：更亮更厚，读成突起玻璃顶面）。
  static const specularHighlight = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xD9FFFFFF), // white @ 0.85
      Color(0x59FFFFFF), // white @ 0.35
      Color(0x00FFFFFF),
    ],
    stops: [0.0, 0.40, 1.0],
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

  // ── 阴影（P34：抬升药片感 = 深阴影 + 顶缘软辉光）──────────────────
  /// Chrome 软阴影（Control Center tile 厚度）。
  static final softShadow = <BoxShadow>[
    BoxShadow(
      color: const Color(0xFF2C2C2E).withValues(alpha: 0.16),
      blurRadius: 28,
      offset: const Offset(0, 12),
      spreadRadius: -4,
    ),
    BoxShadow(
      color: const Color(0xFF2C2C2E).withValues(alpha: 0.07),
      blurRadius: 6,
      offset: const Offset(0, 2),
    ),
    // 顶缘软辉光：读成玻璃突起上沿
    BoxShadow(
      color: const Color(0xFFFFFFFF).withValues(alpha: 0.55),
      blurRadius: 1.5,
      offset: const Offset(0, -0.8),
      spreadRadius: 0,
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

  /// 轻玻璃阴影（介于 chrome 与 content；P34 加顶缘辉光）。
  static final lightGlassShadow = <BoxShadow>[
    BoxShadow(
      color: const Color(0xFF2C2C2E).withValues(alpha: 0.10),
      blurRadius: 20,
      offset: const Offset(0, 8),
      spreadRadius: -2,
    ),
    BoxShadow(
      color: const Color(0xFFFFFFFF).withValues(alpha: 0.40),
      blurRadius: 1.2,
      offset: const Offset(0, -0.6),
    ),
  ];

  /// @Deprecated 用 [contentShadow]。
  static final listCardShadow = contentShadow;
}
