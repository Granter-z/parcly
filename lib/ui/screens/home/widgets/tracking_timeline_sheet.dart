/// 深度映射电商官方风格的物流轨迹抽屉
///
/// 视觉与交互复刻：
/// 1. 顶部承运商与运单号条：品牌名称 + 运单号 + 一键复制
/// 2. 订单与收货信息卡片：订单编号 + 一键复制 + 收货地址（支持折叠展开）
/// 3. 商品与取件凭证栏：商品图文预览，待取件时呈现 Hero 提货码徽章
/// 4. 真实物流时间轴：
///    - 最新节点高亮绿点脉冲，绿色状态与时间戳，加粗轨迹描述
///    - 历史节点灰点串联
///    - 物流客服/派送员电话号码高亮为可点击的蓝色链接（一键拨打）
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/models/package.dart';
import '../../../../core/models/package_status.dart';
import '../../../components/hero_pickup_badge.dart';
import '../../../components/platform_badge.dart';

class TrackingTimelineSheet extends StatefulWidget {
  final Package package;

  const TrackingTimelineSheet({super.key, required this.package});

  static void show(BuildContext context, Package package) {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => TrackingTimelineSheet(package: package),
    );
  }

  @override
  State<TrackingTimelineSheet> createState() => _TrackingTimelineSheetState();
}

class _TrackingTimelineSheetState extends State<TrackingTimelineSheet> {
  bool _isAddressExpanded = false;

  void _copyToClipboard(String text, String label) {
    if (text.isEmpty) return;
    Clipboard.setData(ClipboardData(text: text));
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label 已复制到剪贴板'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _callPhone(String phone) async {
    final cleanPhone = phone.replaceAll(RegExp(r'[\s-]'), '');
    final uri = Uri.parse('tel:$cleanPhone');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  /// 取件凭证栏的站点文案：优先用简洁的驿站名，避免整段收货地址把取件码挤出屏幕
  String _credentialLocation(Package pkg) {
    final station = pkg.stationName?.trim() ?? '';
    if (station.isNotEmpty && station != '未知驿站') return station;
    final original = pkg.originalStation.trim();
    if (original.isNotEmpty) return original;
    return pkg.displayLocation;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pkg = widget.package;
    final courierName = pkg.effectiveCourier.displayName;
    final trackingNo = pkg.trackingNumber;
    final orderSn = pkg.displayOrderSn;
    final address = pkg.location.trim();
    final timelineList = pkg.parsedTimeline;

    return DraggableScrollableSheet(
      initialChildSize: 0.82,
      minChildSize: 0.50,
      maxChildSize: 0.96,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 20,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: Column(
            children: [
              // 顶部拖拽把手
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 10, bottom: 12),
                  width: 38,
                  height: 4.5,
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),

              // 滚动内容主体
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 30),
                  children: [
                    // ── 模块 1：快递承运商与运单号（仿拼多多顶条） ──
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF7F8FA),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: const Color(0xFF00B578).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(7),
                            ),
                            child: const Icon(
                              Icons.local_shipping_rounded,
                              size: 16,
                              color: Color(0xFF00B578),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: RichText(
                              text: TextSpan(
                                children: [
                                  TextSpan(
                                    text: '$courierName: ',
                                    style: const TextStyle(
                                      color: Color(0xFF00B578),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14.5,
                                    ),
                                  ),
                                  TextSpan(
                                    text: trackingNo,
                                    style: const TextStyle(
                                      color: Color(0xFF1C1C1E),
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          _buildCopyButton(
                            onTap: () => _copyToClipboard(trackingNo, '运单号'),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 10),

                    // ── 模块 2：订单编号与收货地址卡片 ──
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF7F8FA),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 订单编号
                          Row(
                            children: [
                              const Icon(
                                Icons.receipt_long_outlined,
                                size: 16,
                                color: Color(0xFF8E8E93),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '订单编号：$orderSn',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFF3A3A3C),
                                    fontWeight: FontWeight.w500,
                                    fontFamily: 'monospace',
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              _buildCopyButton(
                                onTap: () => _copyToClipboard(orderSn, '订单编号'),
                              ),
                            ],
                          ),

                          // 收货地址
                          if (address.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            const Divider(height: 1, color: Color(0xFFE5E5EA)),
                            const SizedBox(height: 10),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Padding(
                                  padding: EdgeInsets.only(top: 1.5),
                                  child: Icon(
                                    Icons.location_on_outlined,
                                    size: 16,
                                    color: Color(0xFF8E8E93),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '收货地址：$address',
                                    style: const TextStyle(
                                      fontSize: 12.5,
                                      color: Color(0xFF3A3A3C),
                                      height: 1.4,
                                    ),
                                    maxLines: _isAddressExpanded ? 4 : 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (address.length > 18)
                                  InkWell(
                                    onTap: () {
                                      HapticFeedback.lightImpact();
                                      setState(() => _isAddressExpanded = !_isAddressExpanded);
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.only(left: 6),
                                      child: Text(
                                        _isAddressExpanded ? '收起 ∧' : '展开 ∨',
                                        style: const TextStyle(
                                          fontSize: 11.5,
                                          color: Color(0xFF8E8E93),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),

                    // ── 模块 3：商品快件概要 ──
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
                      ),
                      child: Row(
                        children: [
                          if (pkg.goodsImageUrl != null && pkg.goodsImageUrl!.isNotEmpty)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(
                                pkg.goodsImageUrl!,
                                width: 50,
                                height: 50,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => _buildPlaceholderIcon(),
                              ),
                            )
                          else
                            _buildPlaceholderIcon(),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    PlatformBadge(platform: pkg.platform),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        pkg.goodsName ?? (pkg.description.isNotEmpty ? pkg.description : '包裹快件'),
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF1C1C1E),
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  pkg.displayLocation,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF8E8E93),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    // ── 模块 4：取件码突出展示（若已到驿站） ──
                    if (pkg.pickupCode.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF007AFF).withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: const Color(0xFF007AFF).withValues(alpha: 0.22),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    '取件凭证',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: Color(0xFF007AFF),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _credentialLocation(pkg),
                                    style: const TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            HeroPickupBadge(
                              pickupCode: pkg.pickupCode,
                              isLarge: true,
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 16),
                    const Divider(height: 1, color: Color(0xFFE5E5EA)),
                    const SizedBox(height: 16),

                    // ── 模块 5：物流轨迹时间轴（对齐拼多多官方风格） ──
                    const Padding(
                      padding: EdgeInsets.only(bottom: 14),
                      child: Text(
                        '物流跟踪轨迹',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1C1C1E),
                        ),
                      ),
                    ),

                    if (timelineList.isNotEmpty)
                      ...List.generate(timelineList.length, (idx) {
                        final node = timelineList[idx];
                        final isLatest = idx == 0;
                        final isLast = idx == timelineList.length - 1;
                        return _buildOfficialTimelineItem(
                          tag: node['tag'] ?? '',
                          time: node['time'] ?? '',
                          text: node['text'] ?? '',
                          isLatest: isLatest,
                          isLast: isLast,
                        );
                      })
                    else
                      ..._buildFallbackSteps(pkg),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCopyButton({required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFFD1D1D6)),
        ),
        child: const Text(
          '复制',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Color(0xFF3A3A3C),
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholderIcon() {
    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(Icons.inventory_2_outlined, color: Colors.grey, size: 24),
    );
  }

  /// 官方风格时间轴节点（第一条绿色高亮，后续为灰色）
  Widget _buildOfficialTimelineItem({
    required String tag,
    required String time,
    required String text,
    required bool isLatest,
    required bool isLast,
  }) {
    const greenColor = Color(0xFF00B578);
    final dotColor = isLatest ? greenColor : const Color(0xFFC4C4C4);
    final textColor = isLatest ? greenColor : const Color(0xFF2C2C2E);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 时间轴左侧：节点图标与垂直连接线
          SizedBox(
            width: 22,
            child: Column(
              children: [
                if (isLatest)
                  Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: greenColor.withValues(alpha: 0.2),
                    ),
                    child: Center(
                      child: Container(
                        width: 9,
                        height: 9,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: greenColor,
                        ),
                      ),
                    ),
                  )
                else
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: dotColor,
                    ),
                  ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 1.5,
                      color: const Color(0xFFE5E5EA),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),

          // 时间轴右侧：状态/时间标头 + 详细轨迹（电话号码可点击）
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 状态与时间标头
                  Row(
                    children: [
                      if (tag.isNotEmpty) ...[
                        Text(
                          tag,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: isLatest ? FontWeight.bold : FontWeight.w600,
                            color: isLatest ? greenColor : const Color(0xFF3A3A3C),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        time,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: isLatest ? FontWeight.w600 : FontWeight.normal,
                          color: isLatest ? greenColor : const Color(0xFF8E8E93),
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),

                  // 轨迹描述正文（解析电话号码高亮）
                  _buildTraceRichText(text, isLatest ? textColor : const Color(0xFF333333)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 解析描述中的电话号码并标蓝可点击
  Widget _buildTraceRichText(String text, Color baseColor) {
    final phoneRegex = RegExp(r'(\b1\d{10}\b|\b0\d{2,3}[-\s]?\d{7,8}\b|\b95\d{3,5}\b)');
    final spans = <TextSpan>[];
    int start = 0;

    for (final match in phoneRegex.allMatches(text)) {
      if (match.start > start) {
        spans.add(TextSpan(
          text: text.substring(start, match.start),
          style: TextStyle(
            fontSize: 13,
            color: baseColor,
            height: 1.45,
          ),
        ));
      }
      final phone = match.group(0)!;
      spans.add(TextSpan(
        text: phone,
        style: const TextStyle(
          fontSize: 13,
          color: Color(0xFF1890FF),
          fontWeight: FontWeight.w600,
          decoration: TextDecoration.underline,
        ),
        recognizer: TapGestureRecognizer()..onTap = () => _callPhone(phone),
      ));
      start = match.end;
    }

    if (start < text.length) {
      spans.add(TextSpan(
        text: text.substring(start),
        style: TextStyle(
          fontSize: 13,
          color: baseColor,
          height: 1.45,
        ),
      ));
    }

    return RichText(text: TextSpan(children: spans));
  }

  /// 兜底时间轴（若未提取到多节点轨迹时呈现智能阶段）
  List<Widget> _buildFallbackSteps(Package pkg) {
    final steps = <Map<String, String>>[];

    if (pkg.status == PackageStatus.pendingShipment) {
      steps.add({
        'tag': '待发货',
        'time': '等待中',
        'text': pkg.description.isNotEmpty ? pkg.description : '商品已下单成功，等待商家打包发货',
      });
      steps.add({
        'tag': '已下单',
        'time': '已完成',
        'text': '订单支付完成，等待系统推送出库',
      });

      return List.generate(steps.length, (idx) {
        final s = steps[idx];
        return _buildOfficialTimelineItem(
          tag: s['tag'] ?? '',
          time: s['time'] ?? '',
          text: s['text'] ?? '',
          isLatest: idx == 0,
          isLast: idx == steps.length - 1,
        );
      });
    }

    if (pkg.status == PackageStatus.pickedUp) {
      steps.add({
        'tag': '已签收',
        'time': '今日',
        'text': '包裹已在 ${pkg.displayLocation} 妥投签收',
      });
    }

    if (pkg.status == PackageStatus.rejected) {
      steps.add({
        'tag': '已拒收',
        'time': '已终止',
        'text': pkg.description.isNotEmpty
            ? pkg.description
            : '包裹已拒收/退回发件人，无需再前往驿站取件',
      });
    }

    if (pkg.status.isArrived || pkg.status == PackageStatus.pickedUp) {
      steps.add({
        'tag': '已到达',
        'time': '今日',
        'text': '快件已到达 ${pkg.displayLocation}${pkg.pickupCode.isNotEmpty ? "，取件凭证：${pkg.pickupCode}" : ""}，请及时提货',
      });
    }

    if (pkg.status == PackageStatus.delivering) {
      steps.add({
        'tag': '派送中',
        'time': '派送中',
        'text': '快递员正在为您派送包裹，请保持手机畅通',
      });
    }

    steps.add({
      'tag': pkg.status.label,
      'time': '运输中',
      'text': pkg.description.isNotEmpty ? pkg.description : '快件正在运送中，发往目的地交付中心',
    });

    steps.add({
      'tag': '已发货',
      'time': '已发货',
      'text': '商家已发货，包裹已被快递公司揽收处理',
    });

    return List.generate(steps.length, (idx) {
      final s = steps[idx];
      return _buildOfficialTimelineItem(
        tag: s['tag'] ?? '',
        time: s['time'] ?? '',
        text: s['text'] ?? '',
        isLatest: idx == 0,
        isLast: idx == steps.length - 1,
      );
    });
  }
}
