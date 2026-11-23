/// 同步历史记录管理器
///
/// 记录每个平台和订单的最近同步时间，用于智能跳过已同步订单
library;

import 'package:hive/hive.dart';

class SyncHistoryManager {
  static const String _boxName = 'sync_history';
  Box? _box;

  /// 初始化（在 main.dart 中调用）
  static Future<void> initialize() async {
    if (!Hive.isBoxOpen(_boxName)) {
      await Hive.openBox(_boxName);
    }
  }

  Future<void> _ensureInit() async {
    if (_box == null || !_box!.isOpen) {
      if (Hive.isBoxOpen(_boxName)) {
        _box = Hive.box(_boxName);
      } else {
        _box = await Hive.openBox(_boxName);
      }
    }
  }

  /// 记录平台同步时间
  Future<void> recordPlatformSync(String platform) async {
    await _ensureInit();
    await _box!.put(
      '${platform.toLowerCase()}_last_sync',
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// 获取平台最近同步时间（同步读）
  ///
  /// 调用方常用新实例直接读（如保活服务），若只认本实例开过的 box 会恒返回 null，
  /// 导致「用户刚同步过，6 小时内跳过保活」失效；这里回退到 App 级已打开的 box。
  DateTime? getPlatformLastSync(String platform) {
    if (_box == null || !_box!.isOpen) {
      if (!Hive.isBoxOpen(_boxName)) return null;
      _box = Hive.box(_boxName);
    }
    final ms = _box!.get('${platform.toLowerCase()}_last_sync') as int?;
    return ms != null ? DateTime.fromMillisecondsSinceEpoch(ms) : null;
  }

  /// P23-b：记录菜鸟驿站 WebView 阶段成功产出时间（子键 `cainiao`）。
  Future<void> recordCainiaoSuccess() => recordPlatformSync('cainiao');

  /// P23-b：上次菜鸟成功产出时间；从未成功则为 null。
  DateTime? getCainiaoLastSuccess() => getPlatformLastSync('cainiao');
}
