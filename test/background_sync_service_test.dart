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
  Future<int> syncAll({void Function()? onEarlyProgress, bool force = false}) async {
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

Package _pkg(PackageStatus status) => Package(
      id: 'p1',
      trackingNumber: 'YT001',
      courier: CourierType.yt,
      urgency: UrgencyLevel.normal,
      status: status,
      addedAt: DateTime(2026, 11, 21, 10),
      platform: 'taobao',
    );

void main() {
  testWidgets('间隔显著变化时重启定时器，不额外触发同步', (tester) async {
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

    // 包裹到站 → 间隔从 15min 变 45min（差 > 5min，触发自适应重启）
    list.replace([_pkg(PackageStatus.arrived)]);
    await tester.pump();

    // 模拟一次定时器到期：跑同步 + 自适应重启
    await service.debugTimerTick();
    await tester.pump();

    // 关键断言：只多了定时器那一次同步，重启没有再补一次
    expect(manager.syncCalls, 2, reason: '自适应重启不得背靠背多跑一轮全量同步');

    service.dispose();
  });
}
