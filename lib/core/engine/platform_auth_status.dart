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
}

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
/// [liveIssue] 是最近一次同步的问题文本。按关键词匹配它是临时办法：
/// 等 P11-d 完成、三个连接器掉线都确定会调用 setExpired 之后删掉这条，
/// 调用方不用改。
PlatformAuthStatus resolvePlatformAuthStatus({
  required String platform,
  required bool isBound,
  required bool isExpired,
  String? liveIssue,
}) {
  if (!isBound) return PlatformAuthStatus.unbound;
  if (isExpired) return PlatformAuthStatus.needsRelogin;
  final issue = liveIssue ?? '';
  if (issue.isNotEmpty && issue.contains(platformIssueKeyword(platform))) {
    return PlatformAuthStatus.needsRelogin;
  }
  return PlatformAuthStatus.ok;
}
