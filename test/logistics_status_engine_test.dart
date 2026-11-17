import 'package:flutter_test/flutter_test.dart';
import 'package:pickup_app/core/engine/logistics_status_engine.dart';
import 'package:pickup_app/core/models/package_status.dart';

Map<String, String> _node(String time, String text, {String tag = ''}) =>
    {'tag': tag, 'time': time, 'text': text};

void main() {
  group('derive 以最新节点为准', () {
    test('最新在途 + 更早的已签收节点 → 在途（旧节点不得反超）', () {
      final derived = LogisticsStatusEngine.derive(
        events: [
          _node('2026-01-02 10:00:00', '快件已发往杭州转运中心'),
          _node('2026-01-01 10:00:00', '快件已签收'),
        ],
      );

      expect(derived.status, PackageStatus.transit);
    });

    test('最新已到驿站待取 → 待取件', () {
      final derived = LogisticsStatusEngine.derive(
        events: [
          _node('2026-01-02 10:00:00', '快件已到驿站，请凭取件码取件'),
          _node('2026-01-01 10:00:00', '快件已发往杭州转运中心'),
        ],
      );

      expect(derived.status, PackageStatus.arrived);
    });

    test('有取件码即待取件（P44-c：优先于轨迹标签与订单侧完成态）', () {
      final derived = LogisticsStatusEngine.derive(
        events: [
          _node('2026-01-02 10:00:00', '快件正在派送中', tag: '运输中'),
        ],
        isOrderSigned: true,
        pickupCode: '3-2-1002',
      );

      expect(derived.status, PackageStatus.arrived);
    });

    test('没有轨迹时取件码单独仍是待取件', () {
      final derived = LogisticsStatusEngine.derive(
        events: const [],
        pickupCode: 'A-1-1',
      );

      expect(derived.status, PackageStatus.arrived);
    });
  });
}
