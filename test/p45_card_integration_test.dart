import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pickup_app/core/models/package.dart';
import 'package:pickup_app/core/models/package_status.dart';
import 'package:pickup_app/ui/components/spring_card.dart';
import 'package:pickup_app/ui/providers/package_provider.dart';
import 'package:pickup_app/ui/screens/home/widgets/completed_packages_sheet.dart';
import 'package:pickup_app/ui/screens/home/widgets/modern_package_card.dart';
import 'package:pickup_app/ui/screens/home/widgets/tracking_timeline_sheet.dart';

Package fixture(PackageStatus status) => Package(
      id: 'QA_MOTION',
      trackingNumber: 'QA-TRACKING',
      goodsName: '虚构测试商品',
      courier: CourierType.yt,
      urgency: UrgencyLevel.normal,
      status: status,
      pickupCode: '9-8-7000-123',
      addedAt: DateTime(2026, 10, 7),
      platform: 'pdd',
    );

class FakePackages extends PackageListNotifier {
  FakePackages() {
    state = [fixture(PackageStatus.pickedUp)];
  }
  final restored = <String>[];
  @override
  void restorePackage(String id) => restored.add(id);
}

void main() {
  testWidgets('已完成共享SpringCard：点击详情、长按撤销、子撤销不冒泡', (t) async {
    final fake = FakePackages();
    final haptics = <dynamic>[];
    t.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') haptics.add(call.arguments);
      return null;
    });
    addTearDown(() => t.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    await t.pumpWidget(ProviderScope(
        overrides: [
          packageListProvider.overrideWith((ref) => fake),
        ],
        child: MaterialApp(
            home: Scaffold(
                body: Builder(
                    builder: (context) => TextButton(
                        onPressed: () => CompletedPackagesSheet.show(context),
                        child: const Text('open')))))));
    await t.tap(find.text('open'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 800));
    await t.pumpAndSettle();
    await t.tap(find.byType(SpringCard));
    await t.pumpAndSettle();
    expect(find.byType(TrackingTimelineSheet), findsOneWidget);
    Navigator.of(t.element(find.byType(TrackingTimelineSheet))).pop();
    await t.pumpAndSettle();
    haptics.clear();
    await t.longPress(find.byType(SpringCard));
    await t.pumpAndSettle();
    expect(find.text('恢复到待取件，可再次取件'), findsOneWidget);
    await t.tap(find.text('恢复到待取件，可再次取件'));
    await t.pumpAndSettle();
    expect(fake.restored, ['QA_MOTION']);
    expect(
        haptics.where((h) => h == 'HapticFeedbackType.mediumImpact').length, 1);
    haptics.clear();
    await t.tap(find.byTooltip('撤销已取'));
    await t.pumpAndSettle();
    expect(fake.restored.length, 2);
    expect(find.byType(TrackingTimelineSheet), findsNothing);
    expect(
        haptics.where((h) => h == 'HapticFeedbackType.lightImpact').length, 1);
  });
  testWidgets('窄屏大字完整码可复制；按压中几何不裁断且保留字号比例', (t) async {
    final copies = <dynamic>[];
    t.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copies.add(call.arguments);
      return null;
    });
    addTearDown(() => t.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    t.view.physicalSize = const Size(360, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(ProviderScope(
        child: MaterialApp(
            home: MediaQuery(
      data: const MediaQueryData(
          size: Size(360, 900), textScaler: TextScaler.linear(1.5)),
      child: Scaffold(
          body: SingleChildScrollView(
              child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: ModernPackageCard(
                      package: fixture(PackageStatus.arrived))))),
    ))));
    expect(find.text('9-8-7000-123'), findsOneWidget);
    expect(t.takeException(), isNull);
    final text = t.widget<Text>(find.text('9-8-7000-123'));
    expect(text.overflow, isNot(TextOverflow.ellipsis));
    final unpressedParagraph =
        t.renderObject<RenderParagraph>(find.text('9-8-7000-123'));
    final unpressedBoxes = unpressedParagraph.getBoxesForSelection(
        const TextSelection(
            baseOffset: 0, extentOffset: '9-8-7000-123'.length));
    final unpressedHeights = [
      for (final box in unpressedBoxes)
        MatrixUtils.transformRect(
                unpressedParagraph.getTransformTo(null), box.toRect())
            .height
    ];
    final gesture = await t.startGesture(t.getCenter(find.text('虚构测试商品')));
    await t.pump(const Duration(milliseconds: 120));
    await t.pump();
    var elapsed = 0;
    for (final ms in [16, 40, 100]) {
      await t.pump(Duration(milliseconds: ms - elapsed));
      elapsed = ms;
      final transform = t.widget<Transform>(find
          .descendant(
              of: find.byType(SpringCard), matching: find.byType(Transform))
          .first);
      expect(transform.transform.storage[0], lessThan(1));
      final paragraph =
          t.renderObject<RenderParagraph>(find.text('9-8-7000-123'));
      expect(paragraph.didExceedMaxLines, false);
      final glyphBoxes = paragraph.getBoxesForSelection(const TextSelection(
          baseOffset: 0, extentOffset: '9-8-7000-123'.length));
      expect(glyphBoxes, isNotEmpty);
      final surface = t.getRect(find.byType(SpringCard));
      final viewport = Offset.zero & t.view.physicalSize;
      expect(glyphBoxes.length, unpressedHeights.length);
      for (var i = 0; i < glyphBoxes.length; i++) {
        final glyphBox = glyphBoxes[i];
        final local = glyphBox.toRect();
        final painted =
            MatrixUtils.transformRect(paragraph.getTransformTo(null), local);
        expect(surface.inflate(.01).contains(painted.topLeft), true);
        expect(surface.inflate(.01).contains(painted.bottomRight), true);
        expect(viewport.contains(painted.topLeft), true);
        expect(viewport.contains(painted.bottomRight), true);
        // 验证按压仅有预期缩放且没有新裁剪；不把几何范围冒充真人辨读。
        debugPrint(
            'P45 glyph sample t=${ms}ms scale=${transform.transform.storage[0]} baselineHeight=${unpressedHeights[i]} painted=$painted');
        expect(
            painted.height / unpressedHeights[i], inInclusiveRange(.97, 1.01));
      }
      expect(t.takeException(), isNull);
    }
    await gesture.cancel();
    await t.pumpAndSettle();
    await t.tap(find.text('9-8-7000-123'));
    await t.pump();
    await t.pump(const Duration(seconds: 2));
    expect(copies.single['text'], '9-8-7000-123');
    expect(find.byType(TrackingTimelineSheet), findsNothing);
    await t.tap(find.text('虚构测试商品'));
    await t.pumpAndSettle();
    expect(find.byType(TrackingTimelineSheet), findsOneWidget);
    expect(find.text('9-8-7000-123'), findsWidgets);
    expect(t.takeException(), isNull);
  });
}
