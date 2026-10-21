/// 后台保活 Worker（WorkManager 后台 isolate 入口）
///
/// App 进程被杀后，WorkManager 定时唤醒本 isolate，对淘宝/京东执行纯 HTTP
/// 续期。拼多多心跳依赖 WebView，后台无 Activity 无法运行，故不在表内。
///
/// 调度闸门与前台 `KeepAliveService` 共用同一份落盘状态（`KeepAliveStore`），
/// 因此前后台不会各自发一轮重复心跳；本 isolate 只写标量键，绝不碰历史记录。
///
/// 判定失效后会尽力推送一次本地通知；是否成功都会由前台在下次检查时兜底。
library;

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:workmanager/workmanager.dart';

import '../../core/engine/keep_alive_outcome.dart';
import '../../core/engine/keep_alive_plan.dart';
import '../../core/models/platform_ids.dart';
import '../storage/keep_alive_store.dart';
import '../storage/platform_auth_store.dart';
import 'keep_alive_notifier.dart';
import 'platform_heartbeat.dart';

/// 后台可续期平台 → 心跳实现。
///
/// 与 [kBackgroundKeepAlivePlatformIds] 对齐：不在表内的平台（拼多多）不可后台续期。
/// 必须与 [kBackgroundKeepAlivePlatformIds] 保持一致（拼多多不在表内）。
final Map<String, PlatformHeartbeat> _backgroundHeartbeats = {
  'taobao': TaobaoHeartbeat(),
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

/// 后台续期主体：初始化存储后，对每个后台可续期平台发送心跳并落盘结果。
///
/// 抽出 [applyHeartbeatOutcome] 供单测验证落盘分支；本函数仍负责 I/O。
Future<void> _runBackgroundKeepAlive() async {
  // 后台 isolate 独立于主进程，需重新初始化存储路径与解密通道。
  // 任一步失败向上抛，由 callbackDispatcher 捕获并返回 false。
  await Hive.initFlutter();
  await PlatformAuthStore.initialize();
  await KeepAliveStore.initialize();

  final authStore = PlatformAuthStore();
  final store = KeepAliveStore();
  await store.loadIntoCache();

  if (!store.enabled) {
    debugPrint('[KeepAliveWorker] keep-alive disabled by user, skip');
    return;
  }

  final now = DateTime.now();

  for (final entry in _backgroundHeartbeats.entries) {
    final platform = entry.key;
    final cookies = authStore.getCookies(platform);
    final skip = resolveBackgroundSkip(
      masterEnabled: store.enabled,
      platformEnabled: store.platformEnabled(platform),
      bound: authStore.isBound(platform),
      hasCookies: cookies != null && cookies.trim().isNotEmpty,
      now: now,
      nextKeepAliveAt: store.nextAt(platform),
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
      // 对齐前台 KeepAliveService：异常不得 continue 丢掉计数。
      // 未分类异常按网络失败累计（isAuthFailure:false），达阈值才 setExpired；
      // 明确登录失效由心跳实现返回 isAuthFailure:true，不会走本 catch。
      debugPrint('[KeepAliveWorker] $platform error: $e');
      result = HeartbeatResult.failure('$e', isAuthFailure: false);
    }

    final kind = classifyHeartbeatResult(result);
    final plan = planKeepAliveOutcome(
      kind: kind,
      currentFailureCount: store.failureCount(platform),
    );
    await applyHeartbeatOutcome(
      platform: platform,
      plan: plan,
      authStore: authStore,
      store: store,
    );

    if (kind == KeepAliveOutcomeKind.success) {
      debugPrint('[KeepAliveWorker] $platform refreshed');
    } else if (kind == KeepAliveOutcomeKind.authFailure) {
      debugPrint('[KeepAliveWorker] $platform login expired');
    } else if (kind == KeepAliveOutcomeKind.skipped) {
      debugPrint('[KeepAliveWorker] $platform skipped: ${result.errorMessage}');
    } else {
      debugPrint(
          '[KeepAliveWorker] $platform refresh failed: ${result.errorMessage}');
    }

    // 跳过不推进闸门，避免「忙一轮」就把下次探活推到数小时后
    if (kind != KeepAliveOutcomeKind.skipped) {
      final interval =
          KeepAlivePlan.calculateInterval(_cookieAge(authStore, platform, now));
      await store.setNext(
        platform,
        KeepAlivePlan.calculateNextTime(interval, now: DateTime.now()),
      );
    }
  }

  // 失效提醒：后台 isolate 里弹通知是尽力而为。KeepAliveNotifier 只在发送成功后才写
  // 去重标记，因此这里失败也不会丢提醒 —— 前台下次检查会补发。
  final expired = _backgroundHeartbeats.keys
      .where((p) => store.platformEnabled(p) && authStore.isExpired(p))
      .toList();
  if (expired.isNotEmpty) {
    try {
      await KeepAliveNotifier(store: store, authStore: authStore)
          .notifyExpired(expired);
    } catch (e) {
      debugPrint('[KeepAliveWorker] notify failed: $e');
    }
  }
}

/// HeartbeatResult → 结局分类（单测可直接喂构造好的 Result）
KeepAliveOutcomeKind classifyHeartbeatResult(HeartbeatResult result) {
  if (result.skipped) return KeepAliveOutcomeKind.skipped;
  if (result.success) return KeepAliveOutcomeKind.success;
  if (result.isAuthFailure) return KeepAliveOutcomeKind.authFailure;
  return KeepAliveOutcomeKind.networkFailure;
}

/// 按 [plan] 落盘：抽出来方便单测验证「成功清失效 / 失效 setExpired / 跳过不动」
Future<void> applyHeartbeatOutcome({
  required String platform,
  required KeepAliveOutcomePlan plan,
  required PlatformAuthStore authStore,
  required KeepAliveStore store,
}) async {
  if (plan.touchExpired) {
    await authStore.setExpired(platform, plan.expiredValue);
  }
  if (plan.failureCount != null) {
    await store.setFailureCount(platform, plan.failureCount!);
  }
  if (plan.clearNotifyMark) {
    await store.setLastNotifiedAt(platform, null);
  }
  if (plan.updateLastSuccess) {
    await store.setLast(platform, DateTime.now());
  }
}

Duration _cookieAge(PlatformAuthStore authStore, String platform, DateTime now) {
  final boundTime = authStore.getBoundTime(platform);
  return boundTime != null ? now.difference(boundTime) : const Duration(days: 999);
}
