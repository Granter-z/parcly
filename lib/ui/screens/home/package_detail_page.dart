/// 包裹详情页
library;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../../core/models/package.dart';
import '../../../core/models/package_status.dart';
import '../../../ui/constants/app_constants.dart';
import '../../../ui/theme/status_extension.dart';

/// 包裹详情页
class PackageDetailPage extends StatelessWidget {
  final Package package;

  const PackageDetailPage(this.package, {super.key});

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text('${package.courier.shortName}详情'),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 顶部包裹信息
            _buildPackageInfo(),
            const Divider(height: 1),
            // 事件列表
            Expanded(
              child: _buildEventList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPackageInfo() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      color: AppColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 状态和取件码
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: package.status.color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Text(
                  package.status.label,
                  style: TextStyle(
                    color: package.status.color,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              if (package.pickupCode.isNotEmpty)
                Expanded(
                  child: Text(
                    '取件码: ${package.pickupCode}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          // 驿站
          if (package.displayLocation.isNotEmpty)
            Row(
              children: [
                const Icon(
                  CupertinoIcons.location_solid,
                  size: 16,
                  color: AppColors.textTertiary,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    package.displayLocation,
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildEventList() {
    // 直接渲染已抓取到的完整物流轨迹（rawTimelineJson 解析出的节点，最新在前）
    final timeline = package.parsedTimeline;

    if (timeline.isEmpty) {
      return const Center(
        child: Text(
          '暂无轨迹记录',
          style: TextStyle(
            color: AppColors.textTertiary,
            fontSize: 15,
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      itemCount: timeline.length,
      itemBuilder: (context, index) {
        final node = timeline[index];
        final tag = node['tag'] ?? '';
        final time = node['time'] ?? '';
        final text = node['text'] ?? '';
        return CupertinoListTile(
          title: Text(
            text.isNotEmpty ? text : tag,
            style: const TextStyle(
              fontSize: 15,
              color: AppColors.textPrimary,
            ),
          ),
          subtitle: Text(
            [tag, time].where((s) => s.isNotEmpty).join(' · '),
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textTertiary,
            ),
          ),
        );
      },
    );
  }
}
