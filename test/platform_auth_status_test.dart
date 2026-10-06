import 'package:flutter_test/flutter_test.dart';
import 'package:pickup_app/core/engine/platform_auth_status.dart';

void main() {
  PlatformAuthStatus r(String p, {bool bound = true, bool expired = false, String? issue}) =>
      resolvePlatformAuthStatus(platform: p, isBound: bound, isExpired: expired, liveIssue: issue);

  test('没绑定就是未绑定，不管有没有过期标记或问题文本', () {
    expect(r('taobao', bound: false, expired: true, issue: '淘宝需重新登录'), PlatformAuthStatus.unbound);
  });

  test('有过期标记就需重登', () {
    expect(r('jd', expired: true), PlatformAuthStatus.needsRelogin);
  });

  test('问题文本里提到这个平台也算需重登，提到别的平台不影响', () {
    expect(r('pdd', issue: '拼多多登录已失效'), PlatformAuthStatus.needsRelogin);
    expect(r('jd', issue: '拼多多登录已失效'), PlatformAuthStatus.ok);
    expect(r('tmall', issue: '淘宝需重新登录'), PlatformAuthStatus.needsRelogin);
  });

  test('已绑定、没过期、没问题就是正常', () {
    expect(r('taobao'), PlatformAuthStatus.ok);
    expect(r('taobao', issue: ''), PlatformAuthStatus.ok);
  });
}
