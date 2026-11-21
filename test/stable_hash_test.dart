import 'package:flutter_test/flutter_test.dart';
import 'package:pickup_app/core/utils/stable_hash.dart';
import 'package:pickup_app/platform/notification/notification_adapter.dart';

void main() {
  group('stableHash32', () {
    test('同输入恒同输出（跨进程稳定的前提）', () {
      const id = 'TB_1000000000000000001';
      final first = stableHash32(id);
      for (var i = 0; i < 100; i++) {
        expect(stableHash32(id), first);
      }
    });

    test('非负且落在默认 27 位内', () {
      for (final s in ['', 'PDD_1', 'JD_2', 'CN_YT123', '中文包裹']) {
        final h = stableHash32(s);
        expect(h, greaterThanOrEqualTo(0));
        expect(h, lessThanOrEqualTo((1 << 27) - 1));
      }
    });

    test('不同输入大概率不同（抽样无碰撞）', () {
      final ids = [
        for (var i = 0; i < 500; i++) 'TB_${1000000000000000000 + i}',
      ];
      final hashes = ids.map(stableHash32).toSet();
      expect(hashes.length, ids.length);
    });

    test('已知向量（FNV-1a 32 位标准值）', () {
      // FNV-1a('a') = 0xe40c292c，默认取低 27 位
      expect(stableHash32('a'), 0xe40c292c & ((1 << 27) - 1));
      // 显式 31 位仍可用
      expect(stableHash32('a', bits: 31), 0xe40c292c & 0x7FFFFFFF);
    });
  });

  group('NotificationAdapter.packageNotificationId', () {
    test('id 由稳定哈希派生，base 偏移正确', () {
      const id = 'PDD_240101123456';
      const base = 1000000;
      expect(
        NotificationAdapter.packageNotificationId(id, base),
        base + stableHash32(id),
      );
    });

    test('到件与提醒号段不重叠', () {
      const id = 'JD_123';
      final arrived = NotificationAdapter.packageNotificationId(id, 1000000);
      final reminder = NotificationAdapter.packageNotificationId(id, 200000000);
      expect(arrived, lessThan(200000000));
      expect(reminder, greaterThanOrEqualTo(200000000));
    });
  });
}
