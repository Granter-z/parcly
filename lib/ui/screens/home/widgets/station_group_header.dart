/// 首页待取件取件点分组标题：站名 + 件数，点一下折叠/展开。
library;

import 'package:flutter/material.dart';

import '../../../../core/engine/station_grouping.dart';
import '../../../constants/app_constants.dart';

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
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Row(
            children: [
              AnimatedRotation(
                turns: collapsed ? 0 : 0.25,
                duration: const Duration(milliseconds: 150),
                child: const Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: AppColors.textTertiary,
                ),
              ),
              const SizedBox(width: 2),
              const Icon(
                Icons.storefront_rounded,
                size: 16,
                color: AppColors.textPrimary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  group.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              Text(
                '${group.packages.length} 件',
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textTertiary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
