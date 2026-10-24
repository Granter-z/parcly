// P42-b：Manager 每平台腿硬超时，不挡其它平台
import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:pickup_app/core/models/package.dart';
import 'package:pickup_app/core/models/package_status.dart';
import 'package:pickup_app/main.dart' show kPackagesBox;
import 'package:pickup_app/platform/connectors/connector_manager.dart';
import 'package:pickup_app/platform/connectors/platform_connector.dart';
import 'package:pickup_app/platform/storage/hive_adapters.dart';
import 'package:pickup_app/platform/storage/hive_package.dart';
import 'package:pickup_app/platform/sync/sync_history_manager.dart';
import 'package:pickup_app/ui/providers/package_provider.dart';

class _HangConnector implements PlatformConnector {
  _HangConnector({this.id = 'jd', this.name = '京东'});
  final String id;
  final String name;
  bool started = false;

  @override
  String get platformId => id;

  @override
  String get displayName => name;

  @override
  String get brandColorHex => '#000000';

  @override
  Future<bool> isAuthenticated() async => true;

  @override
  Future<void> cancelSync() async {}

  @override
  String? get lastIssue => null;

  @override
  Stream<Package> streamSync() async* {
    started = true;
    await Future<void>.delayed(const Duration(hours: 1));
  }
}

class _FastConnector implements PlatformConnector {
  _FastConnector({required this.pkg, this.id = 'taobao', this.name = '淘宝'});
  final Package pkg;
  final String id;
  final String name;

  @override
  String get platformId => id;

  @override
  String get displayName => name;

  @override
  String get brandColorHex => '#FF5000';

  @override
  Future<bool> isAuthenticated() async => true;

  @override
  Future<void> cancelSync() async {}

  @override
  String? get lastIssue => null;

  @override
  Stream<Package> streamSync() async* {
    yield pkg;
  }
}

Package _pkg(String id) => Package(
      id: id,
      trackingNumber: 'YT0000000000001',
      courier: CourierType.yt,
      urgency: UrgencyLevel.normal,
      status: PackageStatus.transit,
      addedAt: DateTime(2026, 10, 25),
      platform: 'taobao',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late ProviderContainer container;

  setUpAll(() {
    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(PackageStatusAdapter());
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(UrgencyLevelAdapter());
    if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(CourierTypeAdapter());
    if (!Hive.isAdapterRegistered(3)) Hive.registerAdapter(HivePackageAdapter());
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('parcly_p42_mgr_');
    Hive.init(tempDir.path);
    await Hive.openBox<HivePackage>(kPackagesBox);
    await SyncHistoryManager.initialize();
    container = ProviderContainer();
  });

  tearDown(() async {
    container.dispose();
    await Hive.close();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('假 connector hang → 在 per-platform timeout 内返回，其它腿结果仍在', () async {
    final hang = _HangConnector();
    final fast = _FastConnector(pkg: _pkg('TB_p42_fast'));
    final manager = container.read(connectorManagerProvider);

    final sw = Stopwatch()..start();
    final count = await manager.syncWithConnectors(
      [hang, fast],
      perPlatformTimeout: const Duration(milliseconds: 300),
    );
    sw.stop();

    expect(hang.started, isTrue);
    expect(count, 1);
    expect(container.read(packageListProvider).any((p) => p.id == 'TB_p42_fast'), isTrue);
    expect(manager.lastIssue, contains('京东'));
    expect(manager.lastIssue, isNot(contains('登录态已失效')));
    expect(sw.elapsedMilliseconds, lessThan(2000));
    expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(250));
  });
}
