import 'package:flutter_test/flutter_test.dart';
import 'package:pickup_app/platform/connectors/jd_trace_parser.dart';

void main() {
  group('isJdCookieHealthy (P30-b ②)', () {
    const original = 'pt_key=KEY_A; pt_pin=user; a=1; b=2; c=3; d=4; e=5';

    test('相同 pt_key + 长度够 → healthy', () {
      final refreshed = '$original; extra=1';
      expect(isJdCookieHealthy(original, refreshed), isTrue);
    });

    test('pt_key 缺失 → unhealthy', () {
      expect(
        isJdCookieHealthy(original, 'pt_pin=user; a=1; b=2; c=3; d=4; e=5'),
        isFalse,
      );
    });

    test('pt_key 值变化 → unhealthy（即使长度够）', () {
      final swapped = original.replaceFirst('KEY_A', 'KEY_B');
      expect(swapped.contains('pt_key='), isTrue);
      expect(swapped.length >= original.length * 0.5, isTrue);
      expect(isJdCookieHealthy(original, swapped), isFalse);
    });

    test('长度萎缩到一半以下 → unhealthy', () {
      expect(isJdCookieHealthy(original, 'pt_key=KEY_A'), isFalse);
    });

    test('空新串 → unhealthy', () {
      expect(isJdCookieHealthy(original, '   '), isFalse);
    });

    test('原串无 pt_key 时不强制要求新串有', () {
      expect(isJdCookieHealthy('a=1; b=2', 'a=1; b=2; c=3'), isTrue);
    });
  });

  group('shouldSkipJdCookiePersist (P30-b ①)', () {
    test('落登录页 → skip', () {
      expect(
        shouldSkipJdCookiePersist(
          landedLoginPage: true,
          markedExpiredThisRound: false,
        ),
        isTrue,
      );
    });

    test('本轮 setExpired(true) → skip', () {
      expect(
        shouldSkipJdCookiePersist(
          landedLoginPage: false,
          markedExpiredThisRound: true,
        ),
        isTrue,
      );
    });

    test('正常成功路径 → 不 skip', () {
      expect(
        shouldSkipJdCookiePersist(
          landedLoginPage: false,
          markedExpiredThisRound: false,
        ),
        isFalse,
      );
    });
  });

  group('kJdPersistCookieHosts (P30-b ④)', () {
    test('采集域不含 plogin', () {
      expect(
        kJdPersistCookieHosts.any((h) => h.toLowerCase().contains('plogin')),
        isFalse,
      );
      expect(kJdPersistCookieHosts, contains('https://trade.m.jd.com'));
      expect(kJdPersistCookieHosts, contains('https://home.m.jd.com'));
      expect(kJdPersistCookieHosts, isNot(contains('https://plogin.m.jd.com')));
    });
  });
}
