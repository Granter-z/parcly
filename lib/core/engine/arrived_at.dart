/// Package.arrivedAt 取值规则（P16）- 纯 Dart
///
/// - 字段语义：北京时间到站时刻；未知为 null
/// - 优先轨迹里「入柜/到站」节点的 time（过 [normalizeTraceTime]）
/// - 否则首次变为待取件（arrived）时记 [now]
/// - 已有值不覆盖
/// - 退回在途/派送/待发货时清空
library;

import 'dart:convert';

import '../models/package_status.dart';
import '../parser/trace_time.dart';

/// 轨迹正文里视为「入柜 / 到站待取」的关键词（按具体→宽泛）
///
/// 故意不含单独的「已到达」：会误伤「已到达分拣中心 / 转运中心」。
const List<String> kArrivedAtNodeKeywords = [
  '入柜',
  '已入柜',
  '放入柜',
  '丰巢',
  '快递柜',
  '已到驿站',
  '入驿站',
  '到驿站',
  '驿站入库',
  '已到菜鸟',
  '待取件',
  '待取',
  '自提点',
  '代收点',
  '已入库',
  '入库成功',
  '到站',
  '已到站',
];

/// 命中这些时不算到站（分拣/转运），即使带了「到站」字样
const List<String> kArrivedAtExcludeKeywords = [
  '分拣',
  '转运中心',
  '转运场',
  '集散',
  '航空',
  '发往',
];

/// 一次 arrivedAt 决议结果
class ArrivedAtDecision {
  /// 写入的值；[clear] 为 true 时调用方应 `clearArrivedAt: true`
  final DateTime? value;
  final bool clear;

  const ArrivedAtDecision.keep(this.value) : clear = false;
  const ArrivedAtDecision.clear()
      : value = null,
        clear = true;
  const ArrivedAtDecision.set(this.value) : clear = false;
}

bool _isInTransitLike(PackageStatus s) =>
    s == PackageStatus.transit ||
    s == PackageStatus.delivering ||
    s == PackageStatus.pendingShipment;

bool looksLikeArrivedAtNode(String text) {
  if (text.isEmpty) return false;
  if (kArrivedAtExcludeKeywords.any(text.contains)) return false;
  return kArrivedAtNodeKeywords.any(text.contains);
}

/// 从 rawTimelineJson 取最早一条入柜/到站节点时间（北京墙钟，存为 UTC 日历分量）
DateTime? extractArrivedAtFromTimeline(
  String? rawTimelineJson, {
  DateTime? now,
}) {
  if (rawTimelineJson == null || rawTimelineJson.isEmpty) return null;
  final List<dynamic> list;
  try {
    final decoded = jsonDecode(rawTimelineJson);
    if (decoded is! List) return null;
    list = decoded;
  } catch (_) {
    return null;
  }

  DateTime? earliest;
  for (final raw in list) {
    if (raw is! Map) continue;
    final map = Map<String, dynamic>.from(raw);
    final text = '${map['text'] ?? map['desc'] ?? map['status'] ?? ''}';
    if (!looksLikeArrivedAtNode(text)) continue;
    final normalized = normalizeTraceTime(map['time'], now: now);
    if (normalized == null) continue;
    final dt = DateTime.tryParse(normalized.replaceFirst(' ', 'T'));
    if (dt == null) continue;
    final wall =
        DateTime.utc(dt.year, dt.month, dt.day, dt.hour, dt.minute, dt.second);
    if (earliest == null || wall.isBefore(earliest)) {
      earliest = wall;
    }
  }
  return earliest;
}

/// 合并/新建时决议 arrivedAt
///
/// [previousStatus]：合并前本地状态；新建时传 null。
ArrivedAtDecision resolveArrivedAt({
  required DateTime? existingArrivedAt,
  required PackageStatus resolvedStatus,
  PackageStatus? previousStatus,
  String? rawTimelineJson,
  DateTime? now,
}) {
  // 退回在途：清空
  if (_isInTransitLike(resolvedStatus)) {
    if (existingArrivedAt != null) return const ArrivedAtDecision.clear();
    return const ArrivedAtDecision.keep(null);
  }

  // 已有值不覆盖（签收/归档也保留历史到站时间）
  if (existingArrivedAt != null) {
    return ArrivedAtDecision.keep(existingArrivedAt);
  }

  final clock = now ?? DateTime.now();
  final fromTrace =
      extractArrivedAtFromTimeline(rawTimelineJson, now: clock);
  if (fromTrace != null) {
    return ArrivedAtDecision.set(fromTrace);
  }

  // 首次变为待取件且轨迹没有可解析节点 → 记 now
  final becameArrived = resolvedStatus == PackageStatus.arrived &&
      previousStatus != PackageStatus.arrived;
  if (becameArrived) {
    return ArrivedAtDecision.set(clock);
  }

  return const ArrivedAtDecision.keep(null);
}
