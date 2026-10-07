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
import '../../../theme/motion.dart';
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
                  _PickupConfirmButton(
                    onConfirmed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('已完成「${package.goodsName ?? "包裹"}」取件'),
                          duration: const Duration(seconds: 2),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                      ref.read(packageListProvider.notifier).markPickedUp(package.id);
                    },
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
      // 兜底历史数据：淘宝曾存过 //img.alicdn.com/... 这类缺协议 scheme 的 URL，直接请求必然失败
      final normalized = url.startsWith('//') ? 'https:$url' : url;
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.network(
          normalized,
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

  /// 状态标签：状态迁移时底色与文字颜色平滑插值，文案做淡入淡出切换。
  Widget _buildStatusPill(PackageStatus status) {
    final visual = _statusVisual(status);

    return AnimatedContainer(
      duration: Motion.normal,
      curve: Motion.standard,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: visual.background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: AnimatedSwitcher(
        duration: Motion.fast,
        child: Text(
          visual.label,
          key: ValueKey(visual.label),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: visual.foreground,
          ),
        ),
      ),
    );
  }

  /// 各状态对应的标签配色与文案。
  ({Color background, Color foreground, String label}) _statusVisual(
    PackageStatus status,
  ) {
    switch (status) {
      case PackageStatus.pendingShipment:
        return (
          background: const Color(0xFF5856D6).withValues(alpha: 0.12),
          foreground: const Color(0xFF5856D6),
          label: '待发货',
        );
      case PackageStatus.arrived:
        return (
          background: const Color(0xFF007AFF).withValues(alpha: 0.1),
          foreground: const Color(0xFF007AFF),
          label: '待取件',
        );
      case PackageStatus.delivering:
        return (
          background: const Color(0xFFFF9500).withValues(alpha: 0.12),
          foreground: const Color(0xFFFF9500),
          label: '派送中',
        );
      case PackageStatus.transit:
        return (
          background: Colors.grey.withValues(alpha: 0.12),
          foreground: Colors.black54,
          label: '在途中',
        );
      case PackageStatus.pickedUp:
        return (
          background: const Color(0xFF34C759).withValues(alpha: 0.12),
          foreground: const Color(0xFF34C759),
          label: '已取件',
        );
      case PackageStatus.rejected:
        // 拒收为异常终结态：实心红底白字，明显区别于其它浅色标签
        return (
          background: const Color(0xFFFF3B30),
          foreground: Colors.white,
          label: '已拒收',
        );
      case PackageStatus.archived:
        return (
          background: Colors.grey.withValues(alpha: 0.1),
          foreground: Colors.grey,
          label: '已归档',
        );
    }
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

/// 「确认取件」按钮：点按后在原位上做一次绿色脉冲 + 放大回弹，
/// 动画播完才真正标记已取，让卡片消失前先给出明确反馈。
class _PickupConfirmButton extends StatefulWidget {
  final VoidCallback onConfirmed;

  const _PickupConfirmButton({required this.onConfirmed});

  @override
  State<_PickupConfirmButton> createState() => _PickupConfirmButtonState();
}

class _PickupConfirmButtonState extends State<_PickupConfirmButton>
    with SingleTickerProviderStateMixin {
  static const _success = Color(0xFF34C759);

  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: Motion.emphasized);
    _scale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 1.12)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 30,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.12, end: 1.0)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 70,
      ),
    ]).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleTap() async {
    if (_controller.isAnimating) return;
    HapticFeedback.mediumImpact();
    await _controller.forward(from: 0);
    if (!mounted) return;
    _controller.value = 0; // 复位，避免交回上层时残留高亮
    widget.onConfirmed();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        // 底色由浅绿加深为实心绿，文字同步反白
        final t = Curves.easeOut.transform(_controller.value);
        final tint = Color.lerp(_success.withValues(alpha: 0.12), _success, t);
        final onTint = Color.lerp(_success, Colors.white, t);

        return Transform.scale(
          scale: _scale.value,
          child: InkWell(
            onTap: _handleTap,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: tint,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_rounded, size: 14, color: onTint),
                  const SizedBox(width: 3),
                  Text(
                    '确认取件',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: onTint,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
