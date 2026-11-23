import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../platform/connectors/connector_manager.dart';
import '../../../platform/keep_alive/keep_alive_controller.dart';
import '../../../platform/storage/platform_auth_store.dart';
import '../../../core/engine/platform_auth_status.dart';
import '../../../core/models/platform_ids.dart';
import '../../components/platform_meta.dart';
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

/// 状态条展示顺序：直接由 [kPlatformIds] 权威顺序与 [platform_meta.dart] 动态生成。
final List<PlatformInfo> kPlatforms = List.unmodifiable([
  for (final id in kPlatformIds)
    PlatformInfo(
      id,
      platformShortName(id),
      platformDisplayName(id),
      platformBrandColor(id),
    ),
]);

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
  // 在跨页面 await 之前预先获取容器与 messenger，避免源 Widget 卸载后操作 ref 或 context 抛异常
  final container = ProviderScope.containerOf(context, listen: false);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final manager = container.read(connectorManagerProvider);
  final store = PlatformAuthStore();
  // P43 B′：UI「需重登」（含 liveIssue 兜底）时先对齐 isExpired，再开登录流
  // → P37-b 不注入旧 cookie + 允许同指纹提交；失败离开仍保持失效（P29-a）
  final uiStatus = resolvePlatformAuthStatus(
    platform: platform,
    isBound: store.isBound(platform),
    isExpired: store.isExpired(platform),
    liveIssue: manager.lastIssue,
  );
  if (shouldAlignExpiredBeforeLoginOpen(uiStatus) && !store.isExpired(platform)) {
    await store.setExpired(platform, true);
  }
  if (!context.mounted) return false;
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
    container.invalidate(platformAuthStatusProvider);
    return false;
  }
  manager.clearLastIssueFor(platform);
  container.invalidate(platformAuthStatusProvider);
  unawaited(container.read(keepAliveControllerProvider.notifier).refresh());
  final connectors = manager.realConnectors
      .where((c) => c.platformId == platform.toLowerCase())
      .toList();
  unawaited(manager.syncWithConnectors(connectors));
  // P27-b：默认回首页（从设置进的也 pop 到根 Navigator）
  if (context.mounted) {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }
  messenger?.hideCurrentSnackBar();
  messenger?.showSnackBar(
    SnackBar(
      content: Text('$displayName 登录成功，正在同步'),
      behavior: SnackBarBehavior.floating,
    ),
  );
  return true;
}
