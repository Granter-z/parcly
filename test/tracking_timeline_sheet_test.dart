// 物流详情抽屉的收回行为测试：点击抽屉外的区域应当收起抽屉。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pickup_app/core/models/package.dart';
import 'package:pickup_app/core/models/package_status.dart';
import 'package:pickup_app/platform/storage/pickup_point_alias_store.dart';
import 'package:pickup_app/ui/providers/pickup_point_alias_provider.dart';
import 'package:pickup_app/ui/screens/home/widgets/tracking_timeline_sheet.dart';

class _FakeAliasStore extends PickupPointAliasStore {
  _FakeAliasStore(this._aliases);

  final Map<String, String> _aliases;

  @override
  Map<String, String> readAll() => _aliases;
}

Package _pkg({
  PackageStatus status = PackageStatus.transit,
  String pickupCode = '',
  String? stationName,
}) =>
    Package(
      id: 'QA_1',
      trackingNumber: 'YT0000000000001',
      courier: CourierType.yt,
      urgency: UrgencyLevel.normal,
      status: status,
      addedAt: DateTime(2026, 10, 7),
      pickupCode: pickupCode,
      stationName: stationName,
      platform: 'pdd',
    );

Widget _host({
  Package? package,
  Map<String, String> aliases = const {},
}) =>
    ProviderScope(
      overrides: [
        pickupPointAliasStoreProvider.overrideWithValue(_FakeAliasStore(aliases)),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () =>
                    TrackingTimelineSheet.show(context, package ?? _pkg()),
                child: const Text('打开物流详情'),
              ),
            ),
          ),
        ),
      ),
    );

void main() {
  testWidgets('点击抽屉外的首页区域可收回物流详情抽屉', (tester) async {
    await tester.pumpWidget(_host());

    await tester.tap(find.text('打开物流详情'));
    await tester.pumpAndSettle();
    expect(find.byType(TrackingTimelineSheet), findsOneWidget);

    // 抽屉占屏幕下部 82%，上方留白处是点击收回区域
    await tester.tapAt(const Offset(200, 40));
    await tester.pumpAndSettle();
    expect(find.byType(TrackingTimelineSheet), findsNothing);
  });

  testWidgets('存在不同取件点别名时在取件凭证区展示「规范名（原名：原始名）」', (tester) async {
    const rawStation = '北门店';
    const canonical = '菜鸟驿站北门店';
    final arrivedPkg = _pkg(
      status: PackageStatus.arrived,
      pickupCode: '1-1-1111',
      stationName: rawStation,
    );

    await tester.pumpWidget(
      _host(
        package: arrivedPkg,
        aliases: const {rawStation: canonical},
      ),
    );

    await tester.tap(find.text('打开物流详情'));
    await tester.pumpAndSettle();

    expect(find.text('$canonical（原名：$rawStation）'), findsOneWidget);
  });
}
