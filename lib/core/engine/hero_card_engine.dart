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
  static HeroCardState decide(
    List<Package> allPackages, {
    DateTime? now,
    Map<String, String> stationAliases = const {},
  }) {
    final pending = allPackages.where((p) => p.status.isPending).toList();

    // 0件 → 今天暂无快递
    if (pending.isEmpty) {
      return HeroCardState.empty();
    }

    final arrived = pending.where(isAwaitingPickup).toList();
    final delivering = pending
        .where((p) => !isAwaitingPickup(p) && p.status == PackageStatus.delivering)
        .toList();
    final transit = pending
        .where((p) => !isAwaitingPickup(p) && p.status == PackageStatus.transit)
        .toList();

    final clock = now ?? DateTime.now();
    final hasOverdue = arrived.any((p) => isNearlyOverdue(p, clock));
    final urgencyScore = _calculateUrgencyScore(pending, hasOverdue: hasOverdue);

    return HeroCardState(
      subtitle: _generateSubtitle(
        arrived,
        urgencyScore,
        hasOverdue: hasOverdue,
        stationAliases: stationAliases,
      ),
      heroEmotionState: _determineHeroEmotionState(
        arrived,
        urgencyScore,
        hasOverdue: hasOverdue,
      ),
      pendingCount: pending.length,
      arrivedCount: arrived.length,
      deliveringCount: delivering.length,
      transitCount: transit.length,
    );
  }

  /// 计算紧急程度评分
  ///
  /// 基础分取各待处理包裹 `status.urgencyScore`（arrived=85、delivering=50、
  /// transit=20、pendingShipment=15）；非 arrived 包裹叠加自身 `effectiveUrgency`
  /// 附加分（最高 50+30=80 <= 100），arrived 包裹普通刚到站不叠加额外分
  /// （保持 85 <= 100），存在快超期件（到站超 3 天）时统一叠加 +30（达到 115 > 100）。
  static int _calculateUrgencyScore(
    List<Package> pending, {
    required bool hasOverdue,
  }) {
    if (pending.isEmpty) return 0;

    var maxScore = 0;
    for (final p in pending) {
      final score = p.status.isArrived
          ? p.status.urgencyScore
          : p.status.urgencyScore + p.effectiveUrgency.score * 10;
      if (score > maxScore) {
        maxScore = score;
      }
    }

    if (hasOverdue) {
      maxScore += 30;
    }
    return maxScore;
  }

  /// 确定Hero情绪状态
  ///
  /// - urgent: 存在快超期件或 urgencyScore > 100
  /// - relaxed: 没有待取件
  /// - normal: 有普通待取件且未超期
  static HeroEmotionState _determineHeroEmotionState(
    List<Package> arrived,
    int urgencyScore, {
    required bool hasOverdue,
  }) {
    if (hasOverdue || urgencyScore > 100) return HeroEmotionState.urgent;
    if (arrived.isEmpty) return HeroEmotionState.relaxed;
    return HeroEmotionState.normal;
  }

  /// 生成副标题
  static String? _generateSubtitle(
    List<Package> arrived,
    int urgencyScore, {
    required bool hasOverdue,
    required Map<String, String> stationAliases,
  }) {
    if (hasOverdue || urgencyScore > 100) return '建议立即取件';
    if (_hasPickupCluster(arrived, stationAliases)) return '建议一起取，节省跑腿';
    return null;
  }

  /// 是否有同一取件点的多个待取件（可一起取）
  ///
  /// 只看待取件，且用 stationName（经别名表归并），不用 location：京东/拼多多的
  /// location 是收货地址，把同地址的在途/待发货件当成「可合并取件」是误报。
  static bool _hasPickupCluster(
    List<Package> arrivedPackages,
    Map<String, String> stationAliases,
  ) {
    final lookup = buildAliasLookup(stationAliases);
    final counts = <String, int>{};
    for (final p in arrivedPackages) {
      final label = stationLabelOf(p);
      if (isUnknownStationLabel(label)) continue;
      final canonical = resolveCanonicalName(label, lookup);
      if (isUnknownStationLabel(canonical)) continue;
      final key = normalizeStationName(canonical);
      if (key.isEmpty) continue;
      final next = (counts[key] ?? 0) + 1;
      if (next >= 2) return true;
      counts[key] = next;
    }
    return false;
  }
}
