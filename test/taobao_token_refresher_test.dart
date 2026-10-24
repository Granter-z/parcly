import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pickup_app/platform/keep_alive/taobao_token_refresher.dart';

void main() {
  group('classifyMtopBody', () {
    test('会话失效关键词', () {
      expect(
        classifyMtopBody('{"ret":["FAIL_SYS_SESSION_EXPIRED::Session过期"]}'),
        MtopBodyKind.sessionExpired,
      );
      expect(
        classifyMtopBody('FAIL_SYS_SID_INVALID'),
        MtopBodyKind.sessionExpired,
      );
      expect(
        classifyMtopBody('您需要登录才能继续访问'),
        MtopBodyKind.sessionExpired,
      );
    });

    test('令牌可重试', () {
      expect(classifyMtopBody('FAIL_SYS_TOKEN_EXPIRED'), MtopBodyKind.tokenRetryable);
      expect(classifyMtopBody('FAIL_SYS_TOKEN_EMPTY'), MtopBodyKind.tokenRetryable);
    });

    test('正常体', () {
      expect(classifyMtopBody('{"data":{"t":1}}'), MtopBodyKind.ok);
    });
  });

  group('MtopRefreshResult 互斥', () {
    test('ok / expired / network 字段互斥', () {
      final ok = MtopRefreshResult.ok(newToken: 'a');
      expect(ok.sessionExpired, isFalse);
      expect(ok.networkError, isFalse);
      expect(ok.rotated, isTrue);

      final expired = MtopRefreshResult.expired();
      expect(expired.sessionExpired, isTrue);
      expect(expired.networkError, isFalse);

      final net = MtopRefreshResult.network();
      expect(net.networkError, isTrue);
      expect(net.sessionExpired, isFalse);
      expect(net.rotated, isFalse);
    });
  });

  group('TaobaoTokenRefresher.refresh（MockClient）', () {
    test('sessionExpired 与 networkError 互斥：服务端失效', () async {
      final client = MockClient((request) async {
        return http.Response(
          '{"ret":["FAIL_SYS_SESSION_EXPIRED::x"]}',
          200,
        );
      });
      final result = await TaobaoTokenRefresher.refresh('k=v; _m_h5_tk=abc_1', client: client);
      expect(result.sessionExpired, isTrue);
      expect(result.networkError, isFalse);
    });

    test('网络异常只标 networkError', () async {
      final client = MockClient((request) async {
        throw http.ClientException('offline');
      });
      final result = await TaobaoTokenRefresher.refresh('k=v', client: client);
      expect(result.networkError, isTrue);
      expect(result.sessionExpired, isFalse);
    });

    test('成功时可带回轮换令牌', () async {
      final client = MockClient((request) async {
        // 单条 Set-Cookie：避免逗号被当成多 header 分隔后误伤解析
        return http.Response(
          '{"ret":["SUCCESS::OK"],"data":{}}',
          200,
          headers: {'set-cookie': '_m_h5_tk=newtok_99; Path=/'},
        );
      });
      final result = await TaobaoTokenRefresher.refresh('k=v; _m_h5_tk=old_1', client: client);
      expect(result.networkError, isFalse, reason: '${result.sessionExpired}/${result.networkError}');
      expect(result.sessionExpired, isFalse);
      expect(result.newToken, 'newtok_99');
    });

    test('TOKEN_EXPIRED 重试仍失败 → sessionExpired', () async {
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        return http.Response('FAIL_SYS_TOKEN_EXPIRED', 200);
      });
      final result = await TaobaoTokenRefresher.refresh('k=v', client: client);
      expect(calls, 2);
      expect(result.sessionExpired, isTrue);
      expect(result.networkError, isFalse);
    });
  });
}
