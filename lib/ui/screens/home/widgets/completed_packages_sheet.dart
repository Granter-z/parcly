/// 已完成包裹二级抽屉面板 - 隔离主屏幕在途视线
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/models/package.dart';
import '../../../../core/models/package_status.dart';
import '../../../providers/package_provider.dart';import '../../../components/spring_card.dart';
import '../../../components/platform_badge.dart';
import '../../../components/staggered_entrance.dart';
import 'tracking_timeline_sheet.dart';

class CompletedPackagesSheet extends ConsumerWidget {
  const CompletedPackagesSheet({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const CompletedPackagesSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final completedPackages = ref.watch(completedPackagesProvider);
    final theme = Theme.of(context);

    return DraggableScrollableSheet(
      // expand 必须为 false：否则控件会撑满整屏，模态遮罩高度被压成 0，
      // 点击抽屉上方留白就无法收回抽屉。
      expand: false,
      initialChildSize: 0.65,
      minChildSize: 0.35,
      maxChildSize: 0.9,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 10, bottom: 12),
                  width: 36,
                  height: 4.5,
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '已完成包裹 (${completedPackages.length})',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '历史记录已归档',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: completedPackages.isEmpty
                    ? const Center(
                        child: Text('暂无已完成的包裹记录', style: TextStyle(color: Colors.grey)),
                      )
                    : ListView.separated(
                        controller: scrollController,
                        padding: const EdgeInsets.all(16),
                        itemCount: completedPackages.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) => StaggeredEntrance(
                          index: index,
                          child: _CompletedPackageCard(
                            package: completedPackages[index],
                          ),
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 已完成列表里的单张卡片：点击进入物流轨迹抽屉，长按可删除。
class _CompletedPackageCard extends ConsumerWidget {
  final Package package;

  const _CompletedPackageCard({required this.package});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pkg = package;

    return SpringCard(
      padding: const EdgeInsets.all(14),
      borderRadius: BorderRadius.circular(14),
      onTap: () => TrackingTimelineSheet.show(context, pkg),
      onLongPress: () {
        HapticFeedback.mediumImpact();
        showModalBottomSheet(
          context: context,
          builder: (ctx) => SafeArea(
            child: Wrap(
              children: [
                ListTile(
                  leading: const Icon(Icons.delete_outline_rounded, color: Colors.red),
                  title: const Text('删除该包裹', style: TextStyle(color: Colors.red)),
                  onTap: () {
                    Navigator.pop(ctx);
                    ref.read(packageListProvider.notifier).removePackage(pkg.id);
                  },
                ),
              ],
            ),
          ),
        );
      },
      child: Row(
        children: [
          PlatformBadge(platform: pkg.platform),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  pkg.goodsName ?? pkg.description.ifEmpty('快件包裹'),
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${pkg.courier.displayName} · ${pkg.trackingNumber}',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: Colors.grey.shade600,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (pkg.status == PackageStatus.rejected)
            // 拒收：实心红底白字标签，与已取件的绿色文字明显区分
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFFF3B30),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                '已拒收',
                style: TextStyle(
                  fontSize: 11.5,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            )
          else
            Text(
              pkg.status.label,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF34C759),
                fontWeight: FontWeight.bold,
              ),
            ),
        ],
      ),
    );
  }
}

extension _StringEmpty on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
