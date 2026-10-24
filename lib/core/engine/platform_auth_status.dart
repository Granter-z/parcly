/// 平台登录状态的唯一判断规则（P11-d / P24 / P25）。
///
/// 纯 Dart，不依赖 Flutter。设置页与首页状态条应走这里；
/// Riverpod 包装见 `lib/ui/providers/platform_auth_status_provider.dart`。
///
/// **主真相是 [isExpired]**（连接器 / 保活心跳掉线时必须 `setExpired(true)`）。
/// `liveIssue` 仅作补充：明确登录失效信号 → needsRelogin；提到本平台但无信号 → syncFailed。
library;

enum PlatformAuthStatus {
  /// 没绑定过
  unbound,

  /// 已绑定且没发现掉线
  ok,

  /// 已绑定但掉线了，需要重新登录
  needsRelogin,

  /// 已绑定、登录没问题，但最近一次同步出错（网络、接口异常等），不用重登
  syncFailed,
}

/// 只有带这些明确信号的问题文本才算「登录失效」。
/// 前三个是淘宝接口原话，「登录态已失效」是三个连接器上报掉线时写的固定文字。
const List<String> kLoginExpiredSignals = [
  'FAIL_SYS_SESSION_EXPIRED',
  'FAIL_SYS_SID_INVALID',
  '您需要登录',
  '登录态已失效',
];

/// 同步问题文本里代表这个平台的关键词。
String platformIssueKeyword(String platform) {
  switch (platform.toLowerCase()) {
    case 'taobao':
    case 'tmall':
      return '淘宝';
    case 'jd':
      return '京东';
    case 'pdd':
      return '拼多多';
    default:
      return platform;
  }
}

/// 判断平台登录状态。
///
/// [liveIssue] 是最近一次同步的问题文本，多个平台的问题用「；」连在一起。
/// - [isExpired] 为真 → 需重登（主路径，连接器/保活必须落盘）
/// - 提到本平台且带 [kLoginExpiredSignals] → 需重登（兜底；正常应已 setExpired）
/// - 提到本平台、无登录信号 → 同步失败
/// - 没提到 → 正常
PlatformAuthStatus resolvePlatformAuthStatus({
  required String platform,
  required bool isBound,
  required bool isExpired,
  String? liveIssue,
}) {
  if (!isBound) return PlatformAuthStatus.unbound;
  if (isExpired) return PlatformAuthStatus.needsRelogin;
  final keyword = platformIssueKeyword(platform);
  final mine = (liveIssue ?? '')
      .split(RegExp('[；;\n]'))
      .where((seg) => seg.contains(keyword))
      .toList();
  if (mine.isEmpty) return PlatformAuthStatus.ok;
  final expired = mine.any((seg) => kLoginExpiredSignals.any(seg.contains));
  return expired ? PlatformAuthStatus.needsRelogin : PlatformAuthStatus.syncFailed;
}

/// 兼容旧调用：是否应展示为「已失效 / 需重登」
bool isPlatformShownExpired({
  required bool bound,
  required bool storeExpired,
  String? liveIssue,
  required String platformKeyword,
}) {
  // platformKeyword 由调用方传入时，反查平台 id 不划算；直接用关键词当 platform。
  final status = resolvePlatformAuthStatus(
    platform: _platformFromKeyword(platformKeyword),
    isBound: bound,
    isExpired: storeExpired,
    liveIssue: liveIssue,
  );
  return status == PlatformAuthStatus.needsRelogin;
}

String _platformFromKeyword(String keyword) {
  switch (keyword) {
    case '淘宝':
      return 'taobao';
    case '京东':
      return 'jd';
    case '拼多多':
      return 'pdd';
    default:
      return keyword;
  }
}
