import 'package:flutter_test/flutter_test.dart';
import 'package:pickup_app/core/engine/hero_card_engine.dart';
import 'package:pickup_app/core/engine/hero_card_state.dart';
import 'package:pickup_app/core/models/package.dart';
import 'package:pickup_app/core/models/package_status.dart';

Package _pkg({
  required String id,
  required PackageStatus status,
  String station = '',
  String location = '',
  String pickupCode = '',
  DateTime? arrivedAt,
  UrgencyLevel urgency = UrgencyLevel.normal,
}) {
  return Package(
    id: id,
    trackingNumber: 'YT0000000000001',
    courier: CourierType.yt,
    status: status,
    urgency: urgency,
    addedAt: DateTime(2026, 1, 1),
    arrivedAt: arrivedAt,
    stationName: station.isEmpty ? null : station,
    location: location,
    pickupCode: pickupCode,
  );
}

void main() {
  final now = DateTime(2026, 10, 7, 12);

  group('Hero 聚类只看取件点与待取件', () {
    test('同一收货地址的待发货件不算「可合并取件」', () {
      // 京东/拼多多的 location 是收货地址；同地址多单不代表同一取件点。
      final state = HeroCardEngine.decide([
        _pkg(id: 'PDD_1', status: PackageStatus.pendingShipment, location: '阳光小区1栋'),
        _pkg(id: 'PDD_2', status: PackageStatus.pendingShipment, location: '阳光小区1栋'),
      ], now: now);

      expect(state.subtitle, isNull);
    });

    test('同一取件点的两个待取件才算「可合并取件」', () {
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
      ], now: now);

      expect(state.heroEmotionState, HeroEmotionState.normal);
      expect(state.subtitle, '建议一起取，节省跑腿');
    });
  });

  group('HeroCardEngine 统一待取口径与情绪分级', () {
    test('在途/派送中但有取件码的包裹计入 arrivedCount，不计入 deliveringCount/transitCount', () {
      final state = HeroCardEngine.decide([
        _pkg(id: 'TB_1', status: PackageStatus.transit, pickupCode: 'A-1-1'),
        _pkg(id: 'TB_2', status: PackageStatus.delivering, pickupCode: 'A-1-2'),
        _pkg(id: 'TB_3', status: PackageStatus.arrived, arrivedAt: now.subtract(const Duration(hours: 2))),
        _pkg(id: 'TB_4', status: PackageStatus.transit),
        _pkg(id: 'TB_5', status: PackageStatus.delivering),
      ], now: now);

      expect(state.pendingCount, 5);
      expect(state.arrivedCount, 3);
      expect(state.deliveringCount, 1);
      expect(state.transitCount, 1);
    });

    test('普通刚到站 arrived（距 now < 3 天）→ HeroEmotionState.normal', () {
      final state = HeroCardEngine.decide([
        _pkg(
          id: 'TB_1',
          status: PackageStatus.arrived,
          station: '测试驿站',
          pickupCode: '1-1-1111',
          urgency: UrgencyLevel.urgent,
          arrivedAt: now.subtract(const Duration(days: 1)),
        ),
      ], now: now);

      expect(state.heroEmotionState, HeroEmotionState.normal);
      expect(state.subtitle, isNull);
    });

    test('同驿站 2 件普通 arrived（含别名映射同规范名）→ normal 且提示一起取', () {
      final sameStationState = HeroCardEngine.decide([
        _pkg(
          id: 'TB_1',
          status: PackageStatus.arrived,
          station: '菜鸟驿站',
          arrivedAt: now.subtract(const Duration(hours: 6)),
        ),
        _pkg(
          id: 'TB_2',
          status: PackageStatus.arrived,
          station: '菜鸟驿站',
          arrivedAt: now.subtract(const Duration(hours: 3)),
        ),
      ], now: now);

      expect(sameStationState.heroEmotionState, HeroEmotionState.normal);
      expect(sameStationState.subtitle, '建议一起取，节省跑腿');

      final aliasedState = HeroCardEngine.decide(
        [
          _pkg(
            id: 'TB_1',
            status: PackageStatus.arrived,
            station: '北门店',
            arrivedAt: now.subtract(const Duration(days: 1)),
          ),
          _pkg(
            id: 'TB_2',
            status: PackageStatus.arrived,
            station: '菜鸟驿站',
            arrivedAt: now.subtract(const Duration(hours: 12)),
          ),
        ],
        now: now,
        stationAliases: const {'北门店': '菜鸟驿站'},
      );

      expect(aliasedState.heroEmotionState, HeroEmotionState.normal);
      expect(aliasedState.subtitle, '建议一起取，节省跑腿');
    });

    test('存在快超期 arrived（arrivedAt 距 now > 3 天）→ urgent 且提示建议立即取件', () {
      final state = HeroCardEngine.decide([
        _pkg(
          id: 'TB_1',
          status: PackageStatus.arrived,
          station: '菜鸟驿站',
          arrivedAt: now.subtract(const Duration(days: 3, seconds: 1)),
        ),
        _pkg(
          id: 'TB_2',
          status: PackageStatus.arrived,
          station: '菜鸟驿站',
          arrivedAt: now.subtract(const Duration(hours: 4)),
        ),
      ], now: now);

      expect(state.heroEmotionState, HeroEmotionState.urgent);
      expect(state.subtitle, '建议立即取件');
    });

    test('无待取件时 → HeroEmotionState.relaxed', () {
      final state = HeroCardEngine.decide([
        _pkg(id: 'TB_1', status: PackageStatus.transit),
        _pkg(id: 'TB_2', status: PackageStatus.delivering),
        _pkg(id: 'TB_3', status: PackageStatus.pendingShipment, pickupCode: '1-2-3'),
      ], now: now);

      expect(state.heroEmotionState, HeroEmotionState.relaxed);
      expect(state.arrivedCount, 0);
      expect(state.subtitle, isNull);
    });
  });
}
