/// 京东物流轨迹与链接解析辅助工具 - 纯 Dart
library;

import '../../core/parser/trace_time.dart';

/// 根据订单信息构建完整京东物流详情页 URL
String buildJdLogisticsUrl({
  required String orderId,
  String? progressLink,
  String? skuId,
  String? shopId,
  String? dealState,
  String? orderType,
}) {
  final link = progressLink?.trim() ?? '';
  if (link.isNotEmpty) {
    if (link.startsWith('//')) return 'https:$link';
    return link;
  }

  if (dealState != null && dealState.isNotEmpty) {
    return 'https://trade.m.jd.com/order/deal_wuliu_jdm.shtml?from=orderdetail'
        '&dealState=$dealState&dealId=$orderId'
        '&orderType=${orderType ?? ''}'
        '&skuid=${skuId ?? ''}'
        '&shopid=${shopId ?? ''}'
        '&source=m_inner_orderList.track_orderTrack';
  }

  return 'https://trade.m.jd.com/order/deal_wuliu_jdm.shtml?dealId=$orderId';
}

final _timeRegex = RegExp(r'^(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}(?::\d{2})?)');
final _skipRegex = RegExp(r'(订单编号|运单号|国内承运人|联系电话|^\d+件$|¥|评论|已售)');
const _noiseWords = {
  '订单跟踪', '联系客服', '复制', '展开详细信息', '展开', '仓库', '签', '派',
  '等待收货', '已发货', '暂无数据',
};
const _logisticsKeywords = [
  '快件', '包裹', '派件', '揽收', '签收', '发往', '到达', '转运',
  '投递', '取件', '出库', '配送', '妥投', '物流', '运输',
];

/// 从 DOM 纯文本中按行状态机解析时间轴节点（{tag, time, text}）。
/// 节点时间经 [normalizeTraceTime] 规范成 yyyy-MM-dd HH:mm:ss，解析不出时间的节点不写入；[now] 供测试注入。
List<Map<String, String>> parseJdDomTimeline(String rawText, {DateTime? now}) {
  var text = rawText.trim();
  if (text.startsWith('"') && text.endsWith('"')) {
    text = text.substring(1, text.length - 1).replaceAll(r'\n', '\n');
  }

  final nodes = <Map<String, String>>[];
  String? currentTimestamp;
  StringBuffer? pendingDesc;

  void flush() {
    final t = currentTimestamp;
    final p = pendingDesc;
    if (t != null && p != null) {
      final desc = p.toString().trim();
      if (desc.isNotEmpty && desc.length >= 4) {
        nodes.add({
          'tag': '',
          'time': t,
          'text': desc,
        });
      }
    }
    pendingDesc = null;
  }

  for (final rawLine in text.split('\n')) {
    final line = rawLine.trim();
    if (line.isEmpty) continue;

    final match = _timeRegex.firstMatch(line);
    if (match != null && line.length <= 25) {
      flush();
      currentTimestamp = normalizeTraceTime(match.group(1), now: now);
      continue;
    }

    if (_noiseWords.contains(line) || _skipRegex.hasMatch(line)) continue;

    final looksLikeDesc = line.contains('【') || _logisticsKeywords.any(line.contains);
    if (looksLikeDesc || (pendingDesc != null && line.length >= 4)) {
      if (pendingDesc == null) {
        pendingDesc = StringBuffer(line);
      } else {
        pendingDesc!.write(' $line');
      }
    }
  }

  flush();
  return nodes;
}

/// 从 cookie 串取出指定 name 的值（首个非空命中）。
String? jdCookieValue(String cookies, String name) {
  for (final part in cookies.split(';')) {
    final idx = part.indexOf('=');
    if (idx <= 0) continue;
    if (part.substring(0, idx).trim() != name) continue;
    final v = part.substring(idx + 1).trim();
    if (v.isNotEmpty) return v;
  }
  return null;
}

/// 校验京东回写 Cookie 是否健康（防止匿名会话降级冲刷已有 pt_key 凭据）。
///
/// P30-b ②：原串有 `pt_key` 时，新串必须仍有 **相同值** 的 `pt_key`
///（不能只看「有没有 + 长度」——值被换掉同样算降级）。
bool isJdCookieHealthy(String originalCookies, String newCookies) {
  if (newCookies.trim().isEmpty) return false;
  final origKey = jdCookieValue(originalCookies, 'pt_key');
  final newKey = jdCookieValue(newCookies, 'pt_key');
  if (origKey != null) {
    if (newKey == null) return false;
    if (newKey != origKey) return false;
  }
  if (originalCookies.isNotEmpty && newCookies.length < (originalCookies.length * 0.5)) {
    return false;
  }
  return true;
}

/// P30-b ④：同步结束后采集 Cookie 的域列表（**不含** plogin）。
const List<String> kJdPersistCookieHosts = [
  'https://www.jd.com',
  'https://trade.m.jd.com',
  'https://wqs.jd.com',
  'https://api.m.jd.com',
  'https://home.m.jd.com',
];

/// P30-b ①：本轮 Fallback 见登录页 / 已 `setExpired(true)` → 禁止 persist。
bool shouldSkipJdCookiePersist({
  required bool landedLoginPage,
  required bool markedExpiredThisRound,
}) =>
    landedLoginPage || markedExpiredThisRound;
