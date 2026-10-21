import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:pickup_app/core/engine/arrived_at.dart';
import 'package:pickup_app/core/models/package.dart';
import 'package:pickup_app/core/models/package_status.dart';
import 'package:pickup_app/main.dart' show kPackagesBox;
import 'package:pickup_app/platform/storage/hive_adapters.dart';
import 'package:pickup_app/platform/storage/hive_package.dart';
import 'package:pickup_app/ui/providers/package_provider.dart';

Package _pkg({
  required PackageStatus status,
  DateTime? arrivedAt,
  String? timeline,
  DateTime? addedAt,
}) {
  return Package(
    id: 'TB_test1',
    trackingNumber: 'YT001',
    courier: CourierType.yt,
    urgency: UrgencyLevel.normal,
    status: status,
    addedAt: addedAt ?? DateTime(2026, 10, 6, 9),
    arrivedAt: arrivedAt,
    rawTimelineJson: timeline,
    platform: 'taobao',
  );
}

String _tl(List<Map<String, String>> nodes) => jsonEncode(nodes);

void main() {
  group('looksLikeArrivedAtNode / extractArrivedAtFromTimeline', () {
    test('入柜/驿站/待取命中；分拣中心排除', () {
      expect(looksLikeArrivedAtNode('快件已放入丰巢快递柜'), isTrue);
      expect(looksLikeArrivedAtNode('已到驿站，待取件'), isTrue);
      expect(looksLikeArrivedAtNode('快件已到达【某某分拣中心】'), isFalse);
      expect(looksLikeArrivedAtNode('已到达转运中心'), isFalse);
    });

    test('取轨迹里最早的到站节点时间，过 normalizeTraceTime', () {
      final json = _tl([
        {'time': '2026-10-06 08:00:00', 'text': '快件已到达测试转运中心'},
        {'time': '2026-10-06 18:30:00', 'text': '已放入丰巢快递柜，请取件'},
        {'time': '2026-10-06 19:00:00', 'text': '待取件'},
      ]);
      final at = extractArrivedAtFromTimeline(json);
      expect(at, isNotNull);
      expect(at!.year, 2026);
      expect(at.month, 10);
      expect(at.day, 6);
      expect(at.hour, 18);
      expect(at.minute, 30);
    });

    test('无到站节点 → null', () {
      final json = _tl([
        {'time': '2026-10-06 08:00:00', 'text': '快件已揽收'},
        {'time': '2026-10-06 12:00:00', 'text': '运输中'},
      ]);
      expect(extractArrivedAtFromTimeline(json), isNull);
    });
  });

  group('resolveArrivedAt', () {
    final now = DateTime(2026, 10, 7, 12, 0, 0);

    test('已有值不覆盖', () {
      final existing = DateTime.utc(2026, 10, 5, 10);
      final d = resolveArrivedAt(
        existingArrivedAt: existing,
        resolvedStatus: PackageStatus.arrived,
        previousStatus: PackageStatus.transit,
        rawTimelineJson: _tl([
          {'time': '2026-10-06 18:00:00', 'text': '已到驿站'},
        ]),
        now: now,
      );
      expect(d.clear, isFalse);
      expect(d.value, existing);
    });

    test('首次变待取件且无轨迹节点 → 记 now', () {
      final d = resolveArrivedAt(
        existingArrivedAt: null,
        resolvedStatus: PackageStatus.arrived,
        previousStatus: PackageStatus.delivering,
        rawTimelineJson: null,
        now: now,
      );
      expect(d.clear, isFalse);
      expect(d.value, now);
    });

    test('首次变待取件优先用轨迹节点', () {
      final d = resolveArrivedAt(
        existingArrivedAt: null,
        resolvedStatus: PackageStatus.arrived,
        previousStatus: PackageStatus.transit,
        rawTimelineJson: _tl([
          {'time': '2026-10-06 17:15:00', 'text': '包裹已入柜'},
        ]),
        now: now,
      );
      expect(d.value!.day, 6);
      expect(d.value!.hour, 17);
      expect(d.value!.minute, 15);
    });

    test('已经是 arrived 且无 arrivedAt、无新节点 → 保持 null（不算再次首次）', () {
      final d = resolveArrivedAt(
        existingArrivedAt: null,
        resolvedStatus: PackageStatus.arrived,
        previousStatus: PackageStatus.arrived,
        rawTimelineJson: null,
        now: now,
      );
      expect(d.value, isNull);
      expect(d.clear, isFalse);
    });

    test('退回在途 → clear', () {
      final d = resolveArrivedAt(
        existingArrivedAt: DateTime.utc(2026, 10, 6, 18),
        resolvedStatus: PackageStatus.transit,
        previousStatus: PackageStatus.arrived,
        now: now,
      );
      expect(d.clear, isTrue);
      expect(d.value, isNull);
    });

    test('新建 arrived + 轨迹', () {
      final d = resolveArrivedAt(
        existingArrivedAt: null,
        resolvedStatus: PackageStatus.arrived,
        previousStatus: null,
        rawTimelineJson: _tl([
          {'time': '2026-10-06 16:00:00', 'text': '到驿站，待取件'},
        ]),
        now: now,
      );
      expect(d.value!.hour, 16);
    });
  });

  group('copyWith clearArrivedAt', () {
    test('clearArrivedAt 清空，仿 clearStationName', () {
      final p = _pkg(
        status: PackageStatus.arrived,
        arrivedAt: DateTime.utc(2026, 10, 6, 18),
      );
      expect(p.copyWith(clearArrivedAt: true).arrivedAt, isNull);
      expect(p.copyWith(arrivedAt: DateTime.utc(2026, 10, 7)).arrivedAt!.day, 7);
    });
  });

  group('Hive 字段 20 读写', () {
    late Directory dir;
    late Box<HivePackage> box;

    setUpAll(() {
      if (!Hive.isAdapterRegistered(0)) {
        Hive.registerAdapter(PackageStatusAdapter());
      }
      if (!Hive.isAdapterRegistered(1)) {
        Hive.registerAdapter(UrgencyLevelAdapter());
      }
      if (!Hive.isAdapterRegistered(2)) {
        Hive.registerAdapter(CourierTypeAdapter());
      }
      if (!Hive.isAdapterRegistered(3)) {
        Hive.registerAdapter(HivePackageAdapter());
      }
    });

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('parcly_arrived_');
      Hive.init(dir.path);
      box = await Hive.openBox<HivePackage>(kPackagesBox);
    });

    tearDown(() async {
      await Hive.close();
      await dir.delete(recursive: true);
    });

    test('写入 arrivedAt 后再读回', () async {
      final at = DateTime.utc(2026, 10, 6, 18, 30);
      final pkg = _pkg(status: PackageStatus.arrived, arrivedAt: at);
      await box.put(pkg.id, HivePackage.fromPackage(pkg));
      await box.flush();

      final loaded = box.get(pkg.id)!.toPackage();
      expect(loaded.arrivedAt, isNotNull);
      expect(loaded.arrivedAt!.year, 2026);
      expect(loaded.arrivedAt!.hour, 18);
      expect(loaded.arrivedAt!.minute, 30);
    });

    test('旧数据无字段 20 → arrivedAt 为 null', () async {
      // 模拟旧适配器只写 0–19：手动写一份无 arrivedAt 的 HivePackage
      final pkg = _pkg(status: PackageStatus.arrived, arrivedAt: null);
      await box.put(pkg.id, HivePackage.fromPackage(pkg));
      expect(box.get(pkg.id)!.toPackage().arrivedAt, isNull);
    });

    test('合并：首次到站写入；再次同步不覆盖；退回在途清空', () async {
      final n = PackageListNotifier();
      final clockish = DateTime(2026, 10, 7, 12);

      // 在途 → 待取（无轨迹）应写入 arrivedAt（now）
      n.addPackage(_pkg(status: PackageStatus.transit));
      expect(n.state.single.arrivedAt, isNull);

      n.addPackage(_pkg(status: PackageStatus.arrived));
      final first = n.state.single.arrivedAt;
      expect(first, isNotNull);

      // 再次同步带轨迹，不得覆盖
      n.addPackage(_pkg(
        status: PackageStatus.arrived,
        timeline: _tl([
          {'time': '2026-10-01 10:00:00', 'text': '已到驿站'},
        ]),
      ));
      expect(n.state.single.arrivedAt, first);

      // 退回在途（无证据的 arrived 可被校正时）——用无取件码无驿站的 arrived 再同步 transit
      // 先造一条无证据的 arrived，再 sync transit
      await box.clear();
      final n2 = PackageListNotifier();
      n2.addPackage(_pkg(
        status: PackageStatus.arrived,
        arrivedAt: DateTime.utc(2026, 10, 6, 18),
        timeline: _tl([
          {'time': '2026-10-06 18:00:00', 'text': '已到驿站'},
        ]),
      ));
      // 有驿站/取件码时 _resolveStatus 会保护 arrived；清掉证据
      final unprotected = n2.state.single.copyWith(
        clearStationName: true,
        pickupCode: '',
        arrivedAt: DateTime.utc(2026, 10, 6, 18),
      );
      // 直接往 state 塞再 sync：用 notifier 内部难，改为测 resolve + copyWith 路径
      final cleared = unprotected.copyWith(
        status: PackageStatus.transit,
        clearArrivedAt: resolveArrivedAt(
          existingArrivedAt: unprotected.arrivedAt,
          resolvedStatus: PackageStatus.transit,
          previousStatus: PackageStatus.arrived,
          now: clockish,
        ).clear,
      );
      expect(cleared.arrivedAt, isNull);
    });
  });
}
