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
  DateTime? arrivedAt,
  String code = '',
}) =>
    Package(
      id: id,
      trackingNumber: 'TEST$id',
      courier: CourierType.zto,
      urgency: UrgencyLevel.normal,
      status: status,
      addedAt: addedAt ?? DateTime(2026, 10, 1, 9),
      arrivedAt: arrivedAt,
      stationName: station,
      location: location,
      pickupCode: code,
    );

List<String> ids(StationGroup g) => [for (final p in g.packages) p.id];

void main() {
  final now = DateTime(2026, 10, 7, 12);

  group('arrivalTimeOf / isNearlyOverdue / arrivedAgo', () {
    test('只读 Package.arrivedAt，绝不回退 addedAt', () {
      final p = pkg('a',
          addedAt: DateTime(2026, 9, 1),
          arrivedAt: DateTime(2026, 10, 3, 8));
      expect(arrivalTimeOf(p), DateTime(2026, 10, 3, 8));
      expect(arrivalTimeOf(pkg('b', addedAt: DateTime(2026, 9, 1))), isNull);
    });

    test('快过期：超过 3 天才标；null 不标', () {
      expect(isNearlyOverdue(pkg('n'), now), isFalse);
      expect(
        isNearlyOverdue(
            pkg('exact', arrivedAt: now.subtract(const Duration(days: 3))), now),
        isFalse,
      );
      expect(
        isNearlyOverdue(
          pkg('over',
              arrivedAt:
                  now.subtract(const Duration(days: 3, seconds: 1))),
          now,
        ),
        isTrue,
      );
    });

    test('arrivedAgoLabelOf：null 不显示文案', () {
      expect(arrivedAgoLabelOf(pkg('n'), now), isNull);
      expect(
        arrivedAgoLabelOf(
            pkg('a', arrivedAt: now.subtract(const Duration(days: 2))), now),
        '2天前到',
      );
    });
  });

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
        pkg('b',
            station: 'S',
            status: PackageStatus.pendingShipment,
            code: '6-2-3022'),
      ]);
      expect(ids(groups.single), ['a']);
    });

    test('组名只用 stationName，location 不参与', () {
      final groups = groupPackagesByStation([
        pkg('a', station: '菜鸟驿站', location: '示例路 1 号'),
        pkg('b', station: '菜鸟驿站', location: '示例路 9 号'),
      ]);
      expect(groups.map((g) => g.name), ['菜鸟驿站']);
    });

    test('组内 null arrivedAt 排在有时间的后面', () {
      final groups = groupPackagesByStation([
        pkg('n', station: 'S', arrivedAt: null),
        pkg('late', station: 'S', arrivedAt: DateTime(2026, 10, 5)),
        pkg('early', station: 'S', arrivedAt: DateTime(2026, 10, 3)),
      ]);
      expect(ids(groups.single), ['early', 'late', 'n']);
    });

    test('整组都没有到站时间的排在所有有时间的组后面', () {
      final groups = groupPackagesByStation([
        pkg('no', station: '无时间站'),
        pkg('yes', station: '有时间站', arrivedAt: DateTime(2026, 10, 4)),
      ]);
      expect(groups.map((g) => g.name), ['有时间站', '无时间站']);
    });

    test('组内按到站从早到晚，组按最早到站从早到晚', () {
      final groups = groupPackagesByStation([
        pkg('x2', station: '驿站X', arrivedAt: DateTime(2026, 10, 5)),
        pkg('y1', station: '驿站Y', arrivedAt: DateTime(2026, 10, 2)),
        pkg('x1', station: '驿站X', arrivedAt: DateTime(2026, 10, 3)),
      ]);
      expect(groups.map((g) => g.name), ['驿站Y', '驿站X']);
      expect(ids(groups[1]), ['x1', 'x2']);
    });

    test('没有 stationName 的进「未知驿站」并排最后', () {
      final groups = groupPackagesByStation([
        pkg('u', location: '示例路 1 号', arrivedAt: DateTime(2026, 9, 1)),
        pkg('a', station: '驿站A', arrivedAt: DateTime(2026, 10, 3)),
        pkg('b', station: '  ', arrivedAt: DateTime(2026, 10, 4)),
      ]);
      expect(groups.map((g) => g.name), ['驿站A', unknownStationName]);
      expect(ids(groups.last), ['u', 'b']);
    });

    test('绝不拿 addedAt 顶替：只有 arrivedAt 参与排序与快过期', () {
      final oldAdded = pkg('oldAdded',
          station: 'S',
          addedAt: DateTime(2026, 9, 1),
          arrivedAt: null);
      final recentArrived = pkg('recent',
          station: 'S',
          addedAt: DateTime(2026, 10, 6),
          arrivedAt: DateTime(2026, 10, 5));
      final groups = groupPackagesByStation([oldAdded, recentArrived]);
      // null 排后面；有 arrivedAt 的在前
      expect(ids(groups.single), ['recent', 'oldAdded']);
      expect(isNearlyOverdue(oldAdded, now), isFalse);
      expect(
        isNearlyOverdue(
            pkg('stale',
                arrivedAt: now.subtract(const Duration(days: 4))),
            now),
        isTrue,
      );
    });
  });
}
