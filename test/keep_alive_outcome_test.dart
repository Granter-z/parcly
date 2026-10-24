import 'package:flutter_test/flutter_test.dart';
import 'package:pickup_app/core/engine/keep_alive_outcome.dart';
import 'package:pickup_app/core/engine/keep_alive_plan.dart';
import 'package:pickup_app/core/models/platform_ids.dart';

void main() {
  group('planKeepAliveOutcome', () {
    test('success 清失效、失败计数归零、允许再提醒', () {
      final plan = planKeepAliveOutcome(
        kind: KeepAliveOutcomeKind.success,
        currentFailureCount: 2,
      );
      expect(plan.touchExpired, isTrue);
      expect(plan.expiredValue, isFalse);
      expect(plan.failureCount, 0);
      expect(plan.clearNotifyMark, isTrue);
      expect(plan.updateLastSuccess, isTrue);
    });

    test('authFailure 一次即失效并顶满失败计数', () {
      final plan = planKeepAliveOutcome(
        kind: KeepAliveOutcomeKind.authFailure,
        currentFailureCount: 0,
      );
      expect(plan.touchExpired, isTrue);
      expect(plan.expiredValue, isTrue);
      expect(plan.failureCount, KeepAlivePlan.failureThreshold);
      expect(plan.updateLastSuccess, isFalse);
    });

    test('networkFailure 累计未达阈值不标失效', () {
      final plan = planKeepAliveOutcome(
        kind: KeepAliveOutcomeKind.networkFailure,
        currentFailureCount: 1,
      );
      expect(plan.touchExpired, isFalse);
      expect(plan.failureCount, 2);
    });

    test('networkFailure 达阈值后标失效', () {
      final plan = planKeepAliveOutcome(
        kind: KeepAliveOutcomeKind.networkFailure,
        currentFailureCount: KeepAlivePlan.failureThreshold - 1,
      );
      expect(plan.touchExpired, isTrue);
      expect(plan.expiredValue, isTrue);
      expect(plan.failureCount, KeepAlivePlan.failureThreshold);
    });

    test('skipped 完全不动状态', () {
      final plan = planKeepAliveOutcome(
        kind: KeepAliveOutcomeKind.skipped,
        currentFailureCount: 2,
      );
      expect(plan, same(KeepAliveOutcomePlan.noop));
      expect(plan.touchExpired, isFalse);
      expect(plan.failureCount, isNull);
      expect(plan.updateLastSuccess, isFalse);
    });
  });

  group('resolveBackgroundSkip', () {
    final now = DateTime(2026, 10, 21, 12);

    test('总开关关闭', () {
      expect(
        resolveBackgroundSkip(
          masterEnabled: false,
          platformEnabled: true,
          bound: true,
          hasCookies: true,
          now: now,
        ),
        BackgroundSkipReason.masterDisabled,
      );
    });

    test('未绑定 / 无 cookie / 闸门未到', () {
      expect(
        resolveBackgroundSkip(
          masterEnabled: true,
          platformEnabled: true,
          bound: false,
          hasCookies: false,
          now: now,
        ),
        BackgroundSkipReason.notBound,
      );
      expect(
        resolveBackgroundSkip(
          masterEnabled: true,
          platformEnabled: true,
          bound: true,
          hasCookies: false,
          now: now,
        ),
        BackgroundSkipReason.noCookies,
      );
      expect(
        resolveBackgroundSkip(
          masterEnabled: true,
          platformEnabled: true,
          bound: true,
          hasCookies: true,
          now: now,
          nextKeepAliveAt: now.add(const Duration(hours: 3)),
        ),
        BackgroundSkipReason.gated,
      );
    });

    test('条件齐全时不跳过', () {
      expect(
        resolveBackgroundSkip(
          masterEnabled: true,
          platformEnabled: true,
          bound: true,
          hasCookies: true,
          now: now,
          nextKeepAliveAt: now.subtract(const Duration(minutes: 1)),
        ),
        isNull,
      );
    });
  });

  group('后台续期能力表', () {
    test('淘宝京东可后台，拼多多不可', () {
      expect(supportsBackgroundKeepAlive('taobao'), isTrue);
      expect(supportsBackgroundKeepAlive('jd'), isTrue);
      expect(supportsBackgroundKeepAlive('pdd'), isFalse);
      expect(kBackgroundKeepAlivePlatformIds, isNot(contains('pdd')));
    });
  });
}
