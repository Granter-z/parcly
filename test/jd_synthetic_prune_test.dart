// 京东 DOM 兜底伪 id 清理与迁移：标题变化/结构化源切换时不能误删用户资产。
import 'package:flutter_test/flutter_test.dart';
import 'package:pickup_app/core/models/package.dart';
import 'package:pickup_app/core/models/package_status.dart';
import 'package:pickup_app/ui/providers/package_provider.dart';

class _FakeList extends PackageListNotifier {
  _FakeList(List<Package> initial) {
    state = initial;
  }
}

Package _p(
  String id, {
  PackageStatus status = PackageStatus.transit,
  DateTime? pickedUpAt,
}) =>
    Package(
      id: id,
      trackingNumber: 'T-$id',
      courier: CourierType.jd,
      urgency: UrgencyLevel.normal,
      status: status,
      addedAt: DateTime(2026, 11, 22),
      pickedUpAt: pickedUpAt,
      platform: 'jd',
    );

Package _arrived({
  required String id,
  required String trackingNumber,
  bool notifiedArrived = false,
  DateTime? pickedUpAt,
}) =>
    Package(
      id: id,
      trackingNumber: trackingNumber,
      courier: CourierType.jd,
      urgency: UrgencyLevel.normal,
      status: PackageStatus.arrived,
      addedAt: DateTime(2026, 11, 20),
      arrivedAt: DateTime(2026, 11, 21),
      pickupCode: '1-2-3001',
      stationName: '测试驿站',
      notifiedArrived: notifiedArrived,
      pickedUpAt: pickedUpAt,
      platform: 'jd',
    );

void main() {
  group('isSyntheticJdId', () {
    test('新前缀 JD_x + 12 位十六进制是伪 id（全数字也可识别）', () {
      expect(PackageListNotifier.isSyntheticJdId('JD_x0123456789ab'), isTrue);
      expect(PackageListNotifier.isSyntheticJdId('JD_x123456789012'), isTrue);
    });

    test('旧格式兼容：12 位十六进制且含 a-f', () {
      expect(PackageListNotifier.isSyntheticJdId('JD_ab12cd34ef56'), isTrue);
      expect(PackageListNotifier.isSyntheticJdId('JD_0123456789ab'), isTrue);
    });

    test('真实十进制订单号不误判', () {
      expect(PackageListNotifier.isSyntheticJdId('JD_123456789012'), isFalse);
      expect(PackageListNotifier.isSyntheticJdId('JD_12345678901'), isFalse);
      expect(PackageListNotifier.isSyntheticJdId('PDD_ab12cd34ef56'), isFalse);
      expect(PackageListNotifier.isSyntheticJdId('JD_abc'), isFalse);
    });
  });

  group('pruneJdSyntheticCardsNotIn（只清活跃且未取件）', () {
    test('清理不在本轮结果里的在途伪卡，保留本轮产出与真实订单号', () {
      final list = _FakeList([
        _p('JD_xaaaaaaaaaaaa'), // 在途伪卡，本轮未产出
        _p('JD_xbbbbbbbbbbbb'), // 在途伪卡，本轮产出
        _p('JD_123456789012'), // 真实十进制订单号
        _p('PDD_1'), // 其它平台
      ]);

      list.pruneJdSyntheticCardsNotIn({'JD_xbbbbbbbbbbbb'});

      final ids = list.state.map((p) => p.id).toSet();
      expect(ids, contains('JD_xbbbbbbbbbbbb'));
      expect(ids, contains('JD_123456789012'));
      expect(ids, contains('PDD_1'));
      expect(ids, isNot(contains('JD_xaaaaaaaaaaaa')));
    });

    test('已完成/已取件/已到件/已归档/拒收的伪卡绝不删除', () {
      final list = _FakeList([
        _p('JD_x111111111111', status: PackageStatus.pendingShipment),
        _p('JD_x222222222222', status: PackageStatus.delivering),
        _p('JD_x333333333333', status: PackageStatus.arrived),
        _p(
          'JD_x444444444444',
          status: PackageStatus.pickedUp,
          pickedUpAt: DateTime(2026, 11, 20),
        ),
        _p('JD_x555555555555', status: PackageStatus.archived),
        _p('JD_x666666666666', status: PackageStatus.rejected),
      ]);

      list.pruneJdSyntheticCardsNotIn(const {});

      final ids = list.state.map((p) => p.id).toSet();
      // 活跃未取件：清理
      expect(ids, isNot(contains('JD_x111111111111')));
      expect(ids, isNot(contains('JD_x222222222222')));
      // 用户资产：保留
      expect(ids, contains('JD_x333333333333'));
      expect(ids, contains('JD_x444444444444'));
      expect(ids, contains('JD_x555555555555'));
      expect(ids, contains('JD_x666666666666'));
    });
  });

  group('伪 id → 真实 id 迁移', () {
    test('resolveMergedJdId 只把合成 id 迁到真实十进制订单号', () {
      final synthetic = _arrived(id: 'JD_x0123456789ab', trackingNumber: 'YT1');
      final real = _arrived(id: 'JD_123456789012', trackingNumber: 'YT1');
      expect(
        PackageListNotifier.resolveMergedJdId(synthetic, real),
        'JD_123456789012',
      );
      expect(
        PackageListNotifier.resolveMergedJdId(real, synthetic),
        'JD_123456789012',
      );
    });

    test('合并迁移保留状态/已取时间/取件码/到件时间/已通知标记', () {
      final pickedAt = DateTime(2026, 11, 19);
      final existing = _arrived(
        id: 'JD_x0123456789ab',
        trackingNumber: 'YT001',
        notifiedArrived: true,
        pickedUpAt: pickedAt,
      );
      final incoming = _arrived(
        id: 'JD_123456789012',
        trackingNumber: 'YT001',
      );
      final list = _FakeList([existing]);

      // 已通知标记为 true，合并时不得再次触发到件通知
      list.addPackage(incoming);

      final merged = list.state.single;
      expect(merged.id, 'JD_123456789012');
      expect(merged.status, PackageStatus.arrived);
      expect(merged.pickedUpAt, pickedAt);
      expect(merged.pickupCode, '1-2-3001');
      expect(merged.arrivedAt, existing.arrivedAt);
      expect(merged.notifiedArrived, isTrue);
    });
  });
}