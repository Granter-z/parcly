/// 电商平台保活服务（前台）
///
/// 职责：
/// 1. 定期发送轻量级心跳请求，保持 Cookie 活跃
/// 2. 智能调度：根据 Cookie 年龄调整频率，并落盘「下次保活时间」避免冷启动重发
/// 3. 静默运行：失败时不抛错，只记录状态与历史
///
/// 进程被系统回收后的续期由 `keep_alive_worker.dart`（WorkManager）承担，
/// 本服务只负责 App 进程存活期间的前台保活。
library;

import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../core/engine/keep_alive_outcome.dart';
import '../../core/engine/keep_alive_plan.dart';
import '../../core/models/keep_alive_state.dart';
import '../../core/models/platform_ids.dart';
import '../storage/keep_alive_store.dart';
import '../storage/platform_auth_store.dart';
import 'keep_alive_notifier.dart';
import 'keep_alive_worker_bridge.dart';
import 'platform_heartbeat.dart';

/// 保活服务
class KeepAliveService {
  final PlatformAuthStore _authStore;
  final KeepAliveStore _store;
  final Map<String, PlatformHeartbeat> _heartbeats;

  /// 最近一次同步时间来源（用于「用户同步后跳过保活」规则）
  final DateTime? Function(String platform)? _lastSyncTimeResolver;

  /// 状态变化回调，供 Riverpod 层推送新快照
  final void Function()? _onChanged;

  /// 平台之间的节流间隔，避免短时间内发送大量请求
  final Duration _interPlatformDelay;

  /// 失效提醒回调：传入本轮需要提醒的平台
  ///
  /// 默认走真实的本地通知；测试可注入空实现以避免触碰插件通道。
  late final Future<void> Function(List<String> platforms) _notifyExpired;

  /// 是否已启用保活（内存态，持久值在 [_store]）
  bool _enabled = true;

  /// 保活定时器（每小时检查一次，是否真正执行由各平台闸门决定）
  Timer? _timer;

  /// 启动中任务 Future：`start()` 的首个 await 之前 `_timer` 仍为空，
  /// 并发调用或中途 `setEnabled` 切换需要可等待与二次校验，防止定时器泄漏或状态反置。
  Future<void>? _startFuture;

  DateTime? _lastCheckAt;

  final Random _random = Random();

  /// [heartbeats] 为各平台心跳实现；拼多多依赖前台连接器的常驻 WebView，
  /// 默认表里只含纯 HTTP 可后台运行的平台，由调用方（`KeepAliveController`）补齐。
  ///
  /// [interPlatformDelay] 为平台之间的节流间隔，测试可传零以跳过等待。
  ///
  /// [notifyExpired] 为失效提醒回调，默认构造真实的本地通知。
  KeepAliveService({
    PlatformAuthStore? authStore,
    KeepAliveStore? store,
    Map<String, PlatformHeartbeat>? heartbeats,
    DateTime? Function(String platform)? lastSyncTimeResolver,
    void Function()? onChanged,
    Duration interPlatformDelay = const Duration(seconds: 5),
    Future<void> Function(List<String> platforms)? notifyExpired,
  })  : _authStore = authStore ?? PlatformAuthStore(),
        _store = store ?? KeepAliveStore(),
        _heartbeats = heartbeats ??
            {
              'taobao': TaobaoHeartbeat(),
              'jd': JdHeartbeat(),
            },
        _lastSyncTimeResolver = lastSyncTimeResolver,
        _onChanged = onChanged,
        _interPlatformDelay = interPlatformDelay {
    _notifyExpired = notifyExpired ??
        KeepAliveNotifier(store: _store, authStore: _authStore).notifyExpired;
  }

  /// 启动保活服务
  ///
  /// 先加载持久化状态：若用户已关闭保活则不启动；若各平台的「下次保活时间」
  /// 仍在闸门内，本轮检查不会发送任何心跳（这是冷启动不再重发请求的关键）。
  Future<void> start() {
    if (_timer != null) return Future<void>.value();
    final inflight = _startFuture;
    if (inflight != null) return inflight;

    final task = _startInner();
    _startFuture = task.whenComplete(() {
      if (identical(_startFuture, task)) _startFuture = null;
    });
    return _startFuture!;
  }

  Future<void> _startInner() async {
    await _store.loadIntoCache();
    // 合并 App 进程不在时 worker 的结果（跨 isolate 不写同一个 Hive box）
    await _applyWorkerResults();
    _enabled = _store.enabled;
    await _syncWorkerConfig();

    if (!_enabled) {
      debugPrint('[KeepAliveService] disabled by user, not starting');
      return;
    }

    debugPrint('[KeepAliveService] Starting keep-alive service...');
    await _performKeepAlive();

    if (!_enabled || _timer != null) return;
    // 每小时检查一次是否需要保活（各平台按动态间隔独立放行）
    _timer = Timer.periodic(const Duration(hours: 1), (_) {
      _performKeepAlive();
    });
  }

  /// 停止保活服务
  void stop() {
    debugPrint('[KeepAliveService] Stopping keep-alive service...');
    _timer?.cancel();
    _timer = null;
  }

  /// 设置是否启用保活（持久化，重启后仍生效）
  Future<void> setEnabled(bool enabled) async {
    await _store.setEnabled(enabled);
    _enabled = enabled;
    if (enabled) {
      final inflight = _startFuture;
      if (inflight != null) {
        await inflight;
      }
      await start();
      await _syncWorkerConfig();
    } else {
      stop();
      await _syncWorkerConfig();
    }
    _onChanged?.call();
  }

  /// 设置单个平台是否参与保活
  Future<void> setPlatformEnabled(String platform, bool enabled) async {
    await _store.setPlatformEnabled(platform, enabled);
    await _syncWorkerConfig();
    _onChanged?.call();
  }

  /// 执行保活（为所有已绑定且启用的平台发送心跳）
  ///
  /// [force] 为 true 时绕过「下次保活时间」闸门与冷却规则（手动保活按钮语义）。
  Future<void> _performKeepAlive({bool force = false}) async {
    if (!_enabled || _checking) return;
    _checking = true;
    try {
      await _performKeepAliveInner(force: force);
    } finally {
      _checking = false;
    }
  }

  /// 重入保护：周期检查与手动保活撞车时，同一平台不得并发发两次心跳、并发写闸门。
  bool _checking = false;

  Future<void> _performKeepAliveInner({bool force = false}) async {
    debugPrint('[KeepAliveService] Performing keep-alive check...');
    final now = DateTime.now();

    for (final platform in kPlatformIds) {
      if (!_enabled) break; // 中途被停止

      if (!_store.platformEnabled(platform)) {
        debugPrint('[KeepAliveService] Skip $platform: disabled');
        continue;
      }

      if (!_authStore.isBound(platform)) {
        debugPrint('[KeepAliveService] Skip $platform: not bound');
        continue;
      }

      // 没有心跳实现就整体跳过，且不推进闸门，否则该平台会被静默地「排期」而不真的探活
      final heartbeat = _heartbeats[platform];
      if (heartbeat == null) {
        debugPrint('[KeepAliveService] Skip $platform: no heartbeat implementation');
        continue;
      }

      final cookies = _authStore.getCookies(platform);
      if (cookies == null || cookies.trim().isEmpty) {
        debugPrint('[KeepAliveService] Skip $platform: no cookies');
        continue;
      }

      // Cookie 年龄：距用户上次授权的时间（不是 Cookie 上次刷新的时间）
      final boundTime = _authStore.getBoundTime(platform);
      final cookieAge = boundTime != null
          ? now.difference(boundTime)
          : const Duration(days: 999); // 未知年龄，假定很老

      // 闸门：持久化的下次保活时间，冷启动后依然生效
      if (!force) {
        final nextTime = _store.nextAt(platform);
        if (nextTime != null && now.isBefore(nextTime)) {
          final remaining = nextTime.difference(now);
          debugPrint(
              '[KeepAliveService] Skip $platform: next keep-alive in ${remaining.inMinutes} min');
          continue;
        }

        // 用户最近同步过 / 刚保活过则跳过
        if (KeepAlivePlan.shouldSkip(
          lastSyncTime: _lastSyncTimeResolver?.call(platform),
          lastKeepAliveTime: _store.lastAt(platform),
          now: now,
        )) {
          continue;
        }
      }

      final interval = KeepAlivePlan.calculateInterval(cookieAge);
      final kind =
          await _performHeartbeatForPlatform(platform, heartbeat, cookies, cookieAge);

      // 落盘下次保活时间（带随机抖动，避开固定时间点）。
      // 跳过不推进闸门：WebView 正忙/网络抖动只是本轮没探活，
      // 不该被排期到数小时后（与后台 worker 的语义保持一致）。
      if (kind != KeepAliveOutcomeKind.skipped) {
        final jitter = Duration(minutes: _random.nextInt(61) - 30);
        await _store.setNext(
          platform,
          KeepAlivePlan.calculateNextTime(interval, now: DateTime.now(), jitter: jitter),
        );
      }

      // 避免短时间内发送大量请求
      if (_interPlatformDelay > Duration.zero) {
        await Future.delayed(_interPlatformDelay);
      }
    }

    // 失效提醒：只对已启用且已绑定的平台提醒，避免打扰只做备份用途的账号
    final expired = kPlatformIds
        .where((p) =>
            _store.platformEnabled(p) && _authStore.isBound(p) && _authStore.isExpired(p))
        .toList();
    if (expired.isNotEmpty) {
      await _notifyExpired(expired);
    }

    // 把最新闸门/开关同步给后台 worker
    await _syncWorkerConfig();

    _lastCheckAt = DateTime.now();
    debugPrint('[KeepAliveService] Keep-alive check completed');
    _onChanged?.call();
  }

  /// 为单个平台执行心跳并落盘结果，返回结局分类（供调用方决定是否推进闸门）
  Future<KeepAliveOutcomeKind> _performHeartbeatForPlatform(
    String platform,
    PlatformHeartbeat heartbeat,
    String cookies,
    Duration cookieAge,
  ) async {
    debugPrint(
        '[KeepAliveService] Sending heartbeat to $platform (age: ${cookieAge.inDays} days)...');

    HeartbeatResult result;
    try {
      result = await heartbeat.performHeartbeat(cookies);
    } catch (e) {
      debugPrint('[KeepAliveService] $platform heartbeat error: $e');
      result = HeartbeatResult.failure('$e');
    }

    return _recordResult(platform, result);
  }

  /// 依据心跳结果更新持久化状态与失效标记，返回结局分类。
  ///
  /// [at] 为结果实际发生时间（合并 worker 结果时使用），默认当前时间。
  Future<KeepAliveOutcomeKind> _recordResult(
    String platform,
    HeartbeatResult result, {
    DateTime? at,
  }) async {
    final recordTime = at ?? DateTime.now();
    final kind = result.skipped
        ? KeepAliveOutcomeKind.skipped
        : result.success
            ? KeepAliveOutcomeKind.success
            : result.isAuthFailure
                ? KeepAliveOutcomeKind.authFailure
                : KeepAliveOutcomeKind.networkFailure;

    final plan = planKeepAliveOutcome(
      kind: kind,
      currentFailureCount: _store.failureCount(platform),
    );

    if (kind == KeepAliveOutcomeKind.skipped) {
      debugPrint('[KeepAliveService] - $platform heartbeat skipped: ${result.errorMessage}');
      await _store.appendHistory(KeepAliveRecord(
        platform: platform,
        time: recordTime,
        success: true,
        skipped: true,
        error: result.errorMessage,
      ));
      return KeepAliveOutcomeKind.skipped;
    }

    if (kind == KeepAliveOutcomeKind.success) {
      debugPrint('[KeepAliveService] ✓ $platform heartbeat success');
    } else if (kind == KeepAliveOutcomeKind.authFailure) {
      debugPrint('[KeepAliveService] ! $platform login expired (auth failure detected): ${result.errorMessage}');
    } else {
      debugPrint('[KeepAliveService] ✗ $platform heartbeat failed: ${result.errorMessage}');
      if (plan.touchExpired) {
        debugPrint(
            '[KeepAliveService] ! $platform login expired (${plan.failureCount} consecutive failures)');
      }
    }

    await applyHeartbeatOutcome(
      platform: platform,
      plan: plan,
      authStore: _authStore,
      store: _store,
      now: recordTime,
    );
    if (kind == KeepAliveOutcomeKind.success) {
      // 前台成功恢复后清除 worker 的失效提醒标记，避免重登后短期再失效被 7 天窗口压掉
      await clearWorkerNotifiedAt(platform);
    }

    await _store.appendHistory(KeepAliveRecord(
      platform: platform,
      time: recordTime,
      success: kind == KeepAliveOutcomeKind.success,
      authFailure: kind == KeepAliveOutcomeKind.authFailure,
      error: kind == KeepAliveOutcomeKind.success ? null : result.errorMessage,
    ));
    return kind;
  }

  /// 合并后台 worker 上次写下的结果。
  ///
  /// worker 不写 Hive，只写 JSON 结果文件；这里按与前台相同的落盘规则合并，
  /// 保证「后台成功恢复 / 后台判定失效」都能反映到前台状态与提醒。
  Future<void> _applyWorkerResults() async {
    final results = await readAndClearWorkerResults();
    if (results.isEmpty) return;
    if (!_store.enabled) {
      debugPrint(
          '[KeepAliveService] keep-alive disabled, discard ${results.length} worker result(s)');
      return;
    }

    debugPrint('[KeepAliveService] Applying ${results.length} worker result(s)');
    for (final r in results) {
      final kind = switch (r.kind) {
        'success' => KeepAliveOutcomeKind.success,
        'authFailure' => KeepAliveOutcomeKind.authFailure,
        'skipped' => KeepAliveOutcomeKind.skipped,
        _ => KeepAliveOutcomeKind.networkFailure,
      };
      final result = switch (kind) {
        KeepAliveOutcomeKind.success => HeartbeatResult.success(),
        KeepAliveOutcomeKind.authFailure =>
          HeartbeatResult.failure(r.error ?? '登录态已失效', isAuthFailure: true),
        KeepAliveOutcomeKind.skipped =>
          HeartbeatResult.skipped(r.error ?? '不可探活'),
        KeepAliveOutcomeKind.networkFailure =>
          HeartbeatResult.failure(r.error ?? '网络错误'),
      };

      await _recordResult(r.platform, result, at: r.time);
      if (kind != KeepAliveOutcomeKind.skipped && r.nextKeepAliveAt != null) {
        await _store.setNext(r.platform, r.nextKeepAliveAt);
      }
    }

    final expired = kPlatformIds
        .where((p) =>
            _store.platformEnabled(p) &&
            _authStore.isBound(p) &&
            _authStore.isExpired(p))
        .toList();
    if (expired.isNotEmpty) {
      await _notifyExpired(expired);
    }
  }

  /// 把开关与闸门同步给后台 worker（worker 只读 JSON 配置）
  Future<void> _syncWorkerConfig() async {
    await writeWorkerConfig(WorkerKeepAliveConfig(
      enabled: _store.enabled,
      platforms: {
        for (final p in kPlatformIds)
          p: WorkerPlatformConfig(
            enabled: _store.platformEnabled(p),
            nextKeepAliveAt: _store.nextAt(p),
            failureCount: _store.failureCount(p),
          ),
      },
    ));
  }

  /// 手动触发保活（状态页「手动保活」按钮）
  ///
  /// 绕过闸门：用户点了一次就应该真的发一次心跳，而不是被冷却规则跳过。
  Future<void> performManualKeepAlive() async {
    debugPrint('[KeepAliveService] Manual keep-alive triggered');
    await _store.loadIntoCache();
    _enabled = _store.enabled;
    await _performKeepAlive(force: true);
  }

  /// 重新读取持久化状态（后台 worker 写入后刷新界面用）
  Future<void> refreshFromStore() async {
    await _store.loadIntoCache();
    _enabled = _store.enabled;
  }

  /// 单个平台的保活状态
  PlatformKeepAliveStatus statusOf(String platform) {
    final now = DateTime.now();
    final boundTime = _authStore.getBoundTime(platform);
    final cookieAge = boundTime != null ? now.difference(boundTime) : null;
    final failureCount = _store.failureCount(platform);
    final isExpired = _authStore.isExpired(platform);

    return PlatformKeepAliveStatus(
      platform: platform,
      bound: _authStore.isBound(platform),
      enabled: _store.platformEnabled(platform),
      cookieAge: cookieAge,
      lastKeepAliveAt: _store.lastAt(platform),
      nextKeepAliveAt: _store.nextAt(platform),
      failureCount: failureCount,
      isExpired: isExpired,
      health: KeepAlivePlan.resolveHealth(
        isExpired: isExpired,
        failureCount: failureCount,
        cookieAge: cookieAge,
      ),
    );
  }

  /// 当前保活快照（界面 watch 的对象）
  KeepAliveSnapshot snapshot() {
    return KeepAliveSnapshot(
      enabled: _store.enabled,
      platforms: kPlatformIds.map(statusOf).toList(),
      history: _store.history.records,
      lastCheckAt: _lastCheckAt,
    );
  }

  /// 释放资源
  void dispose() {
    stop();
  }
}

/// 按 [plan] 将心跳结局落盘（供前台 [KeepAliveService] 合并结果及测试复用）。
Future<void> applyHeartbeatOutcome({
  required String platform,
  required KeepAliveOutcomePlan plan,
  required PlatformAuthStore authStore,
  required KeepAliveStore store,
  DateTime? now,
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
    await store.setLast(platform, now ?? DateTime.now());
  }
}
