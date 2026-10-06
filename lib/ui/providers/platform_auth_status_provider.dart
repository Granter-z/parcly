import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/engine/platform_auth_status.dart';
import '../../platform/connectors/connector_manager.dart';
import '../../platform/storage/platform_auth_store.dart';

export '../../core/engine/platform_auth_status.dart' show PlatformAuthStatus;

/// 某个平台的登录状态（未绑定 / 正常 / 需重登）。
///
/// PlatformAuthStore 和 ConnectorManager 都不会主动通知变化，
/// 同步结束、重新登录、解绑之后调用 `ref.invalidate(platformAuthStatusProvider)` 刷新。
final platformAuthStatusProvider =
    Provider.family<PlatformAuthStatus, String>((ref, platform) {
  final store = PlatformAuthStore();
  return resolvePlatformAuthStatus(
    platform: platform,
    isBound: store.isBound(platform),
    isExpired: store.isExpired(platform),
    liveIssue: ref.watch(connectorManagerProvider).lastIssue,
  );
});
