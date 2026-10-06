/// 三平台共用的物流时间轴组件（P12）
///
/// 只负责渲染 `timelineForDisplay` 整理好的节点，不关心数据来自哪个平台：
/// - 第一个节点（最新）绿色圆点 + 绿色标签/时间/正文高亮，历史节点灰点；
/// - 节点之间用竖线串联，时间用等宽字体，格式为「今天/昨天/日期 + 时分」；
/// - 正文里的电话标蓝加下划线，点击拨打；取件码加粗（轻度强调）；
/// - 节点为空时显示空状态，不出现空白或报错。
///
/// 点击识别器（TapGestureRecognizer）在节点变化时统一创建、在 dispose 时统一释放，
/// 不在 build 里临时创建，避免旧实现的泄漏问题。
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/engine/timeline_view.dart';

/// 时间轴配色，与原物流轨迹抽屉保持一致。
class TrackingTimelineColors {
  TrackingTimelineColors._();

  static const latest = Color(0xFF00B578);
  static const historyDot = Color(0xFFC4C4C4);
  static const connector = Color(0xFFE5E5EA);
  static const historyTag = Color(0xFF3A3A3C);
  static const historyTime = Color(0xFF8E8E93);
  static const historyText = Color(0xFF333333);
  static const phone = Color(0xFF1890FF);
}

/// 默认拨号实现：去掉分隔符后用系统拨号盘打开。
Future<void> launchPhoneCall(String phone) async {
  final number = dialablePhone(phone);
  if (number.isEmpty) return;
  try {
    await launchUrl(Uri(scheme: 'tel', path: number),
        mode: LaunchMode.externalApplication);
  } catch (_) {
    // 设备不支持拨号（如平板/模拟器）时静默忽略，不影响查看轨迹。
  }
}

class TrackingTimeline extends StatefulWidget {
  /// 已整理好的节点（最新在前），一般来自 `timelineForDisplay(pkg.rawTimelineJson)`。
  final List<TimelineNode> nodes;

  /// 包裹取件码，正文里出现时加粗。
  final String? pickupCode;

  /// 无轨迹时空状态里附带显示的当前状态（如「运输中」），可不传。
  final String? statusLabel;

  /// 点击电话的回调；不传则调用系统拨号。测试时可注入。
  final ValueChanged<String>? onCallPhone;

  /// 计算「今天/昨天」用的当前时间，仅测试注入。
  final DateTime? now;

  const TrackingTimeline({
    super.key,
    required this.nodes,
    this.pickupCode,
    this.statusLabel,
    this.onCallPhone,
    this.now,
  });

  @override
  State<TrackingTimeline> createState() => _TrackingTimelineState();
}

class _TrackingTimelineState extends State<TrackingTimeline> {
  /// 每个节点切分后的正文段落。
  List<List<TraceSegment>> _segments = const [];

  /// 每个节点里电话段对应的点击识别器（与 _segments 中电话段一一对应）。
  List<List<TapGestureRecognizer>> _recognizers = const [];

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  @override
  void didUpdateWidget(covariant TrackingTimeline oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.nodes, widget.nodes) ||
        oldWidget.pickupCode != widget.pickupCode) {
      _disposeRecognizers();
      _prepare();
    }
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _prepare() {
    _segments = [
      for (final node in widget.nodes)
        segmentTraceText(node.text, pickupCode: widget.pickupCode),
    ];
    _recognizers = [
      for (final segs in _segments)
        [
          for (final s in segs)
            if (s.type == TraceSegmentType.phone)
              TapGestureRecognizer()..onTap = () => _call(s.text),
        ],
    ];
  }

  void _disposeRecognizers() {
    for (final list in _recognizers) {
      for (final r in list) {
        r.dispose();
      }
    }
    _recognizers = const [];
  }

  void _call(String phone) {
    final handler = widget.onCallPhone;
    if (handler != null) {
      handler(phone);
    } else {
      launchPhoneCall(phone);
    }
  }

  @override
  Widget build(BuildContext context) {
    final nodes = widget.nodes;
    if (nodes.isEmpty) {
      return TrackingTimelineEmpty(statusLabel: widget.statusLabel);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < nodes.length; i++)
          _buildItem(
            index: i,
            node: nodes[i],
            isLatest: i == 0,
            isLast: i == nodes.length - 1,
          ),
      ],
    );
  }

  Widget _buildItem({
    required int index,
    required TimelineNode node,
    required bool isLatest,
    required bool isLast,
  }) {
    const green = TrackingTimelineColors.latest;
    final timeText = formatTimelineTime(node, now: widget.now);

    return IntrinsicHeight(
      key: ValueKey('tracking_timeline_node_$index'),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 左侧：节点圆点与竖向连接线
          SizedBox(
            width: 22,
            child: Column(
              children: [
                if (isLatest)
                  Container(
                    key: const ValueKey('tracking_timeline_latest_dot'),
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: green.withValues(alpha: 0.2),
                    ),
                    child: Center(
                      child: Container(
                        width: 9,
                        height: 9,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: green,
                        ),
                      ),
                    ),
                  )
                else
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: TrackingTimelineColors.historyDot,
                    ),
                  ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 1.5,
                      color: TrackingTimelineColors.connector,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),

          // 右侧：标签 + 时间，下面是正文
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 4 : 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    children: [
                      if (node.tag.isNotEmpty)
                        Text(
                          node.tag,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: isLatest ? FontWeight.bold : FontWeight.w600,
                            color: isLatest ? green : TrackingTimelineColors.historyTag,
                          ),
                        ),
                      if (timeText.isNotEmpty)
                        Text(
                          timeText,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: isLatest ? FontWeight.w600 : FontWeight.normal,
                            color: isLatest ? green : TrackingTimelineColors.historyTime,
                            fontFamily: 'monospace',
                          ),
                        ),
                    ],
                  ),
                  if (node.text.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    _buildTraceText(index, isLatest),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 正文：电话标蓝可点，取件码加粗，其余普通文字。
  Widget _buildTraceText(int index, bool isLatest) {
    final baseColor =
        isLatest ? TrackingTimelineColors.latest : TrackingTimelineColors.historyText;
    final baseStyle = TextStyle(fontSize: 13, color: baseColor, height: 1.45);
    final recognizers = _recognizers[index];
    var phoneIndex = 0;

    final spans = <InlineSpan>[];
    for (final seg in _segments[index]) {
      switch (seg.type) {
        case TraceSegmentType.plain:
          spans.add(TextSpan(text: seg.text));
        case TraceSegmentType.pickupCode:
          spans.add(TextSpan(
            text: seg.text,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ));
        case TraceSegmentType.phone:
          spans.add(TextSpan(
            text: seg.text,
            style: const TextStyle(
              color: TrackingTimelineColors.phone,
              fontWeight: FontWeight.w600,
              decoration: TextDecoration.underline,
              decorationColor: TrackingTimelineColors.phone,
            ),
            recognizer: recognizers[phoneIndex++],
          ));
      }
    }
    return Text.rich(TextSpan(style: baseStyle, children: spans));
  }
}

/// 无轨迹时的空状态：如实说明还没有轨迹，不编造节点和时间。
class TrackingTimelineEmpty extends StatelessWidget {
  final String? statusLabel;

  const TrackingTimelineEmpty({super.key, this.statusLabel});

  @override
  Widget build(BuildContext context) {
    final label = statusLabel?.trim() ?? '';
    return Container(
      key: const ValueKey('tracking_timeline_empty'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8FA),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.timeline_outlined, size: 22, color: Color(0xFFAEAEB2)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '暂无物流轨迹',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF3A3A3C),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  label.isEmpty
                      ? '下次同步后会在这里显示'
                      : '当前状态：$label · 下次同步后会在这里显示',
                  style: const TextStyle(fontSize: 12.5, color: Color(0xFF8E8E93)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
