/// 首页顶部 Hero —— 只回答一个问题：现在最该关心几件包裹。
///
/// P33：Hero 仍是**内容层**（数字 + 文案），用 [ContentSurface] 近实心抬升面，
/// 不再套 Liquid Glass（玻璃留给功能层 chrome）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/hero_decision.dart';
import '../../../components/glass_surface.dart';
import '../../../constants/app_constants.dart';
import '../../../providers/package_provider.dart';
import '../../../theme/glass_tokens.dart';
import '../../../theme/motion.dart';

class HeroStatsDashboard extends ConsumerWidget {
  const HeroStatsDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final decision = ref.watch(heroDecisionProvider);

    // 没有在途 / 待取件时整块收起，让位给页面下方的空态卡片。
    if (decision.isEmpty) return const SizedBox.shrink();

    final lead = decision.lead;
    final theme = Theme.of(context);
    final isUrgent = decision.heroEmotionState == HeroEmotionState.urgent;

    return ContentSurface(
      padding: const EdgeInsets.all(AppSpacing.xl),
      borderRadius: GlassTokens.radiusAll,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              _RollingNumber(
                value: lead.count,
                style: theme.textTheme.displaySmall!.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                lead.unit,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              if (isUrgent) const _UrgentChip(),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            _statusLine(decision),
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.4,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  String _statusLine(HeroDecision decision) {
    final advice = decision.subtitle;
    if (advice != null && advice.isNotEmpty) return advice;

    final lead = decision.lead;
    if (decision.arrivedCount > 0) return '已送达取件点，点击卡片查看取件码';
    if (decision.deliveringCount > 0) return '快递员正在派送，留意来电';
    if (decision.transitCount > 0) return '包裹运送中，到站后会第一时间提醒';
    if (lead.count > 0) return '商家正在备货，发货后自动同步';
    return '';
  }
}

class _UrgentChip extends StatelessWidget {
  const _UrgentChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: AppColors.statusRejected,
        borderRadius: AppRadius.xsAll,
      ),
      child: const Text(
        '紧急',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _RollingNumber extends StatelessWidget {
  final int value;
  final TextStyle style;

  const _RollingNumber({required this.value, required this.style});

  @override
  Widget build(BuildContext context) {
    final duration = Motion.of(context, Motion.emphasized);
    if (duration == Duration.zero) {
      return Text(value.toString(), style: style);
    }

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: value.toDouble()),
      duration: duration,
      curve: Motion.standard,
      builder: (context, animated, _) =>
          Text(animated.round().toString(), style: style),
    );
  }
}
