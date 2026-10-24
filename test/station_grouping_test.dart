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

    test('没有 stationName 的进「未知取件点」并排最后', () {
      final groups = groupPackagesByStation([
        pkg('u', location: '示例路 1 号', arrivedAt: DateTime(2026, 9, 1)),
        pkg('a', station: '驿站A', arrivedAt: DateTime(2026, 10, 3)),
        pkg('b', station: '  ', arrivedAt: DateTime(2026, 10, 4)),
      ]);
      expect(groups.map((g) => g.name), ['驿站A', unknownStationName]);
      expect(ids(groups.last), ['u', 'b']);
    });

    test('旧文案「未知驿站」与空名并入同一未知取件点组', () {
      final groups = groupPackagesByStation([
        pkg('legacy', station: legacyUnknownStationName, arrivedAt: DateTime(2026, 10, 1)),
        pkg('empty', arrivedAt: DateTime(2026, 10, 2)),
        pkg('newLabel', station: unknownStationName, arrivedAt: DateTime(2026, 10, 3)),
        pkg('named', station: '丰巢柜 · 东门', arrivedAt: DateTime(2026, 10, 4)),
      ]);
      expect(groups.map((g) => g.name), ['丰巢柜 · 东门', unknownStationName]);
      expect(ids(groups.last), ['legacy', 'empty', 'newLabel']);
    });

    test('分组键只用 stationName，不用 location', () {
      final groups = groupPackagesByStation([
        pkg('a', station: '同名点', location: '地址甲', arrivedAt: DateTime(2026, 10, 1)),
        pkg('b', station: '同名点', location: '地址乙', arrivedAt: DateTime(2026, 10, 2)),
      ]);
      expect(groups, hasLength(1));
      expect(groups.single.name, '同名点');
      expect(ids(groups.single), ['a', 'b']);
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

  group('P28-d resolveCanonicalName / aliases', () {
    test('未命中别名原样返回；空表不改写', () {
      expect(resolveCanonicalName('北门对面大院', const {}), '北门对面大院');
      expect(resolveCanonicalName(' 北门店 ', {'菜鸟驿站': '北门店'}), '北门店');
    });

    test('别名经规范化命中（空白/全角无关）', () {
      expect(
        resolveCanonicalName('北 门 店', {'北门店': '菜鸟驿站'}),
        '菜鸟驿站',
      );
    });
  });

  group('P28-d groupPackagesByStation + aliases', () {
    // 样例只进单测：北门店 ↔ 含「菜鸟驿站」的北门写法；不进 release 默认表
    const aliases = {'北门店': '菜鸟驿站'};

    test('北门店与菜鸟驿站并组，组头为规范名', () {
      final groups = groupPackagesByStation([
        pkg('a', station: '北门店', arrivedAt: DateTime(2026, 10, 1)),
        pkg('b', station: '菜鸟驿站', arrivedAt: DateTime(2026, 10, 2)),
      ], aliases: aliases);
      expect(groups, hasLength(1));
      expect(groups.single.name, '菜鸟驿站');
      expect(ids(groups.single), ['a', 'b']);
    });

    test('北门对面大院无别名 → 独立组', () {
      final groups = groupPackagesByStation([
        pkg('a', station: '北门店', arrivedAt: DateTime(2026, 10, 1)),
        pkg('b', station: '菜鸟驿站', arrivedAt: DateTime(2026, 10, 2)),
        pkg('c', station: '北门对面大院', arrivedAt: DateTime(2026, 10, 3)),
      ], aliases: aliases);
      expect(groups.map((g) => g.name).toList(), ['菜鸟驿站', '北门对面大院']);
      expect(ids(groups[0]), ['a', 'b']);
      expect(ids(groups[1]), ['c']);
    });

    test('未知仍垫底「未知取件点」；location 不作键', () {
      final groups = groupPackagesByStation([
        pkg('u', arrivedAt: DateTime(2026, 9, 1)),
        pkg('a', station: '北门店', location: '地址甲', arrivedAt: DateTime(2026, 10, 1)),
        pkg('b', station: '菜鸟驿站', location: '地址乙', arrivedAt: DateTime(2026, 10, 2)),
      ], aliases: aliases);
      expect(groups.map((g) => g.name).toList(), ['菜鸟驿站', unknownStationName]);
      expect(ids(groups.first), ['a', 'b']);
    });

    test('无 aliases 参数时行为与旧版一致（两名不并）', () {
      final groups = groupPackagesByStation([
        pkg('a', station: '北门店', arrivedAt: DateTime(2026, 10, 1)),
        pkg('b', station: '菜鸟驿站', arrivedAt: DateTime(2026, 10, 2)),
      ]);
      expect(groups.map((g) => g.name).toSet(), {'北门店', '菜鸟驿站'});
    });
  });

}
