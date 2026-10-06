import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pickup_app/platform/connectors/connector_manager.dart';
import 'package:pickup_app/ui/components/platform_status_bar.dart';
import 'package:pickup_app/ui/providers/platform_auth_status_provider.dart';

Future<void> pumpBar(
  WidgetTester tester,
  Map<String, PlatformAuthStatus> statuses, {
  bool syncing = false,
}) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [
        platformAuthStatusProvider.overrideWith((ref, p) => statuses[p]!),
        syncStateProvider.overrideWith((ref) => syncing),
      ],
      child: const MaterialApp(home: Scaffold(body: PlatformStatusBar())),
    ),
  );
}

Color? barColor(WidgetTester tester) {
  final box = tester.widget<AnimatedContainer>(find.byType(AnimatedContainer));
  return (box.decoration as BoxDecoration?)?.color;
}

void main() {
  const ok = PlatformAuthStatus.ok;

  testWidgets('全部正常：只显示平台名，没有红底', (tester) async {
    await pumpBar(tester, {'pdd': ok, 'jd': ok, 'taobao': ok});
    expect(find.text('拼多多'), findsOneWidget);
    expect(find.text('京东'), findsOneWidget);
    expect(find.text('淘宝'), findsOneWidget);
    expect(find.textContaining('需重登'), findsNothing);
    expect(barColor(tester), Colors.transparent);
  });

  testWidgets('淘宝掉线：明确写出是淘宝需重登，整条变红底，其他平台不受影响', (tester) async {
    await pumpBar(tester, {'pdd': ok, 'jd': ok, 'taobao': PlatformAuthStatus.needsRelogin});
    expect(find.text('淘宝 需重登'), findsOneWidget);
    expect(find.text('京东'), findsOneWidget);
    expect(find.text('拼多多'), findsOneWidget);
    expect(barColor(tester), isNot(Colors.transparent));
  });

  testWidgets('没绑定的平台显示「去绑定」', (tester) async {
    await pumpBar(tester, {'pdd': PlatformAuthStatus.unbound, 'jd': ok, 'taobao': ok});
    expect(find.text('拼多多 去绑定'), findsOneWidget);
  });

  testWidgets('同步中：正常平台显示转圈，点击不响应', (tester) async {
    await pumpBar(tester, {'pdd': ok, 'jd': ok, 'taobao': ok}, syncing: true);
    expect(find.byType(CircularProgressIndicator), findsNWidgets(3));
    final inks = tester.widgetList<InkWell>(find.byType(InkWell));
    expect(inks.every((w) => w.onTap == null), isTrue);
  });

  testWidgets('同步失败（不是掉线）：显示「同步失败」，不显示需重登，也没有红底', (tester) async {
    await pumpBar(tester, {'pdd': ok, 'jd': ok, 'taobao': PlatformAuthStatus.syncFailed});
    expect(find.text('淘宝 同步失败'), findsOneWidget);
    expect(find.textContaining('需重登'), findsNothing);
    expect(barColor(tester), Colors.transparent);
  });

  testWidgets('读屏每个平台只读一遍，点击区域不小于 44', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpBar(tester, {'pdd': ok, 'jd': ok, 'taobao': PlatformAuthStatus.needsRelogin});
    expect(find.bySemanticsLabel('淘宝 需重登'), findsOneWidget);
    for (final e in find.byType(InkWell).evaluate()) {
      expect(tester.getSize(find.byWidget(e.widget)).height, greaterThanOrEqualTo(44));
    }
    handle.dispose();
  });
}
