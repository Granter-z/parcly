/// 登录会话门闸（P29）：区分「注入旧 cookie 的静默回声」与「本轮新登录」。
///
/// 纯 Dart，不依赖 Flutter / Hive，方便单测。
library;

/// 是否判定为已登录会话（与 WebView 登录页 `_hasLoginSession` 口径一致）。
bool cookieStringHasLoginSession(String platform, String cookieStr) {
  String? valueOf(String name) {
    for (final part in cookieStr.split(';')) {
      final idx = part.indexOf('=');
      if (idx <= 0) continue;
      if (part.substring(0, idx).trim() == name) {
        final v = part.substring(idx + 1).trim();
        if (v.isNotEmpty) return v;
      }
    }
    return null;
  }

  switch (platform.toLowerCase()) {
    case 'taobao':
    case 'tmall':
      return valueOf('cookie2') != null &&
          (valueOf('unb') != null || valueOf('cookie1') != null);
    case 'jd':
      return valueOf('pt_key') != null && valueOf('pt_pin') != null;
    case 'pdd':
      return valueOf('PDDAccessToken') != null ||
          valueOf('pdd_user_id') != null ||
          valueOf('pdduid') != null ||
          valueOf('AccessToken') != null;
    default:
      return false;
  }
}

/// 会话指纹：只取代表登录身份的字段，用于判断「是否仍是打开前那份旧会话」。
String? loginSessionFingerprint(String platform, String? cookieStr) {
  if (cookieStr == null || cookieStr.trim().isEmpty) return null;
  if (!cookieStringHasLoginSession(platform, cookieStr)) return null;

  String? valueOf(String name) {
    for (final part in cookieStr.split(';')) {
      final idx = part.indexOf('=');
      if (idx <= 0) continue;
      if (part.substring(0, idx).trim() == name) {
        final v = part.substring(idx + 1).trim();
        if (v.isNotEmpty) return v;
      }
    }
    return null;
  }

  switch (platform.toLowerCase()) {
    case 'taobao':
    case 'tmall':
      return 'tb:${valueOf('cookie2')}|${valueOf('unb') ?? valueOf('cookie1')}';
    case 'jd':
      return 'jd:${valueOf('pt_key')}|${valueOf('pt_pin')}';
    case 'pdd':
      return 'pdd:${valueOf('PDDAccessToken') ?? valueOf('AccessToken')}|'
          '${valueOf('pdd_user_id') ?? valueOf('pdduid') ?? ''}';
    default:
      return null;
  }
}

/// 采集到的会话与打开登录页前的基线是否同一份（注入旧 cookie 的回声）。
bool isSameLoginSession({
  required String platform,
  required String? baselineCookies,
  required String collectedCookies,
}) {
  final a = loginSessionFingerprint(platform, baselineCookies);
  final b = loginSessionFingerprint(platform, collectedCookies);
  if (a == null || b == null) return false;
  return a == b;
}

/// 京东页内「登录异常」等信号（URL + 页面文案）。
bool looksLikeJdLoginAnomaly({required String url, String? pageText}) {
  final t = (pageText ?? '').toLowerCase();
  if (t.contains('登录异常') || t.contains('登陆异常')) return true;
  if (t.contains('登录失败') || t.contains('登陆失败')) return true;
  if (t.contains('账号存在风险') || t.contains('活动太火爆')) return true;
  final u = url.toLowerCase();
  // plogin 错误落地常见带 risk / error 参数，且正文含异常
  if (u.contains('plogin') &&
      (t.contains('异常') || t.contains('验证') && t.contains('失败'))) {
    return true;
  }
  return false;
}

/// 是否允许把本轮采集当成「新登录成功」（可 saveCookies + 清失效 + pop(true)）。
///
/// - 无会话 / 异常页 → 否
/// - 与打开前指纹相同 → 否（堵住注入旧 cookie 的静默假成功）
/// - 否则 → 是
bool mayCommitNewLoginSuccess({
  required String platform,
  required String collectedCookies,
  required String? baselineCookies,
  bool anomalyDetected = false,
}) {
  if (anomalyDetected) return false;
  if (!cookieStringHasLoginSession(platform, collectedCookies)) return false;
  if (isSameLoginSession(
    platform: platform,
    baselineCookies: baselineCookies,
    collectedCookies: collectedCookies,
  )) {
    return false;
  }
  return true;
}

/// 离开登录流且未成功时，是否应立刻把平台标回失效（P29-a）。
bool shouldMarkExpiredOnLoginLeave({
  required bool loginCommitted,
  required bool wasExpiredAtOpen,
  required bool anomalyDetected,
}) {
  if (loginCommitted) return false;
  return wasExpiredAtOpen || anomalyDetected;
}
