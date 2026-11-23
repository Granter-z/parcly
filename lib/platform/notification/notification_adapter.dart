library;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import '../../core/debug/debug_trace.dart';
import '../../core/engine/station_grouping.dart';
import '../../core/models/package.dart';
import '../../core/models/platform_ids.dart';
import '../../core/utils/stable_hash.dart';
import '../../core/utils/text_truncate.dart';
import '../storage/pickup_point_alias_store.dart';

/// 登录状态提醒使用独立通知渠道
///
/// 与「快递通知」分开，用户可单独静音登录提醒而不影响到件提醒——两者语义不同，
/// 混在同一渠道会让用户无法区分。
const String _keepAliveChannelId = 'keep_alive_channel';
const String _keepAliveChannelName = '登录状态提醒';

class NotificationAdapter {
  static final NotificationAdapter _instance = NotificationAdapter._();
  factory NotificationAdapter() => _instance;
  NotificationAdapter._();

  final _plugin = FlutterLocalNotificationsPlugin();

  static const int _arrivedBaseId = 1000000;
  static const int _reminderBaseId = 200000000;

  /// 保活相关通知独立号段，避开包裹通知的两段大区间
  static const int _keepAliveBaseId = 30000;

  /// 包裹通知 id：FNV-1a 稳定哈希 + 大区间，避免 10000 桶的生日碰撞误伤。
  ///
  /// 不用 `String.hashCode`：它不保证跨进程稳定，冷启动后取消/提醒会算出不同 id。
  /// 可见性放开供单测直接断言稳定性。
  @visibleForTesting
  static int packageNotificationId(String packageId, int base) =>
      base + stableHash32(packageId);

  /// 旧版 10000 桶 id（hashCode 口径），升级后仍需取消，避免残留通知。
  /// 注意：这里必须沿用旧算法，否则取消不到历史版本发出的通知。
  @visibleForTesting
  static int legacyPackageNotificationId(String packageId, int base) =>
      base + packageId.hashCode.abs() % 10000;

  /// 上一版（+21～+30）口径：`base + (hashCode & 0x07FFFFFF)`。
  ///
  /// 本 PR 换成稳定哈希后，上一版发出的通知两种旧口径都不是；取消时必须一并
  /// 兼容，否则升级后旧的到件通知取件了也消不掉。
  @visibleForTesting
  static int previousPackageNotificationId(String packageId, int base) =>
      base + (packageId.hashCode & 0x07FFFFFF);

  /// 取消一个包裹时需要尝试的全部 id（三套口径 × 到件/提醒）。
  ///
  /// 取消不存在的 id 是 no-op，多算几个是安全的。
  @visibleForTesting
  static List<int> notificationIdsToCancel(String packageId) => [
        packageNotificationId(packageId, _arrivedBaseId),
        packageNotificationId(packageId, _reminderBaseId),
        previousPackageNotificationId(packageId, _arrivedBaseId),
        previousPackageNotificationId(packageId, _reminderBaseId),
        legacyPackageNotificationId(packageId, _arrivedBaseId),
        legacyPackageNotificationId(packageId, _reminderBaseId),
      ];

  /// 登录失效提醒的点击跳转 payload 前缀
  static const String keepAliveExpiredPrefix = 'keep_alive_expired:';

  /// 点击通知后待处理的路由
  ///
  /// 通知回调拿不到 `BuildContext`，App 还可能处于冷启动，
  /// 因此这里只做「投递」，由 `ui/app.dart` 在首帧后消费并导航。
  static final ValueNotifier<String?> pendingRoute = ValueNotifier<String?>(null);

  static String keepAliveExpiredPayload(String platform) =>
      '$keepAliveExpiredPrefix$platform';

  /// 从 payload 解析出失效平台；非保活 payload 返回 null
  static String? expiredPlatformFromPayload(String? payload) {
    if (payload == null || !payload.startsWith(keepAliveExpiredPrefix)) return null;
    return payload.substring(keepAliveExpiredPrefix.length);
  }

  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;

    tz.initializeTimeZones();

    const android = AndroidInitializationSettings('ic_stat_parcel');

    await _plugin.initialize(
      const InitializationSettings(android: android),
      onDidReceiveNotificationResponse: _onNotificationResponse,
    );
    _initialized = true;

    // 冷启动场景：App 是被用户点击通知拉起来的，补投一次路由
    try {
      final launch = await _plugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp == true) {
        final payload = launch?.notificationResponse?.payload;
        if (expiredPlatformFromPayload(payload) != null) {
          pendingRoute.value = payload;
        }
      }
    } catch (e) {
      DebugTrace.separator('NOTIFICATION LAUNCH DETAILS FAILED: $e');
    }

    DebugTrace.separator('NOTIFICATION SERVICE INITIALIZED');
  }

  /// Android 13+ 通知权限：不申请则到件与登录失效通知都会被系统静默丢弃。
  ///
  /// 由首页首帧调用（此时 Activity 已 resumed），避免在 [initialize] 里弹窗。
  Future<void> ensurePermission() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (android == null) return;
      final enabled = await android.areNotificationsEnabled() ?? false;
      if (enabled) return;
      final granted = await android.requestNotificationsPermission() ?? false;
      DebugTrace.separator('NOTIFICATION PERMISSION: $granted');
    } catch (e) {
      DebugTrace.separator('NOTIFICATION PERMISSION ERROR: $e');
    }
  }

  /// 当前是否真的能发通知（Android 13+ 权限被拒时 notify 会被静默丢弃）。
  Future<bool> notificationsEnabled() async {
    if (defaultTargetPlatform != TargetPlatform.android) return true;
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      return await android?.areNotificationsEnabled() ?? true;
    } catch (_) {
      return true;
    }
  }

  void _onNotificationResponse(NotificationResponse response) {
    DebugTrace.separator('NOTIFICATION CLICKED');
    final payload = response.payload;
    if (expiredPlatformFromPayload(payload) != null) {
      pendingRoute.value = payload;
    }
  }

  /// 通用通知：不绑定 [Package]，供登录失效等平台级提醒使用
  Future<void> notify({
    required int id,
    required String title,
    required String body,
    String? payload,
    String channelId = 'pickup_channel',
    String channelName = '快递通知',
    String channelDescription = '包裹到达提醒',
  }) async {
    await _showNotification(
      id: id,
      title: title,
      body: body,
      payload: payload,
      channelId: channelId,
      channelName: channelName,
      channelDescription: channelDescription,
    );
  }

  /// 登录态失效提醒
  ///
  /// 通知 id 按平台固定槽位，同一平台重复提醒是**替换**而不是堆叠。
  Future<void> showKeepAliveExpiredNotification({
    required String platform,
    required String displayName,
  }) async {
    final slot = kPlatformIds.indexOf(platform);
    final id = _keepAliveBaseId + (slot >= 0 ? slot + 1 : 99);

    DebugTrace.separator('SHOW KEEPALIVE EXPIRED NOTIFICATION');

    await notify(
      id: id,
      title: '$displayName 登录态已失效',
      body: '点击前往「设置」重新登录，以继续自动同步包裹',
      payload: keepAliveExpiredPayload(platform),
      channelId: _keepAliveChannelId,
      channelName: _keepAliveChannelName,
      channelDescription: '平台登录状态提醒',
    );
  }

  Future<void> showArrivedNotification(Package package) async {
    DebugTrace.separator('SHOW ARRIVED NOTIFICATION');
    debugPrint(
        '[Notify] arrived courier=${package.effectiveCourier.shortName} hasCode=${package.pickupCode.trim().isNotEmpty}');

    final title = _buildArrivedTitle(package);
    final body = _buildArrivedBody(package);
    final notificationId = packageNotificationId(package.id, _arrivedBaseId);
    for (final oldId in [
      legacyPackageNotificationId(package.id, _arrivedBaseId),
      previousPackageNotificationId(package.id, _arrivedBaseId),
    ]) {
      try {
        await _plugin.cancel(oldId);
      } catch (_) {}
    }

    await _showNotification(
      id: notificationId,
      title: title,
      body: body,
      payload: 'arrived:${package.id}',
    );
  }

  String _buildArrivedTitle(Package package) {
    // 优先显示商品名，如果没有则显示「快递到了！」
    if (package.goodsName != null && package.goodsName!.trim().isNotEmpty) {
      final goodsName = package.goodsName!.trim();
      // 商品名过长时按码点安全截断（通知标题最多显示约 40 个字符）
      return truncateRunes(goodsName, 18, ellipsis: '...');
    }
    return '快递到了！';
  }

  @visibleForTesting
  String buildArrivedBodyForTest(
    Package package, {
    Map<String, String>? stationAliases,
  }) =>
      _buildArrivedBody(package, stationAliases: stationAliases);

  String _buildArrivedBody(
    Package package, {
    Map<String, String>? stationAliases,
  }) {
    final courier = package.effectiveCourier.shortName;
    final parts = <String>[];

    // 显示快递公司
    parts.add(courier);

    // 显示取件码
    final code = package.pickupCode.trim();
    if (code.isNotEmpty) {
      parts.add('取件码：$code');
    }

    // 显示驿站名（排除未知占位文案，经别名表映射为规范名）
    if (!isUnknownStationLabel(package.stationName)) {
      final canonical = resolveCanonicalName(
        package.stationName!.trim(),
        buildAliasLookup(stationAliases ?? PickupPointAliasStore().readAll()),
      );
      // 驿站名过长时按码点安全截断
      parts.add(truncateRunes(canonical, 12, ellipsis: '...'));
    }

    // 如果没有取件码，显示地址信息
    if (code.isEmpty && package.location.trim().isNotEmpty) {
      parts.add('已到 ${package.location.trim()}');
    }

    return parts.join(' · ');
  }

  Future<void> scheduleReminderNotification(Package package) async {
    DebugTrace.separator('SCHEDULE REMINDER NOTIFICATION');
    debugPrint('[Notify] reminder courier=${package.effectiveCourier.shortName}');

    const title = '快递还在等你';
    final body = '${package.effectiveCourier.shortName} 已等待超过 24 小时';
    final notificationId = packageNotificationId(package.id, _reminderBaseId);
    for (final oldId in [
      legacyPackageNotificationId(package.id, _reminderBaseId),
      previousPackageNotificationId(package.id, _reminderBaseId),
    ]) {
      try {
        await _plugin.cancel(oldId);
      } catch (_) {}
    }

    await _scheduleNotification(
      id: notificationId,
      title: title,
      body: body,
      payload: 'reminder:${package.id}',
      delay: const Duration(hours: 24),
    );
  }

  Future<void> cancelNotification(String packageId) async {
    DebugTrace.separator('CANCEL NOTIFICATION');
    debugPrint('[Notify] cancel');

    try {
      // 三套 id 口径都取消：新版稳定哈希、上一版 hashCode 大区间、
      // 更早的 10000 桶。取消不存在的 id 是 no-op。
      for (final id in notificationIdsToCancel(packageId)) {
        await _plugin.cancel(id);
      }
    } catch (_) {}
  }

  Future<void> _showNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
    String channelId = 'pickup_channel',
    String channelName = '快递通知',
    String channelDescription = '包裹到达提醒',
  }) async {
    final android = AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: channelDescription,
      importance: Importance.high,
      priority: Priority.high,
      icon: 'ic_stat_parcel',
    );
    final details = NotificationDetails(android: android);

    await _plugin.show(id, title, body, details, payload: payload);
  }

  Future<void> _scheduleNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
    required Duration delay,
  }) async {
    const android = AndroidNotificationDetails(
      'pickup_channel',
      '快递通知',
      channelDescription: '包裹到达提醒',
      importance: Importance.high,
      priority: Priority.high,
      icon: 'ic_stat_parcel',
    );
    const details = NotificationDetails(android: android);

    final scheduledDate = tz.TZDateTime.now(tz.local).add(delay);

    await _plugin.zonedSchedule(
      id,
      title,
      body,
      scheduledDate,
      details,
      payload: payload,
      // 24h 提醒不需要秒级精度；exact 在 Android 12+ 需额外授权，未授权会直接抛异常
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }
}