import 'package:flutter_test/flutter_test.dart';
import 'package:pickup_app/platform/keep_alive/platform_heartbeat.dart';

void main() {
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
}
