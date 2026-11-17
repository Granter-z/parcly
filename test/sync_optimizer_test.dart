// 强制重拉：忽略「24 小时内已同步」跳过，但不重拉已完成订单。全部为自造数据。
import 'package:flutter_test/flutter_test.dart';
import 'package:pickup_app/core/models/package.dart';
import 'package:pickup_app/core/models/package_status.dart';
import 'package:pickup_app/platform/connectors/sync_optimizer.dart';

const _orderId = '1000000000000000001';

Package _pkg(
  PackageStatus status, {
  Duration age = const Duration(hours: 1),
  Duration? fetchedAge,
}) =>
    Package(
      id: 'TB_$_orderId',
      trackingNumber: 'YT0055555550001',
      courier: CourierType.yt,
      urgency: UrgencyLevel.normal,
      status: status,
      addedAt: DateTime.now().subtract(age),
      lastFetchedAt: fetchedAge == null
          ? null
          : DateTime.now().subtract(fetchedAge),
    );

void main() {
  group('SyncOptimizer 强制重拉', () {
    test('在途件 1 小时前刚同步过 → 默认跳过', () {
      expect(
        SyncOptimizer.shouldSkipDetailFetch(
          localPackage: _pkg(PackageStatus.arrived),
        ),
        isTrue,
      );
    });

    test('同一件加 force → 不再跳过（这正是驿站名能被拉回的前提）', () {
      expect(
        SyncOptimizer.shouldSkipDetailFetch(
          localPackage: _pkg(PackageStatus.arrived),
          force: true,
        ),
        isFalse,
      );
    });

    test('按 lastFetchedAt 判定：加入很久但刚拉过 → 跳过', () {
      expect(
        SyncOptimizer.shouldSkipDetailFetch(
          localPackage: _pkg(
            PackageStatus.transit,
            age: const Duration(days: 7),
            fetchedAge: const Duration(hours: 1),
          ),
        ),
        isTrue,
      );
    });

    test('按 lastFetchedAt 判定：刚加入但 48h 没拉 → 拉取', () {
      expect(
        SyncOptimizer.shouldSkipDetailFetch(
          localPackage: _pkg(
            PackageStatus.transit,
            age: const Duration(hours: 1),
            fetchedAge: const Duration(hours: 48),
          ),
        ),
        isFalse,
      );
    });

    test('已完成订单即使 force 也跳过：详情不会再变化', () {
      for (final status in [
        PackageStatus.pickedUp,
        PackageStatus.archived,
        PackageStatus.rejected,
      ]) {
        expect(
          SyncOptimizer.shouldSkipDetailFetch(
            localPackage: _pkg(status),
              force: true,
          ),
          isTrue,
          reason: '${status.label} 属于已完成，force 不该把它重新拉一遍',
        );
      }
    });

    test('本地没有该订单 → 无论如何都要拉', () {
      expect(
        SyncOptimizer.shouldSkipDetailFetch(
          localPackage: null,
          force: false,
        ),
        isFalse,
      );
    });

    test('filterNeedsFetch 把 force 透传下去', () {
      final local = [_pkg(PackageStatus.arrived)];
      const orders = [_orderId];

      List<String> run({required bool force}) => SyncOptimizer.filterNeedsFetch<String>(
            orders: orders,
            localPackages: local,
            getOrderId: (order) => order,
            idPrefix: 'TB_',
            force: force,
          );

      expect(run(force: false), isEmpty);
      expect(run(force: true), orders);
    });
  });
}
