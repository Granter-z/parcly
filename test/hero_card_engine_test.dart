import 'package:flutter_test/flutter_test.dart';
import 'package:pickup_app/core/engine/hero_card_engine.dart';
import 'package:pickup_app/core/models/package.dart';
import 'package:pickup_app/core/models/package_status.dart';

Package _pkg({
  required String id,
  required PackageStatus status,
  String station = '',
  String location = '',
  String pickupCode = '',
}) {
  return Package(
    id: id,
    trackingNumber: 'YT1234567890',
    courier: CourierType.yt,
    status: status,
    urgency: UrgencyLevel.normal,
    addedAt: DateTime(2026, 1, 1),
    stationName: station.isEmpty ? null : station,
    location: location,
    pickupCode: pickupCode,
  );
}

void main() {
  group('Hero 聚类只看取件点与待取件', () {
    test('同一收货地址的待发货件不算「可合并取件」', () {
      // 京东/拼多多的 location 是收货地址；同地址多单不代表同一取件点。
      final state = HeroCardEngine.decide([
        _pkg(id: 'PDD_1', status: PackageStatus.pendingShipment, location: '阳光小区1栋'),
        _pkg(id: 'PDD_2', status: PackageStatus.pendingShipment, location: '阳光小区1栋'),
      ]);

      expect(state.subtitle, isNull);
    });

    test('同一取件点的两个待取件才算「可合并取件」', () {
      // 用「在途 + 已有取件码」构造待取件：arrived 的紧急分恒 >80，
      // 会先命中「立即取件」，测不出聚类建议。
      final state = HeroCardEngine.decide([
        _pkg(
          id: 'TB_1',
          status: PackageStatus.transit,
          station: '菜鸟驿站(北门)',
          pickupCode: 'A-1-1',
        ),
        _pkg(
          id: 'TB_2',
          status: PackageStatus.transit,
          station: '菜鸟驿站(北门)',
          pickupCode: 'A-1-2',
        ),
      ]);

      expect(state.subtitle, '建议一起取，节省跑腿');
    });
  });
}
