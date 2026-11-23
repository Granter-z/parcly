/// 平台会话 Cookie 注入工具
///
/// 与 `WebViewCookieManager.setCookie` 的差别：原生 `CookieManager.setCookie(url, cookie)`
/// 接受完整的 Cookie 头字符串，可携带 `HttpOnly` / `Secure` 属性，
/// 而 Dart 侧 `WebViewCookie` 只能传 name/value/path，
/// 会把平台原本的 HttpOnly 会话令牌变成页面脚本可读，削弱平台侧防护。
///
/// 因此优先走原生通道；在不可用时回退到 Dart 侧写入（不携带安全属性）。
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

const MethodChannel _webviewChannel =
    MethodChannel('com.example.pickup_app/webview_hook');

/// 后台 isolate 或测试环境中原生通道不可用时短路跳过，避免重复 IPC 与日志刷屏。
bool _nativeChannelUnavailable = false;

/// 以原生方式写入单条 Cookie（保留 HttpOnly/Secure）
Future<bool> setPlatformCookie({
  required String name,
  required String value,
  required String domain,
  bool httpOnly = true,
  bool secure = true,
  bool flush = true,
}) async {
  if (name.isEmpty || value.isEmpty || domain.isEmpty) return false;
  final host = domain.startsWith('.') ? domain.substring(1) : domain;
  final url = 'https://$host/';
  final cookie = StringBuffer('$name=$value; Path=/; Domain=$domain');
  if (secure) cookie.write('; Secure');
  if (httpOnly) cookie.write('; HttpOnly');

  if (!_nativeChannelUnavailable) {
    try {
      final ok = await _webviewChannel.invokeMethod<bool>('setCookie', {
        'url': url,
        'cookie': cookie.toString(),
        'flush': flush,
      });
      if (ok == true) return true;
    } on MissingPluginException catch (e) {
      _nativeChannelUnavailable = true;
      debugPrint('[Cookie] native channel unavailable, fallback to Dart: $e');
    } catch (e) {
      debugPrint('[Cookie] native setCookie failed, fallback to Dart: $e');
    }
  }

  try {
    await WebViewCookieManager().setCookie(
      WebViewCookie(domain: domain, path: '/', name: name, value: value),
    );
    return true;
  } catch (_) {
    return false;
  }
}

/// 把一整串 `k=v; k2=v2` Cookie 写入指定域名集合。
/// 批量写入后统一落盘，避免每条 Cookie 都触发同步磁盘 I/O。
/// 后台 isolate 没有 MainActivity 通道，保留原有逐条回退行为。
Future<void> injectCookieString({
  required String cookies,
  required List<String> domains,
  bool httpOnly = true,
  bool secure = true,
}) async {
  for (final part in cookies.split(';')) {
    final idx = part.indexOf('=');
    if (idx <= 0) continue;
    final name = part.substring(0, idx).trim();
    final value = part.substring(idx + 1).trim();
    if (name.isEmpty || value.isEmpty) continue;
    for (final domain in domains) {
      await setPlatformCookie(
        name: name,
        value: value,
        domain: domain,
        httpOnly: httpOnly,
        secure: secure,
        flush: false,
      );
    }
  }
  if (!_nativeChannelUnavailable) {
    try {
      await _webviewChannel.invokeMethod<bool>('flushCookies');
    } on MissingPluginException {
      _nativeChannelUnavailable = true;
    } catch (e) {
      debugPrint('[Cookie] batch flush failed: $e');
    }
  }
}
