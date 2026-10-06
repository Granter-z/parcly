/// 首页顶部概览仪表盘 - 聚合待取件、在途状态与一键多平台流式同步
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/models/package_status.dart';
import '../../../providers/package_provider.dart';
import '../../../../platform/connectors/connector_manager.dart';

class HeroStatsDashboard extends ConsumerStatefulWidget {
  const HeroStatsDashboard({super.key});

  @override
  ConsumerState<HeroStatsDashboard> createState() => _HeroStatsDashboardState();
}

class _HeroStatsDashboardState extends ConsumerState<HeroStatsDashboard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spinController;

  @override
  void initState() {
    super.initState();
    _spinController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
  }

  @override
  void dispose() {
    _spinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pendingPackages = ref.watch(pendingPackagesProvider);
    final isSyncing = ref.watch(syncStateProvider);

    if (isSyncing) {
      if (!_spinController.isAnimating) _spinController.repeat();
    } else {
      if (_spinController.isAnimating) _spinController.stop();
    }

    final toPickupCount = pendingPackages.where((p) => p.status.isArrived).length;
    final inTransitCount = pendingPackages.where((p) => p.status == PackageStatus.delivering || p.status == PackageStatus.transit).length;
    final pendingShipmentCount = pendingPackages.where((p) => p.status == PackageStatus.pendingShipment).length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20.0),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF1C1C1E),
            Color(0xFF2C2C2E),
          ],
        ),
        borderRadius: BorderRadius.circular(22.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 顶部小标题 + 一键同步按钮
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.all_inbox_rounded, color: Colors.white70, size: 16),
                  SizedBox(width: 6),
                  Text(
                    '包裹概览',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              InkWell(
                onTap: isSyncing
                    ? null
                    : () async {
                        HapticFeedback.lightImpact();
                        final manager = ref.read(connectorManagerProvider);
                        await manager.syncAll();
                        if (!context.mounted) return;
                        final issue = manager.lastIssue;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(issue ?? '已同步最新物流状态'),
                            duration: const Duration(seconds: 3),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      RotationTransition(
                        turns: _spinController,
                        child: const Icon(
                          Icons.sync_rounded,
                          color: Colors.white,
                          size: 14,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isSyncing ? '同步中...' : '一键同步',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // 核心数字展现（FittedBox 杜绝任意窄屏像素溢出）
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  '$toPickupCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 42,
                    fontWeight: FontWeight.w900,
                    height: 1.0,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(width: 6),
                const Text(
                  '件待取',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 14),
                Container(
                  height: 22,
                  width: 1,
                  color: Colors.white.withValues(alpha: 0.2),
                ),
                const SizedBox(width: 14),
                Text(
                  '$inTransitCount',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    height: 1.0,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  '件在途',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (pendingShipmentCount > 0) ...[
                  const SizedBox(width: 12),
                  Container(
                    height: 22,
                    width: 1,
                    color: Colors.white.withValues(alpha: 0.2),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '$pendingShipmentCount',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      height: 1.0,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    '件待发',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 13.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 12),

          // 底部贴心状态文案
          Text(
            toPickupCount > 0
                ? '已有 $toPickupCount 件快件送达驿站，点击包裹卡片查看取件码与详情'
                : (inTransitCount > 0
                    ? '包裹全速运送中，送达驿站后将第一时间展示取件码'
                    : (pendingShipmentCount > 0
                        ? '已有 $pendingShipmentCount 件商品等待商家发货'
                        : '当前暂无在途与待取件，下拉或点击同步拉取')),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.65),
              fontSize: 12,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}
