/// 现代化流体卡片组件 - 采用弹簧物理按压反馈与高层级信息布局
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/models/package.dart';
import '../../../../core/models/package_status.dart';
import '../../../providers/package_provider.dart';
import '../../../components/spring_card.dart';
import '../../../components/hero_pickup_badge.dart';
import '../../../components/platform_badge.dart';
import 'tracking_timeline_sheet.dart';

class ModernPackageCard extends ConsumerWidget {
  final Package package;

  const ModernPackageCard({
    super.key,
    required this.package,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isArrived = package.status.isArrived;
    final isDelivering = package.status == PackageStatus.delivering;

    return SpringCard(
      padding: const EdgeInsets.all(16.0),
      borderRadius: BorderRadius.circular(18.0),
      border: Border.all(
        color: isArrived
            ? const Color(0xFF007AFF).withValues(alpha: 0.18)
            : Colors.black.withValues(alpha: 0.05),
        width: isArrived ? 1.2 : 0.8,
      ),
      onTap: () => TrackingTimelineSheet.show(context, package),
      onLongPress: () {
        HapticFeedback.mediumImpact();
        showModalBottomSheet(
          context: context,
          builder: (ctx) => SafeArea(
            child: Wrap(
              children: [
                ListTile(
                  leading: const Icon(Icons.copy_rounded),
                  title: const Text('复制运单号'),
                  subtitle: Text(package.trackingNumber),
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: package.trackingNumber));
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('已复制运单号: ${package.trackingNumber}'), behavior: SnackBarBehavior.floating),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.delete_outline_rounded, color: Colors.red),
                  title: const Text('删除该包裹', style: TextStyle(color: Colors.red)),
                  onTap: () {
                    Navigator.pop(ctx);
                    ref.read(packageListProvider.notifier).removePackage(package.id);
                  },
                ),
              ],
            ),
          ),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 顶栏：平台来源 + 快递公司 + 状态标签
          Row(
            children: [
              PlatformBadge(platform: package.platform),
              const SizedBox(width: 8),
              Text(
                package.effectiveCourier.displayName,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2C2C2E),
                ),
              ),
              const Spacer(),
              _buildStatusPill(package.status),
            ],
          ),

          const SizedBox(height: 12),

          // 主体：商品缩略图 + 标题 + 驿站信息
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildProductImage(package.goodsImageUrl),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (package.goodsName?.isNotEmpty == true && package.goodsName != 'OCR')
                          ? package.goodsName!
                          : (package.description.isNotEmpty && package.description != 'OCR' ? package.description : '快件包裹'),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1C1C1E),
                        height: 1.3,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          Icons.location_on_outlined,
                          size: 14,
                          color: Colors.grey.shade600,
                        ),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(
                            package.displayLocation,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: Colors.grey.shade700,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // 最新物流轨迹（来自订单详情页的真实动态）
          if (!isArrived &&
              package.description.isNotEmpty &&
              package.description != '快件包裹' &&
              package.description != 'OCR')
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.local_shipping_outlined, size: 14, color: Color(0xFF8E8E93)),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      package.description,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        color: Colors.grey.shade700,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),

          // 底栏：取件码核心展现 / 派送提示 + 确认取件动作
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: isArrived
                  ? const Color(0xFF007AFF).withValues(alpha: 0.05)
                  : Colors.grey.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                // 左侧：取件码 / 派送提示 / 运单号（用 Wrap 避免长取件码溢出）
                Expanded(
                  child: isArrived && package.pickupCode.isNotEmpty
                      ? Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            const Text(
                              '取件码',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF007AFF),
                              ),
                            ),
                            HeroPickupBadge(pickupCode: package.pickupCode),
                          ],
                        )
                      : isDelivering
                          ? Row(
                              children: [
                                const Icon(Icons.delivery_dining_rounded,
                                    size: 18, color: Color(0xFFFF9500)),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    '快件派送中',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.orange.shade800,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            )
                          : Text(
                              _displayTracking(package),
                              style: TextStyle(
                                fontSize: 12,
                                fontFamily: 'monospace',
                                color: Colors.grey.shade600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                ),

                const SizedBox(width: 8),

                // 右侧：标记已取 / 查看轨迹
                if (isArrived)
                  InkWell(
                    onTap: () {
                      HapticFeedback.mediumImpact();
                      ref.read(packageListProvider.notifier).markPickedUp(package.id);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('已完成「${package.goodsName ?? "包裹"}」取件'),
                          duration: const Duration(seconds: 2),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check_rounded, size: 14, color: Color(0xFF34C759)),
                          SizedBox(width: 3),
                          Text(
                            '确认取件',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF34C759),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('查看轨迹', style: TextStyle(fontSize: 12, color: Colors.grey)),
                      Icon(Icons.chevron_right_rounded, size: 16, color: Colors.grey),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductImage(String? url) {
    if (url != null && url.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.network(
          url,
          width: 54,
          height: 54,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _buildPlaceholder(),
        ),
      );
    }
    return _buildPlaceholder();
  }

  Widget _buildPlaceholder() {
    return Container(
      width: 54,
      height: 54,
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Icon(
        Icons.inventory_2_outlined,
        color: Colors.grey,
        size: 26,
      ),
    );
  }

  Widget _buildStatusPill(PackageStatus status) {
    Color bg;
    Color fg;
    String text;

    switch (status) {
      case PackageStatus.pendingShipment:
        bg = const Color(0xFF5856D6).withValues(alpha: 0.12);
        fg = const Color(0xFF5856D6);
        text = '待发货';
        break;
      case PackageStatus.arrived:
        bg = const Color(0xFF007AFF).withValues(alpha: 0.1);
        fg = const Color(0xFF007AFF);
        text = '待取件';
        break;
      case PackageStatus.delivering:
        bg = const Color(0xFFFF9500).withValues(alpha: 0.12);
        fg = const Color(0xFFFF9500);
        text = '派送中';
        break;
      case PackageStatus.transit:
        bg = Colors.grey.withValues(alpha: 0.12);
        fg = Colors.black54;
        text = '在途中';
        break;
      case PackageStatus.pickedUp:
        bg = const Color(0xFF34C759).withValues(alpha: 0.12);
        fg = const Color(0xFF34C759);
        text = '已取件';
        break;
      case PackageStatus.rejected:
        // 拒收为异常终结态：实心红底白字，明显区别于其它浅色标签
        bg = const Color(0xFFFF3B30);
        fg = Colors.white;
        text = '已拒收';
        break;
      case PackageStatus.archived:
        bg = Colors.grey.withValues(alpha: 0.1);
        fg = Colors.grey;
        text = '已归档';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: fg,
        ),
      ),
    );
  }

  String _displayTracking(Package p) {
    final no = p.trackingNumber.trim();
    if (p.status == PackageStatus.pendingShipment) {
      if (no.isEmpty) return '等待商家发货';
      return '订单号：$no';
    }
    // 排除前端生成的12位哈希，友好展示
    if (RegExp(r'^[0-9a-f]{12}$').hasMatch(no) || no.isEmpty) {
      return '${p.effectiveCourier.displayName} · 运输中';
    }
    return '运单号：$no';
  }
}
