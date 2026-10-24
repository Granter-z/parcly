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
    test('200 + 请登录硬文案 → authFailure', () {
      final r = JdHeartbeat.classifyResponse(
        statusCode: 200,
        body: '请登录后再查看',
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

    // --- P36-b′：硬 / 软 / 订单阳性 ---

    test('P36-b′：SPA 壳含 plogin.m.jd.com + title 订单 → success（本案复现）', () {
      // plogin 子串会命中 login.m.jd.com，但是软信号；订单阳性优先 success
      const body =
          '<html><head><title>订单</title>'
          '<script src="//plogin.m.jd.com/user/login.js"></script>'
          '</head><body>我的订单列表</body></html>';
      final r = JdHeartbeat.classifyResponse(statusCode: 200, body: body);
      expect(r.success, isTrue);
      expect(r.isAuthFailure, isFalse);
    });

    test('P36-b′：200 + login.m.jd.com SPA 壳、无订单 → 非 authFailure', () {
      final r = JdHeartbeat.classifyResponse(
        statusCode: 200,
        body: '<script>var u="//login.m.jd.com/oauth";</script><div>loading</div>',
      );
      expect(r.success, isFalse);
      expect(r.isAuthFailure, isFalse);
      expect(r.errorMessage, contains('软信号'));
    });

    test('P36-b′：200 + passport.jd.com 壳、无订单 → 非 authFailure', () {
      final r = JdHeartbeat.classifyResponse(
        statusCode: 200,
        body: 'cdn passport.jd.com/script.js bootstrap',
      );
      expect(r.isAuthFailure, isFalse);
      expect(r.success, isFalse);
    });

    test('P36-b′：200 + "isLogin":false → authFailure', () {
      final r = JdHeartbeat.classifyResponse(
        statusCode: 200,
        body: '{"isLogin":false,"msg":"need login"}',
      );
      expect(r.isAuthFailure, isTrue);
      expect(r.success, isFalse);
    });

    test('P36-b′：200 + "loginFlag":false → authFailure', () {
      final r = JdHeartbeat.classifyResponse(
        statusCode: 200,
        body: '{"loginFlag":false}',
      );
      expect(r.isAuthFailure, isTrue);
    });

    test('P36-b′：硬 auth 与订单词并存 → 硬优先 authFailure', () {
      final r = JdHeartbeat.classifyResponse(
        statusCode: 200,
        body: '请登录后查看订单 orderList',
      );
      expect(r.isAuthFailure, isTrue);
      expect(r.success, isFalse);
    });

    test('P36-b′：302 Location 含 plogin → authFailure', () {
      final r = JdHeartbeat.classifyResponse(
        statusCode: 302,
        body: '',
        location: 'https://plogin.m.jd.com/login/login',
      );
      expect(r.isAuthFailure, isTrue);
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

    test('P36-b′：wqs login-like + trade soft → 非 auth，不得 touchExpired', () {
      final tradeSoft = HeartbeatResult.failure(
        '无法确认登录态（软信号，不 expire）',
        isAuthFailure: false,
      );
      final combined = JdHeartbeat.combineDualProbe(
        wqs: auth(),
        trade: tradeSoft,
      );
      expect(combined.success, isFalse);
      expect(combined.isAuthFailure, isFalse);

      final plan = planKeepAliveOutcome(
        kind: KeepAliveOutcomeKind.networkFailure,
        currentFailureCount: 0,
      );
      expect(plan.touchExpired, isFalse);
    });

    // --- P36-b″：wqs OK + trade soft 不得累失败 expire ---

    test('P36-b″：wqs success + trade soft → combined.success，不得标失效', () {
      final tradeSoft = HeartbeatResult.failure(
        '无法确认登录态（软信号，不 expire）',
        isAuthFailure: false,
      );
      final combined = JdHeartbeat.combineDualProbe(
        wqs: HeartbeatResult.success(),
        trade: tradeSoft,
      );
      expect(combined.success, isTrue);
      expect(combined.isAuthFailure, isFalse);

      final plan = planKeepAliveOutcome(
        kind: KeepAliveOutcomeKind.success,
        currentFailureCount: 3, // 真机残差基线已有 3 次失败
      );
      // success 可 touchExpired 清失效，但不得 touchExpired:true + expiredValue:true
      expect(plan.touchExpired && plan.expiredValue, isFalse);
      expect(plan.expiredValue, isFalse);
      expect(plan.failureCount, 0);
    });

    test('P36-b″：wqs success + trade 网络抖 → combined.success', () {
      final combined = JdHeartbeat.combineDualProbe(
        wqs: HeartbeatResult.success(),
        trade: net('请求超时'),
      );
      expect(combined.success, isTrue);
      expect(combined.isAuthFailure, isFalse);
    });

    test('P36-b″：wqs auth + trade soft → 仍非 auth（uncertain），不得 expire', () {
      final tradeSoft = HeartbeatResult.failure(
        '无法确认登录态（软信号，不 expire）',
        isAuthFailure: false,
      );
      final combined = JdHeartbeat.combineDualProbe(
        wqs: auth(),
        trade: tradeSoft,
      );
      expect(combined.success, isFalse);
      expect(combined.isAuthFailure, isFalse);

      final plan = planKeepAliveOutcome(
        kind: KeepAliveOutcomeKind.networkFailure,
        currentFailureCount: 0,
      );
      expect(plan.touchExpired, isFalse);
    });

    test('P36-b″：连续 4 次 wqs OK + trade soft → 每次 success，不得累满 expire', () {
      final tradeSoft = HeartbeatResult.failure(
        '无法确认登录态（软信号，不 expire）',
        isAuthFailure: false,
      );
      var failureCount = 3;
      for (var i = 0; i < 4; i++) {
        final combined = JdHeartbeat.combineDualProbe(
          wqs: HeartbeatResult.success(),
          trade: tradeSoft,
        );
        expect(combined.success, isTrue, reason: 'round $i');
        final plan = planKeepAliveOutcome(
          kind: KeepAliveOutcomeKind.success,
          currentFailureCount: failureCount,
        );
        expect(plan.touchExpired && plan.expiredValue, isFalse, reason: 'round $i');
        expect(plan.expiredValue, isFalse, reason: 'round $i');
        failureCount = plan.failureCount ?? 0;
      }
      expect(failureCount, 0);
    });

    test('P36-b″：trade 硬 auth 仍一次 expire（回归）', () {
      final combined = JdHeartbeat.combineDualProbe(
        wqs: HeartbeatResult.success(),
        trade: auth('登录态已失效（HTTP 401）'),
      );
      expect(combined.isAuthFailure, isTrue);
      final plan = planKeepAliveOutcome(
        kind: KeepAliveOutcomeKind.authFailure,
        currentFailureCount: 0,
      );
      expect(plan.touchExpired, isTrue);
      expect(plan.expiredValue, isTrue);
    });
  });
}
