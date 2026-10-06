import 'package:flutter_test/flutter_test.dart';
import 'package:pickup_app/core/engine/station_grouping.dart';
import 'package:pickup_app/core/models/package.dart';
import 'package:pickup_app/core/models/package_status.dart';

Package pkg(
  String id, {
  PackageStatus status = PackageStatus.arrived,
  String? station,
  String location = '',
  DateTime? addedAt,
  DateTime? arrived,
  List<StatusTransition>? history,
  String code = '',
}) =>
    Package(
      id: id,
      trackingNumber: 'TEST$id',
      courier: CourierType.zto,
      urgency: UrgencyLevel.normal,
      status: status,
      addedAt: addedAt ?? DateTime(2026, 10, 1, 9),
      stationName: station,
      location: location,
      // 真实到站时间（P16 之前先放在状态历史里；P16 后改成 arrivedAt）。
      statusHistory: history ??
          [
            if (arrived != null)
              StatusTransition(from: PackageStatus.transit, to: PackageStatus.arrived, timestamp: arrived),
          ],
      pickupCode: code,
    );

List<String> ids(StationGroup g) => [for (final p in g.packages) p.id];

void main() {
  group('groupPackagesByStation', () {
    test('只收待取件，在途和已取的不进分组', () {
      final groups = groupPackagesByStation([
        pkg('a', station: '菜鸟驿站'),
        pkg('b', station: '菜鸟驿站', status: PackageStatus.transit),
        pkg('c', station: '菜鸟驿站', status: PackageStatus.pickedUp),
      ]);
      expect(groups.length, 1);
      expect(ids(groups.single), ['a']);
    });

    test('还在途但已经有取件码的也算待取件，待发货的不算', () {
      final groups = groupPackagesByStation([
        pkg('a', station: 'S', status: PackageStatus.transit, code: '6-2-3021'),
        pkg('b', station: 'S', status: PackageStatus.pendingShipment, code: '6-2-3022'),
      ]);
      expect(ids(groups.single), ['a']);
    });

    test('组名只用 stationName，location 不参与也不显示（可能是收货地址）', () {
      final groups = groupPackagesByStation([
        pkg('a', station: '菜鸟驿站', location: '示例路 1 号 3 栋'),
        pkg('b', station: '菜鸟驿站', location: '示例路 9 号'),
      ]);
      expect(groups.map((g) => g.name), ['菜鸟驿站']);
      expect(ids(groups.single), ['a', 'b']);
    });

    test('空格、全角、大小写不同的驿站名算同一个，显示名用第一次出现的写法', () {
      final groups = groupPackagesByStation([
        pkg('a', station: '丰巢 A3 柜'),
        pkg('b', station: '丰巢Ａ３柜'),
        pkg('c', station: '  丰巢a3柜'),
      ]);
      expect(groups.length, 1);
      expect(groups.single.name, '丰巢 A3 柜');
      expect(groups.single.packages.length, 3);
    });

    test('没有 stationName 的进「未知驿站」并排最后，哪怕 location 有值、等得最久', () {
      final groups = groupPackagesByStation([
        pkg('u', location: '示例路 1 号', arrived: DateTime(2026, 9, 1)),
        pkg('a', station: '驿站A', arrived: DateTime(2026, 10, 3)),
        pkg('b', station: '  ', arrived: DateTime(2026, 10, 4)),
      ]);
      expect(groups.map((g) => g.name), ['驿站A', unknownStationName]);
      expect(ids(groups.last), ['u', 'b']);
    });

    test('组内按到站从早到晚，组按最早到站从早到晚', () {
      final groups = groupPackagesByStation([
        pkg('x2', station: '驿站X', arrived: DateTime(2026, 10, 5)),
        pkg('y1', station: '驿站Y', arrived: DateTime(2026, 10, 2)),
        pkg('x1', station: '驿站X', arrived: DateTime(2026, 10, 3)),
      ]);
      expect(groups.map((g) => g.name), ['驿站Y', '驿站X']);
      expect(ids(groups[1]), ['x1', 'x2']);
    });

    test('到站时间优先取状态历史里最后一次变成 arrived 的时间', () {
      final p = pkg('a', station: 'S', addedAt: DateTime(2026, 9, 1), history: [
        StatusTransition(from: PackageStatus.transit, to: PackageStatus.arrived, timestamp: DateTime(2026, 10, 1)),
        StatusTransition(from: PackageStatus.arrived, to: PackageStatus.delivering, timestamp: DateTime(2026, 10, 2)),
        StatusTransition(from: PackageStatus.delivering, to: PackageStatus.arrived, timestamp: DateTime(2026, 10, 3)),
      ]);
      expect(arrivalTimeOf(p), DateTime(2026, 10, 3));
    });

    test('不知道到站时间时返回 null，绝不拿 addedAt（最近同步时间）顶替', () {
      expect(arrivalTimeOf(pkg('b', addedAt: DateTime(2026, 9, 1))), isNull);
    });

    test('不知道到站时间的排在组内和组间的最后', () {
      final groups = groupPackagesByStation([
        pkg('n', station: 'N'),
        pkg('a2', station: 'A'),
        pkg('a1', station: 'A', arrived: DateTime(2026, 10, 5)),
      ]);
      expect(groups.map((g) => g.name), ['A', 'N']);
      expect(ids(groups.first), ['a1', 'a2']);
    });

    test('到站时间相同的保持原顺序', () {
      final t = DateTime(2026, 10, 1);
      final groups = groupPackagesByStation([
        pkg('b', station: 'B', arrived: t),
        pkg('a', station: 'A', arrived: t),
        pkg('b2', station: 'B', arrived: t),
      ]);
      expect(groups.map((g) => g.name), ['B', 'A']);
      expect(ids(groups.first), ['b', 'b2']);
    });

    test('空列表返回空', () {
      expect(groupPackagesByStation(const []), isEmpty);
    });
  });

  group('isNearlyOverdue', () {
    final now = DateTime(2026, 10, 7, 12);
    test('刚好 3 天不算，超过 3 天算', () {
      expect(isNearlyOverdue(pkg('a', arrived: DateTime(2026, 10, 4, 12)), now), isFalse);
      expect(isNearlyOverdue(pkg('b', arrived: DateTime(2026, 10, 4, 11, 59)), now), isTrue);
    });

    test('不知道到站时间的不标快过期，addedAt 再早也不标', () {
      expect(isNearlyOverdue(pkg('a', addedAt: DateTime(2026, 9, 1)), now), isFalse);
    });
  });
}
