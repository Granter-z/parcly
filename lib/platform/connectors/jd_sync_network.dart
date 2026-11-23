/// P42：京东同步网络硬失败判定与 soft 出口（纯 Dart，可单测）
library;

import 'dart:async';

/// Soft issue：含「京东」、**不含** [kLoginExpiredSignals] → UI 为 syncFailed，不需重登。
const String kJdNetworkSoftIssue = '京东暂时不可达，请稍后重试';

/// 京东 `streamSync` 外层硬超时（§P42-a）。
///
/// 真机冷启动时 hook 常在 6-14s 才拿到 order_list_m，8s 会先判「不可达」，
/// 而 Manager 的 20s 仍兜底。
const Duration kJdStreamSyncHardTimeout = Duration(seconds: 15);

/// Chromium 主文档网络硬失败（至少覆盖真机 P23 的 -6 / ERR_CONNECTION_REFUSED）。
bool jdIsNetworkHardFailure({
  required int errorCode,
  required String description,
}) {
  // Android WebView / Chromium net errors
  const hardCodes = {
    -2, // ERR_FAILED（视情况：主 frame 加载失败常跟不可达）
    -6, // ERR_CONNECTION_REFUSED
    -7, // ERR_CONNECTION_ABORTED
    -8, // ERR_TIMED_OUT
    -101, // ERR_CONNECTION_RESET
    -102, // ERR_CONNECTION_CLOSED
    -104, // ERR_CONNECTION_FAILED
    -105, // ERR_NAME_NOT_RESOLVED
    -106, // ERR_INTERNET_DISCONNECTED
    -109, // ERR_ADDRESS_UNREACHABLE
  };
  if (hardCodes.contains(errorCode)) return true;
  final d = description.toUpperCase();
  return d.contains('ERR_CONNECTION_REFUSED') ||
      d.contains('ERR_CONNECTION_TIMED_OUT') ||
      d.contains('ERR_TIMED_OUT') ||
      d.contains('ERR_NAME_NOT_RESOLVED') ||
      d.contains('ERR_CONNECTION_RESET') ||
      d.contains('ERR_CONNECTION_CLOSED') ||
      d.contains('ERR_CONNECTION_ABORTED') ||
      d.contains('ERR_CONNECTION_FAILED') ||
      d.contains('ERR_INTERNET_DISCONNECTED') ||
      d.contains('ERR_ADDRESS_UNREACHABLE');
}

/// 已标记本轮网络 soft 时，禁止因落 plogin/login 误标需重登（§P42-c）。
bool jdShouldExpireOnLoginLanding({
  required bool networkSoftFailThisRound,
  required String landedUrl,
}) {
  if (networkSoftFailThisRound) return false;
  final raw = landedUrl.trim();
  if (raw.isEmpty || raw.toLowerCase() == 'about:blank') return false;
  final uri = Uri.tryParse(raw);
  // 仅检查 host + path，忽略 query 中的 ReturnUrl=...orderlist... 参数误干扰
  final hostPath = uri != null && uri.host.isNotEmpty
      ? '${uri.host}${uri.path}'.toLowerCase()
      : raw.toLowerCase().split('?').first;
  return hostPath.contains('plogin') ||
      hostPath.contains('passport') ||
      (hostPath.contains('login') && !hostPath.contains('orderlist'));
}

/// 主 frame 硬失败时：置 soft、唤醒 hook 等待，供连接器立刻结束本轮。
class JdNetworkSoftFailGate {
  bool failed = false;
  String? issue;

  /// 订单列表 hook 等待 Completer；硬失败时 complete 以跳过 3.5s 空等。
  Completer<void>? wake;

  void onMainFrameError({
    required int errorCode,
    required String description,
    required bool isForMainFrame,
  }) {
    if (!isForMainFrame) return;
    if (!jdIsNetworkHardFailure(errorCode: errorCode, description: description)) {
      return;
    }
    apply('main frame $errorCode $description');
  }

  void apply(String reason) {
    if (failed) return;
    failed = true;
    issue = kJdNetworkSoftIssue;
    final c = wake;
    if (c != null && !c.isCompleted) {
      c.complete();
    }
  }
}
