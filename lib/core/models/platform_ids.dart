/// 电商平台标识与显示名 - 纯Dart
library;

/// 全部支持保活的平台标识（顺序即界面展示顺序）
///
/// 需求方不要各自硬编码平台列表：保活服务、同步历史统计、设置页都从这里取。
const List<String> kPlatformIds = ['taobao', 'jd', 'pdd'];

/// 平台中文显示名；未知平台回退为标识本身
String platformDisplayName(String platform) {
  switch (platform) {
    case 'taobao':
      return '淘宝 / 天猫';
    case 'jd':
      return '京东商城';
    case 'pdd':
      return '拼多多';
    default:
      return platform;
  }
}

/// 可在 WorkManager 后台 isolate 里纯 HTTP 续期的平台
///
/// 拼多多依赖 WebView + anti_content，裸 FlutterEngine 无法跑，故不在表内。
/// 前台保活仍覆盖全部 [kPlatformIds]；UI 可用 [supportsBackgroundKeepAlive] 提示
/// 「拼多多需打开 App 才能保活」。
const List<String> kBackgroundKeepAlivePlatformIds = ['taobao', 'jd'];

/// 该平台是否支持进程外（后台）续期
bool supportsBackgroundKeepAlive(String platform) =>
    kBackgroundKeepAlivePlatformIds.contains(platform.toLowerCase());
