# P24 账户登录持久性 — 必须嘉豪真机验的步骤

> 日期：2026-10-21  
> 范围：box 上无法完整模拟 WorkManager 6h 续期与国产 ROM 杀后台；下列步骤需真机。

## 前置

- 安装本分支本地构建的 release/profile APK（勿用已过期的旧包）
- 分别绑定淘宝、京东、拼多多（或至少淘宝+京东）
- 打开「设置 → 保活状态」，确认总开关与对应平台开关为开

## 必测清单

1. **后台 isolate 链路（one-off）**  
   保活状态页点「测试后台续期任务」→ logcat 过滤 `KeepAliveWorker`：  
   - 未绑定平台出现 `Skip … notBound` / `notBound`  
   - 已绑定且 Cookie 有效：`Refresh taobao` → `taobao refreshed`  
   - Cookie 已废：`login expired`，设置页该平台显示「已失效」

2. **划掉进程后的持久性（短验证）**  
   最近台划掉 App → 等 ≥ 1 分钟再打开：淘宝/京东绑定仍在，不必立刻重登。  
   （完整 6h periodic 唤醒依赖系统调度，可另选空闲时段看 `dumpsys jobscheduler` 是否仍有任务。）

3. **失效通知**  
   人为废掉京东 Cookie（或等自然失效）→ 前台手动保活或后台测试任务 → 应收到「登录状态提醒」通知；同一失效周期内不重复轰炸；重登成功后标记清除，下次失效可再提醒。

4. **拼多多前台限制**  
   后台测试任务 log 中**不应**出现 `Refresh pdd`。  
   拼多多只能打开 App 后由前台心跳/同步续期；产品文案可用 `supportsBackgroundKeepAlive('pdd') == false`。

5. **P25/P11-d：失效不丢包裹**  
   某平台登录失效后同步：首页已有包裹仍在，不整页清空；设置页仅该平台「已失效」。  
   「同步响应异常，已保留旧数据」不得把卡片标成「已失效」（需含「登录」才标）。

6. **单平台重登**  
   淘宝失效、京东也失效时，只重登淘宝：京东的失效提示应仍在（`clearLastIssueFor`）。

## box 已覆盖（无需真机）

- `planKeepAliveOutcome` / `resolveBackgroundSkip` / `applyHeartbeatOutcome`
- `classifyMtopBody`、MockClient 下 sessionExpired↔networkError 互斥
- `JdHeartbeat.classifyResponse`
- `KeepAliveNotifier` 去重与发送失败不写标记
- `isPlatformShownExpired` 误判回归


## 本轮未改、记给 P23

- **SyncOptimizer** 仍用 `addedAt` 当「最近同步时间」参考（测试 P26 指出）。属同步速度/跳过逻辑，不挡 P24 登录持久；下轮量真机耗时再改。
