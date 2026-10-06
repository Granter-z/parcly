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

  test('只有明确的登录失效信号才算需重登', () {
    expect(r('pdd', issue: '拼多多登录态已失效，请在「设置」中重新登录'), PlatformAuthStatus.needsRelogin);
    expect(r('tmall', issue: '淘宝登录态已失效，请重新登录授权'), PlatformAuthStatus.needsRelogin);
    expect(r('taobao', issue: '淘宝接口返回 FAIL_SYS_SESSION_EXPIRED'), PlatformAuthStatus.needsRelogin);
    expect(r('taobao', issue: '淘宝：FAIL_SYS_SID_INVALID'), PlatformAuthStatus.needsRelogin);
    expect(r('taobao', issue: '淘宝提示您需要登录才能继续访问'), PlatformAuthStatus.needsRelogin);
  });

  test('提到这个平台但不是登录失效，算同步失败，不算需重登', () {
    expect(r('taobao', issue: '淘宝 / 天猫同步响应异常，已保留旧数据'), PlatformAuthStatus.syncFailed);
    expect(r('jd', issue: '京东同步响应异常，已保留旧数据'), PlatformAuthStatus.syncFailed);
  });

  test('多个平台的问题连在一起时各算各的，提到别的平台不影响', () {
    const issue = '拼多多登录态已失效，请在「设置」中重新登录；淘宝 / 天猫同步响应异常，已保留旧数据';
    expect(r('pdd', issue: issue), PlatformAuthStatus.needsRelogin);
    expect(r('taobao', issue: issue), PlatformAuthStatus.syncFailed);
    expect(r('jd', issue: issue), PlatformAuthStatus.ok);
  });

  test('已绑定、没过期、没问题就是正常', () {
    expect(r('taobao'), PlatformAuthStatus.ok);
    expect(r('taobao', issue: ''), PlatformAuthStatus.ok);
  });
}
