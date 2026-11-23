# 拼多多内置商城性能测量（2026-11-23）

## 实现与口径

商城是 Flutter `AppBar` + `WebViewWidget` 加载官方 H5，不是原生商品列表。首屏链路为创建 WebView → 注入 Cookie → `loadRequest` → 网络与 H5 渲染；滚动与图片解码主要在 Chromium，而非 Flutter 列表重建。

设备为 **V2612A / vivo PD2612、Android 16、Chromium WebView 138（7204.179）**；显示面板支持 144Hz，但应用被系统限制为 **60Hz**，测量期间未修改。固定首页、登录态，使用 CDP `Input.dispatchTouchEvent` 以同一坐标和 0.5 秒间隔交替滚动 35 秒。`requestAnimationFrame` 与 `PerformanceObserver(longtask)` 记录主线程阻塞；不把 H5 自己的离屏懒加载节点算作图片失败。原始数据在本目录 JSON。

## Before / after

| 指标 | 基线 | 优化后 | 采集条件 |
|---|---:|---:|---|
| Long task 次数 / 累计阻塞 | 14 / 853ms；14 / 874ms；同窗口 15 / 912ms | 3 / 207ms；2 / 135ms；0 / 0ms | 各 35 秒；after 中后两轮列表更长，结果只作辅助 |
| 相近 DOM 规模的 long task | 15 / 912ms（9153 个节点） | 3 / 207ms（9251 个节点） | 同一 30 分钟授权测量窗口，配对比较：**次数 -80%，阻塞 -77.3%** |
| rAF 间隔 >50ms | 3/2242（0.134%）、5/2253（0.222%）、7/2230（0.314%） | 2/2262（0.088%）、4/2230（0.179%）、5/2249（0.222%） | 中位数 0.178% → 0.179%，**没有总体慢帧率改善** |
| rAF p99 | 49.7ms、49.7ms、49.8ms | 33.3ms、33.3ms、49.8ms | after 第一组与相近 DOM 基线对应；不据此宣称所有场景稳定 |
| 禁用缓存同 WebView 导航 FCP | 516 / 608 / 480ms，中位 516ms | 608 / 580 / 708ms，中位 608ms | **不是应用进程冷启动**：`Network.setCacheDisabled(true)`，三次导航；after 中位 +92ms，**无首屏提升证据**，受网络与动态内容支配 |
| 视口内失败图 / 待加载图 | 0 / 0（长列表 35 秒）；首页 60 图全成功 | 三轮长列表均 0 / 0 | 累计 105 秒真实首页滚动；图片解码/缓存沿用 Chromium |
| 图片资源缓存命中 | 11/145（同窗口长列表） | 25/142（after 第一组） | `transferSize===0 && decodedBodySize>0`，只代表本次页面资源时序，**不能归因于新增缓存** |

### 首屏重复性复核（a0d52aa 之后）

本轮先复测，没有为 FCP 做代码优化。`560 / 596 / 556 / 548 / 540ms` 为同一 WebView 禁用缓存导航 5 次，**中位 556ms、极差 56ms**；随后 5 次为 `648 / 596 / 588 / 636 / 596ms`，中位 596ms、极差 60ms。加入混合内容修复后再测 5 次为 `632 / 528 / 584 / 580 / 544ms`，**中位 580ms、极差 104ms**，原始值见 `perf/pdd-mixed-content-after-fcp-five.json`。90ms 单次差值落在重复测量波动内，判定为噪声；未证实需要优化，因此不追求凑到 550ms。

另测真正的应用进程冷启动：上一轮通过 CDP `Network.clearBrowserCache` 清 WebView 缓存，`force-stop` 后启动并点击商城，**不清应用数据**。FCP 为 `676 / 600 / 680 / 612 / 772ms`，**中位 676ms、极差 172ms**，主文档均返回 200 且非磁盘缓存，见 `perf/pdd-process-cold-five.json`。只有这一组 after，没有 before 基线，不能宣称冷启动已优化或已恢复到某个阈值；它与上表的同 WebView 导航口径不能混用。

混合内容修复的滚动对照为 **4 次 / 273ms → 2 次 / 127ms、3 次 / 229ms**，长任务没有回退；第二轮 DOM 从 9405 增至 18048，故只作回归检查，不作严格性能配对。原始数据为 `perf/pdd-mixed-content-{before,after,after-2}-scroll.json`。

## 图片与跨页回归

首页三轮共 105 秒滚动后，视口内商品图均正常，失败 0；订单页历史商品图正常。个人中心 16 张视口内图片的「火车票」失败，已用 Release + CDP 定位为 **mixed content 阻断**，不是 404、403、清理脚本或懒加载问题。

失败请求为 `http://t00img.yangkeduo.com/goods/2019-11-20/d26747be4edc4904d22628b6fde261ba.png`：`Network.loadingFailed.blockedReason=mixed-content`，请求未获得 HTTP 响应，故状态码不适用、响应大小 0。`Referer` 为空，UA 为应用设置的 Chrome/126 Mobile；`complete=true`、`naturalWidth=0`，没有 `data-src`，显示/可见性正常且没有命中清理规则。资源的 HTTP/HTTPS 独立请求均为 200、image/png、1906 字节，排除服务端下线。

最小修复是在商城的 `AndroidWebViewController` 上设置 `MixedContentMode.compatibilityMode`，不使用 `alwaysAllow`，不改变登录态、Cookie 语义或订单抓取。修复后同一请求 **HTTP 200 image/png**，`loadingFinished.encodedDataLength=2456`，图片解码 **75×75**，火车图标恢复。脱敏请求数据见 `perf/pdd-train-mixed-content-network.json`，不含个人信息的证据截图见 `perf/pdd-train-mixed-content-evidence.png`；完整个人中心截图没有提交。

登录与数据：最终 Release 的个人中心可见用户头像与订单入口，首页保留「已完成 (13)」与三平台已绑定，未卸载、未清应用数据。这里只记录可见会话证据，不把本地「已绑定」等同于服务端会话有效性证明。

## 装机、恢复与限制（必须保留）

- **越界说明**：首次在协调者确认前安装了 profile，属于先装后问；首次 profile 安装记录为 17:52:31（设备 `lastUpdateTime`），首次 Release 恢复为 18:15:38。
- 获明确授权后，第二次优化版 profile 安装为 **18:24:58**，同一设备、同包名、覆盖安装、不卸载不清数据。为同窗口配对，18:30 左右覆盖原始基线 profile，18:32:58 覆盖优化版 profile；全部在约 10 分钟内完成。
- **18:34:37 恢复本分支 Release**，`run-as` 为 package not debuggable、CDP 转发列表为空、屏幕超时恢复原值 30000ms。应用数据与登录状态按上述可见记录核对未丢失。
- 本轮仅使用 Release。为采集 CDP 证据，19:00:17 覆盖安装临时开启 WebView 调试的基线测量包（开始 18:57:45），19:15:45 覆盖安装混合内容修复测量包（开始 19:10:19），19:33:10 恢复最终无调试 Release（开始 19:31:48）。安装窗口 18:57:45–19:33:10 共约 35 分钟；未安装 profile、未卸载或清数据。
- 最终 `run-as` 为 package not debuggable、CDP socket 与转发为空、屏幕超时保持 30000ms。19:34 核对个人中心头像、订单入口与恢复后的火车票图标；应用数据与本地「已完成 (13)」仍在。
- 单设备、60Hz、动态商品流，数据不能外推到其它机型、刷新率或网络。严格相近 DOM 配对只有一组（n=1）；其余 after 列表规模是基线的 1.7–2.5 倍，仅作辅助证据。早期 cold-start 测量发生跨页面时序污染（出现负耗时），原始文件已弃用，不纳入结论。本轮冷启动只有 after，无 before 配对，也没有把混合内容兼容模式作为首屏优化。
- 营销浮标文本与类名选择器仍依赖 PDD 页面。当前页面存在拼接文本的「在App打开」浮标，旧版也未能全部隐藏；本次兼容了拆分文本的隐藏语义，但没有在最终兼容补丁上重新采集性能。页面改版需要重新验证该清理行为，并避免用文本选择器处理业务数据。
- `MixedContentMode.compatibilityMode` 放行或拦截的内容类型由 Android/Chromium 实现决定，并可能随 WebView 版本改变。未来收紧策略时，火车票 HTTP 图标可能静默恢复为不可见且没有告警，需按本条 CDP 请求与 DOM 证据链重新复验。

## 验证

`flutter test`：**614 项全绿，无 skip**；`flutter analyze lib/ test/`：**No issues found**；`./tools/check_no_pii.sh` 通过。`flutter build apk --release` 通过；最终构建已移除临时 WebView 调试开关。

测量工具：在可调试 profile 且已转发 WebView CDP 后，执行 `python3 -I tools/pdd_web_perf.py scroll --seconds 35 --output <json>`。工具不读取或保存 Cookie、订单字段、商品正文；本轮只在临时测量包中开启 CDP，最终 Release 保持关闭。
