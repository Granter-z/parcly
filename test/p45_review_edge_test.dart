import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'animated_package_list_test.dart'
    show Harness, FakePackages, pkg, spring, ids;

void main() {
  for (final action in ['复制运单号', '删除该包裹']) {
    for (final phase in ['normal', 'exit', 'reenter']) {
      testWidgets('menu $action / $phase validates opening generation',
          (t) async {
        final fake = FakePackages();
        final copies = <String>[];
        t.binding.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            copies.add((call.arguments as Map)['text'] as String);
          }
          return null;
        });
        addTearDown(() => t.binding.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null));
        final h = Harness();
        await h.mount(t, [pkg('A')], notifier: fake);
        await t.longPress(spring('A'));
        await t.pumpAndSettle();
        expect(find.text(action), findsOneWidget);
        if (phase != 'normal') {
          await h.update(t, []);
          await t.pump(const Duration(milliseconds: 40));
          if (phase == 'reenter') {
            await h.update(t, [pkg('A', title: 'new-generation')]);
          }
          await t.pumpAndSettle();
          // 不强关已经打开的路由；仅在用户点选时拒绝失效动作。
          expect(find.text(action), findsOneWidget);
        }
        await t.tap(find.text(action));
        await t.pumpAndSettle();
        expect(fake.removed,
            phase == 'normal' && action == '删除该包裹' ? ['A'] : isEmpty);
        expect(copies,
            phase == 'normal' && action == '复制运单号' ? ['TEST-A'] : isEmpty);
        expect(find.text('删除该包裹'), findsNothing);
        expect(t.takeException(), isNull);
      });
    }
  }
  testWidgets('review: zero-progress insertion removed immediately is safe',
      (t) async {
    final h = Harness();
    await h.mount(t, []);
    await h.update(t, [pkg('A')]);
    await h.update(t, []);
    await t.pumpAndSettle();
    expect(ids(t), isEmpty);
    expect(t.takeException(), isNull);
  });
}
