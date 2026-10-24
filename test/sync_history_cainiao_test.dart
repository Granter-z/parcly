// P23-b：SyncHistoryManager 菜鸟成功产出时间读写
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:pickup_app/platform/sync/sync_history_manager.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('sync_history_cainiao');
    Hive.init(tempDir.path);
    await SyncHistoryManager.initialize();
  });

  tearDown(() async {
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('recordCainiaoSuccess / getCainiaoLastSuccess 读写一致', () async {
    final hist = SyncHistoryManager();
    expect(hist.getCainiaoLastSuccess(), isNull);

    final before = DateTime.now();
    await hist.recordCainiaoSuccess();
    final after = DateTime.now();

    final got = hist.getCainiaoLastSuccess();
    expect(got, isNotNull);
    expect(!got!.isBefore(before.subtract(const Duration(seconds: 1))), isTrue);
    expect(!got.isAfter(after.add(const Duration(seconds: 1))), isTrue);
  });

  test('cainiao 与 taobao 平台键互不覆盖', () async {
    final hist = SyncHistoryManager();
    await hist.recordPlatformSync('taobao');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await hist.recordCainiaoSuccess();

    expect(hist.getPlatformLastSync('taobao'), isNotNull);
    expect(hist.getCainiaoLastSuccess(), isNotNull);
    expect(hist.getCainiaoLastSuccess()!.isAfter(hist.getPlatformLastSync('taobao')!), isTrue);
  });
}
