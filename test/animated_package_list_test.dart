// 全部 fixture 为虚构；采样未 settle 的过渡，避免只验证最终态。
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pickup_app/core/models/package.dart';
import 'package:pickup_app/core/models/package_status.dart';
import 'package:pickup_app/ui/components/spring_card.dart';
import 'package:pickup_app/ui/components/staggered_entrance.dart';
import 'package:pickup_app/ui/providers/package_provider.dart';
import 'package:pickup_app/ui/screens/home/widgets/animated_package_list.dart';
import 'package:pickup_app/ui/screens/home/widgets/modern_package_card.dart';
import 'package:pickup_app/ui/screens/home/widgets/tracking_timeline_sheet.dart';

Package pkg(String id, {String? title, bool arrived = false}) => Package(
      id: id,
      goodsName: title ?? 'fixture-$id',
      trackingNumber: 'TEST-$id',
      courier: CourierType.yt,
      urgency: UrgencyLevel.normal,
      status: arrived ? PackageStatus.arrived : PackageStatus.transit,
      pickupCode: arrived ? '9-8-7000' : '',
      addedAt: DateTime(2026, 10, 7),
      platform: 'pdd',
    );

class FakePackages extends PackageListNotifier {
  final picked = <String>[];
  @override
  void markPickedUp(String id) => picked.add(id);
}

class Model {
  final List<Package> packages;
  final bool reduced;
  Model(this.packages, [this.reduced = false]);
}

class Harness {
  final model = ValueNotifier(Model([]));
  final scroll = ScrollController();
  Future<void> mount(WidgetTester t, List<Package> ps,
      {bool reduced = false, FakePackages? notifier}) async {
    model.value = Model(ps, reduced);
    await t.pumpWidget(ProviderScope(
      overrides: [
        if (notifier != null)
          packageListProvider.overrideWith((ref) => notifier)
      ],
      child: MaterialApp(
          home: ValueListenableBuilder<Model>(
        valueListenable: model,
        builder: (context, value, _) => MediaQuery(
          data: MediaQueryData(disableAnimations: value.reduced),
          child: Scaffold(
              body: CustomScrollView(controller: scroll, slivers: [
            AnimatedPackageList(
                packages: value.packages, padding: EdgeInsets.zero)
          ])),
        ),
      )),
    ));
  }

  Future<void> update(WidgetTester t, List<Package> ps,
      {bool reduced = false}) async {
    model.value = Model(ps, reduced);
    await t.pump();
  }
}

Finder row(String id) => find.byKey(ValueKey(id));
Finder card(String id) =>
    find.descendant(of: row(id), matching: find.byType(ModernPackageCard));
Finder spring(String id) =>
    find.descendant(of: row(id), matching: find.byType(SpringCard));
double progress(WidgetTester t, String id) =>
    t.widget<SizeTransition>(row(id)).sizeFactor.value;
double scale(WidgetTester t, String id) => t
    .widget<Transform>(
        find.descendant(of: spring(id), matching: find.byType(Transform)).first)
    .transform
    .storage[0];
List<String> ids(WidgetTester t) => t
    .widgetList<ModernPackageCard>(find.byType(ModernPackageCard))
    .map((c) => c.package.id)
    .toList();
List<String> active(WidgetTester t) => t
    .widgetList<ModernPackageCard>(find.byType(ModernPackageCard))
    .where((c) => c.interactive)
    .map((c) => c.package.id)
    .toList();

void main() {
  testWidgets('首屏即时可读，无交错或延迟任务', (t) async {
    final h = Harness();
    await h.mount(t, [pkg('A'), pkg('B')]);
    expect(ids(t), ['A', 'B']);
    expect(progress(t, 'A'), 1);
    expect(progress(t, 'B'), 1);
    expect(find.byType(StaggeredEntrance), findsNothing);
    expect(t.binding.transientCallbackCount, 0);
  });
  testWidgets('新增使用原生SliverList，16/40/100ms共享线性size+fade', (t) async {
    final h = Harness();
    await h.mount(t, [pkg('B')]);
    await h.update(t, [pkg('A'), pkg('B')]);
    var elapsed = 0;
    for (final ms in [16, 40, 100]) {
      await t.pump(Duration(milliseconds: ms - elapsed));
      elapsed = ms;
      expect(progress(t, 'A'), closeTo(ms / 380, 1e-6));
      final fade = t.widget<FadeTransition>(find
          .descendant(of: row('A'), matching: find.byType(FadeTransition))
          .first);
      expect(fade.opacity.value, progress(t, 'A'));
      expect(active(t), ['A', 'B']);
    }
    await t.pumpAndSettle();
    expect(progress(t, 'A'), 1);
    expect(find.byType(SliverList), findsOneWidget);
  });
  testWidgets('退出即禁用，380ms后移除', (t) async {
    final h = Harness();
    await h.mount(t, [pkg('A'), pkg('B')]);
    await h.update(t, [pkg('B')]);
    expect(ids(t), ['A', 'B']);
    expect(active(t), ['B']);
    await t.pump(const Duration(milliseconds: 100));
    expect(progress(t, 'A'), closeTo(280 / 380, 1e-6));
    await t.pumpAndSettle();
    expect(ids(t), ['B']);
  });
  testWidgets('纯重排+内容更新立刻对齐，不重播', (t) async {
    final h = Harness();
    await h.mount(t, [pkg('A'), pkg('B')]);
    final state = t.state(spring('A'));
    await h.update(t, [pkg('B', title: 'new-B'), pkg('A', title: 'new-A')]);
    expect(ids(t), ['B', 'A']);
    expect(find.text('new-B'), findsOneWidget);
    expect(find.text('new-A'), findsOneWidget);
    expect(t.state(spring('A')), same(state));
    expect(progress(t, 'A'), 1);
    expect(progress(t, 'B'), 1);
  });
  testWidgets('退出重入复用entry/controller/key/card，旧回调不能删除', (t) async {
    final h = Harness();
    await h.mount(t, [pkg('A'), pkg('B')]);
    final state = t.state(spring('A'));
    final controller = t.widget<SizeTransition>(row('A')).sizeFactor;
    await h.update(t, [pkg('B')]);
    await t.pump(const Duration(milliseconds: 100));
    final q = progress(t, 'A');
    await h.update(t, [pkg('B'), pkg('A', title: 'latest')]);
    expect(progress(t, 'A'), q);
    expect(ids(t), ['B', 'A']);
    expect(find.text('latest'), findsOneWidget);
    expect(t.state(spring('A')), same(state));
    expect(t.widget<SizeTransition>(row('A')).sizeFactor, same(controller));
    await t.pump(const Duration(milliseconds: 40));
    expect(progress(t, 'A'), greaterThan(q));
    await h.update(t, [pkg('B')]);
    await t.pump(const Duration(milliseconds: 16));
    await h.update(t, [pkg('A'), pkg('B')]);
    await t.pump(const Duration(milliseconds: 100));
    expect(active(t), ['A', 'B']);
    expect(card('A'), findsOneWidget);
    await t.pumpAndSettle();
    expect(ids(t), ['A', 'B']);
  });
  testWidgets('插入中删除按剩余距离退场；混合增删排用最新内容', (t) async {
    final h = Harness();
    await h.mount(t, [pkg('A'), pkg('B')]);
    await h.update(t, [pkg('X'), pkg('A'), pkg('B')]);
    await t.pump(const Duration(milliseconds: 40));
    final q = progress(t, 'X');
    await h.update(t, [pkg('B', title: 'updated'), pkg('C')]);
    expect(active(t), ['B', 'C']);
    expect(find.text('updated'), findsOneWidget);
    expect(progress(t, 'X'), q);
    await t.pump(const Duration(milliseconds: 16));
    expect(progress(t, 'X'), lessThan(q));
    await t.pump(const Duration(milliseconds: 40));
    expect(row('X'), findsNothing);
    await t.pumpAndSettle();
    expect(ids(t), ['B', 'C']);
  });
  testWidgets('按压A重排不串到B；退出中按下不执行新动作', (t) async {
    final h = Harness();
    await h.mount(t, [pkg('A'), pkg('B')]);
    final gesture = await t.startGesture(t.getCenter(spring('A')));
    await t.pump(const Duration(milliseconds: 140));
    await t.pump();
    await t.pump(const Duration(milliseconds: 40));
    expect(scale(t, 'A'), lessThan(1));
    await h.update(t, [pkg('B'), pkg('A')]);
    expect(scale(t, 'A'), lessThan(1));
    expect(scale(t, 'B'), 1);
    await h.update(t, [pkg('B')]);
    await gesture.up();
    await t.pump(const Duration(milliseconds: 100));
    expect(find.byType(TrackingTimelineSheet), findsNothing);
    await t.pumpAndSettle();
  });
  testWidgets('退出禁pointer/long/semantics/focus和旧action；重入仅一个语义卡', (t) async {
    final semantics = t.ensureSemantics();
    final h = Harness();
    await h.mount(t, [pkg('A'), pkg('B')]);
    final old = t.widget<SpringCard>(spring('A'));
    final node = t.getSemantics(find.text('fixture-A')).id;
    await h.update(t, [pkg('B')]);
    expect(t.widget<ModernPackageCard>(card('A')).interactive, false);
    expect(t.widget<SpringCard>(spring('A')).onTap, isNull);
    expect(
        t
            .widget<IgnorePointer>(find
                .descendant(of: row('A'), matching: find.byType(IgnorePointer))
                .first)
            .ignoring,
        true);
    expect(
        t
            .widget<ExcludeFocus>(find
                .descendant(of: row('A'), matching: find.byType(ExcludeFocus))
                .first)
            .excluding,
        true);
    expect(find.bySemanticsLabel(RegExp('fixture-A')), findsNothing);
    old.onTap!();
    old.onLongPress!();
    t.binding.renderViews.first.owner!.semanticsOwner!
        .performAction(node, SemanticsAction.tap);
    await t.pump(const Duration(milliseconds: 16));
    expect(find.byType(TrackingTimelineSheet), findsNothing);
    expect(find.text('删除该包裹'), findsNothing);
    await h.update(t, [pkg('A'), pkg('B')]);
    old.onTap!();
    old.onLongPress!();
    await t.pump(const Duration(milliseconds: 40));
    expect(find.byType(TrackingTimelineSheet), findsNothing);
    expect(find.bySemanticsLabel(RegExp('fixture-A')), findsOneWidget);
    await t.pumpAndSettle();
    semantics.dispose();
  });
  testWidgets('确认取件异步等待中退出重入，旧generation不得提交', (t) async {
    final fake = FakePackages();
    final h = Harness();
    await h.mount(t, [pkg('A', arrived: true)], notifier: fake);
    await t.tap(find.text('确认取件'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 40));
    await h.update(t, []);
    await t.pump(const Duration(milliseconds: 16));
    await h.update(t, [pkg('A', arrived: true)]);
    await t.pumpAndSettle();
    expect(fake.picked, isEmpty);
    await t.tap(find.text('确认取件'));
    await t.pumpAndSettle();
    expect(fake.picked, ['A']);
    expect(find.byType(TrackingTimelineSheet), findsNothing);
  });
  testWidgets('复制码正常不冒泡；按住子复制时退出不写clipboard', (t) async {
    final calls = <String>[];
    t.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      calls.add(call.method);
      return null;
    });
    addTearDown(() => t.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    final h = Harness();
    await h.mount(t, [pkg('A', arrived: true)]);
    await t.tap(find.text('9-8-7000'));
    await t.pump();
    await t.pump(const Duration(seconds: 2));
    expect(calls.where((m) => m == 'Clipboard.setData').length, 1);
    expect(calls.where((m) => m == 'HapticFeedback.vibrate').length, 1);
    expect(find.byType(TrackingTimelineSheet), findsNothing);
    final gesture = await t.startGesture(t.getCenter(find.text('9-8-7000')));
    await t.pump(const Duration(milliseconds: 100));
    await h.update(t, []);
    await gesture.up();
    await t.pumpAndSettle();
    expect(calls.where((m) => m == 'Clipboard.setData').length, 1);
  });
  testWidgets('退出时已聚焦后代失焦，重入不会恢复旧焦点', (t) async {
    final h = Harness();
    await h.mount(t, [pkg('A', arrived: true), pkg('B')]);
    final context = t.element(find.text('确认取件'));
    final node = Focus.of(context);
    node.requestFocus();
    await t.pump();
    expect(node.hasFocus, true);
    await h.update(t, [pkg('B')]);
    await t.pump(const Duration(milliseconds: 16));
    expect(node.hasFocus, false);
    await h.update(t, [pkg('A', arrived: true), pkg('B')]);
    await t.pump(const Duration(milliseconds: 40));
    expect(node.hasFocus, false);
    await t.pumpAndSettle();
  });
  testWidgets('减少动态效果插入/退出中即终态，关闭不重播', (t) async {
    final h = Harness();
    await h.mount(t, [pkg('A')]);
    await h.update(t, [pkg('B'), pkg('A')]);
    await t.pump(const Duration(milliseconds: 40));
    await h.update(t, [pkg('B')], reduced: true);
    expect(ids(t), ['B']);
    expect(progress(t, 'B'), 1);
    expect(t.binding.transientCallbackCount, 0);
    await h.update(t, [pkg('B')]);
    await t.pump(const Duration(milliseconds: 100));
    expect(progress(t, 'B'), 1);
    await h.update(t, [pkg('C')], reduced: true);
    expect(ids(t), ['C']);
    expect(progress(t, 'C'), 1);
    await h.update(t, [], reduced: true);
    expect(ids(t), isEmpty);
  });
  testWidgets('20轮混合更新、空/单列表与离页无ticker', (t) async {
    final h = Harness();
    await h.mount(t, []);
    for (var i = 0; i < 20; i++) {
      await h.update(t, [pkg('A', title: 'round-$i'), if (i.isEven) pkg('B')]);
      await t.pump(const Duration(milliseconds: 16));
      expect(card('A'), findsOneWidget);
      expect(find.text('round-$i'), findsOneWidget);
      await h.update(t, [if (i.isEven) pkg('B')]);
      await t.pump(const Duration(milliseconds: 40));
    }
    await h.update(t, []);
    await t.pumpAndSettle();
    expect(ids(t), isEmpty);
    await h.update(t, [pkg('A')]);
    await t.pump(const Duration(milliseconds: 16));
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 1));
    expect(t.takeException(), isNull);
    expect(t.binding.transientCallbackCount, 0);
  });
  testWidgets('长列表原生惰性滚动；离屏退场也释放，offset不被重置', (t) async {
    final h = Harness();
    final ps = List.generate(80, (i) => pkg('L$i'));
    await h.mount(t, ps);
    expect(ids(t).length, lessThan(15));
    h.scroll.jumpTo(3000);
    await t.pump();
    final before = h.scroll.offset;
    final visible = ids(t).first;
    await h.update(t, ps.where((p) => p.id != 'L79').toList());
    await t.pump(const Duration(milliseconds: 100));
    expect(h.scroll.offset, before);
    expect(card(visible), findsOneWidget);
    await t.pumpAndSettle();
    await h.update(t, [pkg('L79'), ...ps.where((p) => p.id != 'L79')]);
    h.scroll.jumpTo(0);
    await t.pump();
    await t.pump(const Duration(milliseconds: 16));
    // 离屏退出已结束，重新出现必须是新入场而非还原旧的完成controller。
    expect(progress(t, 'L79'), lessThan(1));
    await t.pumpAndSettle();
    expect(progress(t, 'L79'), 1);
  });
}
