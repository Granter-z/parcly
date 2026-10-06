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

Package pkg({String code = '6-2-3021', DateTime? addedAt}) => Package(
      id: 'p1',
      trackingNumber: 'TEST0001',
      courier: CourierType.zto,
      urgency: UrgencyLevel.normal,
      status: PackageStatus.arrived,
      addedAt: addedAt ?? DateTime(2026, 10, 6, 12),
      pickupCode: code,
      goodsName: '洗衣凝珠',
      platform: 'taobao',
      stationName: '菜鸟驿站',
    );

Future<FakePackageList> pumpCard(WidgetTester tester, Package p) async {
  final fake = FakePackageList([p]);
  await tester.pumpWidget(ProviderScope(
    overrides: [packageListProvider.overrideWith((ref) => fake)],
    child: MaterialApp(
      home: Scaffold(body: PickupCodeCard(package: p, now: now)),
    ),
  ));
  return fake;
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
    await pumpCard(tester, pkg(addedAt: DateTime(2026, 10, 3, 12)));
    expect(find.text('快过期'), findsOneWidget);
  });

  testWidgets('没有取件码时提示「到站了，取件码没拿到」', (tester) async {
    await pumpCard(tester, pkg(code: ''));
    expect(find.text('到站了，取件码没拿到'), findsOneWidget);
  });

  testWidgets('点「已取」标记取件，点撤销恢复原状态', (tester) async {
    final fake = await pumpCard(tester, pkg());
    await tester.tap(find.text('已取'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 750)); // 等 SnackBar 滑进来
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
}
