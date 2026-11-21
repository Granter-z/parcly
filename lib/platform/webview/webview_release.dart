/// 同步用 WebView 的释放工具
///
/// webview_flutter 4.x 的 `WebViewController` 没有 `dispose()`：原生 WebView 的
/// 销毁由 Dart 侧控制器被 GC 后的 Finalizer 触发（见 webview_flutter_android 的
/// `PigeonInstanceManager.remove` → `WebViewPlatformView.destroy`）。
///
/// 因此「释放」= 先加载 about:blank 停掉页面活动与 JS 回调，再丢弃控制器引用，
/// 让 GC 有机会回收原生 WebView。只丢引用不拉 blank，页面会在后台继续跑脚本、
/// 发请求，既耗电也可能在 FlutterJNI detach 后刷警告。
library;

import 'package:webview_flutter/webview_flutter.dart';

/// 停掉页面活动；调用方随后应把持有的控制器引用置空。
Future<void> parkWebView(WebViewController? controller) async {
  if (controller == null) return;
  try {
    await controller.loadRequest(Uri.parse('about:blank'));
  } catch (_) {
    // 控制器可能已随页面销毁失效，忽略
  }
}
