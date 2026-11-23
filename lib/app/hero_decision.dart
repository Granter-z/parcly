library;

import '../core/models/package.dart';
import '../core/engine/hero_card_engine.dart';
import '../core/engine/hero_card_state.dart';

export '../core/engine/hero_card_state.dart' show HeroEmotionState;

/// Hero 仪表盘展示数据：core 算好的计数与文案，UI 只负责摆放。
class HeroDecision {
  final String? subtitle;

  /// 结构化计数 —— 由 core 的 [HeroCardEngine] 算好。
  final int arrivedCount;
  final int deliveringCount;
  final int transitCount;
  final int pendingShipmentCount;

  /// 全部在途与待取之和。
  final int pendingCount;

  final HeroEmotionState heroEmotionState;

  const HeroDecision({
    this.subtitle,
    this.arrivedCount = 0,
    this.deliveringCount = 0,
    this.transitCount = 0,
    this.pendingShipmentCount = 0,
    this.pendingCount = 0,
    this.heroEmotionState = HeroEmotionState.relaxed,
  });

  /// 是否有需要在途 / 待取的包裹。
  bool get isEmpty => pendingCount == 0;

  /// 首页 Hero 该把哪个数字放到最大。
  ///
  /// 顺序即「用户下一步该关心什么」：先看有没有到了要取的，再看有没有正在送的，
  /// 再看路上的，最后才是还没发货的。
  ({int count, String unit}) get lead {
    if (arrivedCount > 0) return (count: arrivedCount, unit: '件待取');
    if (deliveringCount > 0) return (count: deliveringCount, unit: '件派送中');
    if (transitCount > 0) return (count: transitCount, unit: '件在途');
    return (count: pendingShipmentCount, unit: '件待发货');
  }
}

class HeroDecisionService {
  static HeroDecision decide(
    List<Package> allPackages, {
    DateTime? now,
    Map<String, String> stationAliases = const {},
  }) {
    final coreState = HeroCardEngine.decide(
      allPackages,
      now: now,
      stationAliases: stationAliases,
    );

    // core 的 pendingCount 覆盖 pendingShipment / transit / delivering / arrived，
    // 待发货数由差值还原（引擎没有单独输出这一项）。
    final pendingShipmentCount = coreState.pendingCount -
        coreState.arrivedCount -
        coreState.deliveringCount -
        coreState.transitCount;

    return HeroDecision(
      subtitle: coreState.subtitle,
      arrivedCount: coreState.arrivedCount,
      deliveringCount: coreState.deliveringCount,
      transitCount: coreState.transitCount,
      pendingShipmentCount: pendingShipmentCount < 0 ? 0 : pendingShipmentCount,
      pendingCount: coreState.pendingCount,
      heroEmotionState: coreState.heroEmotionState,
    );
  }
}
