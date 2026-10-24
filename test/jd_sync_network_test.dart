import 'dart:async';
// P42-a/c：京东网络硬失败判定与 soft 出口（纯 Dart）
import 'package:flutter_test/flutter_test.dart';
import 'package:pickup_app/core/engine/platform_auth_status.dart';
import 'package:pickup_app/platform/connectors/jd_sync_network.dart';

void main() {
  group('jdIsNetworkHardFailure', () {
    test('ERR_CONNECTION_REFUSED (-6) 是硬失败', () {
      expect(
        jdIsNetworkHardFailure(
          errorCode: -6,
          description: 'net::ERR_CONNECTION_REFUSED',
        ),
        isTrue,
      );
    });

    test('ERR_TIMED_OUT (-8) / ERR_NAME_NOT_RESOLVED (-105) 是硬失败', () {
      expect(
        jdIsNetworkHardFailure(errorCode: -8, description: 'net::ERR_TIMED_OUT'),
        isTrue,
      );
      expect(
        jdIsNetworkHardFailure(
          errorCode: -105,
          description: 'net::ERR_NAME_NOT_RESOLVED',
        ),
        isTrue,
      );
    });

    test('ERR_FAILED (-2) 视情况计入硬失败', () {
      expect(
        jdIsNetworkHardFailure(errorCode: -2, description: 'net::ERR_FAILED'),
        isTrue,
      );
    });

    test('HTTP 类描述不算硬失败', () {
      expect(
        jdIsNetworkHardFailure(errorCode: -200, description: 'HTTP 404'),
        isFalse,
      );
    });
  });

  group('JdNetworkSoftFailGate', () {
    test('主 frame 硬失败立刻置 soft，二次调用幂等', () {
      final gate = JdNetworkSoftFailGate();
      gate.onMainFrameError(
        errorCode: -6,
        description: 'net::ERR_CONNECTION_REFUSED',
        isForMainFrame: true,
      );
      expect(gate.failed, isTrue);
      expect(gate.issue, kJdNetworkSoftIssue);
      gate.onMainFrameError(
        errorCode: -6,
        description: 'net::ERR_CONNECTION_REFUSED',
        isForMainFrame: true,
      );
      expect(gate.issue, kJdNetworkSoftIssue);
    });

    test('非主 frame 不触发', () {
      final gate = JdNetworkSoftFailGate();
      gate.onMainFrameError(
        errorCode: -6,
        description: 'net::ERR_CONNECTION_REFUSED',
        isForMainFrame: false,
      );
      expect(gate.failed, isFalse);
      expect(gate.issue, isNull);
    });

    test('硬失败唤醒 hook Completer', () async {
      final gate = JdNetworkSoftFailGate();
      gate.wake = Completer<void>();
      final future = gate.wake!.future;
      gate.onMainFrameError(
        errorCode: -6,
        description: 'net::ERR_CONNECTION_REFUSED',
        isForMainFrame: true,
      );
      await future.timeout(const Duration(milliseconds: 50));
      expect(gate.failed, isTrue);
    });
  });

  group('jdShouldExpireOnLoginLanding', () {
    test('网络 soft 本轮禁止 expire', () {
      expect(
        jdShouldExpireOnLoginLanding(
          networkSoftFailThisRound: true,
          landedUrl: 'https://plogin.m.jd.com/login',
        ),
        isFalse,
      );
    });

    test('无 soft 且落 plogin 才 expire', () {
      expect(
        jdShouldExpireOnLoginLanding(
          networkSoftFailThisRound: false,
          landedUrl: 'https://plogin.m.jd.com/login/login',
        ),
        isTrue,
      );
      expect(
        jdShouldExpireOnLoginLanding(
          networkSoftFailThisRound: false,
          landedUrl: 'https://wqs.jd.com/order/orderlist_jdm.shtml',
        ),
        isFalse,
      );
    });
  });

  group('P42-c soft issue → syncFailed', () {
    test('kJdNetworkSoftIssue 无登录信号 → syncFailed，不需重登', () {
      final status = resolvePlatformAuthStatus(
        platform: 'jd',
        isBound: true,
        isExpired: false,
        liveIssue: kJdNetworkSoftIssue,
      );
      expect(status, PlatformAuthStatus.syncFailed);
      for (final sig in kLoginExpiredSignals) {
        expect(kJdNetworkSoftIssue.contains(sig), isFalse, reason: sig);
      }
    });

    test('Manager 超时文案同样 syncFailed', () {
      const msg = '京东暂时不可达或同步超时，已保留旧数据';
      expect(
        resolvePlatformAuthStatus(
          platform: 'jd',
          isBound: true,
          isExpired: false,
          liveIssue: msg,
        ),
        PlatformAuthStatus.syncFailed,
      );
    });
  });
}
