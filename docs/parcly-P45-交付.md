# P45 前端交付 / 待 CTO 与 QA 验收

> 当前以文末R3/+15为准；以下R1/+13、R2/+14保留为历史，不是当前候选。

更新时间：2026-11-08 01:30 Asia/Shanghai。

## 范围与基线

- 远端 main 开始/交付前均为 `c9b0128efb08c4b04b9bd7273d1b1fedcc17a813` / `1.0.0+12`，无漂移。
- 已完成 c/d 的初步实现与 e 自动化/候选构建；不代表 QA f 或产品 g 完成，不合入、不发布。
- 开发位置 `/workspace/parcly-p45-fe`，独立分支 `feat/p45-continuous-motion`；未切共享checkout、未操作注册用户电脑或真实数据。
- 运行代码提交 `3adf125acd127423daf56ced3cebc66ecfa08fa0`。后续交付文档提交只影响 Markdown；完整 PR head / URL 记入公司交付单与 Notion。
- SpringCard 先采 q 与有符号 q/s 再 stop，原生 onTap 唯一业务入口；无拖拽或新取件手势。
- 原生 SliverList + 私有 ID entry，重排更新最新内容，退出重入复用controller/key/卡片；退出立即禁pointer/semantics/focus及generation动作门禁。复制badge增默认enabled，异步确认捕获旧代动作，防已退出重入后的旧确认提交。
- Reduce Motion 中途即终态，关闭不重播；首屏无交错。共享 Motion / StaggeredEntrance 未改。
- 未改业务、连接器、鉴权、Hive、登录、同步、排序规则或依赖清单（pubspec只涨版本）。

## SDK 与重要复现限制

现有 box SDK（未升级）Flutter **3.47.6** / framework **5fc346839b**，Dart **3.13.5**；Java17，Android SDK build-tools36。完整输出 `sdk-version.txt`、`java-version.txt`。

`flutter pub get --enforce-lockfile` **exit65**：仓库lock与已装SDK的4个pin不兼容。为本地验证运行标准 `flutter pub get`（exit0），**仅本地**解析 matcher .12.19→.12.20、meta1.17→1.19、test_api .7.10→.7.12、vector_math2.2→2.4.4。原lock已恢复，PR **没有依赖/SDK升级**；不能将本轮结果描述为原始lock完全可重现。`original.pubspec.lock`、`validation.pubspec.lock`、`sdk-lock-diff.patch` 与初次失败日志均保留。CTO/QA须确认构建SDK与pin策略后再合入。

Flutter构建工具自动在本地gradle.properties写2个兼容flag，构建后已恢复，PR无Gradle改动；未升级AGP/Gradle/Kotlin，构建存在其将来支持到期警告。

## 真实验证结果

原始日志目录 **`/workspace/p45-evidence/`**，每份日志首行原命令、末行exit；`results.jsonl`汇总全部尝试，包括失败与修正，未隐藏失败。

| 原命令 | exit / 实际结果 | 原日志 |
|---|---|---|
| `dart format --output=none --set-exit-if-changed` + 4个改动组件与3个测试文件 | 0，7文件无待格式化 | format-check.log |
| `flutter analyze --no-pub` | 1，134条（8warning/126info）；基线135条（8warning/127info），按文件+规则多重集比较**无新增** | candidate-analyze-final.log / baseline-analyze.log / diagnostic-delta.txt |
| `flutter test --no-pub --reporter expanded test/spring_card_test.dart test/animated_package_list_test.dart test/p45_card_integration_test.dart` | 0，**24通过**（8卡片+14列表+2集成） | components-final.log |
| `flutter test --no-pub --reporter expanded` + §8.3业务回归15个文件 | 0，**156通过** | related-regression.log（首行含完整文件参数） |
| `flutter test --no-pub --reporter expanded` | 0，**508通过**，无skip | full-tests-final.log |
| `bash tools/check_no_pii.sh` | 0 | pii-final.log |
| `flutter build apk --release --no-pub --target-platform android-arm64` | 0，候选versionCode13 | apk-build-final.log |
| `apksigner verify --print-certs` | 0，Android Debug签名 | apk-signature.log |

测试不是仅终态：40ms释放与100ms回弹再接管、1µs有限差分速度容差1e-3 q/s、瞬时位置容差1e-6；列表16/40/100ms采样；20次连续点击/20轮增删；同ID两轮退出重入/旧回调；按压中重排；退出复制/确认/旧语义/焦点门禁；Reduce Motion运行中切换；长列表离屏退出与offset；已完成卡点击、长按撤销及子撤销；360px/1.5倍字完整码列表与详情复制。触觉仅mock次数，不是真机体感。

全仓105个lib Dart（34 UI/71非UI）补跑目标组件检索，先前缺失12个非UI文件已包含且无新增目标组件调用点。`full-lib-audit.tsv`、`prior-missing-files.txt`、`calls.txt`。这证明文本调用点审计完整，不宣称逐个业务路径真机验收。

## 候选 APK

- `1.0.0+13`，检查全部24远端分支+tags/releases/open PR：当时最高12，13未占用；记录 remote-versions.json / remote-refs.txt / releases.txt / open-prs.json。
- `/workspace/p45-evidence/parcly-1.0.0+13-arm64-v8a-release.apk`
- SHA256 `4377b4f3e2b22ccfd8eed53486aecc19220827a92677eddd1c3480ba9fc60d37`
- package `com.example.pickup_app`；Android Debug签名；未安装、未上传Release。禁止为签名冲突卸装。

## 启动/查看

原生 Android：在有权限设备上由QA执行 `flutter run --no-pub -d <authorized-android-device>`，或核签名后授权覆盖安装候选；本轮未执行安装/重登/清数据。`flutter devices`在box只见Linux/Chrome，无Android设备。

尝试隔离fixture web-server（源码preview.dart在证据目录），虽编译并监听127.0.0.1:8795，仓库无web/index.html，HTTP根返回404。已停本轮自建进程；**无可用运行地址，未在浏览器查看**。不以服务启动代替可见UI验证。完整命令/结果见preview-server.log、preview-http.txt、preview-limitation.txt。

## 未测 / 已知阻塞

1. 真机录屏、读屏/键盘实际操作、触觉、系统Reduce Motion映射、后台返回、真实三平台会话/P43/P44与同步墙钟均**未测**。不访问用户电脑，不卸装/清Hive/清登录/要求重登。
2. 同设备同刷新率profile前后各3轮、FrameTiming UI/raster p95/慢帧、DevTools/OS无障碍均**未测**，不以单测或debug FPS替代；P45-f仍待QA。
3. **既有布局债**：320px/1.8倍字体，虚构到站卡顶栏右溢11px；候选及未改动基线都真实复现。原失败 `integration-tests.log` / `baseline-narrow-test.log`，基线复现测试保留在 `/workspace/parcly-p45-base/test/p45_card_integration_test.dart`；本轮不扩改布局。360px/1.5倍字测试通过不代表320px极端字号通过；交CTO/QA判断后续修复，不能认定全尺寸无障碍通过。
4. SDK/lock不一致、现有8warning/126info仍在；均非本轮全绿承诺。仅交初步PR审核，不授权合入或发布。

## Todo

- [x] c 卡片实现与采样测试
- [x] d ID呈现列表与生命周期/交互测试
- [x] e 自动化、PII、候选APK和交付证据
- [ ] e PR的CTO审核（本分支将提交PR，链接以公司交付单/Notion为准）
- [ ] f QA真机/录屏/profile与业务全回归
- [ ] g 产品/CTO收口


# R2 审核返修 / 最新候选 +14

> 2026-11-08 01:45 Asia/Shanghai。以下覆盖R1/+13的候选与SDK阻塞结论；R1保留仅供历史审计。待CTO再审/QA，未合入未发布未装机。

## 复现与修复

在隔离Flutter3.41.9、原lock下先执行审核探针：旧菜单→A退出40ms→同ID新A重入→点旧删除，fake.removed确实为['A']，1通过/1失败exit1，原日志 `/workspace/p45-r2-evidence/review-reproduce.log`。没有把审核断言直接当结论，也没有触碰真实数据。

修复仅presentation门禁：菜单打开时捕获当时的interactionAllowed/generation与interactive，用户点复制/删除前同时检查卡片context仍mounted和旧代门禁。失效时仅关闭用户已点选的菜单、不写clipboard、不调用remove；不会因退出而强关现有路由。正常代原业务仍可用。

新增6个菜单测试（复制/删除 × 正常/退出未重入/退出40ms后同ID重入），另保留零进度立即移除探针。已有异步确认旧代回归仍通过。按压码新增16/40/100ms字形绘制矩形、viewport/卡片边界及相对字号采样，不只断言文字存在。

## 精确SDK与原lock可复现性

- 修复运行源码：`7d6fec56ed52c586cda604d1a59152a8e76b4b59`，在全新 `/workspace/parcly-p45-r2-verify` 固定SHA干净worktree验证；基线另开 `/workspace/parcly-p45-r2-base` @ c9b0128。不是R1的3.47.6重解结果。
- SDK：`/workspace/p45-sdk/flutter-3.41.9`，官方Git tag3.41.9远程ls-remote核到 `00b0c91f06209d9e4a41f71b7a512d6eb3b9c694`，engine `42d3d75a56efe1a2e9902f52dc8006099c45d937`，Dart **3.11.5**；由该SDK自举下载专属Dart/engine cache，stamps匹配，不借用3.47.6的Dart cache。未切换共享SDK。
- 官方Linux archive manifest返回404，因此采用官方Git源码+该版自举；`sdk-source-archive.sha256`为本地git archive源码校验，不冒充官方tar签名/checksum。SDK版本/remote/tag/cache/Dart二进制hash/API证据均留档。
- project.metadata revision吻合；实际package_config与官方flutter_test四pin逐一核验：matcher0.12.19、meta1.17.0、test_api0.7.10、vector_math2.2.0。`sdk-lock-pins.json`含解析到隔离PUB_CACHE的实际路径；API已在同SDK组件/全量及APK实际编译。
- 原lock SHA256始终 `956981f554bb63318109639552c683a032bf3764583c70e0d6879e7f68bc7383`。候选/基线干净 `flutter pub get --enforce-lockfile` 均exit0；构建后hash再核一致。**本轮未普通pub get，未重解后恢复lock，未升级依赖**。
- 新增 `tools/check_p45_toolchain.py` 和 `docs/parcly-P45-工具链.md`：精确framework/engine/Dart、cache stamp、metadata、lockhash检查；正确SDK exit0，用共享3.47.6负向测试exit1，确实阻止错SDK。AndroidSDK/Gradle及项目PUB_CACHE也在/workspace隔离。

## 原命令与真实结果

证据根目录 **`/workspace/p45-r2-evidence/`**。每项run日志首行原命令、末行exit，results.jsonl保留失败/修正尝试。

| 命令 | 实际结果 | 日志 |
|---|---|---|
| `flutter pub get --enforce-lockfile` | 候选与基线exit0，原lock不变 | fixedhead-enforce.log / baseline-enforce.log |
| `python3 tools/check_p45_toolchain.py` | 正向exit0，错误SDK负向exit1（预期） | fixedhead-sdk-check.log / final-toolchain-check.log / negative-sdk-check.log |
| `dart format --output=none --set-exit-if-changed` +8个改动/相关Dart文件 | exit0 | format-check.log |
| `flutter test --no-pub --reporter expanded` +4组件测试文件 | exit0，**31通过** | component-tests.log |
| 同命令+既定15个业务回归文件 | exit0，**156通过** | related-regression.log，首行含完整参数 |
| `flutter test --no-pub --reporter expanded` | exit0，**515通过**，无skip | full-tests.log |
| `flutter analyze --no-pub` | 候选与同SDK基线均exit1、132条（8warning/124info），多重集无新增/无减少 | candidate-analyze.log / baseline-analyze.log / diagnostic-delta.txt |
| `bash tools/check_no_pii.sh` | exit0 | pii.log |
| `flutter build apk --release --no-pub --target-platform android-arm64` | exit0 | apk-build.log |
| `aapt dump badging` / `apksigner verify --print-certs` | exit0，versionCode14、arm64-v8a、Android Debug签名 | apk-badging.log / apk-signature.log |

按压采样360px/1.5倍字：未按字形高度约10.087逻辑px；16/40/100ms scale约.99860/.99335/.97969，字形矩形均在卡片和viewport内，保留≥97%原字号比例。**这不是绝对字号可读性通过**：既有FittedBox在此长码配置的绝对字形已约10px，真实辨读仍待QA；最初任意>20px断言失败也保留在fix-tests.log，后续改为明确的相对缩放/边界断言，而非隐藏该事实。

## 新候选与交接

- `1.0.0+14`，查询全部25远端分支及tags，最高13，14未占用；remote-versions.json / remote-refs.txt。不复用+13冒充新包。
- APK `/workspace/p45-r2-evidence/parcly-1.0.0+14-arm64-v8a-release.apk`
- SHA256 `d4a8047cc943c368eaee0c0e14421f441c3ae11f79f99f2b3d097a2ccce9bd59`
- 包名com.example.pickup_app，Android Debug签名。未安装、未发布、未访问用户电脑。签名冲突不得卸装清数据。
- 原生启动命令：用本节SDK+原lock，在获授权Android设备上由QA `flutter run --no-pub -d <authorized-device>`；本轮无设备权限，未执行。无可用网页运行地址，不需要父代理打开桌面完成当前自动化结果。
- 真机录屏、读屏/键盘实操、OS Reduce Motion、触觉、后台返回、真实三平台/P43/P44与同步墙钟、profile前后3轮/FrameTiming p95及慢帧仍**未测**。320px/1.8倍字既有11px顶栏溢出仍留债、不扩修。
- 只正常追加commit/push更新原PR #45，无force/amend/merge/Release。PR最新head与Notion留痕结果以公司交付单和delivery.json为准。

# R3 已完成菜单生命周期 P2 最小补丁 / 当前候选 +15

本节取代上文R2/+14为当前前端交付候选。P1-A与原SDK/lock阻塞保持关闭；QA-R2-C1是完整base已存在的P2，修复待CTO/QA复验，不宣称P45整体验收或发布通过。用户授权仅追加同PR #45，不合入、不发布、不装用户机。

## 独立复现与最小边界

- 已读公司技术审查214行起、base/r2-probe.log、QA supplement/closeout报告及实际探针。自行在完整base c9b0128和原R2代码各重跑删除exit/reenter两条（0PASS/2FAIL、exit1），及旧撤销exit/reenter/程序化移除下层route三条（0PASS/3FAIL、exit1），均disposed-ref；见`base-delete-reproduce.log`、`reproduce-r2.log`、`base-undo-reproduce.log`、`r2-undo-reproduce.log`。这是异常证据，不是误删/进程崩溃证据。程序化Navigator.removeRoute边界不描述成普通用户穿透模态操作。
- 唯一运行时代码更改为`completed_packages_sheet.dart`：原卡局部会话在显示菜单前同步监听原packageListProvider，复用既有status.isCompleted呈现资格；离开完成集合即永久失效，捕捉无中间pump的退出重入。同ID仅内容更新不失效；原卡销毁/ID换绑、原route或菜单退场使会话作废并释放监听；同ID重入不复权。
- 提交先核会话、原owner及菜单route有效性，再从存活菜单Consumer的ref读原notifier。失效仅关自己仍current的菜单，不读ref、不提交删除/恢复、不发成功提示；不自动强关route，不误pop上层新route。不是仅加mounted，也未在打开时预捕获notifier绕过门禁。
- 正常删除/撤销仍调用原按ID方法，详情、子按钮、触觉与文案保留；仅将原卡改为局部State owner。未改数据层/业务规则/取件撤销轨迹；core/platform/providers/login/plugins/共享StaggeredEntrance对main差异0。SpringCard和首页门禁本轮未改。

## 真实验证（隔离SDK + 原lock）

源码/构建固定SHA `4ded7bf917ff72b7e6af1961222a1cc84825cbec`，全新干净worktree `/workspace/parcly-p45-r3-final-verify`；后续提交仅交付文档。Flutter3.41.9 / revision `00b0c91f06209d9e4a41f71b7a512d6eb3b9c694`，engine `42d3d75a56efe1a2e9902f52dc8006099c45d937`，Dart3.11.5。官方Git remote/tag再次核验，专属完整cache，未切共享SDK。原lock前后SHA256 `956981f554bb63318109639552c683a032bf3764583c70e0d6879e7f68bc7383` 不变；actual-lock-pins.json记录原四pin真实解析目录。未普通pub get、未临时重解后恢复lock、未升级依赖。

|检查/原命令（完整参数见results.jsonl）|结果|原始日志（证据根下）|
|---|---|---|
|flutter pub get --offline --enforce-lockfile（全新候选/基线）|各exit0|fixedhead-enforce-final.log / baseline-enforce.log|
|python3 tools/check_p45_toolchain.py；flutter --version --machine；dart --version|exit0|toolchain-final.log / sdk-final.log / dart-final.log|
|dart format --output=none --set-exit-if-changed（10 Dart文件）|exit0，0改变|format-check-final.log|
|flutter test --no-pub --reporter expanded（6组件文件）|48 PASS，exit0|component-tests-final.log|
|flutter test --no-pub --reporter expanded（原15关联文件+新增会话文件）|172 PASS，exit0|related-regression-final.log|
|flutter test --no-pub --reporter expanded（全量）|531 PASS，无skip，exit0|full-tests-final.log|
|flutter analyze --no-pub（候选与main基线）|各exit1、各132（8warning/124info），无新增/移除|candidate-analyze-final.log / baseline-analyze.log / diagnostic-delta.json|
|bash tools/check_no_pii.sh|exit0|pii-final.log|
|flutter build apk --release --no-pub --target-platform android-arm64|exit0|apk-build-final.log|
|aapt dump badging；apksigner verify --print-certs|各exit0，versionCode15，arm64-v8a，Android Debug签名|apk-badging-final.log / apk-signature-final.log|

新增16项真实菜单会话测试使用原provider方法，仅初态注入和提交次数观察：删除/撤销×正常、内容更新、退出、重入、无中间pump重入、程序化移除下层route、行身份换绑；加重复关开5轮/旧闭包拒提交与不误pop其他route。断言失效前后状态与提交计数完全不变、无成功提示，不仅是不抛异常。原共享组件测试所有动作/触觉断言保留，仅把相互矛盾的完成集合override与空source fixture改成实际source初态。原QA补充6项及closeout7项另存探针复跑，不与531累加、不把fixture同步称真实平台同步；原轨迹专项只做既有回归，不改业务。

保留失败尝试：session-tests-first/second为测试import错误；third共用ID碰到真实内存blacklist（改用每测唯一虚构ID，未清任何真实数据/blacklist）。初固定SHA组件47PASS/1FAIL因旧integration夹具完成provider有包裹但source空；只修fixture，不削弱断言，最终48PASS。这些失败日志不覆盖。

## APK、启动与证据

- 候选`1.0.0+15`，25远端分支审计时15未占用，审计`remote-versions.json`；未上传Release/安装。package `com.example.pickup_app`，仅arm64-v8a。
- APK `/workspace/p45-r3-evidence/parcly-1.0.0+15-arm64-v8a-release.apk`
- SHA256 `5447120ab9852784c6d65967ab95c4d542d4378f60e3b98fcae05bdea2ccda38`；原始`apk-hash.log`。Android Debug签名证书SHA256 `92766ddf22ed64c7b604cb40a35d7f5f4c8b5a6ff954656c0e6f3081ae776d93`，不是发布签名。
- 证据根`/workspace/p45-r3-evidence/`，`results.jsonl`记录全部原命令/退出码；`validation-context.json`记录cwd/源码SHA/SDK与Android/Gradle环境，`validate-final.py`可重跑本轮门禁。SDK详见`docs/parcly-P45-工具链.md`。
- 本地复核：按工具链文档配置环境后运行`flutter pub get --offline --enforce-lockfile`、`flutter test --no-pub test/p45_completed_menu_session_test.dart`；只需box、不触真实数据。无可用网页地址，本轮未打开浏览器；原生体验需QA另获设备/安装权限后按既有交付说明执行，本轮不安装、不要求重登。

## 明确保留的未测/阻塞

真机、录屏、profile/FrameTiming前后各3轮、OS Reduce Motion/读屏键盘实际操作、真实剪贴板/通知/触觉、后台返回、真实三平台会话/P43/P44/网络同步墙钟、真人完整码辨读均未测。约10px长码字形真人辨读风险、320px/1.8倍字既有11px顶栏溢出仍保留；按压几何和单测不替代。无用户电脑/真实数据操作、卸装、清Hive、清登录或外发同事消息。待父代理转交CTO/QA复验，不替审核人接受P2风险。
