import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pickup_app/core/models/package.dart';
import 'package:pickup_app/core/models/package_status.dart';
import 'package:pickup_app/ui/components/spring_card.dart';
import 'package:pickup_app/ui/providers/package_provider.dart';
import 'package:pickup_app/ui/screens/home/widgets/completed_packages_sheet.dart';

Package fixture(String id) => Package(
      id: id,
      trackingNumber: 'UI-SESSION-$id',
      courier: CourierType.yt,
      status: PackageStatus.pickedUp,
      pickedUpAt: DateTime(2026, 11, 7),
      urgency: UrgencyLevel.normal,
      addedAt: DateTime(2026, 11, 7),
      goodsName: 'Session fixture $id',
      platform: 'pdd',
    );

// Observe submissions, but execute the original provider methods unchanged.
int nextFixtureId = 0;

class ObservedNotifier extends PackageListNotifier {
  final String id = 'MENU-SESSION-${++nextFixtureId}';
  ObservedNotifier() {
    state = [fixture(id)];
  }
  int restores = 0;
  int removals = 0;
  @override
  void restorePackage(String id) {
    restores++;
    super.restorePackage(id);
  }

  @override
  void removePackage(String id) {
    removals++;
    super.removePackage(id);
  }
}

Future<void> mount(WidgetTester tester, ObservedNotifier notifier) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [packageListProvider.overrideWith((ref) => notifier)],
    child: MaterialApp(
        home: Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                    onPressed: () => CompletedPackagesSheet.show(context),
                    child: const Text('Open completed'))))),
  ));
  await tester.tap(find.text('Open completed'));
  await tester.pumpAndSettle();
}

Future<void> openMenu(WidgetTester tester) async {
  await tester.longPress(find.byType(SpringCard).first);
  await tester.pumpAndSettle();
  expect(find.text('删除该包裹'), findsOneWidget);
}

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (_) async => null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('dexterous.com/flutter/local_notifications'),
            (_) async => null);
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('dexterous.com/flutter/local_notifications'),
            null);
  });

  for (final action in ['删除该包裹', '撤销已取']) {
    for (final phase in [
      'normal',
      'content-update',
      'exit',
      'reenter',
      'no-pump-reenter',
      'remove-origin-route',
      'rebind-row'
    ]) {
      testWidgets('$action session $phase preserves submission authority',
          (tester) async {
        final n = ObservedNotifier();
        await mount(tester, n);
        final originContext =
            tester.element(find.byType(CompletedPackagesSheet));
        final originRoute = ModalRoute.of(originContext)!;
        final navigator = Navigator.of(originContext);
        await openMenu(tester);
        if (phase == 'content-update') {
          n.addPackage(
              fixture(n.id).copyWith(goodsName: 'Updated without exit'));
          await tester.pump();
        } else if (phase == 'remove-origin-route') {
          // Programmatic route-lifecycle boundary, NOT user input through a modal.
          navigator.removeRoute(originRoute);
          await tester.pump();
        } else if (phase == 'rebind-row') {
          n.addPackage(
              fixture('${n.id}-B').copyWith(pickedUpAt: DateTime(2026, 11, 8)));
          await tester.pumpAndSettle();
        } else if (phase != 'normal') {
          n.restorePackage(n.id);
          if (phase != 'no-pump-reenter') {
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 40));
          }
          if (phase == 'reenter' || phase == 'no-pump-reenter') {
            n.markPickedUp(n.id);
            await tester.pumpAndSettle();
          }
        }
        final restoreCount = n.restores;
        final removeCount = n.removals;
        final before = n.state.toList();
        // Invalidating the card never forcibly closes the independent menu.
        expect(find.text(action), findsOneWidget);
        await tester.tap(find.text(action));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('删除该包裹'), findsNothing);
        final allowed = phase == 'normal' || phase == 'content-update';
        if (!allowed) {
          expect(n.restores, restoreCount);
          expect(n.removals, removeCount);
          expect(n.state, orderedEquals(before));
          expect(find.text('已撤销取件，包裹回到待取列表'), findsNothing);
        } else if (action == '删除该包裹') {
          expect(n.removals, removeCount + 1);
          expect(n.state, isEmpty);
        } else {
          expect(n.restores, restoreCount + 1);
          expect(n.state.single.status, PackageStatus.arrived);
          expect(n.state.single.pickedUpAt, isNull);
          expect(find.text('已撤销取件，包裹回到待取列表'), findsOneWidget);
          if (phase == 'content-update') {
            expect(n.state.single.goodsName, 'Updated without exit');
          }
        }
        if (phase != 'remove-origin-route') {
          expect(find.byType(CompletedPackagesSheet), findsOneWidget);
        }
      });
    }
  }

  testWidgets('dismissed menu callbacks are retired; fresh repeated menus work',
      (tester) async {
    final n = ObservedNotifier();
    await mount(tester, n);
    for (var i = 0; i < 5; i++) {
      await openMenu(tester);
      final staleDelete = tester
          .widget<ListTile>(find.widgetWithText(ListTile, '删除该包裹'))
          .onTap!;
      Navigator.of(tester.element(find.text('删除该包裹'))).pop();
      await tester.pumpAndSettle();
      n.restorePackage(n.id);
      n.markPickedUp(n.id);
      await tester.pumpAndSettle();
      final restores = n.restores;
      staleDelete();
      await tester.pumpAndSettle();
      expect(n.removals, 0);
      expect(n.restores, restores);
      expect(n.state.single.status, PackageStatus.pickedUp);
      expect(find.byType(CompletedPackagesSheet), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    await openMenu(tester);
    await tester.tap(find.text('删除该包裹'));
    await tester.pumpAndSettle();
    expect(n.removals, 1);
    expect(n.state, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('old callback cannot pop another route above its own menu',
      (tester) async {
    final n = ObservedNotifier();
    await mount(tester, n);
    await openMenu(tester);
    final menuContext = tester.element(find.text('删除该包裹'));
    final oldDelete =
        tester.widget<ListTile>(find.widgetWithText(ListTile, '删除该包裹')).onTap!;
    final navigator = Navigator.of(menuContext);
    navigator.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('New top route'))));
    await tester.pumpAndSettle();
    oldDelete();
    await tester.pumpAndSettle();
    expect(find.text('New top route'), findsOneWidget);
    expect(n.removals, 0);
    expect(n.restores, 0);
    expect(tester.takeException(), isNull);
  });
}
