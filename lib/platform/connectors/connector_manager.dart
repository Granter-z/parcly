/// 平台连接管理器 - 仅调度真实已绑定平台同步并汇总数据流
library;

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/package_status.dart';
import '../../ui/providers/package_provider.dart';
import 'platform_connector.dart';
import 'taobao_connector.dart';
import 'jd_connector.dart';
import 'pdd_connector.dart';
import '../storage/platform_auth_store.dart';
import '../sync/sync_history_manager.dart';

final connectorManagerProvider = Provider<ConnectorManager>((ref) {
  final manager = ConnectorManager(ref);
  return manager;
});

final syncStateProvider = StateProvider<bool>((ref) => false);

/// P42-b：每平台同步腿硬超时（> 京东 streamSync 15s）。
///
/// 真机日志：三平台并行冷启动 WebView 时，京东 13.7s、拼多多 17s 才返回首包，
/// 12s 会把已经拿到的数据误杀成「同步失败」。
const Duration kConnectorPerPlatformTimeout = Duration(seconds: 20);

final RegExp _shelfCodeReg = RegExp(r'^\d{1,3}-\d{1,3}-\d{2,5}$');

class ConnectorManager {
  final Ref _ref;
  final List<PlatformConnector> _realConnectors = [];
  String? _lastIssue;

  /// 本次同步是否为用户主动触发的强制重拉（忽略「24 小时内已同步」跳过）
  bool _forceRefetch = false;

  /// 本次同步是否强制重拉已签收且有轨迹的订单详情
  bool _forceSignedDetail = false;

  ConnectorManager(this._ref) {
    _realConnectors.addAll([
      TaobaoH5Connector(
        getActiveTrackingNumbers: () {
          final list = _ref.read(packageListProvider);
          return list
              .where((p) =>
                  p.status == PackageStatus.arrived &&
                  !_shelfCodeReg.hasMatch(p.pickupCode.trim()))
              .map((p) => p.trackingNumber.trim())
              .where((tn) => tn.isNotEmpty && !tn.contains('-'))
              .toList();
        },
        // 已签收订单只请求一次详情：连接器请求前查本地包裹
        getLocalPackages: () => _ref.read(packageListProvider),
        shouldForceRefetch: () => _forceRefetch,
        shouldForceSignedDetail: () => _forceSignedDetail,
      ),
      JdH5Connector(),
      PddH5Connector(
        getLocalPackages: () => _ref.read(packageListProvider),
      ),
    ]);
  }

  List<PlatformConnector> get realConnectors => List.unmodifiable(_realConnectors);

  /// 最近一次同步出现的可提示问题（如登录态失效）
  String? get lastIssue => _lastIssue;

  /// 用户重新授权后清理上一次的失效提示，避免设置页残留旧状态
  ///
  /// 注意：会清空**全部**平台的 issue。单平台重登请用 [clearLastIssueFor]。
  void clearLastIssue() {
    _lastIssue = null;
    for (final c in _realConnectors) {
      c.clearLastIssue();
    }
  }

  /// 只清某一个平台的 issue，并重建汇总 [_lastIssue]
  ///
  /// 前端重登某一平台时应优先调用本方法，避免把其它平台仍有效的失效提示抹掉。
  void clearLastIssueFor(String platform) {
    final p = platform.toLowerCase();
    for (final c in _realConnectors) {
      if (c.platformId.toLowerCase() != p) continue;
      c.clearLastIssue();
    }
    _rebuildLastIssue();
  }

  void _rebuildLastIssue() {
    String? merged;
    for (final c in _realConnectors) {
      final issue = c.lastIssue;
      if (issue == null) continue;
      merged = merged == null ? issue : '$merged;$issue';
    }
    _lastIssue = merged;
  }

  /// 触发所有可用真实平台在途包裹聚合同步
  /// [onEarlyProgress]：首批在途件到达或首个通道完成时触发，供 UI 提前结束下拉刷新动画
  /// [force]：忽略「24 小时内已同步」跳过，强制重新拉取订单详情
  /// [forceSignedDetail]：忽略「已签收且本地有轨迹」跳过，强制重拉已签收订单详情
  Future<int> syncAll({
    void Function()? onEarlyProgress,
    bool force = false,
    bool forceSignedDetail = false,
  }) async {
    final activeRealConnectors = <PlatformConnector>[];
    for (final c in _realConnectors) {
      final auth = await c.isAuthenticated();
      if (auth) {
        activeRealConnectors.add(c);
      }
    }
    return syncWithConnectors(
      activeRealConnectors,
      onEarlyProgress: onEarlyProgress,
      force: force,
      forceSignedDetail: forceSignedDetail,
    );
  }

  /// 以指定连接器列表执行同步（支持依赖注入与单测）
  Future<int> syncWithConnectors(
    List<PlatformConnector> connectors, {
    void Function()? onEarlyProgress,
    bool force = false,
    bool forceSignedDetail = false,
    /// 单测可缩短；生产默认 [kConnectorPerPlatformTimeout]
    Duration? perPlatformTimeout,
  }) async {
    debugPrint('[ConnectorManager] syncWithConnectors invoked (${connectors.length} connectors)');
    final syncState = _ref.read(syncStateProvider.notifier);
    if (syncState.state) {
      debugPrint('[ConnectorManager] already syncing, skip');
      return 0;
    }

    syncState.state = true;
    _forceRefetch = force;
    _forceSignedDetail = forceSignedDetail;
    final notifier = _ref.read(packageListProvider.notifier);
    int newCount = 0;
    final sw = Stopwatch()..start();
    _lastIssue = null;

    var earlyProgressFired = false;
    void triggerEarly() {
      if (!earlyProgressFired) {
        earlyProgressFired = true;
        onEarlyProgress?.call();
      }
    }

    try {
      debugPrint('[ConnectorManager] Active connectors: ${connectors.map((e) => e.platformId).toList()}');
      if (connectors.isEmpty) {
        triggerEarly();
        return 0;
      }

      final legTimeout = perPlatformTimeout ?? kConnectorPerPlatformTimeout;
      final futures = connectors.map((connector) async {
        final cw = Stopwatch()..start();
        var completed = false;
        try {
          // P42-b：单腿硬超时；只结束本平台 future，不取消其它平台
          await (() async {
            await for (final package in connector.streamSync()) {
              if (!PlatformAuthStore().isBlacklisted(package.id, trackingNumber: package.trackingNumber)) {
                notifier.addPackage(package);
                newCount++;
                if (package.status == PackageStatus.delivering ||
                    package.status == PackageStatus.arrived ||
                    package.status == PackageStatus.transit) {
                  triggerEarly();
                }
              }
            }
          })().timeout(legTimeout);
          completed = true;
        } on TimeoutException {
          debugPrint(
            '[ConnectorManager] ${connector.platformId} sync timed out '
            '(${legTimeout.inMilliseconds}ms)',
          );
          // 超时只结束 Future 不会取消 stream，显式通知连接器停手
          try {
            await connector.cancelSync();
          } catch (_) {}
          // 若连接器内部已给出明确问题（如登录失效），优先保留；否则报超时 soft issue
          final msg = connector.lastIssue ??
              '${connector.displayName}暂时不可达或同步超时，已保留旧数据';
          if (_lastIssue == null || !_lastIssue!.contains(msg)) {
            _lastIssue = _lastIssue == null ? msg : '$_lastIssue；$msg';
          }
        } catch (e, stack) {
          debugPrint('[ConnectorManager] Error syncing ${connector.platformId}: ${e.runtimeType}\n$stack');
          try {
            await connector.cancelSync();
          } catch (_) {}
          final msg = connector.lastIssue ??
              '${connector.displayName}同步响应异常，已保留旧数据';
          if (_lastIssue == null || !_lastIssue!.contains(msg)) {
            _lastIssue = _lastIssue == null ? msg : '$_lastIssue；$msg';
          }
        } finally {
          cw.stop();
          triggerEarly();
          debugPrint('[ConnectorManager] ${connector.platformId} sync took ${cw.elapsedMilliseconds}ms');
          // 只记录真正完成的同步：超时/软失败/登录失效若也记，会误让保活跳过 6 小时心跳
          final authExpired = PlatformAuthStore().isExpired(connector.platformId);
          if (completed && connector.lastSyncSucceeded && !authExpired) {
            await SyncHistoryManager().recordPlatformSync(connector.platformId);
          }
          // 京东 DOM 兜底的伪 id 会随标题变化，清掉本轮没再产出的旧卡；
          // 结构化订单列表成功解析时（即使过滤后 0 单）也清理：
          // 结构化源已判定没有快递时，DOM 伪卡不应继续留在列表里。
          if (completed &&
              connector is JdH5Connector &&
              connector.lastSyncCompleted &&
              connector.lastSyncSawStructuredList) {
            notifier.pruneJdSyntheticCardsNotIn(connector.lastSyncYieldedIds);
          }
          final issue = connector.lastIssue;
          if (issue != null && (_lastIssue == null || !_lastIssue!.contains(issue))) {
            _lastIssue = _lastIssue == null ? issue : '$_lastIssue；$issue';
          }
        }
      });

      await Future.wait(futures);
      sw.stop();
      debugPrint('[ConnectorManager] sync done: $newCount packages in ${sw.elapsedMilliseconds}ms');
      return newCount;
    } finally {
      _forceRefetch = false;
      _forceSignedDetail = false;
      syncState.state = false;
    }
  }
}
