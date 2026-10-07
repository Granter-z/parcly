/// 电商平台保活服务
///
/// 职责：
/// 1. 定期发送轻量级心跳请求，保持 Cookie 活跃
/// 2. 智能调度：根据 Cookie 年龄与平台特性调整频率
/// 3. 静默运行：失败时不通知用户，仅记录日志
library;

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../storage/platform_auth_store.dart';
import 'keep_alive_scheduler.dart';
import 'platform_heartbeat.dart';

/// 保活服务
class KeepAliveService {
  final PlatformAuthStore _authStore;
  final Map<String, PlatformHeartbeat> _heartbeats;

  /// 最近一次保活时间（platform -> timestamp）
  final Map<String, DateTime> _lastKeepAliveTime = {};

  /// 保活失败计数器（连续失败 3 次才判定登录态失效）
  final Map<String, int> _failureCount = {};

  /// 是否已启用保活
  bool _enabled = true;

  /// 保活定时器
  Timer? _timer;

  KeepAliveService({
    PlatformAuthStore? authStore,
    Map<String, PlatformHeartbeat>? heartbeats,
  })  : _authStore = authStore ?? PlatformAuthStore(),
        _heartbeats = heartbeats ?? {
          'taobao': TaobaoHeartbeat(),
          'jd': JdHeartbeat(),
          'pdd': PddHeartbeat(),
        };

  /// 启动保活服务
  void start() {
    if (_timer != null) return;

    debugPrint('[KeepAliveService] Starting keep-alive service...');
    _enabled = true;

    // 立即执行一次保活（启动时）
    _performKeepAlive();

    // 定期执行保活（默认每 12 小时检查一次）
    _timer = Timer.periodic(const Duration(hours: 12), (_) {
      _performKeepAlive();
    });
  }

  /// 停止保活服务
  void stop() {
    debugPrint('[KeepAliveService] Stopping keep-alive service...');
    _enabled = false;
    _timer?.cancel();
    _timer = null;
  }

  /// 设置是否启用保活
  void setEnabled(bool enabled) {
    _enabled = enabled;
    if (enabled) {
      start();
    } else {
      stop();
    }
  }

  /// 执行保活（为所有已绑定平台发送心跳）
  Future<void> _performKeepAlive() async {
    if (!_enabled) return;

    debugPrint('[KeepAliveService] Performing keep-alive check...');

    final platforms = ['taobao', 'jd', 'pdd'];

    for (final platform in platforms) {
      if (!_enabled) break; // 中途停止

      // 检查是否已绑定
      if (!_authStore.isBound(platform)) {
        debugPrint('[KeepAliveService] Skip $platform: not bound');
        continue;
      }

      // 获取 Cookie
      final cookies = _authStore.getCookies(platform);
      if (cookies == null || cookies.trim().isEmpty) {
        debugPrint('[KeepAliveService] Skip $platform: no cookies');
        continue;
      }

      // 获取 Cookie 年龄
      final boundTime = _authStore.getBoundTime(platform);
      final cookieAge = boundTime != null
          ? DateTime.now().difference(boundTime)
          : const Duration(days: 999); // 未知年龄，假定很老

      // 判断是否应该跳过
      if (KeepAliveScheduler.shouldSkip(
        lastSyncTime: null, // TODO: 从 ConnectorManager 获取最近同步时间
        lastKeepAliveTime: _lastKeepAliveTime[platform],
      )) {
        continue;
      }

      // 执行心跳
      await _performHeartbeatForPlatform(platform, cookies, cookieAge);

      // 避免短时间内发送大量请求
      await Future.delayed(const Duration(seconds: 5));
    }

    debugPrint('[KeepAliveService] Keep-alive check completed');
  }

  /// 为单个平台执行心跳
  Future<void> _performHeartbeatForPlatform(
    String platform,
    String cookies,
    Duration cookieAge,
  ) async {
    final heartbeat = _heartbeats[platform];
    if (heartbeat == null) {
      debugPrint('[KeepAliveService] No heartbeat implementation for $platform');
      return;
    }

    debugPrint('[KeepAliveService] Sending heartbeat to $platform (age: ${cookieAge.inDays} days)...');

    try {
      final result = await heartbeat.performHeartbeat(cookies);

      if (result.success) {
        debugPrint('[KeepAliveService] ✓ $platform heartbeat success');
        _lastKeepAliveTime[platform] = DateTime.now();
        _failureCount[platform] = 0; // 重置失败计数
      } else {
        debugPrint('[KeepAliveService] ✗ $platform heartbeat failed: ${result.errorMessage}');
        _failureCount[platform] = (_failureCount[platform] ?? 0) + 1;

        // 连续失败 3 次才判定登录态失效
        if (_failureCount[platform]! >= 3) {
          debugPrint('[KeepAliveService] ⚠️  $platform login expired (3 consecutive failures)');
          // TODO: 通知 ConnectorManager 登录态失效
        }
      }
    } catch (e) {
      debugPrint('[KeepAliveService] $platform heartbeat error: $e');
      _failureCount[platform] = (_failureCount[platform] ?? 0) + 1;
    }
  }

  /// 手动触发保活（用于测试）
  Future<void> performManualKeepAlive() async {
    debugPrint('[KeepAliveService] Manual keep-alive triggered');
    await _performKeepAlive();
  }

  /// 获取平台保活状态
  Map<String, dynamic> getStatus(String platform) {
    final boundTime = _authStore.getBoundTime(platform);
    final cookieAge = boundTime != null
        ? DateTime.now().difference(boundTime)
        : null;

    return {
      'platform': platform,
      'bound': _authStore.isBound(platform),
      'cookieAge': cookieAge,
      'lastKeepAlive': _lastKeepAliveTime[platform],
      'failureCount': _failureCount[platform] ?? 0,
      'health': cookieAge != null
          ? KeepAliveScheduler.getCookieHealthDescription(cookieAge)
          : 'unknown',
    };
  }

  /// 获取所有平台的保活状态
  List<Map<String, dynamic>> getAllStatus() {
    return ['taobao', 'jd', 'pdd'].map((p) => getStatus(p)).toList();
  }

  /// 释放资源
  void dispose() {
    stop();
  }
}

/// Riverpod Provider
final keepAliveServiceProvider = Provider<KeepAliveService>((ref) {
  final authStore = ref.read(platformAuthStoreProvider);
  final service = KeepAliveService(authStore: authStore);

  // 启动保活服务
  service.start();

  // 服务销毁时停止
  ref.onDispose(() {
    service.dispose();
  });

  return service;
});
