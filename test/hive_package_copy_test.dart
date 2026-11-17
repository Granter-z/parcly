import 'package:flutter_test/flutter_test.dart';
import 'package:pickup_app/platform/storage/hive_package.dart';

void main() {
  test('HivePackage.copyWith 必须保留时间轴 JSON', () {
    const timeline = '[{"tag":"","time":"2026-01-01 00:00:00","text":"运输中"}]';
    final p = HivePackage(
      id: 'PDD_1',
      trackingNumber: 'YT1234567890',
      courier: CourierType.yt,
      urgency: UrgencyLevel.normal,
      status: PackageStatus.transit,
      addedAt: DateTime(2026, 1, 1),
      rawTimelineJson: timeline,
    );

    final copy = p.copyWith(status: PackageStatus.arrived);

    expect(copy.status, PackageStatus.arrived);
    expect(copy.rawTimelineJson, timeline);
  });
}
