# 账号持久化：进程外保活（WorkManager）

> 日期：2026-10-07（更新：2026-11-26）
> 状态：代码完成，测试通过；前后台续期与失效闭环已接入

## 问题

此前的保活与后台同步全部依赖 Dart 内存 `Timer`（`KeepAliveService`、`BackgroundSyncService`）。
App 进程被用户划掉或系统回收后定时器消失，Cookie 到期即失效——这是「账号无法长期保持登录」的根本原因。

## 方案总览

| 层 | 组件 | 职责 |
|---|---|---|
| 存储 | `secure_store` 本地插件 | Keystore AES-GCM 加解密，注册为独立 FlutterPlugin，前后台 FlutterEngine 都能加载 |
| 续期 | `TaobaoTokenRefresher` | 纯 Dart：轻量 mtop 请求轮换 `_m_h5_tk` 令牌并判定登录态 |
| 心跳 | `TaobaoHeartbeat`（HTTP 版） | 替换原 WebView 方案，可后台运行；京东心跳本为 HTTP，支持 `wqs` + `trade` 双探 |
| 调度 | `Workmanager` periodic | 每 4 小时（`keep_alive_periodic_v2`，CONNECTIVITY 约束，`ExistingPeriodicWorkPolicy.keep`），App 被杀后仍由系统唤醒 |
| 入口 | `callbackDispatcher` | 后台 isolate：以只读模式初始化凭据存储，按 JSON 桥接读取配置并写回结果，不写 Hive |

分平台后台续期能力用一张 registry 表达（`_backgroundHeartbeats`，与 `kBackgroundKeepAlivePlatformIds` 对齐）：
淘宝、京东可后台续期；拼多多心跳依赖 WebView，后台无 Activity 不可运行，不在表内。

## 关键改动

1. **`plugins/secure_store/`（本地插件）**：加密逻辑从 `MainActivity` 抽出。
   WorkManager 后台 isolate 创建的是裸 `FlutterEngine`，不走 `MainActivity.configureFlutterEngine`，
   只有注册为 pubspec 声明的插件（经 `GeneratedPluginRegistrant` 自动注册）才能在后台解密 Cookie。
   channel 名保持 `com.example.pickup_app/secure_store` 不变。
2. **`lib/platform/keep_alive/taobao_token_refresher.dart`**：`MtopRefreshResult`
   用互斥结局表达（轮换成功 / `sessionExpired` / `networkError`），令牌落盘由调用方处理。
3. **`lib/platform/keep_alive/platform_heartbeat.dart`**：`TaobaoHeartbeat` 为纯 HTTP，
   前台内部完成令牌落盘（`updateCookieTokenFields`，仅更新令牌字段，**不刷新 `updated_at` 年龄锚点、不误清 `expired_at`**；后台 worker 置 `persistTokenRotation: false`，避免跨 isolate 写 Hive），返回 `isAuthFailure` 供调度层落盘失效标记。
4. **`lib/platform/storage/platform_auth_store.dart` 与 `keep_alive_store.dart`**：
   - **保活/同步续期**：连接器同步成功回写完整 Cookie 时调用 `refreshCookiesInPlace`，仅就地刷新加密 Cookie 与内存缓存，**不刷新 `updated_at` 年龄锚点、不误清 `expired_at`**；
   - **用户重新登录 `saveCookies` 与解绑 `unbind`**：自动清理旧失效标记及 `KeepAliveStore` 的保活状态（`setNext(p, null)`、`setFailureCount(p, 0)`、`setLastNotifiedAt(p, null)`），并调用 `clearWorkerNotifiedAt` / `clearWorkerGate` 清理后台 worker 的通知与闸门 JSON 文件；
   - **`KeepAliveStore` 进程内静态共享缓存**：所有实例共享同一份静态内存缓存，同步 getter 不必等待 box 打开即可返回一致状态。
5. **`lib/platform/keep_alive/keep_alive_worker.dart`**：`@pragma('vm:entry-point')` 顶层
   `callbackDispatcher`；后台 isolate 内 `Hive.initFlutter()` + `PlatformAuthStore.initialize(readOnly: true)`，通过 `keep_alive_worker_bridge.dart` 读写 JSON 通道（`keep_alive_worker_config.json` / `keep_alive_worker_result_*.json` / `keep_alive_worker_notify.json` / `keep_alive_worker_gate.json`），不再打开或写入 `keep_alive_state` box。
6. **`lib/main.dart`**：`Workmanager().initialize` + `registerPeriodicTask`（`keep_alive_periodic_v2`，4 小时，CONNECTIVITY，`ExistingPeriodicWorkPolicy.keep`）。

失效闭环：后台/前台判定失效 → `setExpired(platform, true)` → 本地通知提醒（点击直达设置页）+ 设置页「已失效 / 重新授权」。

## 验证状态

已验证（真机 V2307A，Android 16，release 构建）：
- App 前台正常启动，`Workmanager` 初始化与 `registerPeriodicTask` 无崩溃；`dumpsys jobscheduler` 确认 periodic 任务已注册（6 小时间隔 + CONNECTIVITY 约束）。
- 前台心跳：京东 Cookie 已失效时，纯 HTTP 心跳返回 `login required in response body`，`isAuthFailure` 判定后落盘失效标记，设置页显示「已失效，请点击重新授权」。
- **后台 isolate 全链路**（保活状态页「测试后台续期任务」注册 one-off 任务触发）：
  ```
  [KeepAliveWorker] Skip taobao: not bound
  [KeepAliveWorker] Refresh jd...
  [KeepAlive] JD heartbeat starting...
  [KeepAlive] JD heartbeat failed: login required in response body
  [KeepAliveWorker] jd login expired
  ```
  证明后台 isolate 内 `Hive.initFlutter` → `PlatformAuthStore.initialize()`（Keystore 解密）→
  HTTP 心跳 → 失效落盘整条链路可用；后台与前台判定结果一致。
- **正向续期路径**（release，淘宝有效 Cookie）：`Refresh taobao → Taobao heartbeat success → taobao refreshed`，
  后台解密、mtop 请求、清除失效标记全链路成功；同轮京东失效判定依旧正确，正负两路互证。
- 令牌轮换仅在服务端判定令牌过期时触发（mtop 机制：仅此时经 Set-Cookie 下发新令牌），
  新登录后首几次心跳不轮换属预期；令牌过期后由后续心跳自动轮换并落盘（日志 `Taobao mtop token rotated`）。

## 调试方法

- 强制运行 periodic 任务对未到期的 work 无效（WorkManager 只执行到期的 work，`cmd jobscheduler run -f` 会被秒退）。
- 验证后台链路请用保活状态页的「测试后台续期任务」：注册 3 秒后触发的 one-off 任务（taskName `keepAliveTask`），logcat 过滤 `KeepAliveWorker`。

## 已知限制

- 拼多多无法进程外续期，只能依赖用户打开 App。前台心跳现已委托给 `PddH5Connector.keepAliveProbe()`
  （复用其常驻 WebView，不再自建控制器）；后台**不尝试**拼多多：WebView 需要 platform view 与主线程，
  裸 FlutterEngine 没有 Activity，且其 proxy 接口要求 `anti_content` 动态签名，纯 HTTP 会被风控返回 424。
- WorkManager 周期任务最小间隔 15 分钟且由系统批量调度，不保证精确时刻；对「每天数次的续期」场景足够。
- 同一 Hive box 的前台/后台并发写风险已通过写入隔离彻底消除：后台 worker 以 `PlatformAuthStore.initialize(readOnly: true)` 只读凭据 box、**不再打开或写入任何 Hive box**（也不写 `keep_alive_state`），所有结果/闸门/去重状态均经 `keep_alive_worker_bridge.dart` 的原子 JSON 通道交由主 isolate 合并入库，保活历史亦仅由主 isolate 写入。详见 `keep-alive-implementation.md` 的「持久化」一节。
- 失效后的本地通知提醒**已实现**：`KeepAliveNotifier` 统一收口（独立渠道 `keep_alive_channel`，
  固定 id 槽位，去重标记仅在发送成功后落盘，因此后台发送失败时前台会补发）。
  详见 `keep-alive-implementation.md` 的「失效提醒闭环」一节。
