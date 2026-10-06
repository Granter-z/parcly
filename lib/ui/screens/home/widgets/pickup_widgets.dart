/// 首页待取件和在途的卡片（P4，见 docs/pickup_app-界面.md 第 3、4 节）。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/engine/station_grouping.dart';
import '../../../../core/models/package.dart';
import '../../../../core/models/package_status.dart';
import '../../../components/platform_badge.dart';
import '../../../providers/package_provider.dart';
import 'tracking_timeline_sheet.dart';

/// 「2天前到」「3小时前到」「刚到」
String arrivedAgoText(DateTime arrived, DateTime now) {
  final d = now.difference(arrived);
  if (d.inDays >= 1) return '${d.inDays}天前到';
  if (d.inHours >= 1) return '${d.inHours}小时前到';
  if (d.inMinutes >= 1) return '${d.inMinutes}分钟前到';
  return '刚到';
}

/// 撤销窗口里攒着的「已取」：5 秒内连续点多个，一个「撤销」全部恢复。
final List<Package> _undoBatch = [];
int _undoGeneration = 0;

/// 标记已取件，并弹出 5 秒「撤销」。
///
/// 5 秒内再点别的包裹「已取」，会并进同一条提示（「已标记取件 2 件」），撤销时一起恢复，
/// 前一个的撤销入口不会被顶掉。
void markPickedUpWithUndo(BuildContext context, WidgetRef ref, Package pkg) {
  HapticFeedback.mediumImpact();
  final notifier = ref.read(packageListProvider.notifier);
  notifier.markPickedUp(pkg.id);
  _undoBatch
    ..removeWhere((p) => p.id == pkg.id)
    ..add(pkg);

  final generation = ++_undoGeneration;
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  final count = _undoBatch.length;
  messenger
      .showSnackBar(
        SnackBar(
          content: Text(count == 1 ? '已标记取件' : '已标记取件 $count 件'),
          duration: const Duration(seconds: 5),
          // 带按钮的 SnackBar 默认不会自动消失，必须显式关掉 persist。
          persist: false,
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: '撤销',
            onPressed: () {
              for (final original in List.of(_undoBatch)) {
                notifier.restorePackage(original);
              }
              _undoBatch.clear();
            },
          ),
        ),
      )
      .closed
      .then((_) {
    // 只有最新那条提示关掉（超时、划走、点了撤销）才结束这一批；
    // 被下一次「已取」替换掉的旧提示不清。
    if (generation == _undoGeneration) _undoBatch.clear();
  });
}

/// 驿站分组标题：驿站名 + 件数，点一下折叠或展开。
class StationGroupHeader extends StatelessWidget {
  final StationGroup group;
  final bool collapsed;
  final VoidCallback onToggle;

  const StationGroupHeader({
    super.key,
    required this.group,
    required this.collapsed,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onToggle,
      borderRadius: BorderRadius.circular(10),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Row(
          children: [
            AnimatedRotation(
              turns: collapsed ? 0 : 0.25,
              duration: const Duration(milliseconds: 150),
              child: const Icon(Icons.chevron_right_rounded,
                  size: 20, color: Color(0xFF8E8E93)),
            ),
            const SizedBox(width: 2),
            const Icon(Icons.storefront_rounded,
                size: 16, color: Color(0xFF3A3A3C)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                group.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF3A3A3C)),
              ),
            ),
            Text(
              '${group.packages.length} 件',
              style: const TextStyle(fontSize: 13, color: Color(0xFF8E8E93)),
            ),
          ],
        ),
      ),
    );
  }
}

/// 待取件卡片：取件码最大（≥32sp，等宽加粗），点码复制，点「已取」归档可撤销。
class PickupCodeCard extends ConsumerStatefulWidget {
  final Package package;
  final DateTime now;

  const PickupCodeCard({super.key, required this.package, required this.now});

  @override
  ConsumerState<PickupCodeCard> createState() => _PickupCodeCardState();
}

class _PickupCodeCardState extends ConsumerState<PickupCodeCard> {
  bool _copied = false;
  Timer? _copiedTimer;

  Package get package => widget.package;

  @override
  void dispose() {
    _copiedTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = widget.now;
    final code = package.pickupCode.trim();
    final arrived = arrivalTimeOf(package);
    final overdue = isNearlyOverdue(package, now);
    final goods = (package.goodsName ?? '').trim();
    // 到站时长放最前：一行放不下时被截断的是商品名，而不是「几天前到」。
    // 不知道真实到站时间就不写（不拿同步时间冒充）。
    final meta = [
      if (arrived != null) arrivedAgoText(arrived, now),
      package.courier.displayName,
      if (goods.isNotEmpty) goods,
    ].join(' · ');

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => TrackingTimelineSheet.show(context, package),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: code.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.symmetric(vertical: 6),
                            child: Text(
                              '到站了，取件码没拿到',
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF8E8E93)),
                            ),
                          )
                        : GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => _copyCode(code),
                            child: Semantics(
                              label:
                                  _copied ? '取件码 $code，已复制' : '取件码 $code，点按复制',
                              excludeSemantics: true,
                              child: ConstrainedBox(
                                constraints:
                                    const BoxConstraints(minHeight: 48),
                                child: Row(
                                  children: [
                                    Flexible(
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        alignment: Alignment.centerLeft,
                                        child: Text(
                                          code,
                                          style: const TextStyle(
                                            fontSize: 34,
                                            height: 1.1,
                                            fontWeight: FontWeight.w800,
                                            fontFamily: 'monospace',
                                            letterSpacing: 1,
                                            color: Color(0xFF1C1C1E),
                                          ),
                                        ),
                                      ),
                                    ),
                                    // 复制反馈就地显示，不用 SnackBar，免得顶掉「撤销」。
                                    if (_copied)
                                      const Padding(
                                        padding: EdgeInsets.only(left: 8),
                                        child: Text(
                                          '已复制',
                                          style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: Color(0xFF34C759)),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                  ),
                  const SizedBox(width: 8),
                  PlatformBadge(platform: package.platform),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  if (overdue) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF9500).withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: const Text(
                        '快过期',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFE67E00)),
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Expanded(
                    child: Text(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13, color: Color(0xFF6C6C70)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Semantics(
                    button: true,
                    label:
                        '标记已取，${code.isNotEmpty ? code : goods.isNotEmpty ? goods : package.courier.displayName}',
                    excludeSemantics: true,
                    child: FilledButton.tonalIcon(
                      onPressed: () =>
                          markPickedUpWithUndo(context, ref, package),
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: const Text('已取'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 44),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _copyCode(String code) {
    Clipboard.setData(ClipboardData(text: code));
    HapticFeedback.lightImpact();
    setState(() => _copied = true);
    _copiedTimer?.cancel();
    _copiedTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _copied = false);
    });
  }
}

/// 在途包裹的单行紧凑卡片：快递公司 · 状态 · 商品名。点开看时间轴。
class InTransitRow extends StatelessWidget {
  final Package package;

  const InTransitRow({super.key, required this.package});

  @override
  Widget build(BuildContext context) {
    final goods = (package.goodsName ?? '').trim();
    return InkWell(
      onTap: () => TrackingTimelineSheet.show(context, package),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: [
            const Icon(Icons.local_shipping_outlined,
                size: 18, color: Color(0xFF8E8E93)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                [
                  package.courier.displayName,
                  package.status.label,
                  if (goods.isNotEmpty) goods,
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14, color: Color(0xFF3A3A3C)),
              ),
            ),
            const SizedBox(width: 6),
            PlatformBadge(platform: package.platform),
          ],
        ),
      ),
    );
  }
}

/// 在途区底部的「N 件待发货」折叠行：待发货的还没出仓，不算在途（产品 10-07 定）。
class AwaitingShipmentRow extends StatelessWidget {
  final int count;
  final bool expanded;
  final VoidCallback onToggle;

  const AwaitingShipmentRow({
    super.key,
    required this.count,
    required this.expanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onToggle,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: [
            const Icon(Icons.inventory_2_outlined,
                size: 18, color: Color(0xFFAEAEB2)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '$count 件待发货',
                style: const TextStyle(fontSize: 14, color: Color(0xFF8E8E93)),
              ),
            ),
            Icon(
              expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
              size: 20,
              color: const Color(0xFFAEAEB2),
            ),
          ],
        ),
      ),
    );
  }
}
