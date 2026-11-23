// 首页冒烟测试：空态 / 在途分区 / 已完成入口的渲染，不碰通知与真实连接器。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:pickup_app/core/models/package.dart';
import 'package:pickup_app/core/models/package_status.dart';
import 'package:pickup_app/platform/connectors/connector_manager.dart';
import 'package:pickup_app/platform/keep_alive/keep_alive_worker_bridge.dart';
import 'package:pickup_app/platform/storage/keep_alive_store.dart';
import 'package:pickup_app/ui/providers/package_provider.dart';
import 'package:pickup_app/ui/providers/platform_auth_status_provider.dart';
import 'package:pickup_app/ui/screens/home/home_screen.dart';

/// 内存态包裹列表，不碰 Hive
class _FakePackageList extends PackageListNotifier {
  _FakePackageList(List<Package> initial) {
    state = initial;
  }
}

/// 不触发真实同步的管理器
class _NoopManager extends ConnectorManager {
  _NoopManager(super.ref);

  @override
  Future<int> syncAll({
    void Function()? onEarlyProgress,
    bool force = false,
    bool forceSignedDetail = false,
  }) async =>
      0;
}

Package _pkg({
  String id = 'p1',
  PackageStatus status = PackageStatus.transit,
  DateTime? pickedUpAt,
}) =>
    Package(
      id: id,
      trackingNumber: 'YT001',
      courier: CourierType.yt,
      urgency: UrgencyLevel.normal,
      status: status,
      addedAt: DateTime(2026, 11, 21, 10),
      pickedUpAt: pickedUpAt,
      goodsName: '测试商品',
      platform: 'taobao',
    );

Future<void> pumpHome(
  WidgetTester tester, {
  List<Package> packages = const [],
  Map<String, PlatformAuthStatus> statuses = const {
    'pdd': PlatformAuthStatus.ok,
    'jd': PlatformAuthStatus.ok,
    'taobao': PlatformAuthStatus.ok,
  },
}) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [
        packageListProvider.overrideWith((ref) => _FakePackageList(packages)),
        connectorManagerProvider.overrideWith((ref) => _NoopManager(ref)),
        platformAuthStatusProvider.overrideWith((ref, p) => statuses[p]!),
        syncStateProvider.overrideWith((ref) => false),
      ],
      child: const MaterialApp(home: HomeScreen()),
    ),
  );
}

void main() {
  late Directory tempDir;
  late Directory bridgeDir;

  setUp(() async {
    // 首页首帧会启动保活服务，需要 Hive 已初始化；用临时目录隔离
    tempDir = Directory.systemTemp.createTempSync('home_screen_test');
    bridgeDir = Directory.systemTemp.createTempSync('home_screen_bridge');
    debugBridgeDirOverride = bridgeDir;
    Hive.init(tempDir.path);
    await KeepAliveStore.initialize();
  });

  tearDown(() async {
    debugBridgeDirOverride = null;
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    if (bridgeDir.existsSync()) bridgeDir.deleteSync(recursive: true);
  });

  testWidgets('空态：无包裹时显示「暂无待取快件」，不显示分区', (tester) async {
    await pumpHome(tester);
    await tester.pump();

    expect(find.text('暂无待取快件'), findsOneWidget);
    expect(find.textContaining('待取件'), findsNothing);
    expect(find.textContaining('在途 ('), findsNothing);
  });

  testWidgets('在途包裹：显示「在途」分区，不显示空态', (tester) async {
    await pumpHome(tester, packages: [_pkg(status: PackageStatus.transit)]);
    await tester.pump();

    expect(find.text('在途 (1)'), findsOneWidget);
    expect(find.text('暂无待取快件'), findsNothing);
  });

  testWidgets('只有已完成包裹：显示已完成入口，不显示在途分区', (tester) async {
    await pumpHome(tester, packages: [
      _pkg(status: PackageStatus.pickedUp, pickedUpAt: DateTime(2026, 11, 20)),
    ]);
    await tester.pump();

    expect(find.textContaining('已完成'), findsWidgets);
    expect(find.textContaining('在途 ('), findsNothing);
  });

  testWidgets('平台掉线：状态条显示需重登，本地包裹不被清空', (tester) async {
    await pumpHome(
      tester,
      packages: [_pkg(status: PackageStatus.transit)],
      statuses: {
        'pdd': PlatformAuthStatus.ok,
        'jd': PlatformAuthStatus.ok,
        'taobao': PlatformAuthStatus.needsRelogin,
      },
    );
    await tester.pump();

    expect(find.text('淘宝 需重登'), findsOneWidget);
    expect(find.text('在途 (1)'), findsOneWidget);
  });
}
