# 取件助手 (Pickup App)

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-3.6+-02569B?logo=flutter&logoColor=white" alt="Flutter" />
  <img src="https://img.shields.io/badge/Dart-3.6+-0175C2?logo=dart&logoColor=white" alt="Dart" />
  <img src="https://img.shields.io/badge/Android-10+-3DDC84?logo=android&logoColor=white" alt="Android" />
  <img src="https://img.shields.io/badge/Material%20Design-3-7B1FA2" alt="Material 3" />
  <img src="https://img.shields.io/badge/Release-v1.0.0-00B578" alt="Version 1.0.0" />
  <img src="https://img.shields.io/badge/License-GPLv3-blue" alt="License" />
</p>

一款现代化、高刷新率的中文在途快件追踪与待取包裹聚合管理 Android 应用。

聚合拼多多、京东、淘宝/天猫等多电商平台真实物流，结合截图 OCR，彻底解决包裹分散、双端登录互踢、取件码格式不一等日常取件痛点。

---

## 解决的核心痛点

1. **包裹散落多平台，来回切换繁琐**：日常购物分散在拼多多、京东、淘宝各处，查看在途包裹或找取件码需要逐个打开 App。
2. **拼多多双端登录单设备互踢**：拼多多服务端实行严格的单设备会话控制，第三方聚合读取往往导致手机官方 App 被踢下线。
3. **物流轨迹与取件信息简陋不全**：普通工具仅能抓取粗略的文字，缺乏完整的转运时间轴、准确的运单号/订单号、网点派送员电话及真实收货地址。
4. **即时订单与退款订单污染列表**：外卖闪送（如秒送、达达、餐饮）及退款取消的订单常常误入包裹列表，干扰判断。

---

## 核心功能特性

### 1. 多电商平台聚合与在途自动化同步
- **拼多多 (Pinduoduo)**：抓取在途及待取包裹，智能提取多多驿站/代收点取件码、真实商品图与物流节点。
- **京东商城 (JD)**：精准定位待收货购物订单，深度提取自营物流、便民柜自提码与在途配送状态；自动排除外卖、秒送、到家即时订单。
- **淘宝 / 天猫 (Taobao)**：通过 MTOP 与移动网页端凭据对接，聚合菜鸟驿站取件码及在途商品图文。
- **智能承运商识别**：根据快递运单号前缀规律（如 `JT` 极兔速递、`SF` 顺丰速运、`YT` 圆通速递、`ST` 申通快递、`JD` 京东快递、`ZTO` 中通快递等）自动补全承运商，杜绝显示为“其他”。

### 2. 拼多多内置移动端商城（免 App 防互踢）
- **完整的移动端容器**：封装原生优化的 H5 单页容器，支持商品浏览、搜索、加入购物车、下单与支付。
- **打通第三方支付**：拦截外部 App 导流唤起的同时，放行微信支付（`weixin://`）与支付宝（`alipays://`），实现在应用内一站式完成购物。
- **彻底杜绝双端互踢**：应用本身即作为日常拼多多使用的主要窗口，无需在手机上保留或切换至官方 App，从根本上避开单设备互踢限制。
- **纯净浏览体验**：内置动态 DOM 与全局 CSS 清理脚本，自动实时剔除「在App打开 〉」浮标、顶部/底部诱导下载横幅。
- **无感登录态保持与秒级退出**：自动持久化会话 Cookie；左侧配置专用 `✕` 关闭按钮，无论浏览多深均可一键秒回应用首页；进入订单中心时自动静默调度数据同步。

### 3. 官方级深度物流时间轴（二级抽屉）
- **视觉风格深度复刻**：
  - **承运商与运单号栏**：品牌绿色高亮显示，附带一键复制运单号及触觉反馈。
  - **订单编号与收货信息卡**：清晰展示真实订单编号（带独立复制按钮），以及真实收货地址（支持多行长地址展开/收起）。
  - **翠绿色动态在途节点**：最新轨迹节点采用翠绿色脉冲双环与高亮文字，醒目标记当前最新位置。
  - **完整历史转运流**：灰色圆点连线串联发货、打包、各转运中心与分拨交付节点。
  - **电话号码智能高亮呼叫**：自动匹配轨迹文案中的派送员手机号、网点座机与官方客服热线，高亮为蓝色超链接，点击一键唤起系统拨号盘拨打。

### 4. 现代化在途优先 UI (120Hz Fluid Design)
- **Hero 统计仪表盘**：主页顶部动态呈现“待取件”与“在途快件”总数，支持一键旋转动效触发全平台同步。
- **物理弹簧卡片 (Spring Card)**：基于物理模拟的触摸反馈，支持 120Hz 原生流畅手势与阶梯式进场动画。
- **待取件凭证徽章 (HeroPickupBadge)**：包裹到达自提点后，以显眼的大号提货码呈现，一目了然。
- **二级完成面板 (Completed Packages Sheet)**：已签收完成的历史订单自动归档至二级抽屉，保持主列表清爽聚焦。

### 5. 截图 OCR 兜底
- **Google ML Kit 截图 OCR**：支持截屏导入，通过专有文本清洗管道（噪声过滤、正则提取、置信度裁定）离线识别取件码与快递信息。
- **去重与生命周期推进**：以取件码与运单特征为核心，单向推进包裹生命周期（在途 → 派送中 → 到达待取 → 已提货），防止重复入库。

---

## 系统架构

项目遵循严格的**四层单向依赖架构**，保障模块解耦与跨平台复用：

```text
       ┌────────┐
       │   ui/  │ ── 渲染层：Flutter 页面、组件、Riverpod Providers、Theme
       └───┬────┘
           │
           ├───────────────┐
           ▼               ▼
       ┌────────┐      ┌───────────┐
       │  app/  │      │ platform/ │ ── 适配层：Hive 存储、连接器、通知服务、ML Kit
       └───┬────┘      └─────┬─────┘
           │                 │
           └────────┬────────┘
                    ▼
               ┌────────┐
               │ core/  │ ── 纯 Dart 核心逻辑（冻结层）：不可变模型、状态机、解析器
               └────────┘
```

> **架构约束**：`lib/core/` 必须保持为纯 Dart 代码，严禁导入 Flutter SDK、平台驱动或状态管理包，确保核心计算与业务逻辑具备 100% 的可测试性。

### 双模型序列化设计
- **`Package`** (`lib/core/models/package.dart`)：纯 Dart 不可变领域模型，包含完整商品元数据、承运商、取件码、序列化轨迹 JSON 等。
- **`HivePackage`** (`lib/platform/storage/hive_package.dart`)：适配本地 NoSQL 存储的 TypeAdapter 包装器，支持平滑迁移与向后兼容。

---

## 快速上手

### 环境要求
- **Flutter SDK**：`^3.6.0`（推荐使用 Flutter 3.29+ / Dart 3.7+）
- **Android SDK**：Min SDK 24 (Android 7.0+)，Target SDK 34 (Android 14) / 兼容 Android 15 & 16
- **JDK**：Java 17
- **开发设备**：建议使用物理 Android 设备测试 Impeller Vulkan 渲染与平台 CookieManager

### 获取源码与依赖

```bash
# 克隆仓库
git clone git@github.com:Granter-z/pickup_app.git
cd pickup_app

# 获取 Flutter 依赖
flutter pub get
```

### 编译与运行

```bash
# 启动开发调试（支持物理机与模拟器）
flutter run

# 代码规范与静态检查
flutter analyze lib/

# 运行全量单元测试与回归套件
flutter test

# 构建正式 Release APK
flutter build apk --release
```

编译产物位于：`build/app/outputs/flutter-apk/app-release.apk`。

---

## 项目目录结构

```text
lib/
├── core/                        # 纯 Dart 业务逻辑层（冻结）
│   ├── models/                  # Package、OrderMeta、PickupInfo 等领域模型
│   ├── parser/                  # 快递公司、单号、取件码文本提取器与词典
│   └── utils/                   # 文本归一化与清洗工具
├── platform/                    # 基础设施与平台适配层
│   ├── connectors/              # 电商连接器（拼多多、京东、淘宝、管理器）
│   ├── notification/            # 本地通知提醒（到达提醒与 24 小时取件提醒）
│   ├── ocr/                     # Google ML Kit 离线文本识别
│   └── storage/                 # Hive 存储与 Cookie/凭据持久化
└── ui/                          # 视图与交互表现层
    ├── components/              # 弹簧卡片、平台徽章、Hero取件码等通用组件
    ├── providers/               # Riverpod 状态提供者（PackageListNotifier 等）
    └── screens/
        ├── home/                # 在途优先主页、仪表盘、物流轨迹抽屉
        ├── pdd/                 # 拼多多内置移动端商城容器（PddWebScreen）
        ├── login/               # 平台账号授权与 Cookie 捕获页面
        └── settings/            # 平台绑定管理与系统权限配置
```

---

## 版本历史

### v1.0.0 (2026-10-04)
- **多平台数据聚合**：正式支持拼多多、京东、淘宝/天猫真实订单聚合同步。
- **拼多多内置移动端**：封装独立 H5 商城，支持浏览下单、微信/支付宝支付，智能拦截营销导流浮标，彻底避免单设备登录互踢。
- **官方级二级物流抽屉**：复刻拼多多物流详情页，支持运单号/订单号复制、收货地址折叠、在途绿点高亮、客服电话一键呼叫。
- **承运商智能识别**：新增基于运单号前缀的承运商智能推断（支持极兔、顺丰、圆通、京东等）。
- **交互与动效升级**：主页 120Hz 弹簧卡片、Hero 概览仪表盘与已完成归档抽屉。

---

## 许可证

本项目基于 [GNU General Public License v3.0 (GPL-3.0)](LICENSE) 协议开源。
