/// 保活任务调度器
///
/// 根据 Cookie 年龄动态调整保活频率，智能调度保活任务。
library;

import 'package:flutter/foundation.dart';

/// 保活间隔策略
class KeepAliveScheduler {
  /// 计算下次保活间隔（基于 Cookie 年龄）
  static Duration calculateInterval(Duration cookieAge) {
    final days = cookieAge.inDays;

    if (days <= 3) {
      // 0-3 天：新鲜期，低频维护
      debugPrint('[KeepAliveScheduler] Cookie age: $days days → 24 hours interval');
      return const Duration(hours: 24);
    } else if (days <= 7) {
      // 4-7 天：中期，适度保活
      debugPrint('[KeepAliveScheduler] Cookie age: $days days → 12 hours interval');
      return const Duration(hours: 12);
    } else if (days <= 10) {
      // 8-10 天：临期，积极保活
      debugPrint('[KeepAliveScheduler] Cookie age: $days days → 6 hours interval');
      return const Duration(hours: 6);
    } else {
      // 11+ 天：危险期，高频保活
      debugPrint('[KeepAliveScheduler] Cookie age: $days days → 4 hours interval');
      return const Duration(hours: 4);
    }
  }

  /// 是否应该跳过保活（用户最近有活动）
  static bool shouldSkip({
    required DateTime? lastSyncTime,
    required DateTime? lastKeepAliveTime,
  }) {
    final now = DateTime.now();

    // 用户主动同步后 6 小时内跳过保活
    if (lastSyncTime != null) {
      final timeSinceSync = now.difference(lastSyncTime);
      if (timeSinceSync.inHours < 6) {
        debugPrint('[KeepAliveScheduler] Skip: user synced ${timeSinceSync.inMinutes} min ago');
        return true;
      }
    }

    // 最近刚保活过，跳过
    if (lastKeepAliveTime != null) {
      final timeSinceKeepAlive = now.difference(lastKeepAliveTime);
      if (timeSinceKeepAlive.inHours < 2) {
        debugPrint('[KeepAliveScheduler] Skip: kept alive ${timeSinceKeepAlive.inMinutes} min ago');
        return true;
      }
    }

    return false;
  }

  /// 计算下一次保活的推荐时间（随机化，避免固定时间点）
  static DateTime calculateNextTime(Duration interval) {
    final now = DateTime.now();
    final baseTime = now.add(interval);

    // 添加随机偏移（±30 分钟），避免固定时间点请求
    final randomOffsetMinutes = (DateTime.now().millisecond % 60) - 30;
    final randomizedTime = baseTime.add(Duration(minutes: randomOffsetMinutes));

    return randomizedTime;
  }

  /// 判断是否处于推荐保活时段（避免干扰用户）
  static bool isPreferredTimeSlot() {
    final now = DateTime.now();
    final hour = now.hour;

    // 推荐时段：凌晨 2:00-4:00 或 下午 14:00-16:00
    final isNightSlot = hour >= 2 && hour < 4;
    final isAfternoonSlot = hour >= 14 && hour < 16;

    return isNightSlot || isAfternoonSlot;
  }

  /// 获取 Cookie 健康度描述
  static String getCookieHealthDescription(Duration cookieAge) {
    final days = cookieAge.inDays;

    if (days <= 3) {
      return '健康';
    } else if (days <= 7) {
      return '良好';
    } else if (days <= 10) {
      return '临期';
    } else if (days <= 14) {
      return '需要保活';
    } else {
      return '即将过期';
    }
  }

  /// 获取 Cookie 健康度颜色
  static String getCookieHealthColor(Duration cookieAge) {
    final days = cookieAge.inDays;

    if (days <= 3) {
      return '#4CAF50'; // 绿色
    } else if (days <= 7) {
      return '#8BC34A'; // 浅绿
    } else if (days <= 10) {
      return '#FFC107'; // 黄色
    } else if (days <= 14) {
      return '#FF9800'; // 橙色
    } else {
      return '#F44336'; // 红色
    }
  }
}
