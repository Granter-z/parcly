/// 平台登录状态的唯一判断规则（P4）。设置页和首页状态条都走这里。
///
/// 纯 Dart，不依赖 Flutter。Riverpod 包装见
/// lib/ui/providers/platform_auth_status_provider.dart。
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
/// 按文本判断是临时办法：等 P11-d 完成、三个连接器掉线都确定会调用 setExpired
/// 之后删掉这段，调用方不用改。
/// - 提到这个平台、并且带 [kLoginExpiredSignals] 里的信号 → 需重登；
/// - 提到这个平台、但没有登录失效信号 → 同步失败；
/// - 没提到 → 正常。
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
