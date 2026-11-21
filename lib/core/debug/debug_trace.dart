/// Debug 追踪工具（纯 Dart）
///
/// 只保留生产代码实际使用的两个入口；`enabled` 由 `main.dart` 按 kDebugMode 设置，
/// Release 不输出。日志不得包含运单号 / 订单号 / 取件码明文。
///
/// core 层禁止依赖 Flutter，无法用 debugPrint，故此处用 print 并整文件豁免 lint。
// ignore_for_file: avoid_print
library;

class DebugTrace {
  static bool enabled = true;

  static void separator(String label) {
    if (!enabled) return;
    print('');
    print('═══════════════════════════════════════════════════');
    print('  $label');
    print('═══════════════════════════════════════════════════');
  }

  static void error(String message, {Object? error, StackTrace? stackTrace}) {
    if (!enabled) return;
    print('ERROR: $message');
    if (error != null) print('  error: $error');
    if (stackTrace != null) print('  stack: $stackTrace');
  }
}
