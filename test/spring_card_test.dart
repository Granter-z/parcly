import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pickup_app/ui/components/spring_card.dart';

Widget host(
        {VoidCallback? tap,
        VoidCallback? long,
        bool reduced = false,
        Widget? child,
        double pressScale = .975}) =>
    MaterialApp(
        home: MediaQuery(
      data: MediaQueryData(disableAnimations: reduced),
      child: Scaffold(
          body: Center(
              child: SpringCard(
                  onTap: tap,
                  onLongPress: long,
                  pressScale: pressScale,
                  child: child ??
                      const SizedBox(
                          width: 220, height: 160, child: Text('card'))))),
    ));
Finder get card => find.byType(SpringCard);
GestureDetector detector(WidgetTester t) => t.widget<GestureDetector>(
    find.descendant(of: card, matching: find.byType(GestureDetector)).first);
double scale(WidgetTester t) => t
    .widget<Transform>(
        find.descendant(of: card, matching: find.byType(Transform)).first)
    .transform
    .storage[0];
double q(WidgetTester t) => (scale(t) - 1) / (.975 - 1);
const spring = SpringDescription(mass: 1, stiffness: 520, damping: 32);

void main() {
  testWidgets('release and re-press preserve q and signed q/s trajectory',
      (t) async {
    await t.pumpWidget(host(tap: () {}));
    detector(t).onTapDown!(TapDownDetails());
    await t.pump();
    await t.pump(const Duration(milliseconds: 40));
    final press = SpringSimulation(spring, 0, 1, 0);
    expect(q(t), closeTo(press.x(.04), 1e-9));
    final atRelease = q(t);
    detector(t).onTapUp!(TapUpDetails(kind: PointerDeviceKind.touch));
    expect(q(t), closeTo(atRelease, 1e-6));
    await t.pump();
    final release = SpringSimulation(spring, atRelease, 0, press.dx(.04));
    await t.pump(const Duration(microseconds: 1));
    expect((q(t) - atRelease) / 1e-6, closeTo(press.dx(.04), 1e-3));
    await t.pump(const Duration(microseconds: 99999));
    expect(q(t), closeTo(release.x(.1), 1e-9));
    expect(release.dx(.1), lessThan(0));
    final before = q(t);
    detector(t).onTapDown!(TapDownDetails());
    expect(q(t), closeTo(before, 1e-6));
    await t.pump();
    await t.pump(const Duration(microseconds: 1));
    expect((q(t) - before) / 1e-6, closeTo(release.dx(.1), 1e-3));
    await t.pump(const Duration(milliseconds: 16));
    final repress = SpringSimulation(spring, before, 1, release.dx(.1));
    expect(q(t), closeTo(repress.x(.016001), 1e-8));
    detector(t).onTapCancel!();
    await t.pumpAndSettle();
    expect(scale(t), 1);
  });

  testWidgets(
      'real tap exactly once; cancel never commits; rapid 20 taps settle',
      (t) async {
    var taps = 0;
    await t.pumpWidget(host(tap: () => taps++));
    final gesture = await t.startGesture(t.getCenter(card));
    await t.pump(const Duration(milliseconds: 140));
    await gesture.cancel();
    await t.pumpAndSettle();
    expect(taps, 0);
    for (var i = 0; i < 20; i++) {
      await t.tap(card);
      await t.pump(const Duration(milliseconds: 16));
    }
    await t.pumpAndSettle();
    expect(taps, 20);
    expect(scale(t), 1);
  });

  testWidgets('long press and long-only preserve action without tap',
      (t) async {
    var taps = 0;
    var longs = 0;
    await t.pumpWidget(host(tap: () => taps++, long: () => longs++));
    await t.longPress(card);
    await t.pumpAndSettle();
    expect(taps, 0);
    expect(longs, 1);
    expect(scale(t), 1);
    await t.pumpWidget(host(long: () => longs++));
    final semantics = t.ensureSemantics();
    expect(
        t
            .getSemantics(find.text('card'))
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        false);
    await t.longPress(card);
    await t.pumpAndSettle();
    expect(longs, 2);
    semantics.dispose();
  });

  testWidgets('semantic activation goes through onTap once', (t) async {
    var taps = 0;
    final semantics = t.ensureSemantics();
    await t.pumpWidget(host(tap: () => taps++));
    t.binding.renderViews.first.owner!.semanticsOwner!.performAction(
        t.getSemantics(find.text('card')).id, SemanticsAction.tap);
    await t.pump();
    expect(taps, 1);
    expect(scale(t), 1);
    semantics.dispose();
  });

  testWidgets('child copy and confirm actions do not bubble to card',
      (t) async {
    var taps = 0;
    var copies = 0;
    var confirms = 0;
    await t.pumpWidget(host(
        tap: () => taps++,
        child: Row(children: [
          TextButton(onPressed: () => copies++, child: const Text('copy')),
          TextButton(onPressed: () => confirms++, child: const Text('confirm')),
        ])));
    await t.tap(find.text('copy'));
    await t.pumpAndSettle();
    await t.tap(find.text('confirm'));
    await t.pumpAndSettle();
    expect(taps, 0);
    expect(copies, 1);
    expect(confirms, 1);
  });

  testWidgets('scroll wins arena; no tap and scale returns', (t) async {
    var taps = 0;
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ListView(children: [
      SpringCard(
          onTap: () => taps++,
          child: const SizedBox(height: 200, child: Text('scroll'))),
      const SizedBox(height: 1400),
    ]))));
    await t.drag(card, const Offset(0, -160));
    await t.pumpAndSettle();
    expect(taps, 0);
    expect(scale(t), 1);
  });

  testWidgets(
      'reduce initially and mid-press: immediate 1; off does not replay',
      (t) async {
    var taps = 0;
    await t.pumpWidget(host(tap: () => taps++, reduced: true));
    detector(t).onTapDown!(TapDownDetails());
    await t.pump(const Duration(milliseconds: 100));
    expect(scale(t), 1);
    await t.pumpWidget(host(tap: () => taps++));
    detector(t).onTapDown!(TapDownDetails());
    await t.pump();
    await t.pump(const Duration(milliseconds: 40));
    expect(scale(t), lessThan(1));
    await t.pumpWidget(host(tap: () => taps++, reduced: true));
    expect(scale(t), 1);
    await t.pumpWidget(host(tap: () => taps++));
    await t.pump(const Duration(milliseconds: 100));
    expect(scale(t), 1);
    detector(t).onTap!();
    expect(taps, 1);
  });

  testWidgets(
      'disabled callbacks settle; pressScale update and dispose cancel safely',
      (t) async {
    await t.pumpWidget(host(tap: () {}));
    detector(t).onTapDown!(TapDownDetails());
    await t.pump();
    await t.pump(const Duration(milliseconds: 40));
    final before = q(t);
    await t.pumpWidget(host(tap: () {}, pressScale: .95));
    expect(scale(t), closeTo(1 + (.95 - 1) * before, 1e-9));
    await t.pumpWidget(host());
    expect(scale(t), 1);
    expect(detector(t).onTap, isNull);
    await t.pumpWidget(host(tap: () {}));
    detector(t).onTapDown!(TapDownDetails());
    await t.pump();
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 1));
    expect(t.takeException(), isNull);
  });
}
