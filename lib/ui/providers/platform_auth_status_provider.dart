import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/engine/platform_auth_status.dart';
import '../../platform/connectors/connector_manager.dart';
import '../../platform/keep_alive/keep_alive_controller.dart';
import '../../platform/storage/platform_auth_store.dart';

export '../../core/engine/platform_auth_status.dart' show PlatformAuthStatus;

/// 某个平台的登录状态（未绑定 / 正常 / 需重登 / 同步失败）。
///
/// 每次同步开始/结束（syncStateProvider）或保活快照变化（keepAliveControllerProvider）
/// 时都会自动重算，确保后台/前台保活判定 Cookie 失效后状态栏与设置页立即变为「需重登」。
/// PlatformAuthStore 本身不通知变化，所以重新登录、解绑之后仍需调用
/// `ref.invalidate(platformAuthStatusProvider)`。
final platformAuthStatusProvider =
    Provider.family<PlatformAuthStatus, String>((ref, platform) {
  ref.watch(syncStateProvider);
  ref.watch(keepAliveControllerProvider);
  final store = PlatformAuthStore();
  return resolvePlatformAuthStatus(
    platform: platform,
    isBound: store.isBound(platform),
    isExpired: store.isExpired(platform),
    liveIssue: ref.watch(connectorManagerProvider).lastIssue,
  );
});
