import 'package:flutter_test/flutter_test.dart';
import 'package:pickup_app/core/engine/keep_alive_outcome.dart';
import 'package:pickup_app/platform/keep_alive/platform_heartbeat.dart';

void main() {
  group('JdHeartbeat 探活 URL（P36-b 双探）', () {
    test('保留 wqs 探活，并以 trade 为失效真相源', () {
      expect(
        JdHeartbeat.probeUrl,
        'https://wqs.jd.com/order/orderlist_jdm.shtml',
      );
      expect(
        JdHeartbeat.tradeProbeUrl,
        'https://trade.m.jd.com/order/orderlist_jdm.shtml',
      );
    });
  });

  group('JdHeartbeat.classifyResponse', () {
    test('200 + 登录关键词 → authFailure', () {
      final r = JdHeartbeat.classifyResponse(
        statusCode: 200,
        body: '请登录后再查看订单',
      );
      expect(r.success, isFalse);
      expect(r.isAuthFailure, isTrue);
    });

    test('200 + 订单数据 → success', () {
      final r = JdHeartbeat.classifyResponse(
        statusCode: 200,
        body: '{"orderList":[]}',
      );
      expect(r.success, isTrue);
      expect(r.isAuthFailure, isFalse);
    });

    test('302 到登录页 → authFailure', () {
      final r = JdHeartbeat.classifyResponse(
        statusCode: 302,
        body: '',
        location: 'https://passport.jd.com/login',
      );
      expect(r.isAuthFailure, isTrue);
    });

    test('401/403 → authFailure；500 → 非 auth', () {
      expect(
        JdHeartbeat.classifyResponse(statusCode: 401, body: '').isAuthFailure,
        isTrue,
      );
      expect(
        JdHeartbeat.classifyResponse(statusCode: 500, body: '').isAuthFailure,
        isFalse,
      );
    });
  });

  group('JdHeartbeat.combineDualProbe（P36-b）', () {
    HeartbeatResult auth([String msg = '登录态已失效（响应要求登录）']) =>
        HeartbeatResult.failure(msg, isAuthFailure: true);

    HeartbeatResult net([String msg = '网络错误']) =>
        HeartbeatResult.failure(msg, isAuthFailure: false);

    test('trade 成功 + wqs 像登录 → success，且不得 touchExpired:true(失效)', () {
      final combined = JdHeartbeat.combineDualProbe(
        wqs: auth(),
        trade: HeartbeatResult.success(),
      );
      expect(combined.success, isTrue);
      expect(combined.isAuthFailure, isFalse);

      final plan = planKeepAliveOutcome(
        kind: KeepAliveOutcomeKind.success,
        currentFailureCount: 0,
      );
      // success 会 touchExpired 但 expiredValue=false（清失效），不得标失效
      expect(plan.touchExpired, isTrue);
      expect(plan.expiredValue, isFalse);
    });

    test('trade 也登录 → authFailure，才 expire', () {
      final combined = JdHeartbeat.combineDualProbe(
        wqs: auth(),
        trade: auth('登录态已失效（trade）'),
      );
      expect(combined.success, isFalse);
      expect(combined.isAuthFailure, isTrue);
      expect(combined.errorMessage, contains('trade'));

      final plan = planKeepAliveOutcome(
        kind: KeepAliveOutcomeKind.authFailure,
        currentFailureCount: 0,
      );
      expect(plan.touchExpired, isTrue);
      expect(plan.expiredValue, isTrue);
    });

    test('仅 trade 登录（wqs 成功）→ 仍 authFailure', () {
      final combined = JdHeartbeat.combineDualProbe(
        wqs: HeartbeatResult.success(),
        trade: auth(),
      );
      expect(combined.isAuthFailure, isTrue);
    });

    test('wqs 像登录 + trade 网络失败 → 非 auth（uncertain，不立刻 expire）', () {
      final combined = JdHeartbeat.combineDualProbe(
        wqs: auth(),
        trade: net('请求超时'),
      );
      expect(combined.success, isFalse);
      expect(combined.isAuthFailure, isFalse);
      expect(combined.errorMessage, contains('不确定'));

      final plan = planKeepAliveOutcome(
        kind: KeepAliveOutcomeKind.networkFailure,
        currentFailureCount: 0,
      );
      expect(plan.touchExpired, isFalse);
    });

    test('两边都成功 → success', () {
      final combined = JdHeartbeat.combineDualProbe(
        wqs: HeartbeatResult.success(),
        trade: HeartbeatResult.success(),
      );
      expect(combined.success, isTrue);
    });

    test('两边网络失败 → 非 auth', () {
      final combined = JdHeartbeat.combineDualProbe(
        wqs: net('超时'),
        trade: net('超时'),
      );
      expect(combined.isAuthFailure, isFalse);
      expect(combined.success, isFalse);
    });
  });
}
