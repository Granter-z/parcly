import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../platform/connectors/connector_manager.dart';
import '../../../platform/storage/platform_auth_store.dart';
import '../../providers/platform_auth_status_provider.dart';
import '../pdd/pdd_web_screen.dart';
import 'platform_login_screen.dart';

/// 平台的展示信息，设置页和首页状态条共用。
class PlatformInfo {
  final String id;
  final String shortName;
  final String displayName;
  final Color brandColor;

  const PlatformInfo(this.id, this.shortName, this.displayName, this.brandColor);
}

/// 状态条展示顺序：拼多多 → 京东 → 淘宝（与界面稿一致）。
const List<PlatformInfo> kPlatforms = [
  PlatformInfo('pdd', '拼多多', '拼多多', Color(0xFFE02E24)),
  PlatformInfo('jd', '京东', '京东商城', Color(0xFFE1251B)),
  PlatformInfo('taobao', '淘宝', '淘宝 / 天猫', Color(0xFFFF5000)),
];

/// 只同步这一个平台（重新登录后用，不打扰其他平台）。
Future<int> syncSinglePlatform(WidgetRef ref, String platform) {
  final manager = ref.read(connectorManagerProvider);
  final connectors =
      manager.realConnectors.where((c) => c.platformId == platform.toLowerCase()).toList();
  return manager.syncWithConnectors(connectors);
}

/// 打开某个平台的登录（或重新登录）页面。登录成功返回 true。
///
/// 成功后清掉旧的失效提示、刷新登录状态，并只同步这个平台（三个平台一样）。
/// P27：成功后 pop 到根路由（默认回首页）；失败/取消不跳转。
Future<bool> openPlatformLogin(
  BuildContext context,
  WidgetRef ref, {
  required String platform,
  required String displayName,
  required Color brandColor,
}) async {
  final manager = ref.read(connectorManagerProvider);
  final store = PlatformAuthStore();
  // P29-a：记录进入时是否已失效；失败/取消离开后立刻对齐，不等下次刷新
  final wasExpiredAtOpen = store.isExpired(platform);
  final bool ok;
  if (platform.toLowerCase() == 'pdd') {
    // P27：登录意图打开时，检测到有效会话后自动 pop(true)；取消/失败不误跳。
    final result = await PddWebScreen.open(
      context,
      url: 'https://mobile.yangkeduo.com/login.html',
      popOnLoginSuccess: true,
    );
    // P29：失败/取消不得用「旧 cookie 仍在且未标失效」冒充成功
    ok = result == true;
  } else {
    ok = await PlatformLoginScreen.show(
          context,
          platform: platform,
          displayName: displayName,
          brandColor: brandColor,
        ) ==
        true;
  }
  if (!ok) {
    if (wasExpiredAtOpen) {
      await store.setExpired(platform, true);
    }
    ref.invalidate(platformAuthStatusProvider);
    return false;
  }
  manager.clearLastIssueFor(platform);
  ref.invalidate(platformAuthStatusProvider);
  syncSinglePlatform(ref, platform);
  // P27-b：默认回首页（从设置进的也 pop 到根 Navigator）
  if (context.mounted) {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }
  return true;
}
