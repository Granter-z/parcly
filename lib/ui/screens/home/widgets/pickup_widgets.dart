/// 首页待取件和在途的卡片（P4，见 docs/pickup_app-界面.md 第 3、4 节）。
library;

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

/// 标记已取件，并弹出 5 秒「撤销」。
void markPickedUpWithUndo(BuildContext context, WidgetRef ref, Package pkg) {
  HapticFeedback.mediumImpact();
  final notifier = ref.read(packageListProvider.notifier);
  notifier.markPickedUp(pkg.id);
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: const Text('已标记取件'),
      duration: const Duration(seconds: 5),
      behavior: SnackBarBehavior.floating,
      action: SnackBarAction(
        label: '撤销',
        onPressed: () => notifier.restorePackage(pkg),
      ),
    ),
  );
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
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            AnimatedRotation(
              turns: collapsed ? 0 : 0.25,
              duration: const Duration(milliseconds: 150),
              child: const Icon(Icons.chevron_right_rounded, size: 20, color: Color(0xFF8E8E93)),
            ),
            const SizedBox(width: 2),
            const Icon(Icons.storefront_rounded, size: 16, color: Color(0xFF3A3A3C)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                group.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF3A3A3C)),
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
class PickupCodeCard extends ConsumerWidget {
  final Package package;
  final DateTime now;

  const PickupCodeCard({super.key, required this.package, required this.now});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final code = package.pickupCode.trim();
    final arrived = arrivalTimeOf(package);
    final overdue = isNearlyOverdue(package, now);
    final goods = (package.goodsName ?? '').trim();
    // 到站时长放最前：一行放不下时被截断的是商品名，而不是「几天前到」。
    final meta = [
      arrivedAgoText(arrived, now),
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
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF8E8E93)),
                            ),
                          )
                        : GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => _copyCode(context, code),
                            child: Semantics(
                              label: '取件码 $code，点按复制',
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
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF9500).withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: const Text(
                        '快过期',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFFE67E00)),
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Expanded(
                    child: Text(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, color: Color(0xFF6C6C70)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonalIcon(
                    onPressed: () => markPickedUpWithUndo(context, ref, package),
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: const Text('已取'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 40),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
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

  void _copyCode(BuildContext context, String code) {
    Clipboard.setData(ClipboardData(text: code));
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(
        content: Text('取件码已复制'),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ));
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
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          children: [
            const Icon(Icons.local_shipping_outlined, size: 18, color: Color(0xFF8E8E93)),
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
