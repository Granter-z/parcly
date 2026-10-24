import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pickup_app/platform/keep_alive/platform_heartbeat.dart';
import 'package:pickup_app/platform/keep_alive/taobao_token_refresher.dart';

void main() {
  group('TaobaoHeartbeat.networkErrorMessage', () {
    test('无细节 → 光杆网络错误（兜底）', () {
      expect(TaobaoHeartbeat.networkErrorMessage(null), '网络错误');
      expect(TaobaoHeartbeat.networkErrorMessage(''), '网络错误');
    });

    test('有细节 → 网络错误: …', () {
      expect(
        TaobaoHeartbeat.networkErrorMessage('ClientException: offline'),
        '网络错误: ClientException: offline',
      );
    });
  });

  group('MtopRefreshResult → 历史副文案对齐', () {
    test('ClientException 经 refresher 后可拼出带细节的副文案', () async {
      final client = MockClient((request) async {
        throw http.ClientException('Connection refused');
      });
      final result = await TaobaoTokenRefresher.refresh('k=v', client: client);
      expect(result.networkError, isTrue);
      final msg = TaobaoHeartbeat.networkErrorMessage(result.errorDetail);
      expect(msg, startsWith('网络错误: '));
      expect(msg, contains('Connection refused'));
    });
  });

  group('TaobaoHeartbeat 网络短重试', () {
    test('首次 network → 重试成功 → success，共 2 次 refresh', () async {
      var calls = 0;
      final hb = TaobaoHeartbeat(
        refreshOverride: (cookies) async {
          calls++;
          if (calls == 1) {
            return MtopRefreshResult.network('Connection refused');
          }
          return MtopRefreshResult.ok();
        },
      );
      final r = await hb.performHeartbeat('k=v');
      expect(calls, 2);
      expect(r.success, isTrue);
      expect(r.isAuthFailure, isFalse);
    });

    test('两次均 network → 落盘带细节，且不标鉴权', () async {
      var calls = 0;
      final hb = TaobaoHeartbeat(
        refreshOverride: (cookies) async {
          calls++;
          return MtopRefreshResult.network('Connection refused');
        },
      );
      final r = await hb.performHeartbeat('k=v');
      expect(calls, 2);
      expect(r.success, isFalse);
      expect(r.isAuthFailure, isFalse);
      expect(r.errorMessage, '网络错误: Connection refused');
    });

    test('sessionExpired 不重试', () async {
      var calls = 0;
      final hb = TaobaoHeartbeat(
        refreshOverride: (cookies) async {
          calls++;
          return MtopRefreshResult.expired();
        },
      );
      final r = await hb.performHeartbeat('k=v');
      expect(calls, 1);
      expect(r.isAuthFailure, isTrue);
    });
  });
}
