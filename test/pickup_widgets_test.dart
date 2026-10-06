import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pickup_app/core/models/package.dart';
import 'package:pickup_app/core/models/package_status.dart';
import 'package:pickup_app/ui/providers/package_provider.dart';
import 'package:pickup_app/ui/screens/home/widgets/pickup_widgets.dart';

/// 不碰 Hive 和系统通知的假 notifier。
class FakePackageList extends PackageListNotifier {
  FakePackageList(List<Package> initial) {
    state = initial;
  }

  @override
  void markPickedUp(String id) {
    state = [
      for (final p in state)
        if (p.id == id) p.copyWith(status: PackageStatus.pickedUp, pickedUpAt: DateTime(2026, 10, 7)) else p,
    ];
  }
}

final now = DateTime(2026, 10, 7, 12);

Package pkg({
  String id = 'p1',
  String code = '6-2-3021',
  DateTime? arrived,
  bool knownArrival = true,
  String? timeline,
}) =>
    Package(
      id: id,
      trackingNumber: 'TEST0001',
      courier: CourierType.zto,
      urgency: UrgencyLevel.normal,
      status: PackageStatus.arrived,
      // addedAt 故意设成「刚同步」：界面不能拿它当到站时间。
      addedAt: now,
      statusHistory: [
        if (knownArrival)
          StatusTransition(
            from: PackageStatus.transit,
            to: PackageStatus.arrived,
            timestamp: arrived ?? DateTime(2026, 10, 6, 12),
          ),
      ],
      rawTimelineJson: timeline,
      pickupCode: code,
      goodsName: '洗衣凝珠',
      platform: 'taobao',
      stationName: '菜鸟驿站',
    );

Future<FakePackageList> pumpCard(WidgetTester tester, Package p) => pumpCards(tester, [p]);

Future<FakePackageList> pumpCards(WidgetTester tester, List<Package> ps) async {
  final fake = FakePackageList(ps);
  await tester.pumpWidget(ProviderScope(
    overrides: [packageListProvider.overrideWith((ref) => fake)],
    child: MaterialApp(
      home: Scaffold(
        body: ListView(children: [for (final p in ps) PickupCodeCard(package: p, now: now)]),
      ),
    ),
  ));
  return fake;
}

/// 等 SnackBar 滑进来。
Future<void> settleIn(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 750));
}

void main() {
  test('arrivedAgoText', () {
    expect(arrivedAgoText(DateTime(2026, 10, 5, 12), now), '2天前到');
    expect(arrivedAgoText(DateTime(2026, 10, 7, 9), now), '3小时前到');
    expect(arrivedAgoText(DateTime(2026, 10, 7, 11, 50), now), '10分钟前到');
    expect(arrivedAgoText(now, now), '刚到');
  });

  testWidgets('取件码大字号（≥32）等宽显示，附商品、快递公司、到站时长', (tester) async {
    await pumpCard(tester, pkg());
    final code = tester.widget<Text>(find.text('6-2-3021'));
    expect(code.style!.fontSize, greaterThanOrEqualTo(32));
    expect(code.style!.fontFamily, 'monospace');
    expect(find.textContaining('洗衣凝珠'), findsOneWidget);
    expect(find.textContaining('1天前到'), findsOneWidget);
    expect(find.text('快过期'), findsNothing);
  });

  testWidgets('到站超过 3 天显示「快过期」', (tester) async {
    await pumpCard(tester, pkg(arrived: DateTime(2026, 10, 3, 12)));
    expect(find.text('快过期'), findsOneWidget);
  });

  testWidgets('不知道真实到站时间：不写「X前到」、不标快过期（不拿同步时间冒充）', (tester) async {
    await pumpCard(tester, pkg(knownArrival: false));
    expect(find.textContaining('前到'), findsNothing);
    expect(find.textContaining('刚到'), findsNothing);
    expect(find.text('快过期'), findsNothing);
  });

  testWidgets('没有取件码时提示「到站了，取件码没拿到」', (tester) async {
    await pumpCard(tester, pkg(code: ''));
    expect(find.text('到站了，取件码没拿到'), findsOneWidget);
  });

  testWidgets('点「已取」标记取件，点撤销恢复原状态', (tester) async {
    final fake = await pumpCard(tester, pkg());
    await tester.tap(find.text('已取'));
    await settleIn(tester);
    expect(fake.state.single.status, PackageStatus.pickedUp);
    expect(find.text('已标记取件'), findsOneWidget);

    await tester.tap(find.text('撤销'));
    await tester.pump();
    expect(fake.state.single.status, PackageStatus.arrived);
    expect(fake.state.single.pickedUpAt, isNull);
  });

  test('restorePackage：包裹已删除时不恢复，不会多出一份', () {
    final fake = FakePackageList([]);
    fake.restorePackage(pkg());
    expect(fake.state, isEmpty);
  });

  test('restorePackage：撤销窗口里状态已被改掉（不是已取）时不覆盖', () {
    final original = pkg();
    final fake = FakePackageList([original.copyWith(status: PackageStatus.archived)]);
    fake.restorePackage(original);
    expect(fake.state.single.status, PackageStatus.archived);
    expect(fake.state.length, 1);
  });

  testWidgets('撤销提示 5 秒后自动消失', (tester) async {
    final fake = await pumpCard(tester, pkg());
    await tester.tap(find.text('已取'));
    await settleIn(tester);
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(find.text('撤销'), findsNothing);
    expect(fake.state.single.status, PackageStatus.pickedUp);
  });

  testWidgets('5 秒内连续标记两个：合并成一条提示，撤销两个都恢复', (tester) async {
    final fake = await pumpCards(tester, [pkg(id: 'a', code: '1-1-1001'), pkg(id: 'b', code: '2-2-2002')]);
    await tester.tap(find.text('已取').first);
    await settleIn(tester);
    await tester.tap(find.text('已取').last);
    await settleIn(tester);
    expect(find.text('已标记取件 2 件'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1)); // 旧提示收起、新提示滑进来
    await tester.tap(find.text('撤销'));
    await tester.pump();
    expect(fake.state.map((p) => p.status), everyElement(PackageStatus.arrived));
  });

  testWidgets('撤销窗口里复制别的取件码，撤销入口还在', (tester) async {
    final fake = await pumpCards(tester, [pkg(id: 'a', code: '1-1-1001'), pkg(id: 'b', code: '2-2-2002')]);
    await tester.tap(find.text('已取').first);
    await settleIn(tester);
    await tester.tap(find.text('2-2-2002'));
    await tester.pump();
    expect(find.text('已复制'), findsOneWidget);
    expect(find.text('撤销'), findsOneWidget);

    await tester.tap(find.text('撤销'));
    await tester.pump();
    expect(fake.state.first.status, PackageStatus.arrived);
    await tester.pump(const Duration(seconds: 2)); // 让「已复制」的计时器走完
  });

  test('restorePackage：撤销窗口里同步进来新轨迹，撤销后状态恢复、新轨迹还在', () {
    final original = pkg(timeline: '[节点1]');
    final fake = FakePackageList([original]);
    fake.markPickedUp(original.id);
    // 模拟撤销窗口里来了一次同步：仍是已取，但多了新节点。
    fake.state = [fake.state.single.copyWith(rawTimelineJson: '[节点1,节点2]')];

    fake.restorePackage(original);
    final p = fake.state.single;
    expect(p.status, PackageStatus.arrived);
    expect(p.pickedUpAt, isNull);
    expect(p.rawTimelineJson, '[节点1,节点2]');
  });
}
