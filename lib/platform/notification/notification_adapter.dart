library;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import '../../core/models/package.dart';
import '../../core/debug/debug_trace.dart';

class NotificationAdapter {
  static final NotificationAdapter _instance = NotificationAdapter._();
  factory NotificationAdapter() => _instance;
  NotificationAdapter._();

  final _plugin = FlutterLocalNotificationsPlugin();

  static const int _arrivedBaseId = 10000;
  static const int _reminderBaseId = 20000;

  Future<void> initialize() async {
    tz.initializeTimeZones();

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();

    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
      onDidReceiveNotificationResponse: _onNotificationResponse,
    );

    DebugTrace.separator('NOTIFICATION SERVICE INITIALIZED');
  }

  void _onNotificationResponse(NotificationResponse response) {
    DebugTrace.separator('NOTIFICATION CLICKED');
    print('payload: ${response.payload}');
  }

  Future<void> showArrivedNotification(Package package) async {
    DebugTrace.separator('SHOW ARRIVED NOTIFICATION');
    print('package: ${package.courier.shortName} ${package.pickupCode}');

    final title = '快递到了！';
    final body = _buildArrivedBody(package);
    final notificationId = _arrivedBaseId + package.id.hashCode.abs() % 10000;

    await _showNotification(
      id: notificationId,
      title: title,
      body: body,
      payload: 'arrived:${package.id}',
    );
  }

  String _buildArrivedBody(Package package) {
    final courier = package.courier.shortName;

    if (package.pickupCode.isNotEmpty) {
      return '$courier 取件码：${package.pickupCode}';
    } else if (package.location.isNotEmpty) {
      return '$courier 已到 ${package.location}，请尽快取件';
    } else {
      return '$courier 已到达，请尽快取件';
    }
  }

  Future<void> scheduleReminderNotification(Package package) async {
    DebugTrace.separator('SCHEDULE REMINDER NOTIFICATION');
    print('package: ${package.courier.shortName}');

    final title = '快递还在等你';
    final body = '${package.courier.shortName} 已等待超过 24 小时';
    final notificationId = _reminderBaseId + package.id.hashCode.abs() % 10000;

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
    print('packageId: $packageId');

    final arrivedId = _arrivedBaseId + packageId.hashCode.abs() % 10000;
    final reminderId = _reminderBaseId + packageId.hashCode.abs() % 10000;

    try {
      await _plugin.cancel(arrivedId);
      await _plugin.cancel(reminderId);
    } catch (_) {}
  }

  Future<void> _showNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    const android = AndroidNotificationDetails(
      'pickup_channel',
      '快递通知',
      channelDescription: '包裹到达提醒',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );
    const ios = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    const details = NotificationDetails(android: android, iOS: ios);

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
      icon: '@mipmap/ic_launcher',
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
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }
}