import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:pickup_app/core/engine/station_grouping.dart';
import 'package:pickup_app/core/models/package.dart';
import 'package:pickup_app/core/models/package_status.dart';
import 'package:pickup_app/platform/notification/notification_adapter.dart';
import 'package:pickup_app/platform/storage/pickup_point_alias_store.dart';
import 'package:pickup_app/ui/providers/pickup_point_alias_provider.dart';

void main() {
  test('preferredCanonicalName：较长优先', () {
    expect(preferredCanonicalName('北门店', '菜鸟驿站'), '菜鸟驿站');
    expect(preferredCanonicalName('菜鸟驿站北门店', '北门店'), '菜鸟驿站北门店');
  });

  group('PickupPointAliasStore.setAlias 规范化与防成环', () {
    late Directory tempDir;
    late PickupPointAliasStore store;

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('pickup_point_alias_');
      Hive.init(tempDir.path);
      await PickupPointAliasStore.initialize();
      store = PickupPointAliasStore();
    });

    tearDown(() async {
      await Hive.close();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('忽略规范化同值自映射（空白/全角/大小写）', () async {
      await store.setAlias(' 北门店 ', '北　门 店');
      await store.setAlias('Station A', 'Ｓｔａｔｉｏｎ　ａ');
      expect(store.readAll(), isEmpty);
    });

    test('覆盖规范化同键冲突，不残留旧变体键', () async {
      await store.setAlias('北门店', '菜鸟驿站甲');
      await store.setAlias('北　门 店', '菜鸟驿站乙');

      final all = store.readAll();
      expect(all, hasLength(1));
      expect(all['北　门 店'], '菜鸟驿站乙');
    });

    test('设置 A -> B 后再设 B -> C 及 C -> A 时自动展平链条且绝不成环', () async {
      await store.setAlias('站点A', '站点B');
      expect(store.readAll(), {'站点A': '站点B'});

      await store.setAlias('站点B', '站点C');
      expect(store.readAll(), {'站点A': '站点C', '站点B': '站点C'});

      // 反向声明 C -> A：去掉 A 旧规则并将原指向 C 的映射展平指向 A，不成环
      await store.setAlias('站点C', '站点A');
      final all = store.readAll();
      expect(all, {'站点B': '站点A', '站点C': '站点A'});

      final normKeys = all.keys.map(normalizeStationName).toSet();
      final normVals = all.values.map(normalizeStationName).toSet();
      expect(normKeys.intersection(normVals), isEmpty);
    });
  });

  test('NotificationAdapter.buildArrivedBodyForTest 使用别名表将原始驿站名映射为规范名', () {
    final pkg = Package(
      id: 'TB_1000000000000000001',
      trackingNumber: 'YT0000000000001',
      courier: CourierType.yt,
      urgency: UrgencyLevel.normal,
      status: PackageStatus.arrived,
      addedAt: DateTime(2026, 10, 7),
      pickupCode: '1-1-1111',
      stationName: '北门店',
      platform: 'taobao',
    );

    final body = NotificationAdapter().buildArrivedBodyForTest(
      pkg,
      stationAliases: const {'北门店': '菜鸟驿站北门店'},
    );

    expect(body, '圆通 · 取件码：1-1-1111 · 菜鸟驿站北门店');
    expect(body, isNot(contains(' · 北门店')));
  });
}
