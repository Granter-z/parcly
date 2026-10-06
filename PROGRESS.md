# 项目进度追踪板 (Project Progress Tracker)

> 最近更新时间：2026-10-06 03:42:00 (UTC+8)  
> 当前迭代状态：进行中 (联调与平台适配阶段)

---

## 🎯 当前阶段目标 (Current Milestone)
- 全面打通电商平台（拼多多 / 京东 / 淘宝菜鸟）官方物流时间轴与状态推导（B+ 架构）。
- 实现多平台账号会话持久化与免密保活，保障无感拉取包裹最新物流状态。

---

## 📊 总体进度概览
- [x] 阶段 1：拼多多全量官方物流时间轴直取与防残缺合并
- [x] 阶段 2：核心架构瘦身，剥离冗余事件聚合，落地纯 Dart `timeline_merge` 引擎
- [x] 阶段 3：京东连接器精简与秒送/外卖实物订单过滤 (`jd_delivery_filter`)
- [/] 阶段 4：淘宝/菜鸟连接器物流时间轴深度适配 (进行中)
- [ ] 阶段 5：全平台账号凭证持久化保活机制 (待启动)

---

## 🔄 最新工作记录 (Recent Updates)
### [2026-10-06 03:42] 核心架构精简与京东/淘宝时间轴接入
- **改动范围**：
  - `./lib/core/engine/timeline_merge.dart`
  - `./lib/platform/connectors/jd_delivery_filter.dart`
  - `./lib/platform/connectors/jd_connector.dart`
  - `./lib/platform/connectors/taobao_connector.dart`
  - `./lib/core/models/package.dart`
  - `./lib/ui/screens/home/package_detail_page.dart`
  - `./lib/ui/screens/home/widgets/package_card.dart`
  - 清理：移除旧版 `event_aggregator.dart`、`logistics_event.dart`、`event_provider.dart`、`package_timeline_widget.dart`
- **核心成果**：
  1. **架构轻量化**：剥离重型多事件聚合管道，转向统一纯 Dart 时间轴合并 (`timeline_merge.dart`)，支持脏数据清洗与时间倒序去重。
  2. **京东过滤与清洗**：实现 `jd_delivery_filter.dart`，以 `progressId=logistics` 严格过滤外卖、秒送与虚拟订单；重构 JD 抓取与异常处理逻辑。
  3. **淘宝时间轴初版打通**：在 `taobao_connector.dart` 中实现 `multiStage` 节点解析，接入 `LogisticsStatusEngine` 状态推导并写入 `rawTimelineJson`。
  4. **UI组件轻量化**：详情页直接消费解析后的轨迹时间轴，移除废弃的复杂 timeline widget 与冗余调试代码。
- **遗留待办 (Next Steps)**：
  - [ ] **账号持久保活**：设计并实现 Cookie / Token 长期有效与保活机制，降低会话过期与重复扫码频率。
  - [ ] **淘宝物流时间轴完善**：完善菜鸟与淘宝物流详情的深层节点抓取，覆盖更丰富的订单类型与阶段状态对齐。
- **关键决策与注意事项**：
  - 严格保持 `lib/core/` 零 Flutter / 平台依赖的纯 Dart 设计。
  - 淘宝 H5 接口反爬与风控敏感度高，后续抓取深度与频率需维持平稳节奏。

---

## 📜 历史归档日志 (Historical Changelog)
*(当前为初始记录，后续每次 /inte 增量归档在此)*
