import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/engine/platform_auth_status.dart';
import '../../platform/connectors/connector_manager.dart';
import '../../platform/storage/platform_auth_store.dart';

export '../../core/engine/platform_auth_status.dart' show PlatformAuthStatus;

/// 某个平台的登录状态（未绑定 / 正常 / 需重登）。
///
/// 每次同步开始、结束都会自动重算（监听 syncStateProvider）。
/// PlatformAuthStore 本身不通知变化，所以重新登录、解绑之后要调用
/// `ref.invalidate(platformAuthStatusProvider)`。
final platformAuthStatusProvider =
    Provider.family<PlatformAuthStatus, String>((ref, platform) {
  ref.watch(syncStateProvider);
  final store = PlatformAuthStore();
  return resolvePlatformAuthStatus(
    platform: platform,
    isBound: store.isBound(platform),
    isExpired: store.isExpired(platform),
    liveIssue: ref.watch(connectorManagerProvider).lastIssue,
  );
});
