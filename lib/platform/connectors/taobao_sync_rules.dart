/// 淘宝同步的请求策略 - 纯 Dart（不引用 Flutter）
///
/// P11-b 后续（产品经理、技术负责人 10-07 定）：已签收订单只请求一次物流详情。
/// 请求前按包裹匹配规则找到本地对应的 Package，已签收（或已归档）且轨迹不为空就跳过；
/// 不另存「已请求」标记，本地没有或轨迹为空时照常请求。
library;

import '../../core/models/package.dart';
import '../../core/models/package_status.dart';

/// 淘宝订单产出的包裹 ID：`TB_<订单号>`。
///
/// 包裹 ID 必须由平台订单号派生（与 `PackageListNotifier._findExistingPackage` 的第 1 条匹配规则、
/// 拼多多 `PDD_<订单号>`、京东 `JD_<订单号>` 一致），请求详情前才能凭订单号找到本地包裹。
/// 运单号放在 `trackingNumber`，同一包裹的 `CN_<运单号>` 记录照旧按运单号合并。
String taobaoPackageId(String orderId) => 'TB_$orderId';

/// 按现有匹配方式找本地包裹：先按包裹 ID，再按运单号（没有运单号时 trackingNumber 就是订单号）。
///
/// 请求详情前只知道订单号，取件码那条匹配规则用不上。
Package? findLocalTaobaoPackage(Iterable<Package> local, String orderId) {
  final id = orderId.trim();
  if (id.isEmpty) return null;
  final byId = taobaoPackageId(id);
  for (final p in local) {
    if (p.id == byId) return p;
  }
  for (final p in local) {
    if (p.trackingNumber.trim() == id) return p;
  }
  return null;
}

/// 本地已有这单、已签收（pickedUp，或由它归档的 archived）、轨迹不为空 → 跳过详情请求。
bool shouldSkipSignedDetail(Package? local) {
  if (local == null) return false;
  if (local.status != PackageStatus.pickedUp && local.status != PackageStatus.archived) return false;
  return local.parsedTimeline.isNotEmpty;
}
