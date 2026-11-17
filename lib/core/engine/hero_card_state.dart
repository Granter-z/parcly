/// HeroCard 决策结果 - 纯 Dart
///
/// 只保留首页仪表盘实际消费的字段：计数、副标题、情绪状态。
library;

/// HeroCard状态
class HeroCardState {
  /// 副标题（紧急提示 / 合并取件建议）；无建议为 null
  final String? subtitle;

  /// Hero情绪状态
  final HeroEmotionState heroEmotionState;

  /// 待处理包裹数量（待发货 / 在途 / 派送 / 待取件之和）
  final int pendingCount;

  /// 已到达包裹数量
  final int arrivedCount;

  /// 派送中包裹数量
  final int deliveringCount;

  /// 运送中包裹数量
  final int transitCount;

  const HeroCardState({
    this.subtitle,
    this.heroEmotionState = HeroEmotionState.relaxed,
    this.pendingCount = 0,
    this.arrivedCount = 0,
    this.deliveringCount = 0,
    this.transitCount = 0,
  });

  /// 创建空状态
  factory HeroCardState.empty() => const HeroCardState();

  /// 是否为空状态
  bool get isEmpty => pendingCount == 0;
}

/// Hero情绪状态：直接对应用户感知
/// - relaxed: 没有待取件
/// - normal: 有 arrived 包裹
/// - urgent: urgencyScore > 80
enum HeroEmotionState { relaxed, normal, urgent }
