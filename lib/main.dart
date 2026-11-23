import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:workmanager/workmanager.dart';
import 'platform/storage/hive_adapters.dart';
import 'core/debug/debug_trace.dart';
import 'platform/storage/hive_package.dart';
import 'platform/storage/platform_auth_store.dart';
import 'platform/storage/keep_alive_store.dart';
import 'platform/storage/pickup_point_alias_store.dart';
import 'platform/sync/sync_history_manager.dart';
import 'platform/notification/notification_adapter.dart';
import 'platform/keep_alive/keep_alive_worker.dart';
import 'ui/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 调试追踪默认开启；Release 关闭，避免生产包持续输出调试横幅。
  DebugTrace.enabled = kDebugMode;

  await _guard('Hive.initFlutter', () async {
    DebugTrace.separator('MAIN: Hive.initFlutter');
    await Hive.initFlutter();
    debugPrint('Hive.initFlutter done');
  });

  try {
    Hive
      ..registerAdapter(PackageStatusAdapter())
      ..registerAdapter(UrgencyLevelAdapter())
      ..registerAdapter(CourierTypeAdapter())
      ..registerAdapter(HivePackageAdapter());
    debugPrint('Adapters registered (4)');
  } catch (e, st) {
    DebugTrace.error('registerAdapters failed', error: e, stackTrace: st);
  }

  // 包裹 box：损坏时删除并重建空盒，绝不能让启动链抛到 runApp 之前（否则永久黑屏）
  await _guard('openBox', () async {
    try {
      final box = await Hive.openBox<HivePackage>(kPackagesBox);
      debugPrint('box.name: ${box.name}, length: ${box.length}');
    } catch (e, st) {
      DebugTrace.error('openBox failed, rebuilding empty box',
          error: e, stackTrace: st);
      try {
        await Hive.deleteBoxFromDisk(kPackagesBox);
        await Hive.openBox<HivePackage>(kPackagesBox);
      } catch (e2, st2) {
        DebugTrace.error('rebuild box failed', error: e2, stackTrace: st2);
      }
    }
  });

  // 预打开平台凭据存储，确保重启后已绑定的平台账号立即可读
  await _guard('PlatformAuthStore', () async {
    await PlatformAuthStore.initialize();
    debugPrint('PlatformAuthStore initialized');
  });

  // 保活调度状态（含「下次保活时间」闸门）：落盘后冷启动不再重发心跳
  await _guard('KeepAliveStore', () async {
    await KeepAliveStore.initialize();
    await KeepAliveStore().ensureSchemaVersion();
    debugPrint('KeepAliveStore initialized');
  });

  // 预打开同步历史：保活靠「最近同步时间」跳过刚同步过的平台
  await _guard('SyncHistoryManager', () async {
    await SyncHistoryManager.initialize();
    debugPrint('SyncHistoryManager initialized');
  });

  // 取件点别名表（P28-d）：默认空，真机在设置里声明
  await _guard('PickupPointAliasStore', () async {
    await PickupPointAliasStore.initialize();
    await PickupPointAliasStore().ensureSchemaVersion();
    debugPrint('PickupPointAliasStore initialized');
  });

  await _guard('NotificationAdapter', () async {
    DebugTrace.separator('MAIN: NotificationAdapter');
    await NotificationAdapter().initialize();
    debugPrint('NotificationAdapter initialized');
  });

  // 注册后台保活任务（WorkManager）：App 进程被杀后仍能定时续期淘宝/京东登录态
  //
  // P45：旧实现每次冷启动都用 update 重新入队，WorkManager 会重置周期计时，
  // 用户频繁打开 App 时后台任务可能永远等不到 6 小时窗口。改为 keep 后，
  // 只有首次安装会排期；同时迁移到新任务名以把周期降为 4 小时（最紧急档）。
  await _guard('WorkManager', () async {
    await Workmanager().initialize(callbackDispatcher);
    await Workmanager().cancelByUniqueName('keep_alive_periodic');
    await Workmanager().registerPeriodicTask(
      'keep_alive_periodic_v2',
      'keepAliveTask',
      frequency: const Duration(hours: 4),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    );
    debugPrint('WorkManager keep-alive task registered');
  });

  DebugTrace.separator('MAIN: runApp');
  runApp(const ProviderScope(child: PickupApp()));
}

/// 分块启动：任一初始化失败只记录，不阻断 runApp。
Future<void> _guard(String name, Future<void> Function() action) async {
  try {
    await action();
  } catch (e, st) {
    DebugTrace.error('$name failed', error: e, stackTrace: st);
  }
}
