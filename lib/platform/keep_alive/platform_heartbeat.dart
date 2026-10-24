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

/// 京东心跳（P36-b：双探，以 trade 为失效真相源）
///
/// wqs 与同步用的 trade.m.jd.com 常不一致；仅当 **trade** 也要求登录才
/// `isAuthFailure:true`（进而 setExpired）。wqs 单边像登录 → 记不确定/
/// 网络失败，不立刻 expire。
class JdHeartbeat implements PlatformHeartbeat {
  static const _ua =
      'Mozilla/5.0 (Linux; Android 14; 25102RKBEC Build/UP1A.231005.007) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36';

  @override
  String get platformId => 'jd';

  /// 历史探活端点（wqs）；P36-b 仍探测，但不再单独决定失效
  static const probeUrl = 'https://wqs.jd.com/order/orderlist_jdm.shtml';

  /// 与同步 WebView 一致的订单列表（失效真相源）
  static const tradeProbeUrl =
      'https://trade.m.jd.com/order/orderlist_jdm.shtml';

  /// 根据 HTTP 状态 / 响应体 / Location 判定单次探活结局（纯函数，可单测）
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

  /// 合并 wqs + trade 双探结果（纯函数，可单测）
  ///
  /// - trade 成功 → 成功（即使 wqs 像登录，P36-a 已坐实误标）
  /// - trade 明确要登录 → authFailure（才可 setExpired）
  /// - wqs 单边像登录且 trade 未确认 → 非 auth（→ networkFailure/uncertain）
  /// - 其余网络/异常 → 非 auth
  static HeartbeatResult combineDualProbe({
    required HeartbeatResult wqs,
    required HeartbeatResult trade,
  }) {
    if (trade.success) {
      if (wqs.isAuthFailure) {
        // 保留 success；文案留给日志；errorMessage 在 success 时通常不用
        return HeartbeatResult.success();
      }
      return HeartbeatResult.success();
    }

    if (trade.isAuthFailure) {
      return HeartbeatResult.failure(
        '登录态已失效（trade 要求登录）',
        isAuthFailure: true,
      );
    }

    // trade 网络/不确定
    if (wqs.isAuthFailure) {
      return HeartbeatResult.failure(
        '登录态不确定（wqs 像登录但 trade 未确认）',
        isAuthFailure: false,
      );
    }
    if (wqs.success) {
      // trade 抖但 wqs 活着：不 expire；按网络失败累计，避免误标
      return HeartbeatResult.failure(
        'trade 探活未确认（wqs 正常）: ${trade.errorMessage ?? "未知"}',
        isAuthFailure: false,
      );
    }

    return HeartbeatResult.failure(
      '网络错误（wqs: ${wqs.errorMessage ?? "?"} / trade: ${trade.errorMessage ?? "?"})',
      isAuthFailure: false,
    );
  }

  /// 网络抖动短重试间隔（socket/超时最多再试 1 次再落盘）
  static const _networkRetryDelay = Duration(milliseconds: 400);

  Future<HeartbeatResult> _probeOnce(String url, String cookies) async {
    final uri = Uri.parse(url);
    final referer = '${uri.scheme}://${uri.host}/';
    final response = await http.get(
      uri,
      headers: {
        'Cookie': cookies,
        'User-Agent': _ua,
        'Referer': referer,
      },
    ).timeout(const Duration(seconds: 10));

    return classifyResponse(
      statusCode: response.statusCode,
      body: response.body,
      location: response.headers['location'] ?? '',
    );
  }

  /// 单 host 探活：网络/超时短重试 1 次；鉴权结果不重试
  Future<HeartbeatResult> _probeHost(String url, String cookies, String hostTag) async {
    try {
      final result = await _probeOnce(url, cookies);
      _logHost(hostTag, result);
      return result;
    } on TimeoutException {
      debugPrint('[KeepAlive] JD $hostTag timeout, retry once...');
      await Future.delayed(_networkRetryDelay);
      try {
        final result = await _probeOnce(url, cookies);
        _logHost(hostTag, result, afterRetry: true);
        return result;
      } on TimeoutException {
        debugPrint('[KeepAlive] JD $hostTag timeout');
        return HeartbeatResult.failure('请求超时', isAuthFailure: false);
      } catch (e) {
        debugPrint('[KeepAlive] JD $hostTag error: $e');
        return HeartbeatResult.failure('网络错误: $e', isAuthFailure: false);
      }
    } catch (e) {
      debugPrint('[KeepAlive] JD $hostTag error: $e, retry once...');
      await Future.delayed(_networkRetryDelay);
      try {
        final result = await _probeOnce(url, cookies);
        _logHost(hostTag, result, afterRetry: true);
        return result;
      } on TimeoutException {
        debugPrint('[KeepAlive] JD $hostTag timeout');
        return HeartbeatResult.failure('请求超时', isAuthFailure: false);
      } catch (e2) {
        debugPrint('[KeepAlive] JD $hostTag error: $e2');
        return HeartbeatResult.failure('网络错误: $e2', isAuthFailure: false);
      }
    }
  }

  void _logHost(String hostTag, HeartbeatResult result, {bool afterRetry = false}) {
    final suffix = afterRetry ? ' (after retry)' : '';
    if (result.success) {
      debugPrint('[KeepAlive] JD $hostTag OK$suffix');
    } else if (result.isAuthFailure) {
      debugPrint('[KeepAlive] JD $hostTag login-like$suffix');
    } else {
      debugPrint('[KeepAlive] JD $hostTag fail: ${result.errorMessage}$suffix');
    }
  }

  @override
  Future<HeartbeatResult> performHeartbeat(String cookies) async {
    debugPrint('[KeepAlive] JD heartbeat starting (dual probe wqs+trade)...');
    final wqs = await _probeHost(probeUrl, cookies, 'wqs');
    final trade = await _probeHost(tradeProbeUrl, cookies, 'trade');
    final combined = combineDualProbe(wqs: wqs, trade: trade);

    if (combined.success) {
      if (wqs.isAuthFailure) {
        debugPrint(
          '[KeepAlive] JD heartbeat success (trade OK; ignored wqs login-like)',
        );
      } else {
        debugPrint('[KeepAlive] JD heartbeat success');
      }
    } else if (combined.isAuthFailure) {
      debugPrint(
        '[KeepAlive] JD heartbeat failed: login required (host=trade)',
      );
    } else {
      debugPrint('[KeepAlive] JD heartbeat failed: ${combined.errorMessage}');
    }
    return combined;
  }
}
