/// 全局动效令牌：集中动画时长与曲线，避免魔法数字散落在各个组件里。
///
/// 只服务于 `ui/` 层的过渡与反馈，不承载任何业务语义。
library;

import 'package:flutter/animation.dart';

class Motion {
  Motion._();

  /// 即时反馈：颜色微调、状态标签切换。
  static const Duration fast = Duration(milliseconds: 160);

  /// 常规过渡：淡入淡出、文案切换。
  static const Duration normal = Duration(milliseconds: 240);

  /// 强调过渡：列表项进出场、卡片展开。
  static const Duration emphasized = Duration(milliseconds: 380);

  /// 交错入场的基础间隔：第 n 项延后 `n * stagger`。
  static const Duration stagger = Duration(milliseconds: 45);

  /// 进入曲线：轻微回弹，克制收尾。
  static const Curve enter = Curves.easeOutBack;

  /// 退出曲线：加速离场，干脆利落。
  static const Curve exit = Curves.easeInCubic;

  /// 通用缓出。
  static const Curve standard = Curves.easeOutCubic;
}
