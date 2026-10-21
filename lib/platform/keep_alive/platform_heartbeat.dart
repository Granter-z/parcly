/// 各电商平台心跳实现
///
/// 为每个平台定义轻量级心跳请求，用于保持 Cookie 活跃。
/// 心跳请求极简（1-2 个 API 调用），避免触发风控。
library;

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../storage/platform_auth_store.dart';
import 'taobao_token_refresher.dart';

/// 心跳结果
class HeartbeatResult {
  final bool success;
  final String? errorMessage;
  final DateTime timestamp;

  /// 是否为登录态失效（true: 登录失效，false/null: 网络错误或其他）
  final bool isAuthFailure;

  /// 本轮未真正发起心跳（平台当前不可探活，如连接器正忙）
  ///
  /// 语义上既不是成功也不是失败：调用方**不得**据此清除失效标记或累加失败计数。
  final bool skipped;

  const HeartbeatResult({
    required this.success,
    this.errorMessage,
    required this.timestamp,
    this.isAuthFailure = false,
    this.skipped = false,
  });

  factory HeartbeatResult.success() => HeartbeatResult(
    success: true,
    timestamp: DateTime.now(),
    isAuthFailure: false,
  );

  factory HeartbeatResult.failure(String error, {bool isAuthFailure = false}) => HeartbeatResult(
    success: false,
    errorMessage: error,
    timestamp: DateTime.now(),
    isAuthFailure: isAuthFailure,
  );

  /// 本轮未探活，[reason] 说明原因
  factory HeartbeatResult.skipped(String reason) => HeartbeatResult(
    success: false,
    skipped: true,
    errorMessage: reason,
    timestamp: DateTime.now(),
  );
}

/// 平台心跳接口
abstract class PlatformHeartbeat {
  /// 执行心跳请求
  Future<HeartbeatResult> performHeartbeat(String cookies);

  /// 平台标识
  String get platformId;
}

/// 淘宝/天猫心跳（纯 HTTP，可后台运行）
///
/// 发起菜鸟 mtop 请求轮换 `_m_h5_tk` 令牌，既能真正续期，又能通过返回
/// 错误码判定登录态失效。区别于原 WebView 方案（访问首页但不轮换令牌），
/// 此实现可在 WorkManager 后台 isolate 中运行。
class TaobaoHeartbeat implements PlatformHeartbeat {
  final PlatformAuthStore _authStore;

  TaobaoHeartbeat({PlatformAuthStore? authStore})
      : _authStore = authStore ?? PlatformAuthStore();

  @override
  String get platformId => 'taobao';

  @override
  Future<HeartbeatResult> performHeartbeat(String cookies) async {
    try {
      debugPrint('[KeepAlive] Taobao heartbeat starting...');
      final result = await TaobaoTokenRefresher.refresh(cookies);

      if (result.sessionExpired) {
        debugPrint('[KeepAlive] Taobao heartbeat failed: session expired');
        return HeartbeatResult.failure('登录态已失效', isAuthFailure: true);
      }
      if (result.networkError) {
        debugPrint('[KeepAlive] Taobao heartbeat error: network');
        return HeartbeatResult.failure('网络错误', isAuthFailure: false);
      }

      // 轮换令牌就地落盘，不刷新授权绑定时间
      if (result.rotated) {
        await _authStore.updateCookieTokenFields(
          'taobao',
          token: result.newToken,
          tokenEnc: result.newTokenEnc,
        );
        debugPrint('[KeepAlive] Taobao mtop token rotated');
      }

      debugPrint('[KeepAlive] Taobao heartbeat success');
      return HeartbeatResult.success();
    } catch (e) {
      debugPrint('[KeepAlive] Taobao heartbeat error: $e');
      return HeartbeatResult.failure('网络错误: $e', isAuthFailure: false);
    }
  }
}

/// 京东心跳
class JdHeartbeat implements PlatformHeartbeat {
  static const _ua =
      'Mozilla/5.0 (Linux; Android 14; 25102RKBEC Build/UP1A.231005.007) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36';

  @override
  String get platformId => 'jd';

  /// 根据 HTTP 状态 / 响应体 / Location 判定心跳结局（纯函数，可单测）
  static HeartbeatResult classifyResponse({
    required int statusCode,
    required String body,
    String location = '',
  }) {
    if (statusCode == 200) {
      if (body.contains('请登录') ||
          body.contains('login.m.jd.com') ||
          body.contains('passport.jd.com') ||
          body.contains('"isLogin":false') ||
          body.contains('"loginFlag":false')) {
        return HeartbeatResult.failure('登录态已失效（响应要求登录）', isAuthFailure: true);
      }
      if (body.contains('orderList') ||
          body.contains('订单') ||
          body.contains('我的订单')) {
        return HeartbeatResult.success();
      }
      return HeartbeatResult.failure('无法确认登录态（响应异常）', isAuthFailure: false);
    }
    if (statusCode == 302 || statusCode == 301) {
      if (location.contains('login')) {
        return HeartbeatResult.failure('登录态已失效（重定向到登录页）', isAuthFailure: true);
      }
      return HeartbeatResult.success();
    }
    if (statusCode == 401 || statusCode == 403) {
      return HeartbeatResult.failure(
        '登录态已失效（HTTP $statusCode）',
        isAuthFailure: true,
      );
    }
    return HeartbeatResult.failure('HTTP $statusCode', isAuthFailure: false);
  }

  @override
  Future<HeartbeatResult> performHeartbeat(String cookies) async {
    try {
      debugPrint('[KeepAlive] JD heartbeat starting...');

      final response = await http.get(
        Uri.parse('https://wqs.jd.com/order/orderlist_jdm.shtml'),
        headers: {
          'Cookie': cookies,
          'User-Agent': _ua,
          'Referer': 'https://wqs.jd.com/',
        },
      ).timeout(const Duration(seconds: 10));

      final result = classifyResponse(
        statusCode: response.statusCode,
        body: response.body,
        location: response.headers['location'] ?? '',
      );
      if (result.success) {
        debugPrint('[KeepAlive] JD heartbeat success');
      } else if (result.isAuthFailure) {
        debugPrint('[KeepAlive] JD heartbeat failed: login required');
      } else {
        debugPrint('[KeepAlive] JD heartbeat failed: ${result.errorMessage}');
      }
      return result;
    } on TimeoutException {
      debugPrint('[KeepAlive] JD heartbeat timeout');
      return HeartbeatResult.failure('请求超时', isAuthFailure: false);
    } catch (e) {
      debugPrint('[KeepAlive] JD heartbeat error: $e');
      return HeartbeatResult.failure('网络错误: $e', isAuthFailure: false);
    }
  }
}
