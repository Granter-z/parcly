/// 大号醒目取件码胶囊徽标 - 支持物理点击缩放与一键复制触觉反馈
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

class _HeroPickupBadgeState extends State<HeroPickupBadge> with SingleTickerProviderStateMixin {
  bool _isCopied = false;
  late final AnimationController _morphController;

  @override
  void initState() {
    super.initState();
    _morphController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
  }

  @override
  void dispose() {
    _morphController.dispose();
    super.dispose();
  }

  Future<void> _handleCopy() async {
    if (widget.pickupCode.trim().isEmpty) return;

    await Clipboard.setData(ClipboardData(text: widget.pickupCode));
    HapticFeedback.mediumImpact();

    if (!mounted) return;
    setState(() => _isCopied = true);
    _morphController.forward(from: 0.0);
    widget.onCopied?.call();

    await Future.delayed(const Duration(milliseconds: 1800));
    if (mounted) {
      setState(() => _isCopied = false);
      _morphController.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.pickupCode.trim().isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.grey.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Text(
          '待到站生成',
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    }

    final fontSize = widget.isLarge ? 22.0 : 16.0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _handleCopy,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: EdgeInsets.symmetric(
            horizontal: widget.isLarge ? 14 : 10,
            vertical: widget.isLarge ? 8 : 5,
          ),
          decoration: BoxDecoration(
            gradient: _isCopied
                ? const LinearGradient(
                    colors: [Color(0xFF34C759), Color(0xFF28A745)],
                  )
                : const LinearGradient(
                    colors: [Color(0xFF007AFF), Color(0xFF0056B3)],
                  ),
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: (_isCopied ? const Color(0xFF34C759) : const Color(0xFF007AFF))
                    .withValues(alpha: 0.25),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _isCopied ? Icons.check_circle_rounded : Icons.copy_rounded,
                size: fontSize * 0.85,
                color: Colors.white,
              ),
              const SizedBox(width: 6),
              AnimatedCrossFade(
                firstChild: Text(
                  widget.pickupCode,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: fontSize,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                    color: Colors.white,
                  ),
                ),
                secondChild: Text(
                  '已复制!',
                  style: TextStyle(
                    fontSize: fontSize * 0.9,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                crossFadeState: _isCopied
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                duration: const Duration(milliseconds: 200),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
