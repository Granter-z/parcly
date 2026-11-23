/// 平台连接器接口抽象 - 桥接各电商平台与包裹聚合引擎
library;

import '../../core/models/package.dart';

abstract class PlatformConnector {
  String get platformId;
  String get displayName;

  /// 检查当前是否拥有有效登录态
  Future<bool> isAuthenticated();

  /// 触发拉取/流式同步包裹
  Stream<Package> streamSync();

  /// 取消当前同步任务
  Future<void> cancelSync();

  /// 最近一次同步中出现的问题（例如登录态失效），无问题时为 null
  String? get lastIssue => null;

  /// 最近一次同步是否真实成功（无内部硬超时、网络软失败或取消）
  bool get lastSyncSucceeded => lastIssue == null;

  /// 清理上一次的失效或异常提示
  void clearLastIssue() {}
}
