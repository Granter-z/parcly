import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pickup_app/platform/keep_alive/platform_heartbeat.dart';
import 'package:pickup_app/platform/keep_alive/taobao_token_refresher.dart';
import 'package:pickup_app/platform/storage/platform_auth_store.dart';

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

    test('明确成功才算 ok', () {
      expect(
        classifyMtopBody('{"ret":["SUCCESS::调用成功"],"data":{}}'),
        MtopBodyKind.ok,
      );
      // 无失效信号但没有成功标记（门户页/未知 retcode）不能当成登录有效
      expect(classifyMtopBody('{"data":{"t":1}}'), MtopBodyKind.unknown);
      expect(classifyMtopBody('<html>登录页</html>'), MtopBodyKind.unknown);
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

      final net = MtopRefreshResult.network('ClientException: offline');
      expect(net.networkError, isTrue);
      expect(net.sessionExpired, isFalse);
      expect(net.rotated, isFalse);
      expect(net.errorDetail, 'ClientException: offline');

      final bare = MtopRefreshResult.network();
      expect(bare.networkError, isTrue);
      expect(bare.errorDetail, isNull);
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

    test('网络异常只标 networkError，并保留异常摘要', () async {
      final client = MockClient((request) async {
        throw http.ClientException('offline');
      });
      final result = await TaobaoTokenRefresher.refresh('k=v', client: client);
      expect(result.networkError, isTrue);
      expect(result.sessionExpired, isFalse);
      expect(result.errorDetail, isNotNull);
      expect(result.errorDetail, contains('offline'));
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

    test('探活走用户维度的菜鸟包裹列表接口', () async {
      Uri? requested;
      final client = MockClient((request) async {
        requested = request.url;
        return http.Response('{"ret":["SUCCESS::OK"],"data":{}}', 200);
      });
      await TaobaoTokenRefresher.refresh('k=v', client: client);

      expect(
        requested!.path,
        '/h5/${TaobaoTokenRefresher.probeApi}/1.0/',
      );
      expect(requested!.queryParameters['data'], contains('pageSize'));
    });

    test('无法识别的响应按网络错误处理，不误报 success', () async {
      final client = MockClient((request) async {
        return http.Response('<html>wifi login</html>', 200);
      });
      final result = await TaobaoTokenRefresher.refresh('k=v', client: client);
      expect(result.networkError, isTrue);
      expect(result.sessionExpired, isFalse);
      expect(result.errorDetail, contains('无法识别'));
    });

    test('TOKEN_EMPTY 时用 Set-Cookie 下发的新令牌重试成功', () async {
      var calls = 0;
      String? retryCookie;
      final client = MockClient((request) async {
        calls++;
        if (calls == 1) {
          return http.Response(
            'FAIL_SYS_TOKEN_EMPTY',
            200,
            headers: {'set-cookie': '_m_h5_tk=tok1_1; Path=/'},
          );
        }
        retryCookie = request.headers['Cookie'];
        return http.Response('{"ret":["SUCCESS::OK"],"data":{}}', 200);
      });
      final result = await TaobaoTokenRefresher.refresh('k=v', client: client);

      expect(calls, 2);
      expect(result.sessionExpired, isFalse);
      expect(result.networkError, isFalse);
      expect(retryCookie, contains('tok1'));
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

    test('首轮 Set-Cookie 下发新令牌且返回 TOKEN_EMPTY，次轮成功未再下发 Set-Cookie 时持久化新令牌', () async {
      final tempDir = Directory.systemTemp.createTempSync('tb_refresher_persist_');
      Hive.init(tempDir.path);
      await Hive.openBox(kPlatformAuthBox);
      addTearDown(() async {
        await Hive.close();
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });

      final authStore = PlatformAuthStore();
      await authStore.saveCookies(
        'taobao',
        'cookie2=testc2; unb=testunb; _m_h5_tk=oldtok_1; _m_h5_tk_enc=oldenc_1',
      );

      var calls = 0;
      String? secondCookie;
      final client = MockClient((request) async {
        calls++;
        if (calls == 1) {
          return http.Response(
            'FAIL_SYS_TOKEN_EMPTY',
            200,
            headers: {
              'set-cookie': '_m_h5_tk=newtok_2; Path=/, _m_h5_tk_enc=newenc_2; Path=/',
            },
          );
        }
        secondCookie = request.headers['Cookie'];
        return http.Response('{"ret":["SUCCESS::OK"],"data":{}}', 200);
      });

      final hb = TaobaoHeartbeat(
        authStore: authStore,
        refreshOverride: (cookies) =>
            TaobaoTokenRefresher.refresh(cookies, client: client),
      );
      final hbResult = await hb.performHeartbeat(authStore.getCookies('taobao')!);

      expect(calls, 2);
      expect(hbResult.success, isTrue);
      expect(secondCookie, contains('_m_h5_tk=newtok_2'));

      final persisted = authStore.getCookies('taobao');
      expect(persisted, isNotNull);
      expect(persisted, contains('_m_h5_tk=newtok_2'));
      expect(persisted, contains('_m_h5_tk_enc=newenc_2'));
      expect(persisted, isNot(contains('oldtok_1')));
      expect(persisted, isNot(contains('oldenc_1')));
    });
  });
}
