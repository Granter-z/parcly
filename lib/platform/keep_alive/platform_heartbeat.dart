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

  /// 单测可注入，生产走 [TaobaoTokenRefresher.refresh]
  final Future<MtopRefreshResult> Function(String cookies)? _refreshOverride;

  TaobaoHeartbeat({
    PlatformAuthStore? authStore,
    Future<MtopRefreshResult> Function(String cookies)? refreshOverride,
  })  : _authStore = authStore ?? PlatformAuthStore(),
        _refreshOverride = refreshOverride;

  @override
  String get platformId => 'taobao';

  /// 网络抖动短重试间隔（socket/超时最多再试 1 次再落盘）
  static const _networkRetryDelay = Duration(milliseconds: 400);

  /// 保活历史副文案：带异常摘要，避免光杆「网络错误」
  static String networkErrorMessage(String? detail) {
    if (detail == null || detail.isEmpty) return '网络错误';
    return '网络错误: $detail';
  }

  Future<MtopRefreshResult> _doRefresh(String cookies) {
    final override = _refreshOverride;
    if (override != null) return override(cookies);
    return TaobaoTokenRefresher.refresh(cookies);
  }

  @override
  Future<HeartbeatResult> performHeartbeat(String cookies) async {
    try {
      debugPrint('[KeepAlive] Taobao heartbeat starting...');
      var result = await _doRefresh(cookies);

      // 鉴权失效不重试；仅对网络失败短重试 1 次
      if (result.networkError && !result.sessionExpired) {
        debugPrint('[KeepAlive] Taobao network blip, retry once...');
        await Future.delayed(_networkRetryDelay);
        result = await _doRefresh(cookies);
      }

      if (result.sessionExpired) {
        debugPrint('[KeepAlive] Taobao heartbeat failed: session expired');
        return HeartbeatResult.failure('登录态已失效', isAuthFailure: true);
      }
      if (result.networkError) {
        final msg = networkErrorMessage(result.errorDetail);
        debugPrint('[KeepAlive] Taobao heartbeat error: $msg');
        return HeartbeatResult.failure(msg, isAuthFailure: false);
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

  /// 网络抖动短重试间隔（socket/超时最多再试 1 次再落盘）
  static const _networkRetryDelay = Duration(milliseconds: 400);

  /// 既定探活端点（与同步 WebView 的 trade.m.jd.com 分工不同，勿擅自改域名）
  static const probeUrl = 'https://wqs.jd.com/order/orderlist_jdm.shtml';

  Future<HeartbeatResult> _probeOnce(String cookies) async {
    final response = await http.get(
      Uri.parse(probeUrl),
      headers: {
        'Cookie': cookies,
        'User-Agent': _ua,
        'Referer': 'https://wqs.jd.com/',
      },
    ).timeout(const Duration(seconds: 10));

    return classifyResponse(
      statusCode: response.statusCode,
      body: response.body,
      location: response.headers['location'] ?? '',
    );
  }

  @override
  Future<HeartbeatResult> performHeartbeat(String cookies) async {
    debugPrint('[KeepAlive] JD heartbeat starting...');
    try {
      final result = await _probeOnce(cookies);
      if (result.success) {
        debugPrint('[KeepAlive] JD heartbeat success');
      } else if (result.isAuthFailure) {
        debugPrint('[KeepAlive] JD heartbeat failed: login required');
      } else {
        debugPrint('[KeepAlive] JD heartbeat failed: ${result.errorMessage}');
      }
      return result;
    } on TimeoutException {
      debugPrint('[KeepAlive] JD heartbeat timeout, retry once...');
      await Future.delayed(_networkRetryDelay);
      try {
        final result = await _probeOnce(cookies);
        if (result.success) {
          debugPrint('[KeepAlive] JD heartbeat success (after retry)');
        } else if (result.isAuthFailure) {
          debugPrint('[KeepAlive] JD heartbeat failed: login required (after retry)');
        }
        return result;
      } on TimeoutException {
        debugPrint('[KeepAlive] JD heartbeat timeout');
        return HeartbeatResult.failure('请求超时', isAuthFailure: false);
      } catch (e) {
        debugPrint('[KeepAlive] JD heartbeat error: $e');
        return HeartbeatResult.failure('网络错误: $e', isAuthFailure: false);
      }
    } catch (e) {
      // socket / ClientException 等：短重试 1 次再落盘；鉴权分类不走此路径
      debugPrint('[KeepAlive] JD heartbeat error: $e, retry once...');
      await Future.delayed(_networkRetryDelay);
      try {
        final result = await _probeOnce(cookies);
        if (result.success) {
          debugPrint('[KeepAlive] JD heartbeat success (after retry)');
        } else if (result.isAuthFailure) {
          debugPrint('[KeepAlive] JD heartbeat failed: login required (after retry)');
        }
        return result;
      } on TimeoutException {
        debugPrint('[KeepAlive] JD heartbeat timeout');
        return HeartbeatResult.failure('请求超时', isAuthFailure: false);
      } catch (e2) {
        debugPrint('[KeepAlive] JD heartbeat error: $e2');
        return HeartbeatResult.failure('网络错误: $e2', isAuthFailure: false);
      }
    }
  }
}
