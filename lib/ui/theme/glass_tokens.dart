/// P31 液态玻璃主题令牌 —— 填充 / 描边 / 模糊 / 阴影的唯一真源。
///
/// 页面与组件禁止内联 blur sigma 或半透明白魔法数；一律读这里。
/// 约束见 docs/pickup_app-技术方案.md §P31：
/// - 真 [BackdropFilter] 只给少量表面（Hero、状态条）；
/// - 滚动列表卡用半透明填充、不开逐行 blur。
library;

import 'package:flutter/material.dart';

/// 液态玻璃材质令牌。
class GlassTokens {
  GlassTokens._();

  // ── 画布 ──────────────────────────────────────────────────────────────
  /// 柔和多段渐变：淡紫 → 柔蓝 → 暖奶油。
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

  // ── 填充（白半透明）──────────────────────────────────────────────────
  /// 标准玻璃填充（~55%）。
  static const fill = Color(0x8CFFFFFF);

  /// 略实（Hero / 空态，~65%）。
  static const fillStrong = Color(0xA6FFFFFF);

  /// 更淡（状态条正常态 / 列表卡，~45%）。
  static const fillSoft = Color(0x73FFFFFF);

  /// 列表滚动卡专用：半透明白、**不开** BackdropFilter（~58%）。
  static const fillListCard = Color(0x94FFFFFF);

  // ── 描边 ──────────────────────────────────────────────────────────────
  static const border = Color(0x99FFFFFF);

  /// 到站卡主色玻璃描边（primary @ 0.35）。
  static const arrivedBorder = Color(0x59007AFF);

  // ── 模糊 ──────────────────────────────────────────────────────────────
  /// Hero / 大面板。
  static const blurSigma = 22.0;

  /// 状态条等较小表面。
  static const blurSigmaSoft = 18.0;

  // ── 圆角（玻璃表面）──────────────────────────────────────────────────
  static const radius = 24.0;
  static BorderRadius get radiusAll => BorderRadius.circular(radius);

  // ── 阴影 ──────────────────────────────────────────────────────────────
  static final softShadow = <BoxShadow>[
    BoxShadow(
      color: const Color(0xFF2C2C2E).withValues(alpha: 0.06),
      blurRadius: 20,
      offset: const Offset(0, 8),
    ),
  ];

  static final listCardShadow = <BoxShadow>[
    BoxShadow(
      color: const Color(0xFF2C2C2E).withValues(alpha: 0.05),
      blurRadius: 14,
      offset: const Offset(0, 4),
    ),
  ];
}
