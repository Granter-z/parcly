import 'package:flutter_test/flutter_test.dart';
import 'package:pickup_app/core/engine/login_session_gate.dart';

void main() {
  group('cookieStringHasLoginSession', () {
    test('京东需要 pt_key + pt_pin', () {
      expect(cookieStringHasLoginSession('jd', 'pt_key=A; pt_pin=u'), isTrue);
      expect(cookieStringHasLoginSession('jd', 'pt_key=A'), isFalse);
      expect(cookieStringHasLoginSession('jd', 'foo=bar'), isFalse);
    });

    test('淘宝需要 cookie2 + unb/cookie1', () {
      expect(cookieStringHasLoginSession('taobao', 'cookie2=x; unb=1'), isTrue);
      expect(cookieStringHasLoginSession('taobao', '_m_h5_tk=only'), isFalse);
    });
  });

  group('isSameLoginSession / mayCommitNewLoginSuccess', () {
    const baseline = 'pt_key=OLDKEY; pt_pin=jiahao; other=1';
    const sameEcho = 'pt_key=OLDKEY; pt_pin=jiahao; other=2';
    const fresh = 'pt_key=NEWKEY; pt_pin=jiahao; other=3';

    test('注入旧 cookie 后采到相同指纹 → 同会话', () {
      expect(
        isSameLoginSession(
          platform: 'jd',
          baselineCookies: baseline,
          collectedCookies: sameEcho,
        ),
        isTrue,
      );
    });

    test('静默假成功：同会话不得 commit', () {
      expect(
        mayCommitNewLoginSuccess(
          platform: 'jd',
          collectedCookies: sameEcho,
          baselineCookies: baseline,
        ),
        isFalse,
      );
    });

    test('新 pt_key 可 commit', () {
      expect(
        mayCommitNewLoginSuccess(
          platform: 'jd',
          collectedCookies: fresh,
          baselineCookies: baseline,
        ),
        isTrue,
      );
    });

    test('首次绑定无基线：有会话可 commit', () {
      expect(
        mayCommitNewLoginSuccess(
          platform: 'jd',
          collectedCookies: fresh,
          baselineCookies: null,
        ),
        isTrue,
      );
    });

    test('异常信号禁止 commit', () {
      expect(
        mayCommitNewLoginSuccess(
          platform: 'jd',
          collectedCookies: fresh,
          baselineCookies: baseline,
          anomalyDetected: true,
        ),
        isFalse,
      );
    });
  });

  group('looksLikeJdLoginAnomaly', () {
    test('正文含登录异常', () {
      expect(
        looksLikeJdLoginAnomaly(url: 'https://home.m.jd.com/', pageText: '登录异常，请稍后重试'),
        isTrue,
      );
    });

    test('正常个人中心不误判', () {
      expect(
        looksLikeJdLoginAnomaly(url: 'https://home.m.jd.com/myJd/', pageText: '我的京东 待收货'),
        isFalse,
      );
    });
  });

  group('shouldMarkExpiredOnLoginLeave', () {
    test('成功离开不标失效', () {
      expect(
        shouldMarkExpiredOnLoginLeave(
          loginCommitted: true,
          wasExpiredAtOpen: true,
          anomalyDetected: true,
        ),
        isFalse,
      );
    });

    test('重登入口失败离开 → 标失效', () {
      expect(
        shouldMarkExpiredOnLoginLeave(
          loginCommitted: false,
          wasExpiredAtOpen: true,
          anomalyDetected: false,
        ),
        isTrue,
      );
    });

    test('异常离开 → 标失效', () {
      expect(
        shouldMarkExpiredOnLoginLeave(
          loginCommitted: false,
          wasExpiredAtOpen: false,
          anomalyDetected: true,
        ),
        isTrue,
      );
    });

    test('首次绑定取消 → 不标失效', () {
      expect(
        shouldMarkExpiredOnLoginLeave(
          loginCommitted: false,
          wasExpiredAtOpen: false,
          anomalyDetected: false,
        ),
        isFalse,
      );
    });
  });
}
