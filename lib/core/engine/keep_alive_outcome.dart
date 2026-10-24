/// 心跳结果 → 落盘动作（纯 Dart，前后台共用）
///
/// WorkManager worker 与前台 KeepAliveService 对成功 / 登录失效 / 网络失败 /
/// 跳过的处理必须一致：本文件是唯一真相源，便于单测覆盖分支。
library;

import 'keep_alive_plan.dart';

/// 一次心跳探活的分类结局（与平台传输细节解耦）
enum KeepAliveOutcomeKind {
  /// 探活成功（可能伴随令牌轮换，由调用方另行落盘）
  success,

  /// 明确的登录态失效
  authFailure,

  /// 网络 / 超时 / 未知错误（累计失败）
  ///
  /// P36-b：京东双探「不确定」（如 wqs 像登录但 trade 未确认）也归此类，
  /// **勿**立刻 setExpired；达 [KeepAlivePlan.failureThreshold] 才标失效。
  networkFailure,

  /// 本轮未真正探活（忙 / 不可用）；不得改失效标记或失败计数
  skipped,
}

/// 根据心跳结局算出应对存储做什么
class KeepAliveOutcomePlan {
  /// 是否调用 setExpired
  final bool touchExpired;

  /// touchExpired 为 true 时写入的值
  final bool expiredValue;

  /// 新的失败计数；null 表示不改
  final int? failureCount;

  /// 是否清空「本失效周期已通知」标记（成功恢复后允许下次再提醒）
  final bool clearNotifyMark;

  /// 是否刷新 last_keep_alive_at
  final bool updateLastSuccess;

  const KeepAliveOutcomePlan({
    required this.touchExpired,
    required this.expiredValue,
    required this.failureCount,
    required this.clearNotifyMark,
    required this.updateLastSuccess,
  });

  static const KeepAliveOutcomePlan noop = KeepAliveOutcomePlan(
    touchExpired: false,
    expiredValue: false,
    failureCount: null,
    clearNotifyMark: false,
    updateLastSuccess: false,
  );
}

/// 由心跳分类 + 当前失败计数，算出落盘计划
KeepAliveOutcomePlan planKeepAliveOutcome({
  required KeepAliveOutcomeKind kind,
  required int currentFailureCount,
  int failureThreshold = KeepAlivePlan.failureThreshold,
}) {
  switch (kind) {
    case KeepAliveOutcomeKind.skipped:
      return KeepAliveOutcomePlan.noop;
    case KeepAliveOutcomeKind.success:
      return const KeepAliveOutcomePlan(
        touchExpired: true,
        expiredValue: false,
        failureCount: 0,
        clearNotifyMark: true,
        updateLastSuccess: true,
      );
    case KeepAliveOutcomeKind.authFailure:
      return KeepAliveOutcomePlan(
        touchExpired: true,
        expiredValue: true,
        failureCount: failureThreshold,
        clearNotifyMark: false,
        updateLastSuccess: false,
      );
    case KeepAliveOutcomeKind.networkFailure:
      final next = currentFailureCount + 1;
      final expired = next >= failureThreshold;
      return KeepAliveOutcomePlan(
        touchExpired: expired,
        expiredValue: true,
        failureCount: next,
        clearNotifyMark: false,
        updateLastSuccess: false,
      );
  }
}

/// 后台 worker 是否应跳过某平台（在发心跳之前）
enum BackgroundSkipReason {
  masterDisabled,
  platformDisabled,
  notBound,
  noCookies,
  gated,
}

/// 返回非 null 表示本轮跳过该平台
BackgroundSkipReason? resolveBackgroundSkip({
  required bool masterEnabled,
  required bool platformEnabled,
  required bool bound,
  required bool hasCookies,
  required DateTime now,
  DateTime? nextKeepAliveAt,
}) {
  if (!masterEnabled) return BackgroundSkipReason.masterDisabled;
  if (!platformEnabled) return BackgroundSkipReason.platformDisabled;
  if (!bound) return BackgroundSkipReason.notBound;
  if (!hasCookies) return BackgroundSkipReason.noCookies;
  if (nextKeepAliveAt != null && now.isBefore(nextKeepAliveAt)) {
    return BackgroundSkipReason.gated;
  }
  return null;
}
