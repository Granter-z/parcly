// 首页「已完成」抽屉的收回行为测试：点击抽屉外的区域应当收起抽屉。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pickup_app/core/models/package.dart';
import 'package:pickup_app/core/models/package_status.dart';
import 'package:pickup_app/platform/storage/pickup_point_alias_store.dart';
import 'package:pickup_app/ui/providers/package_provider.dart';
import 'package:pickup_app/ui/providers/pickup_point_alias_provider.dart';
import 'package:pickup_app/ui/screens/home/widgets/completed_packages_sheet.dart';

class _FakeAliasStore extends PickupPointAliasStore {
  _FakeAliasStore(this._aliases);

  final Map<String, String> _aliases;

  @override
  Map<String, String> readAll() => _aliases;
}

Widget _host({
  List<Package> completed = const <Package>[],
  Map<String, String> aliases = const {},
}) =>
    ProviderScope(
      overrides: [
        completedPackagesProvider.overrideWithValue(completed),
        pickupPointAliasStoreProvider.overrideWithValue(_FakeAliasStore(aliases)),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => CompletedPackagesSheet.show(context),
                child: const Text('打开已完成'),
              ),
            ),
          ),
        ),
      ),
    );

void main() {
  testWidgets('点击抽屉外的首页区域可收回「已完成」菜单', (tester) async {
    await tester.pumpWidget(_host());

    await tester.tap(find.text('打开已完成'));
    await tester.pumpAndSettle();
    expect(find.byType(CompletedPackagesSheet), findsOneWidget);

    // 抽屉只占屏幕下部 65%，上方留白处是点击收回区域
    await tester.tapAt(const Offset(200, 60));
    await tester.pumpAndSettle();
    expect(find.byType(CompletedPackagesSheet), findsNothing);
  });

  testWidgets('存在取件点别名时展示规范别名', (tester) async {
    final pkg = Package(
      id: 'TB_1000000000000000001',
      trackingNumber: 'YT0000000000001',
      courier: CourierType.yt,
      urgency: UrgencyLevel.normal,
      status: PackageStatus.pickedUp,
      addedAt: DateTime(2026, 10, 7),
      pickedUpAt: DateTime(2026, 10, 7, 12),
      goodsName: '测试商品',
      stationName: '北门店',
      platform: 'taobao',
    );

    await tester.pumpWidget(
      _host(
        completed: [pkg],
        aliases: const {'北门店': '菜鸟驿站北门店'},
      ),
    );

    await tester.tap(find.text('打开已完成'));
    await tester.pumpAndSettle();

    expect(find.text('圆通速递 · YT0000000000001 · 菜鸟驿站北门店'), findsOneWidget);
    expect(find.text('圆通速递 · YT0000000000001 · 北门店'), findsNothing);
  });
}
