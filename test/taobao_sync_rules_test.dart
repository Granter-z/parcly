// P11-b 后续：已签收订单只请求一次物流详情。全部为自造数据。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pickup_app/core/models/package.dart';
import 'package:pickup_app/core/models/package_status.dart';
import 'package:pickup_app/platform/connectors/taobao_sync_rules.dart';

final _timeline = jsonEncode([
  {'tag': '已签收', 'time': '2026-10-06 19:33:00', 'text': '您已在测试小区北门店完成取件'},
]);

Package _pkg({
  String id = 'TB_1000000000000000001',
  String tracking = 'YT0000000000001',
  PackageStatus status = PackageStatus.pickedUp,
  String? timeline,
}) =>
    Package(
      id: id,
      trackingNumber: tracking,
      courier: CourierType.yt,
      urgency: UrgencyLevel.normal,
      status: status,
      addedAt: DateTime(2026, 10, 6),
      platform: 'taobao',
      rawTimelineJson: timeline,
    );

void main() {
  test('包裹 ID 由订单号派生', () {
    expect(taobaoPackageId('1000000000000000001'), 'TB_1000000000000000001');
  });

  group('findLocalTaobaoPackage：按包裹 ID，其次按运单号（无运单号时就是订单号）', () {
    test('按 ID 找到', () {
      final p = _pkg();
      expect(findLocalTaobaoPackage([_pkg(id: 'PDD_x', tracking: 'x'), p], '1000000000000000001'), same(p));
    });

    test('没有运单号的旧记录 trackingNumber 就是订单号，也能找到', () {
      final p = _pkg(id: 'CN_x', tracking: '1000000000000000001');
      expect(findLocalTaobaoPackage([p], '1000000000000000001'), same(p));
    });

    test('ID 优先于运单号', () {
      final byTracking = _pkg(id: 'CN_x', tracking: '1000000000000000001');
      final byId = _pkg(tracking: 'YT0000000000009');
      expect(findLocalTaobaoPackage([byTracking, byId], '1000000000000000001'), same(byId));
    });

    test('找不到 / 订单号为空', () {
      expect(findLocalTaobaoPackage([_pkg()], '1000000000000000002'), isNull);
      expect(findLocalTaobaoPackage([_pkg()], ' '), isNull);
      expect(findLocalTaobaoPackage(const [], '1000000000000000001'), isNull);
    });
  });

  group('shouldSkipSignedDetail', () {
    test('已签收 + 轨迹不为空 → 跳过', () {
      expect(shouldSkipSignedDetail(_pkg(timeline: _timeline)), isTrue);
    });

    test('已归档（由已签收归档）+ 轨迹不为空 → 跳过', () {
      expect(shouldSkipSignedDetail(_pkg(status: PackageStatus.archived, timeline: _timeline)), isTrue);
    });

    test('第一次同步：本地没有 → 照常请求', () {
      expect(shouldSkipSignedDetail(null), isFalse);
    });

    test('已签收但轨迹为空（null、空串、空数组、坏 JSON）→ 照常请求', () {
      for (final t in [null, '', '[]', 'not json']) {
        expect(shouldSkipSignedDetail(_pkg(timeline: t)), isFalse, reason: 'timeline=$t');
      }
    });

    test('未签收（在途 / 派送 / 待取 / 待发货 / 拒收）有轨迹也照常请求', () {
      for (final s in [
        PackageStatus.transit,
        PackageStatus.delivering,
        PackageStatus.arrived,
        PackageStatus.pendingShipment,
        PackageStatus.rejected,
      ]) {
        expect(shouldSkipSignedDetail(_pkg(status: s, timeline: _timeline)), isFalse, reason: '$s');
      }
    });

    test('连接器的组合用法：15 单里 3 单有物流，其中 1 单本地已签收有轨迹 → 只请求 2 单', () {
      final local = [
        _pkg(id: 'TB_1000000000000000009', tracking: 'YT00*******0003', timeline: _timeline),
        _pkg(id: 'TB_1000000000000000001', tracking: '0000*******0001', status: PackageStatus.transit, timeline: _timeline),
      ];
      final withLogistics = ['1000000000000000001', '1000000000000000002', '1000000000000000009'];
      final toRequest = withLogistics.where((o) => !shouldSkipSignedDetail(findLocalTaobaoPackage(local, o))).toList();
      expect(toRequest, ['1000000000000000001', '1000000000000000002']);
    });
  });

  group('P23-a：详情任务列表吃 finalNeedFetch（已签收有轨迹 → 0 次详情）', () {
    test('智能跳过后再滤已签收 → 详情任务长度为 0', () {
      final local = [
        _pkg(id: 'TB_1000000000000000001', tracking: 'YT00*******0001', timeline: _timeline),
      ];
      // 模拟 connector：订单列表只有这一单有物流
      final withLogistics = ['1000000000000000001'];
      // SyncOptimizer 对已签收也会跳（completed），但即使 force 拉进 needFetch，
      // shouldSkipSignedDetail 仍会滤掉 → finalNeedFetch 为空
      final needFetch = withLogistics.where((o) {
        final lp = findLocalTaobaoPackage(local, o);
        // 与 SyncOptimizer 已完成跳过同口径：这里直接用 shouldSkipSignedDetail 覆盖「已签收有轨迹」
        return !shouldSkipSignedDetail(lp);
      }).toList();
      expect(needFetch, isEmpty, reason: '已签收有轨迹不得进入详情任务列表');
    });

    test('在途本地 → 仍需进详情任务列表', () {
      final local = [
        _pkg(
          id: 'TB_1000000000000000002',
          tracking: 'YT00*******0002',
          status: PackageStatus.transit,
          timeline: _timeline,
        ),
      ];
      final withLogistics = ['1000000000000000002'];
      final finalNeedFetch = withLogistics
          .where((o) => !shouldSkipSignedDetail(findLocalTaobaoPackage(local, o)))
          .toList();
      expect(finalNeedFetch, ['1000000000000000002']);
    });
  });

  group('P23-b：菜鸟 WebView 可跳', () {
    final now = DateTime(2026, 10, 24, 23, 50);

    Package awaitingWithCode() => Package(
          id: 'CN_YT0012345678901',
          trackingNumber: 'YT0012345678901',
          courier: CourierType.yt,
          urgency: UrgencyLevel.urgent,
          status: PackageStatus.arrived,
          addedAt: now.subtract(const Duration(hours: 1)),
          platform: 'cainiao',
          pickupCode: '12-3-4567',
          stationName: '测试驿站',
        );

    test('hasLocalAwaitingPickupWithCode：待取+码 → true；无码/已取 → false', () {
      expect(hasLocalAwaitingPickupWithCode([awaitingWithCode()]), isTrue);
      expect(
        hasLocalAwaitingPickupWithCode([
          awaitingWithCode().copyWith(pickupCode: ''),
        ]),
        isFalse,
      );
      expect(
        hasLocalAwaitingPickupWithCode([
          awaitingWithCode().copyWith(status: PackageStatus.pickedUp),
        ]),
        isFalse,
      );
      expect(hasLocalAwaitingPickupWithCode(const []), isFalse);
    });

    test('非 force + 本地有码 + 10 分钟前成功 → 跳过', () {
      expect(
        shouldSkipCainiaoWebView(
          force: false,
          hasLocalAwaitingWithCode: true,
          lastCainiaoSuccess: now.subtract(const Duration(minutes: 10)),
          now: now,
        ),
        isTrue,
      );
    });

    test('force=true → 不跳（下拉必跑阶段 1）', () {
      expect(
        shouldSkipCainiaoWebView(
          force: true,
          hasLocalAwaitingWithCode: true,
          lastCainiaoSuccess: now.subtract(const Duration(minutes: 1)),
          now: now,
        ),
        isFalse,
      );
    });

    test('从未成功 / 超过 20min / 本地无待取码 → 不跳', () {
      expect(
        shouldSkipCainiaoWebView(
          force: false,
          hasLocalAwaitingWithCode: true,
          lastCainiaoSuccess: null,
          now: now,
        ),
        isFalse,
      );
      expect(
        shouldSkipCainiaoWebView(
          force: false,
          hasLocalAwaitingWithCode: true,
          lastCainiaoSuccess: now.subtract(const Duration(minutes: 21)),
          now: now,
        ),
        isFalse,
      );
      expect(
        shouldSkipCainiaoWebView(
          force: false,
          hasLocalAwaitingWithCode: false,
          lastCainiaoSuccess: now.subtract(const Duration(minutes: 1)),
          now: now,
        ),
        isFalse,
      );
    });

    test('跳过时 seed 保留待取件+码，供 applyCainiaoPriority', () {
      final local = [
        awaitingWithCode(),
        _pkg(status: PackageStatus.transit, timeline: _timeline),
      ];
      final seed = localCainiaoSeedForPriority(local);
      expect(seed, hasLength(1));
      expect(seed.single.pickupCode, '12-3-4567');
    });
  });
}
