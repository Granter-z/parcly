// P25：撤销已取 — markPickedUp 后 restorePackage 清空 pickedUpAt 并恢复待处理状态。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pickup_app/core/models/package.dart';
import 'package:pickup_app/core/models/package_status.dart';
import 'package:pickup_app/ui/providers/package_provider.dart';
import 'package:pickup_app/ui/screens/home/widgets/completed_packages_sheet.dart';

Package _arrived({
  String id = 'p1',
  PackageStatus status = PackageStatus.arrived,
  DateTime? pickedUpAt,
}) =>
    Package(
      id: id,
      trackingNumber: 'YT001',
      courier: CourierType.yt,
      pickupCode: '1-2-3001',
      urgency: UrgencyLevel.normal,
      status: status,
      addedAt: DateTime(2026, 10, 6, 10),
      pickedUpAt: pickedUpAt,
      goodsName: '测试洗衣液',
      platform: 'taobao',
      stationName: '测试驿站',
    );

/// 不碰 Hive / 系统通知；restorePackage 走真实实现（_box == null 时 _sync 空操作）。
class FakePackageList extends PackageListNotifier {
  FakePackageList(List<Package> initial) {
    state = initial;
  }

  @override
  void markPickedUp(String id) {
    state = [
      for (final p in state)
        if (p.id == id)
          p.copyWith(
            status: PackageStatus.pickedUp,
            pickedUpAt: DateTime(2026, 10, 7, 12),
            statusHistory: [
              ...p.statusHistory,
              StatusTransition(
                from: p.status,
                to: PackageStatus.pickedUp,
                timestamp: DateTime(2026, 10, 7, 12),
                reason: 'user_mark_picked_up',
              ),
            ],
          )
        else
          p,
    ];
  }
}

/// 与首页卡片相同的 5 秒撤销 SnackBar 路径。
void markPickedUpWithUndo(BuildContext context, WidgetRef ref, Package pkg) {
  final notifier = ref.read(packageListProvider.notifier);
  notifier.markPickedUp(pkg.id);
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Text('已标记取件「${pkg.goodsName ?? "包裹"}」'),
      duration: const Duration(seconds: 5),
      behavior: SnackBarBehavior.floating,
      persist: false,
      action: SnackBarAction(
        label: '撤销',
        onPressed: () => notifier.restorePackage(pkg.id),
      ),
    ),
  );
}

void main() {
  test('markPickedUp → restorePackage：清空 pickedUpAt，状态回到 arrived', () {
    final n = FakePackageList([_arrived()]);
    n.markPickedUp('p1');
    expect(n.state.single.status, PackageStatus.pickedUp);
    expect(n.state.single.pickedUpAt, isNotNull);

    n.restorePackage('p1');
    expect(n.state.single.status, PackageStatus.arrived);
    expect(n.state.single.pickedUpAt, isNull);
    expect(n.state.single.pickupCode, '1-2-3001');
    expect(n.state.single.goodsName, '测试洗衣液');
  });

  test('restorePackage：非已取状态不改动', () {
    final n = FakePackageList([_arrived()]);
    n.restorePackage('p1');
    expect(n.state.single.status, PackageStatus.arrived);
    expect(n.state.single.pickedUpAt, isNull);
  });

  test('restorePackage：从 statusHistory 恢复到 delivering', () {
    final n = FakePackageList([
      _arrived(status: PackageStatus.delivering),
    ]);
    n.markPickedUp('p1');
    n.restorePackage('p1');
    expect(n.state.single.status, PackageStatus.delivering);
    expect(n.state.single.pickedUpAt, isNull);
  });

  test('撤销后离开已完成列表，回到 pending', () {
    final n = FakePackageList([_arrived()]);
    n.markPickedUp('p1');
    expect(n.state.where((p) => p.status.isCompleted), hasLength(1));

    n.restorePackage('p1');
    expect(n.state.where((p) => p.status.isCompleted), isEmpty);
    expect(n.state.where((p) => p.status.isPending), hasLength(1));
  });

  testWidgets('首页 5 秒 SnackBar「撤销」可恢复', (tester) async {
    final fake = FakePackageList([_arrived()]);
    final pkg = fake.state.single;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          packageListProvider.overrideWith((ref) => fake),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => Center(
                child: ElevatedButton(
                  onPressed: () => markPickedUpWithUndo(context, ref, pkg),
                  child: const Text('确认取件'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.tap(find.text('确认取件'));
    await tester.pump(); // 建 SnackBar
    await tester.pump(const Duration(milliseconds: 50));
    expect(fake.state.single.status, PackageStatus.pickedUp);
    expect(find.textContaining('已标记取件'), findsOneWidget);
    expect(find.byType(SnackBarAction), findsOneWidget);

    // 直接调 action，避免 floating SnackBar 在默认视口里点不中
    final action = tester.widget<SnackBarAction>(find.byType(SnackBarAction));
    action.onPressed();
    await tester.pump();
    expect(fake.state.single.status, PackageStatus.arrived);
    expect(fake.state.single.pickedUpAt, isNull);
  });

  testWidgets('已完成抽屉「撤销已取」可触发 restorePackage', (tester) async {
    final fake = FakePackageList([
      _arrived(
        status: PackageStatus.pickedUp,
        pickedUpAt: DateTime(2026, 10, 7, 9),
      ),
    ]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          packageListProvider.overrideWith((ref) => fake),
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
      ),
    );

    await tester.tap(find.text('打开已完成'));
    // 有 SpringCard 时不用 pumpAndSettle（无界弹簧动画不会停）
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(CompletedPackagesSheet), findsOneWidget);
    expect(find.byTooltip('撤销已取'), findsOneWidget);

    await tester.tap(find.byTooltip('撤销已取'));
    await tester.pump();
    expect(fake.state.single.status, PackageStatus.arrived);
    expect(fake.state.single.pickedUpAt, isNull);
  });
}
