# Parcly

<p align="center">
  <img src="https://img.shields.io/badge/Android-7.0+-3DDC84?logo=android&logoColor=white" alt="Android" />
  <img src="https://img.shields.io/badge/Flutter-3.6+-02569B?logo=flutter&logoColor=white" alt="Flutter" />
  <img src="https://img.shields.io/badge/Release-v1.0.0%2B4-00B578" alt="Version" />
  <img src="https://img.shields.io/badge/License-GPLv3-blue" alt="License" />
</p>

**打开一个 App，就知道哪些包裹到了、在哪个驿站、取件码是多少。**

Parcly 聚合拼多多、京东、淘宝 / 天猫的真实物流，把「待取件」放在首页最显眼的位置——站在驿站或快递柜前，掏出手机几秒内就能看到取件码，不用再挨个打开电商 App 翻订单。

数据只存在你的手机里，不上传任何服务器。

---

## 它解决什么

- **包裹散落多平台**：购物在拼多多、京东、淘宝各处，取件码也散在各个 App 里。
- **站柜前找码慢**：核心场景是人已经站在驿站 / 快递柜前，需要立刻看到码，而不是再刷一遍物流。
- **拼多多双端互踢**：官方 App 与第三方登录容易互踢；Parcly 内置拼多多移动端商城，可当作日常入口，从根上绕开互踢。
- **无关订单干扰**：外卖、秒送、退款取消等不进包裹列表。

---

## 现在能做什么

- **三平台聚合同步**：拼多多、京东、淘宝 / 天猫；手动同步或打开 App 时拉取在途与待取包裹。
- **待取件优先首页**：首页突出「待取件」与取件码；已完成订单收入二级列表，不抢视线。
- **物流详情**：承运商、运单号、订单信息与完整转运时间轴；轨迹里的电话可一键拨打。
- **到件提醒**：状态变为待取件时发本地通知（快递公司 · 取件码 · 驿站）。
- **登录状态可见**：平台登录失效时提示哪个平台需要重登，其他平台不受影响。
- **隐私优先**：账号凭证与订单数据仅存本机（Hive）；日志对运单号 / 订单号 / 取件码脱敏。

> 已知限制：平台改版或风控可能导致某一端暂时拉不到数据；京东偶发网络不可达时，不会拖死整次同步，也不会误标成「需重登」。国内应用商店未必收这类 App，当前以 APK 分发为主。

---

## 下载安装

正式版见 [Releases](https://github.com/Granter-z/parcly/releases/latest)。按机型选包：

| 文件 | 适用 |
| --- | --- |
| `parcly-*-arm64-v8a-release.apk` | 绝大多数近年手机，**首选** |
| `parcly-*-universal-release.apk` | 不确定架构时的通用包 |

安装前需允许「未知来源」。各包 SHA-256 见 Release 页的 `SHA256SUMS.txt`。

请只用自己的电商账号登录；本应用读取的是你自己的订单数据。

---

## 给开发者

本地构建（Flutter `^3.6`、Android minSdk 24）：

```bash
git clone git@github.com:Granter-z/parcly.git
cd parcly
flutter pub get
flutter run
flutter test
flutter build apk --release --split-per-abi
```

架构与模块划分见仓库内 `docs/` 与源码目录约定：`lib/core/`（纯 Dart）、`lib/platform/`、`lib/ui/`。

---

## 许可证

[GNU GPL v3.0](LICENSE)
