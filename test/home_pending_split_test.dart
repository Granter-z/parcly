// 首页待取件按取件点、在途扁平：provider 切分口径。
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pickup_app/core/engine/station_grouping.dart';
import 'package:pickup_app/core/models/package.dart';
import 'package:pickup_app/core/models/package_status.dart';
import 'package:pickup_app/ui/providers/package_provider.dart';

class _FakeList extends PackageListNotifier {
  _FakeList(List<Package> initial) {
    state = initial;
  }

  @override
  void markPickedUp(String id) {}
}

Package _p(
  String id, {
  PackageStatus status = PackageStatus.arrived,
  String? station,
  String code = '',
  DateTime? arrivedAt,
}) =>
    Package(
      id: id,
      trackingNumber: 'T$id',
      courier: CourierType.yt,
      urgency: UrgencyLevel.normal,
      status: status,
      addedAt: DateTime(2026, 10, 1),
      arrivedAt: arrivedAt,
      stationName: station,
      pickupCode: code,
      platform: 'taobao',
    );

void main() {
  test('groupedPending 只含待取件；inTransit 扁平且不含待取', () {
    final pkgs = [
      _p('a', station: '驿站A', arrivedAt: DateTime(2026, 10, 3), code: '1-1-1'),
      _p('b', station: '驿站B', arrivedAt: DateTime(2026, 10, 2)),
      _p('t', status: PackageStatus.transit),
      _p('d', status: PackageStatus.delivering),
      _p('s', status: PackageStatus.pendingShipment),
      _p('codeTransit',
          status: PackageStatus.transit, station: '驿站A', code: '9-9-9'),
    ];
    final container = ProviderContainer(
      overrides: [
        packageListProvider.overrideWith((ref) => _FakeList(pkgs)),
      ],
    );
    addTearDown(container.dispose);

    final groups = container.read(groupedPendingPackagesProvider);
    final transit = container.read(inTransitPackagesProvider);

    final groupedIds = [for (final g in groups) ...g.packages.map((p) => p.id)];
    expect(groupedIds.toSet(), {'a', 'b', 'codeTransit'});
    expect(groups.map((g) => g.name).toList(), ['驿站B', '驿站A']); // B 更早到站
    expect(idsIn(groups, '驿站A'), ['a', 'codeTransit']);

    expect(transit.map((p) => p.id).toList(), ['d', 't', 's']); // 派送>运送>待发货
    for (final p in transit) {
      expect(isAwaitingPickup(p), isFalse);
    }
  });
}

List<String> idsIn(List<StationGroup> groups, String name) => [
      for (final g in groups)
        if (g.name == name)
          for (final p in g.packages) p.id,
    ];
