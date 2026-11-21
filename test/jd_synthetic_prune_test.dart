// 京东 DOM 兜底伪 id（md5 12 位十六进制）清理：标题变化后旧卡不能残留在在途里。
import 'package:flutter_test/flutter_test.dart';
import 'package:pickup_app/core/models/package.dart';
import 'package:pickup_app/core/models/package_status.dart';
import 'package:pickup_app/ui/providers/package_provider.dart';

class _FakeList extends PackageListNotifier {
  _FakeList(List<Package> initial) {
    state = initial;
  }
}

Package _p(String id) => Package(
      id: id,
      trackingNumber: 'T-$id',
      courier: CourierType.jd,
      urgency: UrgencyLevel.normal,
      status: PackageStatus.transit,
      addedAt: DateTime(2026, 11, 22),
      platform: 'jd',
    );

void main() {
  group('isSyntheticJdId', () {
    test('12 位十六进制且含 a-f 才是伪 id', () {
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

  test('清理不在本轮结果里的伪卡，保留本轮产出与真实订单号', () {
    final list = _FakeList([
      _p('JD_ab12cd34ef56'), // 旧标题生成的伪 card，本轮未产出
      _p('JD_0123456789ab'), // 本轮产出的伪 card
      _p('JD_123456789012'), // 真实十进制订单号
      _p('PDD_1'), // 其它平台
    ]);

    list.pruneJdSyntheticCardsNotIn({'JD_0123456789ab'});

    final ids = list.state.map((p) => p.id).toSet();
    expect(ids, contains('JD_0123456789ab'));
    expect(ids, contains('JD_123456789012'));
    expect(ids, contains('PDD_1'));
    expect(ids, isNot(contains('JD_ab12cd34ef56')));
  });

  test('结构化源判定 0 快递时（keep 为空）清掉全部伪卡，真实单号仍保留', () {
    final list = _FakeList([
      _p('JD_ab12cd34ef56'),
      _p('JD_0123456789ab'),
      _p('JD_123456789012'),
    ]);

    list.pruneJdSyntheticCardsNotIn(const {});

    final ids = list.state.map((p) => p.id).toSet();
    expect(ids, isNot(contains('JD_ab12cd34ef56')));
    expect(ids, isNot(contains('JD_0123456789ab')));
    expect(ids, contains('JD_123456789012'));
  });
}