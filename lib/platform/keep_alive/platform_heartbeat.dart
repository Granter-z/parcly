/// 各电商平台心跳实现
///
/// 为每个平台定义轻量级心跳请求，用于保持 Cookie 活跃。
/// 心跳请求极简（1-2 个 API 调用），避免触发风控。
library;

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:webview_flutter/webview_flutter.dart';

/// 心跳结果
class HeartbeatResult {
  final bool success;
  final String? errorMessage;
  final DateTime timestamp;

  const HeartbeatResult({
    required this.success,
    this.errorMessage,
    required this.timestamp,
  });

  factory HeartbeatResult.success() => HeartbeatResult(
    success: true,
    timestamp: DateTime.now(),
  );

  factory HeartbeatResult.failure(String error) => HeartbeatResult(
    success: false,
    errorMessage: error,
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

/// 淘宝/天猫心跳
class TaobaoHeartbeat implements PlatformHeartbeat {
  static const _ua =
      'Mozilla/5.0 (Linux; Android 14; 25102RKBEC Build/UP1A.231005.007) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36';

  @override
  String get platformId => 'taobao';

  @override
  Future<HeartbeatResult> performHeartbeat(String cookies) async {
    try {
      debugPrint('[KeepAlive] Taobao heartbeat starting...');

      // 方案：访问菜鸟驿站首页（最轻量）
      // 此请求不拉取数据，仅触发服务端刷新 Cookie
      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setUserAgent(_ua);

      // 注入 Cookie
      final cookieManager = WebViewCookieManager();
      final cookiePairs = cookies.split(';');
      for (final pair in cookiePairs) {
        final trimmed = pair.trim();
        if (trimmed.isEmpty) continue;
        final parts = trimmed.split('=');
        if (parts.length < 2) continue;

        final name = parts[0].trim();
        final value = parts.sublist(1).join('=').trim();

        await cookieManager.setCookie(WebViewCookie(
          name: name,
          value: value,
          domain: '.taobao.com',
          path: '/',
        ));
      }

      // 加载页面
      await controller.loadRequest(
        Uri.parse('https://cnstation.m.taobao.com/station'),
      );

      // 等待页面加载
      await Future.delayed(const Duration(seconds: 3));

      // 检查是否被重定向到登录页
      final currentUrl = await controller.currentUrl();
      if (currentUrl != null && currentUrl.contains('login')) {
        debugPrint('[KeepAlive] Taobao heartbeat failed: redirected to login');
        return HeartbeatResult.failure('登录态已失效（重定向到登录页）');
      }

      debugPrint('[KeepAlive] Taobao heartbeat success');
      return HeartbeatResult.success();
    } catch (e) {
      debugPrint('[KeepAlive] Taobao heartbeat error: $e');
      return HeartbeatResult.failure('网络错误: $e');
    }
  }
}

/// 京东心跳
class JdHeartbeat implements PlatformHeartbeat {
  static const _ua =
      'Mozilla/5.0 (Linux; Android 14; 25102RKBEC Build/UP1A.231005.007) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36';

  @override
  String get platformId => 'jd';

  @override
  Future<HeartbeatResult> performHeartbeat(String cookies) async {
    try {
      debugPrint('[KeepAlive] JD heartbeat starting...');

      // 方案：简单访问订单页（不执行复杂逻辑）
      final response = await http.head(
        Uri.parse('https://wqs.jd.com/order/orderlist_jdm.shtml'),
        headers: {
          'Cookie': cookies,
          'User-Agent': _ua,
          'Referer': 'https://wqs.jd.com/',
        },
      ).timeout(const Duration(seconds: 10));

      // 检查响应状态
      if (response.statusCode == 200) {
        debugPrint('[KeepAlive] JD heartbeat success');
        return HeartbeatResult.success();
      } else if (response.statusCode == 302 || response.statusCode == 301) {
        // 检查是否重定向到登录页
        final location = response.headers['location'] ?? '';
        if (location.contains('login')) {
          debugPrint('[KeepAlive] JD heartbeat failed: redirected to login');
          return HeartbeatResult.failure('登录态已失效（重定向到登录页）');
        }
        // 其他重定向视为成功（可能是正常的页面跳转）
        debugPrint('[KeepAlive] JD heartbeat success (redirected)');
        return HeartbeatResult.success();
      } else {
        debugPrint('[KeepAlive] JD heartbeat failed: status=${response.statusCode}');
        return HeartbeatResult.failure('HTTP ${response.statusCode}');
      }
    } on TimeoutException {
      debugPrint('[KeepAlive] JD heartbeat timeout');
      return HeartbeatResult.failure('请求超时');
    } catch (e) {
      debugPrint('[KeepAlive] JD heartbeat error: $e');
      return HeartbeatResult.failure('网络错误: $e');
    }
  }
}

/// 拼多多心跳
class PddHeartbeat implements PlatformHeartbeat {
  static const _ua =
      'Mozilla/5.0 (Linux; Android 14; 25102RKBEC Build/UP1A.231005.007) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36';

  @override
  String get platformId => 'pdd';

  @override
  Future<HeartbeatResult> performHeartbeat(String cookies) async {
    try {
      debugPrint('[KeepAlive] PDD heartbeat starting...');

      // 方案：访问拼多多主页（触发 Cookie 刷新）
      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setUserAgent(_ua);

      // 注入 Cookie
      final cookieManager = WebViewCookieManager();
      final cookiePairs = cookies.split(';');
      for (final pair in cookiePairs) {
        final trimmed = pair.trim();
        if (trimmed.isEmpty) continue;
        final parts = trimmed.split('=');
        if (parts.length < 2) continue;

        final name = parts[0].trim();
        final value = parts.sublist(1).join('=').trim();

        await cookieManager.setCookie(WebViewCookie(
          name: name,
          value: value,
          domain: '.pinduoduo.com',
          path: '/',
        ));
      }

      // 加载页面
      await controller.loadRequest(
        Uri.parse('https://mobile.yangkeduo.com/'),
      );

      // 等待页面加载
      await Future.delayed(const Duration(seconds: 3));

      // 检查是否被重定向到登录页
      final currentUrl = await controller.currentUrl();
      if (currentUrl != null && currentUrl.contains('login')) {
        debugPrint('[KeepAlive] PDD heartbeat failed: redirected to login');
        return HeartbeatResult.failure('登录态已失效（重定向到登录页）');
      }

      debugPrint('[KeepAlive] PDD heartbeat success');
      return HeartbeatResult.success();
    } catch (e) {
      debugPrint('[KeepAlive] PDD heartbeat error: $e');
      return HeartbeatResult.failure('网络错误: $e');
    }
  }
}
