/// 电池优化豁免（Doze 白名单）状态与申请入口。
///
/// WorkManager 周期任务在 Doze 下会被推迟；国产 ROM 还会额外限制后台。
/// 这里只负责申请系统级的「忽略电池优化」，不触碰厂商私有省电开关。
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class BatteryOptimization {
  static const _channel = MethodChannel('com.example.pickup_app/power');

  static Future<bool> isIgnoring() async {
    if (defaultTargetPlatform != TargetPlatform.android) return true;
    try {
      return await _channel
              .invokeMethod<bool>('isIgnoringBatteryOptimizations') ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// 打开系统「忽略电池优化」授权页（异步拉起系统界面）。
  ///
  /// 注意：系统弹窗本身是非阻塞的，返回值只反映调用瞬间是否已处于豁免态；
  /// 用户在系统界面授权后的真实状态需在页面 `resumed` 生命周期里通过 [isIgnoring] 刷新。
  static Future<bool> requestIgnore() async {
    if (defaultTargetPlatform != TargetPlatform.android) return true;
    try {
      return await _channel
              .invokeMethod<bool>('requestIgnoreBatteryOptimizations') ??
          false;
    } catch (_) {
      return false;
    }
  }
}
