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
  List<StatusTransition> history = const [],
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
      statusHistory: history,
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

    test('同叫「菜鸟驿站」但位置不同的分成两组', () {
      final groups = groupPackagesByStation([
        pkg('a', station: '菜鸟驿站', location: '东门'),
        pkg('b', station: '菜鸟驿站', location: '西门'),
        pkg('c', station: '菜鸟驿站', location: '东门'),
      ]);
      expect(groups.map((g) => g.name), ['菜鸟驿站 · 东门', '菜鸟驿站 · 西门']);
      expect(ids(groups.first), ['a', 'c']);
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

    test('没有 stationName 时用 location；两个都没有进「未知驿站」并排最后', () {
      final groups = groupPackagesByStation([
        pkg('u', addedAt: DateTime(2026, 9, 1)),
        pkg('a', location: '3 号楼快递柜', addedAt: DateTime(2026, 10, 3)),
        pkg('b', station: '', location: '3号楼快递柜', addedAt: DateTime(2026, 10, 4)),
      ]);
      expect(groups.map((g) => g.name), ['3 号楼快递柜', unknownStationName]);
      expect(ids(groups.first), ['a', 'b']);
      expect(ids(groups.last), ['u']);
    });

    test('组内按到站从早到晚，组按最早到站从早到晚', () {
      final groups = groupPackagesByStation([
        pkg('x2', station: '驿站X', addedAt: DateTime(2026, 10, 5)),
        pkg('y1', station: '驿站Y', addedAt: DateTime(2026, 10, 2)),
        pkg('x1', station: '驿站X', addedAt: DateTime(2026, 10, 3)),
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
      expect(arrivalTimeOf(pkg('b')), DateTime(2026, 10, 1, 9));
    });

    test('到站时间相同的保持原顺序', () {
      final t = DateTime(2026, 10, 1);
      final groups = groupPackagesByStation([
        pkg('b', station: 'B', addedAt: t),
        pkg('a', station: 'A', addedAt: t),
        pkg('b2', station: 'B', addedAt: t),
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
      expect(isNearlyOverdue(pkg('a', addedAt: DateTime(2026, 10, 4, 12)), now), isFalse);
      expect(isNearlyOverdue(pkg('b', addedAt: DateTime(2026, 10, 4, 11, 59)), now), isTrue);
    });
  });
}
