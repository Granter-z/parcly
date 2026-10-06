library;

import 'package:flutter/material.dart';
import '../ui/constants/app_constants.dart';
import '../core/models/package.dart';
import '../core/engine/hero_card_engine.dart';
import '../core/engine/hero_card_state.dart';

export '../core/engine/hero_card_state.dart'
    show HeroBadgeType, EmotionState, SuggestedAction, HeroEmotionState;

class HeroBadge {
  final String label;
  final HeroBadgeType type;

  const HeroBadge({required this.label, required this.type});
}

class HeroDecision {
  final String title;
  final String? subtitle;
  final List<HeroBadge> badges;
  final IconData icon;
  final Color color;

  const HeroDecision({
    required this.title,
    this.subtitle,
    this.badges = const [],
    this.icon = Icons.local_shipping_outlined,
    this.color = AppColors.primary,
  });
}

class HeroDecisionService {
  static HeroDecision decide(List<Package> allPackages) {
    final coreState = HeroCardEngine.decide(allPackages);
    return _convert(coreState);
  }

  static HeroDecision _convert(HeroCardState state) {
    final badges = state.badges
        .map((b) => HeroBadge(label: b.label, type: b.type))
        .toList();

    return HeroDecision(
      title: state.title,
      subtitle: state.subtitle,
      badges: badges,
      icon: _icon(state.heroEmotionState),
      color: _color(state.heroEmotionState),
    );
  }

  static Color _color(HeroEmotionState emotion) {
    switch (emotion) {
      case HeroEmotionState.relaxed:
        return AppColors.success;
      case HeroEmotionState.normal:
        return AppColors.primary;
      case HeroEmotionState.urgent:
        return AppColors.urgent;
    }
  }

  static IconData _icon(HeroEmotionState emotion) {
    switch (emotion) {
      case HeroEmotionState.relaxed:
        return Icons.check_circle_outline;
      case HeroEmotionState.normal:
        return Icons.local_shipping_outlined;
      case HeroEmotionState.urgent:
        return Icons.warning_amber_rounded;
    }
  }
}