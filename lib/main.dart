import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'platform/storage/hive_adapters.dart';
import 'core/debug/debug_trace.dart';
import 'platform/storage/hive_package.dart';
import 'platform/storage/platform_auth_store.dart';
import 'platform/notification/notification_adapter.dart';
import 'ui/app.dart';

const String kPackagesBox = 'packages';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  DebugTrace.separator('MAIN: Hive.initFlutter');
  await initializeDateFormatting('zh_CN', null);
  await Hive.initFlutter();
  print('Hive.initFlutter done');

  Hive
    ..registerAdapter(PackageStatusAdapter())
    ..registerAdapter(UrgencyLevelAdapter())
    ..registerAdapter(CourierTypeAdapter())
    ..registerAdapter(HivePackageAdapter());
  print('Adapters registered (4)');

  DebugTrace.separator('MAIN: openBox');
  final box = await Hive.openBox<HivePackage>(kPackagesBox);
  print('box.name: ${box.name}');
  print('box.isOpen: ${box.isOpen}');
  print('box.length: ${box.length}');

  // 预打开平台凭据存储，确保重启后已绑定的平台账号立即可读
  await PlatformAuthStore.initialize();
  print('PlatformAuthStore initialized');

  DebugTrace.separator('MAIN: NotificationAdapter');
  await NotificationAdapter().initialize();
  print('NotificationAdapter initialized');

  DebugTrace.separator('MAIN: runApp');
  runApp(const ProviderScope(child: PickupApp()));
}