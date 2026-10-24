/// 大号醒目取件码徽标 - 支持一键复制与触觉反馈
///
/// 取件码是这个 App 里最重要的一条信息（用户就是来读它的），所以它值得：
/// - 更大的字号（默认 28 / 大号 32+），驿站门口一眼可读；
/// - 等宽数字 + 字距，避免不同数字宽度导致复制时看串位；
/// - 实心强调色底 + 白字，白字对比 5.80:1（WCAG AA）。
///
/// 改版去掉了原先的蓝色外发光阴影与一个从未被读取的 `_morphController`。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants/app_constants.dart';
import '../theme/motion.dart';

class HeroPickupBadge extends StatefulWidget {
  final String pickupCode;
  final bool isLarge;
  final VoidCallback? onCopied;

  const HeroPickupBadge({
    super.key,
    required this.pickupCode,
    this.isLarge = false,
    this.onCopied,
  });

  @override
  State<HeroPickupBadge> createState() => _HeroPickupBadgeState();
}

class _HeroPickupBadgeState extends State<HeroPickupBadge> {
  bool _isCopied = false;

  Future<void> _handleCopy() async {
    if (widget.pickupCode.trim().isEmpty) return;

    await Clipboard.setData(ClipboardData(text: widget.pickupCode));
    HapticFeedback.mediumImpact();

    if (!mounted) return;
    setState(() => _isCopied = true);
    widget.onCopied?.call();

    await Future.delayed(const Duration(milliseconds: 1800));
    if (mounted) setState(() => _isCopied = false);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.pickupCode.trim().isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: AppColors.surfaceSunken,
          borderRadius: AppRadius.xsAll,
        ),
        child: const Text(
          '待到站生成',
          style: TextStyle(
            fontSize: 12,
            color: AppColors.textTertiary,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    }

    final fontSize = widget.isLarge ? 32.0 : 28.0;
    final fill = _isCopied ? AppColors.statusPickedUp : AppColors.primaryStrong;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _handleCopy,
        borderRadius: AppRadius.xsAll,
        child: AnimatedContainer(
          duration: Motion.of(context, Motion.fast),
          curve: Motion.standard,
          padding: EdgeInsets.symmetric(
            horizontal: widget.isLarge ? 14 : AppSpacing.md,
            vertical: widget.isLarge ? AppSpacing.sm : 6,
          ),
          decoration: BoxDecoration(color: fill, borderRadius: AppRadius.xsAll),
          // P38：去掉内部 Flexible+ellipsis。徽标以完整码固有宽参与布局；
          // 父级给出有界 maxWidth 时 FittedBox 才略缩小，优先一眼可读。
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _isCopied ? Icons.check_rounded : Icons.copy_rounded,
                  size: fontSize * 0.8,
                  color: Colors.white,
                ),
                const SizedBox(width: 6),
                AnimatedCrossFade(
                  firstChild: Text(
                    widget.pickupCode,
                    maxLines: 1,
                    softWrap: false,
                    style: TextStyle(
                      fontSize: fontSize,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                      height: 1.15,
                      color: Colors.white,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  secondChild: Text(
                    '已复制',
                    maxLines: 1,
                    softWrap: false,
                    style: TextStyle(
                      fontSize: fontSize * 0.85,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  crossFadeState: _isCopied
                      ? CrossFadeState.showSecond
                      : CrossFadeState.showFirst,
                  duration: Motion.of(context, Motion.fast),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
