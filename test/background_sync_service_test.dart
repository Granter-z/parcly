// 后台同步自适应重启回归：间隔变化时只换定时器周期，不得背靠背多跑一轮同步。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pickup_app/core/models/package.dart';
import 'package:pickup_app/core/models/package_status.dart';
import 'package:pickup_app/platform/connectors/connector_manager.dart';
import 'package:pickup_app/platform/sync/background_sync_service.dart';
import 'package:pickup_app/ui/providers/package_provider.dart';

/// 计数 syncAll，不触碰真实连接器
class _CountingManager extends ConnectorManager {
  _CountingManager(super.ref);

  int syncCalls = 0;

  @override
  Future<int> syncAll({
    void Function()? onEarlyProgress,
    bool force = false,
    bool forceSignedDetail = false,
  }) async {
    syncCalls++;
    return 0;
  }
}

/// 内存态包裹列表，不碰 Hive；可在测试里直接换状态
class _FakePackageList extends PackageListNotifier {
  _FakePackageList(List<Package> initial) {
    state = initial;
  }

  void replace(List<Package> next) => state = next;
}

Package _pkg(
  PackageStatus status, {
  UrgencyLevel urgency = UrgencyLevel.normal,
}) =>
    Package(
      id: 'p1',
      trackingNumber: 'YT0000000000001',
      courier: CourierType.yt,
      urgency: urgency,
      status: status,
      addedAt: DateTime(2026, 11, 21, 10),
      platform: 'taobao',
    );

void main() {
  for (final arrivalUrgency in [UrgencyLevel.normal, UrgencyLevel.urgent]) {
    testWidgets(
      '间隔显著变化时重启定时器，不额外触发同步（arrived urgency=${arrivalUrgency.name} 统一 30min）',
      (tester) async {
        final logs = <String>[];
        final prevDebugPrint = debugPrint;
        debugPrint = (String? message, {int? wrapWidth}) {
          if (message != null) logs.add(message);
        };
        try {
          late _CountingManager manager;
          late _FakePackageList list;
          late BackgroundSyncService service;

          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                packageListProvider.overrideWith((ref) {
                  list = _FakePackageList([_pkg(PackageStatus.delivering)]); // 15min
                  return list;
                }),
                connectorManagerProvider.overrideWith((ref) {
                  manager = _CountingManager(ref);
                  return manager;
                }),
              ],
              child: Consumer(
                builder: (context, ref, _) {
                  // 在这里强制读一次，确保两个 override 的创建闭包已执行
                  manager = ref.read(connectorManagerProvider) as _CountingManager;
                  list = ref.read(packageListProvider.notifier) as _FakePackageList;
                  service = BackgroundSyncService(ref);
                  return const SizedBox();
                },
              ),
            ),
          );

          // 注册生命周期监听，再模拟进入后台：启动定时器并立即同步一次
          service.initialize();
          tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
          await tester.pump();
          expect(manager.syncCalls, 1);
          expect(logs, contains('[BackgroundSyncService] Next sync interval: 15 minutes'));
          logs.clear();

          // 包裹到站 → 间隔从 15min 变 30min（无论普通还是紧急待取均统一 30min，差 15min > 5min，触发自适应重启）
          list.replace([_pkg(PackageStatus.arrived, urgency: arrivalUrgency)]);
          await tester.pump();

          // 模拟一次定时器到期：跑同步 + 自适应重启
          await service.debugTimerTick();
          await tester.pump();

          // 关键断言：只多了定时器那一次同步，重启没有再补一次，且新周期统一为 30 分钟
          expect(manager.syncCalls, 2, reason: '自适应重启不得背靠背多跑一轮全量同步');
          expect(logs, contains('[BackgroundSyncService] Interval changed, restarting timer...'));
          expect(logs, contains('[BackgroundSyncService] Next sync interval: 30 minutes'));

          // 从普通 arrived 切到紧急 arrived（或反之）：同属 30 分钟档位，不再触发重启
          logs.clear();
          final otherUrgency = arrivalUrgency == UrgencyLevel.normal
              ? UrgencyLevel.urgent
              : UrgencyLevel.normal;
          list.replace([_pkg(PackageStatus.arrived, urgency: otherUrgency)]);
          await tester.pump();
          await service.debugTimerTick();
          await tester.pump();
          expect(manager.syncCalls, 3);
          expect(
            logs.any((l) => l.contains('Interval changed, restarting timer...')),
            isFalse,
            reason: '普通待取件与紧急待取件均统一为 30 分钟档位，互相切换不应触发间隔重启',
          );

          service.dispose();
        } finally {
          debugPrint = prevDebugPrint;
        }
      },
    );
  }
}
