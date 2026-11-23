# 保活机制健康状态判断修复

## 问题描述

用户报告：京东登录失效了一天，保活机制显示"健康"，失败次数 3，但保活时间不到 2 小时。

## 根本原因

### 1. 健康状态只看 Cookie 年龄，忽略失败次数
```dart
// 修复前 - lib/platform/keep_alive/keep_alive_service.dart:169
'health': KeepAliveScheduler.getCookieHealthDescription(cookieAge)
```
即使心跳连续失败 3 次、登录已失效，只要 Cookie 是 3 天前绑定的，仍显示"健康"。

### 2. 京东心跳不可靠
```dart
// 修复前 - lib/platform/keep_alive/platform_heartbeat.dart:123
final response = await http.head(...)  // HEAD 请求无响应体
if (response.statusCode == 200) {
  return HeartbeatResult.success();  // 200 不代表登录有效
}
```
HEAD 请求无法获取响应体验证登录态，200 状态码可能是"请登录"页面。

### 3. 失败后不标记登录态失效
```dart
// 修复前 - lib/platform/keep_alive/keep_alive_service.dart:151
if (_failureCount[platform]! >= 3) {
  debugPrint('login expired');
  // TODO: 通知 ConnectorManager 登录态失效  ❌ 只打印日志
}
```

### 4. 固定 12 小时间隔，不响应 Cookie 老化
```dart
// 修复前 - lib/platform/keep_alive/keep_alive_service.dart:54
_timer = Timer.periodic(const Duration(hours: 12), (_) { ... });
```
`KeepAliveScheduler.calculateInterval()` 计算的 4-24 小时动态间隔完全没用上。

### 5. `shouldSkip()` 过度保守
```dart
// lib/platform/keep_alive/keep_alive_scheduler.dart:52
if (timeSinceKeepAlive.inHours < 2) {
  return true;  // 2 小时内跳过
}
```
即使定时器每 12 小时触发一次，如果距上次保活不到 2 小时也会跳过。

## 修复方案（已与当前架构对齐）

### 1. 增强健康状态判断（综合失败次数）✅

**文件**: [lib/core/engine/keep_alive_plan.dart](../lib/core/engine/keep_alive_plan.dart)、[lib/platform/keep_alive/keep_alive_service.dart](../lib/platform/keep_alive/keep_alive_service.dart)

健康度判定已下沉至纯 Dart 的 `KeepAlivePlan.resolveHealth(...)`，`KeepAliveService.statusOf(platform)` 返回强类型 `PlatformKeepAliveStatus`：

```dart
// lib/core/engine/keep_alive_plan.dart
static String resolveHealth({
  required bool isExpired,
  required int failureCount,
  Duration? cookieAge,
}) {
  if (isExpired || failureCount >= failureThreshold) return '失效';
  if (failureCount >= 1) return '不稳定';
  if (cookieAge != null) return cookieHealthDescription(cookieAge);
  return 'unknown';
}
```

### 2. 改进京东心跳（wqs + trade 双探与响应分级）✅

**文件**: [lib/platform/keep_alive/platform_heartbeat.dart](../lib/platform/keep_alive/platform_heartbeat.dart)

`JdHeartbeat` 已升级为 `wqs` + `trade.m.jd.com` 双探（关闭自动重定向 `followRedirects = false`，以 `trade` 作为失效真相源，经 `classifyResponse` 与 `combineDualProbe` 综合判定）：
- 仅 `trade` 出现硬失效信号（`"isLogin":false`、`"loginFlag":false`、`请登录`、重定向到 `login`/`passport`、HTTP `401`/`403`）才返回 `isAuthFailure: true`；
- SPA 壳常见 `login.m.jd.com` / `passport.jd.com` 作为软信号处理，不直接触发 `setExpired`；
- 任一探针出现明确订单阳性（`orderList` / `订单` / `我的订单`）且 `trade` 非硬失效时视为成功。

### 3. 失败后标记登录态失效 ✅

**文件**: [lib/core/engine/keep_alive_outcome.dart](../lib/core/engine/keep_alive_outcome.dart)、[lib/platform/keep_alive/keep_alive_service.dart](../lib/platform/keep_alive/keep_alive_service.dart)

`_performHeartbeatForPlatform` 通过 `planKeepAliveOutcome` 与 `applyHeartbeatOutcome` 统一更新状态（并持久化到 `KeepAliveStore`）：
- `authFailure`：立即 `setExpired(platform, true)` 且 `failureCount = 3`；
- `networkFailure`：累加 `failureCount`，连续 ≥ 3 次后 `setExpired(platform, true)`；
- `success`：归零 `failureCount`、清除 `expired_at`、清空失效通知去重标记与 worker 通知标记；
- `skipped`：既不算成功也不累加失败，不推进闸门。

### 4. Cookie 生命周期写边界与重登/解绑清理 ✅

**文件**: [lib/platform/storage/platform_auth_store.dart](../lib/platform/storage/platform_auth_store.dart)、[lib/platform/storage/keep_alive_store.dart](../lib/platform/storage/keep_alive_store.dart)

- **保活/同步续期**：连接器同步成功回写完整 Cookie 时调用 `refreshCookiesInPlace(platform, cookies)`（淘宝 mtop 令牌轮换调用 `updateCookieTokenFields`），仅就地刷新加密 Cookie 与内存缓存，**不刷新 `updated_at` 年龄锚点、不误清 `expired_at`**；
- **用户重新登录 `saveCookies` 与解绑 `unbind`**：清除 `expired_at` 的同时，自动重置 `KeepAliveStore` 的闸门（`setNext(p, null)`）、失败计数（`setFailureCount(p, 0)`）、通知去重标记（`setLastNotifiedAt(p, null)`），并调用 `clearWorkerNotifiedAt(p)` 与 `clearWorkerGate(p)` 清理后台 worker 的通知与闸门 JSON 文件，防止重新绑定后继承旧状态。

### 5. 动态保活间隔与持久化共享缓存 ✅

**文件**: [lib/core/engine/keep_alive_plan.dart](../lib/core/engine/keep_alive_plan.dart)、[lib/platform/storage/keep_alive_store.dart](../lib/platform/storage/keep_alive_store.dart)、[lib/platform/keep_alive/keep_alive_service.dart](../lib/platform/keep_alive/keep_alive_service.dart)

- `KeepAliveStore` 采用**进程内静态共享缓存**，多处实例化均读写同一份内存缓存并持久化到 `keep_alive_state` Hive box（冷启动时 `next_keep_alive_at` 闸门依然生效）；
- 前台定时器每 1 小时检查一次，各平台按 `KeepAlivePlan.calculateInterval(cookieAge)` 独立计算下次保活时间（带 ±30 分钟随机抖动）。

## 保活间隔策略

根据 Cookie 年龄（`now - PlatformAuthStore.getBoundTime()`）动态调整：
- **≤3 天**：24 小时（新鲜期，低频维护）
- **4–10 天**：6 小时（中期/临期，缩小会话失效空窗）
- **11+ 天**：4 小时（危险期，高频保活）

定时器每 1 小时检查一次，各平台独立计算下次保活时间。

## 验证方法

### 1. 模拟登录失效
手动删除京东 Cookie 中的 `pt_key` 字段（或使用已失效账号）。

### 2. 触发保活
```dart
await ref.read(keepAliveControllerProvider.notifier).manualKeepAlive();
```

### 3. 检查状态
```dart
final snapshot = ref.read(keepAliveControllerProvider);
final jd = snapshot.platforms.firstWhere((p) => p.platform == 'jd');
debugPrint('health=${jd.health}, failures=${jd.failureCount}, expired=${jd.isExpired}');
// 应为 health=失效, failureCount=3, isExpired=true
```

### 4. 重新绑定
在登录页重新授权（`saveCookies`）后，`isExpired`、失败计数、闸门及 worker 通知/闸门文件会自动清除。

## 影响范围

- ✅ 健康状态现在准确反映登录态
- ✅ 京东心跳更可靠（`wqs` + `trade` 双探与硬/软信号分级）
- ✅ 失败后立即或达阈值标记失效状态
- ✅ 保活间隔根据 Cookie 年龄动态调整（≤3 天 24h、4–10 天 6h、11+ 天 4h）并持久化
- ✅ 保活/同步续期调用 `refreshCookiesInPlace` 不篡改 `updated_at` / `expired_at`，重登与解绑自动清理保活及 worker 状态

## 相关文件

- [lib/core/engine/keep_alive_plan.dart](../lib/core/engine/keep_alive_plan.dart)
- [lib/core/engine/keep_alive_outcome.dart](../lib/core/engine/keep_alive_outcome.dart)
- [lib/platform/keep_alive/keep_alive_service.dart](../lib/platform/keep_alive/keep_alive_service.dart)
- [lib/platform/keep_alive/platform_heartbeat.dart](../lib/platform/keep_alive/platform_heartbeat.dart)
- [lib/platform/keep_alive/keep_alive_worker_bridge.dart](../lib/platform/keep_alive/keep_alive_worker_bridge.dart)
- [lib/platform/storage/keep_alive_store.dart](../lib/platform/storage/keep_alive_store.dart)
- [lib/platform/storage/platform_auth_store.dart](../lib/platform/storage/platform_auth_store.dart)
