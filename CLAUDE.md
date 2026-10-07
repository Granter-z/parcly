# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

现代化中文快递包裹追踪与聚合管理 Android 应用，使用 Flutter 构建。聚合拼多多、京东、淘宝等多电商平台真实物流，结合在途优先 UI 与官方级物流时间轴，解决包裹分散、双端登录互踢、取件码格式不一等痛点。

- **语言**: Dart 3.6+, Flutter 3.6+
- **平台**: Android (Min SDK 24, Target SDK 34)
- **状态管理**: Riverpod
- **存储**: Hive (NoSQL)
- **网络**: http + webview_flutter (电商平台容器与 Cookie 捕获)

## Common Commands

```bash
# 开发运行（支持物理机与模拟器）
flutter run

# 代码静态检查
flutter analyze lib/

# 运行测试套件
flutter test

# Hive TypeAdapter 代码生成（修改存储模型后）
flutter pub run build_runner build --delete-conflicting-outputs

# 构建 Release APK
flutter build apk --release
```

生产物位于 `build/app/outputs/flutter-apk/app-release.apk`。

## Architecture: Strict Four-Layer Unidirectional Dependency

项目严格遵循**四层单向依赖架构**，保障模块解耦与跨平台复用：

```
       ┌────────┐
       │   ui/  │  渲染层：Flutter 页面、Riverpod Providers、Theme、组件
       └───┬────┘
           │
           ├───────────────┐
           ▼               ▼
       ┌────────┐      ┌───────────┐
       │  app/  │      │ platform/ │  适配层：Hive 存储、电商连接器、通知、WebView
       └───┬────┘      └─────┬─────┘
           │                 │
           └────────┬────────┘
                    ▼
               ┌────────┐
               │ core/  │  纯 Dart 核心逻辑（冻结层）：不可变模型、状态机、解析器
               └────────┘
```

### **CRITICAL: `lib/core/` Purity Constraint**

`lib/core/` 必须保持为**纯 Dart 代码**：
- ❌ 严禁导入 Flutter SDK (`package:flutter/`)
- ❌ 严禁导入平台驱动 (Hive, http, webview)
- ❌ 严禁导入状态管理 (Riverpod, Provider)
- ✅ 只允许纯 Dart 依赖 (`dart:core`, `dart:convert`, `package:equatable`)

**目的**: 核心计算与业务逻辑具备 100% 可测试性，独立于渲染与平台。

### Key Layers

#### 1. `lib/core/` — Pure Dart Business Logic

**子模块**:
- `models/`: 不可变领域模型 (`Package`, `PackageStatus`, `CourierType`, `OrderMeta`, `PickupInfo`, `TrackingTrace`)
- `engine/`: 核心状态机与推断引擎
  - `package_identity.dart`: 包裹身份判定、打码单号匹配、合并规则（P11-b: 淘宝打码单号与菜鸟完整单号合并逻辑）
  - `logistics_status_engine.dart`: 基于轨迹时间流推导 `PackageStatus`、物流稳定性与同步间隔
  - `timeline_merge.dart`: 多源轨迹时间线合并与去重
  - `hero_card_engine.dart`: 包裹卡片显示决策（Hero 取件码徽章、紧急度、颜色）
- `parser/`: 文本提取器与词典
  - `extractors.dart`: 快递公司、运单号前缀、取件码、状态提取
  - `courier_dictionary.dart`: 承运商别名映射（极兔 JT, 顺丰 SF, 圆通 YT 等）
  - `regex_patterns.dart`: 运单号、手机号正则
- `sanitizer/`: 文本归一化与清洗
- `debug/`: 调试追踪与性能度量（不污染生产代码）

**不可变模型设计**:
```dart
class Package {
  final String id;             // 包裹唯一标识 (PDD_<订单号>, JD_<订单号>, TB_<订单号>, CN_<运单号>)
  final String trackingNumber; // 运单号（可能为打码单号如 YT12*******5678）
  final CourierType courier;
  final PackageStatus status;
  final String? pickupCode;    // 取件码
  final String? stationName;   // 自提点/驿站名
  final String? goodsName;
  final String? goodsImageUrl;
  final String? rawTimelineJson; // 序列化的物流轨迹 JSON
  final DateTime? pickedUpAt;  // 用户手动标记已取的时间（同步从不清空此字段）
  // ... 使用 copyWith() 实现不可变更新
}
```

#### 2. `lib/platform/` — Infrastructure & Platform Adapters

**子模块**:
- `connectors/`: 电商平台数据连接器
  - `platform_connector.dart`: 抽象接口 (`PlatformConnector`)
  - `pdd_connector.dart`: 拼多多 (支持内置 H5 商城、防互踢)
  - `jd_connector.dart`: 京东 (过滤外卖闪送订单)
  - `taobao_connector.dart`: 淘宝/天猫 (MTOP API + 菜鸟驿站)
  - `connector_manager.dart`: 多平台同步调度器
  - `taobao_sync_rules.dart`: 淘宝同步策略（打码单号合并、已签收订单跳过请求）
  - `*_trace_parser.dart`: 各平台物流轨迹 JSON 解析器
- `storage/`: 持久化层
  - `hive_package.dart`: Hive 序列化包装器 (`HivePackage` ↔ `Package`)
  - `hive_adapters.dart`: Hive TypeAdapter 注册
  - `platform_auth_store.dart`: Cookie 与凭据持久化
- `notification/`: 本地推送通知

**关键设计**:
- 每个 `PlatformConnector` 通过 `Stream<Package> streamSync()` 流式产出包裹数据
- `taobao_connector.dart` 包含打码单号补全与菜鸟优先级逻辑（P11-b 后续）

#### 3. `lib/ui/` — Presentation Layer

**子模块**:
- `providers/`: Riverpod 状态提供者
  - `package_provider.dart`: `PackageListNotifier` (包裹列表状态管理、合并逻辑、Hive 持久化)
- `screens/`:
  - `home/`: 在途优先主页、Hero 仪表盘、物流时间轴抽屉 (`tracking_timeline_sheet.dart`)
  - `pdd/`: 拼多多内置移动端商城容器 (`PddWebScreen`)
  - `login/`: 平台账号授权与 Cookie 捕获
  - `settings/`: 平台绑定管理
- `components/`: 通用组件（弹簧卡片、平台徽章、Hero 取件码徽章）

**状态管理模式**:
- `PackageListNotifier` 管理全局包裹列表，负责：
  - 从 Hive 加载与持久化
  - 合并同步数据（调用 `package_identity.dart` 判定同一包裹）
  - 生命周期推进（`pendingShipment → transit → delivering → arrived → pickedUp → archived`）
  - 清洗存量脏数据（外卖订单、OCR 幽灵数据、拼多多广告污染）

## Critical Business Logic

### 1. Package Identity & Merging (P11-b)

**文件**: `lib/core/engine/package_identity.dart`

**核心规则**:
- **淘宝打码单号与菜鸟完整单号合并**: 淘宝物流详情页运单号打码（如 `YT12*******5678`），菜鸟驿站给完整单号。打码单号露出位数 ≥6 位、快递公司相同、非不同订单号时合并，ID 保留 `TB_<订单号>`。
- **旧 ID 迁移**: 旧版本存下的 `TB_<打码运单号>` 记录，同步时换成 `TB_<订单号>`，用户状态随记录迁移。
- **已取状态保护**: `pickedUpAt != null` 表示用户在 App 里手动点过「已取」，同步从不清空此字段（同步唯一会写它的是拒收态）。

**关键函数**:
```dart
bool maskedTrackingMatches(String masked, String full)  // 打码单号与完整单号是否对得上
int findUniqueMaskedMatch(List<Package> local, Package incoming)  // 查找唯一打码匹配
bool isLegacyMaskedTaobaoId(String id)  // 识别旧 TB_<打码运单号> ID
```

### 2. Taobao Sync Strategy

**文件**: `lib/platform/connectors/taobao_sync_rules.dart`

**策略**:
- **已签收订单跳过详情请求**: 本地已有、已签收（`pickedUp` 或 `archived`）、轨迹不为空 → 跳过 MTOP 物流详情请求（降低 API 调用量）
- **菜鸟优先级**: 淘宝详情判为已签收，但菜鸟驿站列表仍挂着这件（打码单号恰好匹配）且有取件码 → 改回待取件并带上菜鸟的取件码与完整单号（驿站代签 ≠ 用户取件）

### 3. Logistics Status Derivation

**文件**: `lib/core/engine/logistics_status_engine.dart`

基于时间排序的轨迹节点流推导 `PackageStatus`，区分主状态与异常 Overlay，输出物流稳定性等级与推荐同步间隔。

**状态优先级**（只能前进）:
```
pendingShipment → transit → delivering → arrived → pickedUp → archived
                                                              ↓
                                                          rejected (异常终结态)
```

### 4. Image URL Normalization (P11-b 后续)

**根因**: 淘宝商品图 URL 为协议相对格式 (`//img.alicdn.com/...`)，缺 `https:` 前缀，`Image.network` 加载失败。

**修复位置**:
- `taobao_connector.dart`: 源头补 `https:` 前缀
- `modern_package_card.dart` / `tracking_timeline_sheet.dart`: 渲染兜底，对历史 `//` 开头 URL 补 scheme

## Testing

**测试文件结构**:
```
test/
├── package_identity_test.dart          # 包裹身份判定、打码单号匹配
├── package_merge_sync_test.dart        # 同步合并逻辑（Hive + PackageListNotifier）
├── taobao_sync_rules_test.dart         # 淘宝同步策略
├── pickup_display_rules_test.dart      # Hero 取件码显示规则
├── timeline_view_test.dart             # 物流时间线视图
├── trace_time_test.dart                # 轨迹时间解析
└── legacy_regression_test.dart         # 回归测试
```

**运行特定测试**:
```bash
flutter test test/package_identity_test.dart
flutter test test/taobao_sync_rules_test.dart
```

## Development Workflow

### When Adding/Modifying E-commerce Connectors

1. **解析逻辑放 `platform/connectors/`**: HTTP 调用、JSON 解析、Cookie 管理
2. **核心判定放 `core/`**: 状态推导、身份判定、合并规则（保持纯 Dart）
3. **更新 `package_identity.dart`**: 如涉及新的包裹 ID 格式或合并规则
4. **添加测试**: 在 `test/` 下覆盖新逻辑

### When Modifying Hive Models

1. 修改 `lib/platform/storage/hive_package.dart` 或 `hive_adapters.dart`
2. 运行代码生成:
   ```bash
   flutter pub run build_runner build --delete-conflicting-outputs
   ```
3. 更新 `PackageListNotifier` 的加载/持久化逻辑
4. 添加迁移逻辑（如需向后兼容）

### When Adding UI Components

1. **通用组件放 `lib/ui/components/`**
2. **屏幕级组件放对应 `screens/` 子目录**
3. **使用 Riverpod Providers 读取状态**: 避免直接操作 Hive

## Common Pitfalls

1. **勿在 `core/` 导入 Flutter**: 破坏架构纯洁性，导致核心逻辑不可测
2. **勿在同步逻辑清空 `pickedUpAt`**: 用户手动标记的状态需保护（除非拒收）
3. **协议相对 URL 需补前缀**: 淘宝/拼多多图片 URL 可能缺 `https:`，渲染前补全
4. **打码单号需特殊处理**: 菜鸟驿站查询、身份判定时需识别 `*` 标记
5. **外卖订单需过滤**: 京东「达达」「秒送」等即时订单不是快递，需排除

## Project-Specific Conventions

- **日志脱敏**: 运单号、订单号、取件码只记录平台前缀与计数，不打包完整值
- **中文注释**: 核心业务逻辑注释使用简体中文（领域语言为中文）
- **包裹 ID 格式**: `<平台前缀>_<平台订单号>` (如 `PDD_240101123456`, `TB_1000000000000000001`, `CN_YT1234567890123`)
- **Cookie 管理**: 各平台凭据存 `PlatformAuthStore`，WebView 捕获后持久化

## Recent Work (Reference Only)

最近一次重大改动见 `PROGRESS.md`（P11-b 后续：淘宝商品图 URL 修复、打码单号合并、登录态失效 UI）。该文件为迭代日志，**不代表当前最新状态**，仅供理解最近改动上下文。
