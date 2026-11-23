/// 同步优化器 - 智能跳过最近已同步的订单
///
/// 减少重复请求，提升二次及后续同步速度
library;

import 'package:flutter/foundation.dart';
import '../../core/models/package.dart';
import '../../core/models/package_status.dart';

class SyncOptimizer {
  /// 判断是否应该跳过订单详情请求
  ///
  /// 规则：
  /// 1. 本地无此订单 → 不跳过（首次同步）
  /// 2. 已完成状态（已取件/已归档/已拒收）→ 跳过
  /// 3. 在途状态但 24 小时内已同步过 → 跳过
  /// 4. 在途状态且超过 24 小时 → 不跳过（需要更新）
  ///
  /// [force] 为真时用户主动要求强制重拉：忽略规则 3 的 24 小时窗口，但规则 2 仍然生效
  /// （已完成订单的详情不会再变化，重拉只是白费请求）。用在数据卡住需要立刻刷新时，
  /// 例如驿站名/取件码被降级后想立刻拉回正确值。
  static bool shouldSkipDetailFetch({
    required Package? localPackage,
    Duration recentThreshold = const Duration(hours: 24),
    bool force = false,
  }) {
    // 本地无此订单，首次同步
    if (localPackage == null) return false;

    // 已完成状态，跳过
    if (localPackage.status == PackageStatus.pickedUp ||
        localPackage.status == PackageStatus.archived ||
        localPackage.status == PackageStatus.rejected) {
      debugPrint('[SyncOptimizer] Skip: already completed (${localPackage.status.label})');
      return true;
    }

    // 强制重拉：忽略 24 小时窗口
    if (force) {
      debugPrint('[SyncOptimizer] Fetch: forced, ignoring recent-sync window');
      return false;
    }

    // 在途状态，检查最近一次详情拉取时间（旧数据回退到加入时间）
    final now = DateTime.now();
    final lastUpdate = localPackage.lastFetchedAt ?? localPackage.addedAt;
    final timeSinceUpdate = now.difference(lastUpdate);

    if (timeSinceUpdate < recentThreshold) {
      debugPrint('[SyncOptimizer] Skip: recently synced ${timeSinceUpdate.inHours}h ago');
      return true;
    }

    // 需要更新
    debugPrint('[SyncOptimizer] Fetch: last sync ${timeSinceUpdate.inHours}h ago');
    return false;
  }

  /// 过滤需要拉取详情的订单列表
  /// [idPrefix] 为平台 ID 前缀（如 `TB_`）。传入后只匹配 `前缀 + 订单号` 的精确 ID，
  /// 避免一方订单号恰好是另一方 ID 后缀时跨平台误匹配。
  static List<T> filterNeedsFetch<T>({
    required List<T> orders,
    required List<Package> localPackages,
    required String Function(T) getOrderId,
    String? idPrefix,
    Duration recentThreshold = const Duration(hours: 24),
    bool force = false,
  }) {
    final result = <T>[];
    var skippedCount = 0;

    final byId = <String, Package>{
      for (final p in localPackages) p.id: p,
    };

    for (final order in orders) {
      final orderId = getOrderId(order).trim();
      Package? localPackage;
      if (orderId.isNotEmpty) {
        if (idPrefix != null) {
          localPackage = byId['$idPrefix$orderId'];
        } else {
          final suffix = '_$orderId';
          for (final p in localPackages) {
            if (p.id == orderId || p.id.endsWith(suffix)) {
              localPackage = p;
              break;
            }
          }
        }
      }

      final shouldSkip = shouldSkipDetailFetch(
        localPackage: localPackage,
        recentThreshold: recentThreshold,
        force: force,
      );

      if (shouldSkip) {
        skippedCount++;
      } else {
        result.add(order);
      }
    }

    debugPrint('[SyncOptimizer] Total: ${orders.length}, Need fetch: ${result.length}, Skipped: $skippedCount');
    return result;
  }
}
