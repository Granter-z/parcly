library;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import '../../core/models/package.dart';
import '../../core/models/platform_ids.dart';
import '../../core/debug/debug_trace.dart';
import '../../core/utils/stable_hash.dart';

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
  static int _legacyPackageNotificationId(String packageId, int base) =>
      base + packageId.hashCode.abs() % 10000;

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
    const ios = DarwinInitializationSettings();

    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
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
        '[Notify] arrived courier=${package.courier.shortName} hasCode=${package.pickupCode.isNotEmpty}');

    final title = _buildArrivedTitle(package);
    final body = _buildArrivedBody(package);
    final notificationId = packageNotificationId(package.id, _arrivedBaseId);
    try {
      await _plugin.cancel(
          _legacyPackageNotificationId(package.id, _arrivedBaseId));
    } catch (_) {}

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
      // 商品名过长时截断（通知标题最多显示约 40 个字符）
      return goodsName.length > 18 ? '${goodsName.substring(0, 18)}...' : goodsName;
    }
    return '快递到了！';
  }

  String _buildArrivedBody(Package package) {
    final courier = package.courier.shortName;
    final parts = <String>[];

    // 显示快递公司
    parts.add(courier);

    // 显示取件码
    if (package.pickupCode.isNotEmpty) {
      parts.add('取件码：${package.pickupCode}');
    }

    // 显示驿站名（如果有）
    if (package.stationName != null && package.stationName!.trim().isNotEmpty) {
      final stationName = package.stationName!.trim();
      // 驿站名过长时截断
      final displayStation = stationName.length > 12 ? '${stationName.substring(0, 12)}...' : stationName;
      parts.add(displayStation);
    }

    // 如果没有取件码，显示地址信息
    if (package.pickupCode.isEmpty && package.location.isNotEmpty) {
      parts.add('已到 ${package.location}');
    }

    return parts.join(' · ');
  }

  Future<void> scheduleReminderNotification(Package package) async {
    DebugTrace.separator('SCHEDULE REMINDER NOTIFICATION');
    debugPrint('[Notify] reminder courier=${package.courier.shortName}');

    const title = '快递还在等你';
    final body = '${package.courier.shortName} 已等待超过 24 小时';
    final notificationId = packageNotificationId(package.id, _reminderBaseId);
    try {
      await _plugin.cancel(
          _legacyPackageNotificationId(package.id, _reminderBaseId));
    } catch (_) {}

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

    final arrivedId = packageNotificationId(packageId, _arrivedBaseId);
    final reminderId = packageNotificationId(packageId, _reminderBaseId);
    final legacyArrivedId =
        _legacyPackageNotificationId(packageId, _arrivedBaseId);
    final legacyReminderId =
        _legacyPackageNotificationId(packageId, _reminderBaseId);

    try {
      await _plugin.cancel(arrivedId);
      await _plugin.cancel(reminderId);
      await _plugin.cancel(legacyArrivedId);
      await _plugin.cancel(legacyReminderId);
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
    const ios = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    final details = NotificationDetails(android: android, iOS: ios);

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
    const ios = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    const details = NotificationDetails(android: android, iOS: ios);

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