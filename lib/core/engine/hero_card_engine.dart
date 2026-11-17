/// HeroCard决策引擎 - 纯Dart
///
/// 职责：
/// 1. 基于包裹状态生成 Hero 决策（计数、副标题、情绪状态）
/// 2. 纯逻辑，不依赖Flutter
library;

import '../models/package.dart';
import '../models/package_status.dart';
import 'hero_card_state.dart';
import 'logistics_status_engine.dart';
import 'station_grouping.dart';

/// HeroCard决策引擎
class HeroCardEngine {
  /// 生成HeroCard状态
  static HeroCardState decide(List<Package> allPackages) {
    final pending = allPackages.where((p) => p.status.isPending).toList();

    // 0件 → 今天暂无快递
    if (pending.isEmpty) {
      return HeroCardState.empty();
    }

    final arrived = pending.where((p) => p.status.isArrived).toList();
    final delivering = pending.where((p) => p.status == PackageStatus.delivering).toList();
    final transit = pending.where((p) => p.status == PackageStatus.transit).toList();

    final urgencyScore = _calculateUrgencyScore(pending);

    return HeroCardState(
      subtitle: _generateSubtitle(pending, urgencyScore),
      heroEmotionState: _determineHeroEmotionState(arrived, urgencyScore),
      pendingCount: pending.length,
      arrivedCount: arrived.length,
      deliveringCount: delivering.length,
      transitCount: transit.length,
    );
  }

  /// 计算紧急程度评分
  static int _calculateUrgencyScore(List<Package> pending) {
    if (pending.isEmpty) return 0;

    final statusScores = pending.map((p) => p.status.urgencyScore).toList();
    final maxStatusScore = statusScores.reduce((a, b) => a > b ? a : b);

    final urgencyScores = pending.map((p) => p.effectiveUrgency.score * 10).toList();
    final maxUrgencyScore = urgencyScores.reduce((a, b) => a > b ? a : b);

    return maxStatusScore + maxUrgencyScore;
  }

  /// 确定Hero情绪状态
  ///
  /// - relaxed: 没有 arrived 包裹
  /// - urgent: urgencyScore > 80
  /// - normal: 其余（有 arrived 但未达紧急阈值的场景在生产中会被 arrived 的紧急分覆盖）
  static HeroEmotionState _determineHeroEmotionState(
    List<Package> arrived,
    int urgencyScore,
  ) {
    if (urgencyScore > 80) return HeroEmotionState.urgent;
    if (arrived.isEmpty) return HeroEmotionState.relaxed;
    return HeroEmotionState.normal;
  }

  /// 生成副标题
  static String? _generateSubtitle(List<Package> pending, int urgencyScore) {
    if (pending.isEmpty) return null;

    if (urgencyScore > 80) return '建议立即取件';
    if (_hasPickupCluster(pending)) return '建议一起取，节省跑腿';
    return null;
  }

  /// 是否有同一取件点的多个待取件（可一起取）
  ///
  /// 只看待取件，且用 stationName，不用 location：京东/拼多多的 location
  /// 是收货地址，把同地址的在途/待发货件当成「可合并取件」是误报。
  static bool _hasPickupCluster(List<Package> packages) {
    final counts = <String, int>{};
    for (final p in packages) {
      if (!isAwaitingPickup(p)) continue;
      final label = stationLabelOf(p);
      if (isUnknownStationLabel(label)) continue;
      final key = normalizeStationName(label);
      if (key.isEmpty) continue;
      final next = (counts[key] ?? 0) + 1;
      if (next > 1) return true;
      counts[key] = next;
    }
    return false;
  }
}
