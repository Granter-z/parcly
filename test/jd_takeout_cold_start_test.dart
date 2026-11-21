// 冷启动外卖清理只允许清理 DOM 时代遗留的合成 id，结构化真实快递不得误删。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:pickup_app/platform/storage/hive_adapters.dart';
import 'package:pickup_app/platform/storage/hive_package.dart';
import 'package:pickup_app/ui/providers/package_provider.dart';

Package _jd({
  required String id,
  required String trackingNumber,
  required String goodsName,
}) =>
    Package(
      id: id,
      trackingNumber: trackingNumber,
      courier: CourierType.jd,
      urgency: UrgencyLevel.normal,
      status: PackageStatus.transit,
      addedAt: DateTime(2026, 11, 22),
      goodsName: goodsName,
      platform: 'jd',
      // description 为空：新下单无轨迹 / 详情拉取失败
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late Box<HivePackage> box;

  setUpAll(() {
    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(PackageStatusAdapter());
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(UrgencyLevelAdapter());
    if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(CourierTypeAdapter());
    if (!Hive.isAdapterRegistered(3)) Hive.registerAdapter(HivePackageAdapter());
  });

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('parcly_jd_cold_start_');
    Hive.init(dir.path);
    box = await Hive.openBox<HivePackage>(kPackagesBox);
  });

  tearDown(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  test('结构化真实京东单：商品名带渠道词也不得冷启动清理', () async {
    final p = _jd(
      id: 'JD_123456789012',
      trackingNumber: 'JDV123456789',
      goodsName: '外卖打包盒 100只',
    );
    await box.put(p.id, HivePackage.fromPackage(p));

    final n = PackageListNotifier();

    expect(n.state.map((e) => e.id), contains(p.id));
    expect(box.get(p.id), isNotNull, reason: '_sync 后 Hive 记录必须还在');
  });

  test('合成 id 的外卖卡：冷启动仍会清理并从 Hive 删除', () async {
    final p = _jd(
      id: 'JD_x0123456789ab',
      trackingNumber: 'x0123456789ab',
      goodsName: '外卖打包盒 100只',
    );
    await box.put(p.id, HivePackage.fromPackage(p));

    final n = PackageListNotifier();

    expect(n.state, isEmpty);
    expect(box.get(p.id), isNull);
  });
}