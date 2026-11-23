/// 后台保活 Worker（WorkManager 后台 isolate 入口）
///
/// App 进程被杀后，WorkManager 定时唤醒本 isolate，对淘宝/京东执行纯 HTTP
/// 续期。拼多多心跳依赖 WebView，后台无 Activity 无法运行，故不在表内。
///
/// P45：worker **不写任何 Hive box**。主 App 与 worker 在同一进程的不同 isolate
/// 打开同一个 box 时，Hive 的写偏移各自缓存，主 App 崩溃恢复截断文件后 worker
/// 继续按旧偏移写入会反复损坏 box（真机每次冷启动打印 "Recovering corrupted box."）。
/// 现在改为：读主 isolate 下发的 JSON 配置，结果写 JSON 文件，下次启动由主 isolate 合并。
library;

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:workmanager/workmanager.dart';

import '../../core/engine/keep_alive_outcome.dart';
import '../../core/engine/keep_alive_plan.dart';
import '../../core/models/platform_ids.dart';
import '../notification/notification_adapter.dart';
import '../storage/platform_auth_store.dart';
import 'keep_alive_worker_bridge.dart';
import 'platform_heartbeat.dart';

export 'keep_alive_service.dart' show applyHeartbeatOutcome;

/// 后台可续期平台 → 心跳实现。
///
/// 与 [kBackgroundKeepAlivePlatformIds] 对齐：不在表内的平台（拼多多）不可后台续期。
final Map<String, PlatformHeartbeat> _backgroundHeartbeats = {
  // 不把轮换令牌写回 Hive：跨 isolate 写 box 会损坏文件；下次前台会自行轮换。
  'taobao': TaobaoHeartbeat(persistTokenRotation: false),
  'jd': JdHeartbeat(),
};

/// WorkManager 回调入口（顶层函数，@pragma 保证 release 下不被 tree-shake）。
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    try {
      await _runBackgroundKeepAlive();
      return true;
    } catch (e) {
      // Hive / Keystore 初始化失败也会落到这里：返回 false 让系统可重试
      debugPrint('[KeepAliveWorker] task error: $e');
      return false;
    }
  });
}

/// 后台续期主体：读取主 isolate 配置，对每个平台发送心跳，结果写 JSON 待合并。
Future<void> _runBackgroundKeepAlive() async {
  // 后台 isolate 独立于主进程，需重新初始化存储路径与解密通道。
  // readOnly：禁止 worker 触发 Hive 崩溃恢复/压缩写入凭据盒。
  await Hive.initFlutter();
  await PlatformAuthStore.initialize(readOnly: true);

  final authStore = PlatformAuthStore();
  final config = await readWorkerConfig();
  if (config == null) {
    debugPrint('[KeepAliveWorker] no config yet, skip');
    return;
  }
  if (!config.enabled) {
    debugPrint('[KeepAliveWorker] keep-alive disabled by user, skip');
    return;
  }

  final now = DateTime.now();
  final results = <WorkerHeartbeatResult>[];
  final notifiedAt = await readWorkerNotifiedAt();
  final gates = await readWorkerGates();
  var notifyDirty = false;
  var gateDirty = false;

  for (final entry in _backgroundHeartbeats.entries) {
    final platform = entry.key;
    final platformConfig = config.platforms[platform];
    final cookies = authStore.getCookies(platform);
    final skip = resolveBackgroundSkip(
      masterEnabled: config.enabled,
      platformEnabled: platformConfig?.enabled ?? true,
      bound: authStore.isBound(platform),
      hasCookies: cookies != null && cookies.trim().isNotEmpty,
      now: now,
      // 主 isolate 的闸门与 worker 自己上次算出的闸门取较晚者：
      // App 长期不打开时 worker 仍遵守 12-24h 的间隔，而不是每 4h 重发。
      nextKeepAliveAt: _laterOf(platformConfig?.nextKeepAliveAt, gates[platform]),
    );
    if (skip != null) {
      debugPrint('[KeepAliveWorker] Skip $platform: ${skip.name}');
      continue;
    }

    debugPrint('[KeepAliveWorker] Refresh $platform...');
    HeartbeatResult result;
    try {
      result = await entry.value.performHeartbeat(cookies!);
    } catch (e) {
      // 未分类异常按网络失败上报，达阈值由主 isolate 决定是否失效。
      debugPrint('[KeepAliveWorker] $platform error: $e');
      result = HeartbeatResult.failure('$e', isAuthFailure: false);
    }

    final kind = classifyHeartbeatResult(result);
    final interval =
        KeepAlivePlan.calculateInterval(_cookieAge(authStore, platform, now));
    final next = kind == KeepAliveOutcomeKind.skipped
        ? null
        : KeepAlivePlan.calculateNextTime(interval, now: DateTime.now());
    if (next != null) {
      gates[platform] = next;
      gateDirty = true;
    }

    results.add(WorkerHeartbeatResult(
      platform: platform,
      kind: kind.name,
      error: result.errorMessage,
      time: DateTime.now(),
      nextKeepAliveAt: next,
    ));

    if (kind == KeepAliveOutcomeKind.authFailure) {
      // 去重标记由 worker 自己的 JSON 维护；成功恢复后清除，下一轮可再提醒。
      final last = notifiedAt[platform];
      final shouldNotify = last == null ||
          DateTime.now().difference(last) > const Duration(days: 7);
      if (shouldNotify) {
        try {
          final adapter = NotificationAdapter();
          await adapter.initialize();
          // 权限未授予时 Android 会静默丢弃通知，不能写去重标记
          if (await adapter.notificationsEnabled()) {
            await adapter.showKeepAliveExpiredNotification(
              platform: platform,
              displayName: platformDisplayName(platform),
            );
            notifiedAt[platform] = DateTime.now();
            notifyDirty = true;
          }
        } catch (e) {
          debugPrint('[KeepAliveWorker] notify failed: $e');
        }
      }
    } else if (kind == KeepAliveOutcomeKind.success) {
      if (notifiedAt.remove(platform) != null) notifyDirty = true;
    }

    debugPrint('[KeepAliveWorker] $platform → ${kind.name}');
  }

  if (notifyDirty) await writeWorkerNotifiedAt(notifiedAt);
  if (gateDirty) await writeWorkerGates(gates);
  await writeWorkerResults(results);
}

DateTime? _laterOf(DateTime? a, DateTime? b) {
  if (a == null) return b;
  if (b == null) return a;
  return a.isAfter(b) ? a : b;
}

/// HeartbeatResult → 结局分类（单测可直接喂构造好的 Result）
KeepAliveOutcomeKind classifyHeartbeatResult(HeartbeatResult result) {
  if (result.skipped) return KeepAliveOutcomeKind.skipped;
  if (result.success) return KeepAliveOutcomeKind.success;
  if (result.isAuthFailure) return KeepAliveOutcomeKind.authFailure;
  return KeepAliveOutcomeKind.networkFailure;
}

Duration _cookieAge(
    PlatformAuthStore authStore, String platform, DateTime now) {
  final boundTime = authStore.getBoundTime(platform);
  return boundTime != null
      ? now.difference(boundTime)
      : const Duration(days: 999);
}
