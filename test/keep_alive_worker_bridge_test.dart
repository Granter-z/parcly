import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pickup_app/platform/keep_alive/keep_alive_worker_bridge.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('keep_alive_bridge');
    debugBridgeDirOverride = tempDir;
  });

  tearDown(() {
    debugBridgeDirOverride = null;
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('配置可往返读写', () async {
    final next = DateTime(2026, 11, 16, 20);
    await writeWorkerConfig(WorkerKeepAliveConfig(
      enabled: false,
      platforms: {
        'taobao': WorkerPlatformConfig(
          enabled: false,
          nextKeepAliveAt: next,
          failureCount: 2,
        ),
      },
    ));

    final config = await readWorkerConfig();

    expect(config, isNotNull);
    expect(config!.enabled, isFalse);
    expect(config.platforms['taobao']!.enabled, isFalse);
    expect(config.platforms['taobao']!.nextKeepAliveAt, next);
    expect(config.platforms['taobao']!.failureCount, 2);
  });

  test('配置文件缺失时返回 null', () async {
    expect(await readWorkerConfig(), isNull);
  });

  test('结果可往返读取且读取后清空', () async {
    await writeWorkerResults([
      WorkerHeartbeatResult(
        platform: 'taobao',
        kind: 'authFailure',
        error: '登录态已失效',
        time: DateTime(2026, 11, 16, 18),
        nextKeepAliveAt: DateTime(2026, 11, 17, 0),
      ),
    ]);

    final results = await readAndClearWorkerResults();

    expect(results, hasLength(1));
    expect(results.single.platform, 'taobao');
    expect(results.single.kind, 'authFailure');
    expect(results.single.error, '登录态已失效');
    expect(results.single.nextKeepAliveAt, DateTime(2026, 11, 17, 0));
    expect(await readAndClearWorkerResults(), isEmpty);
  });

  test('提醒去重表可往返读写', () async {
    final at = DateTime(2026, 11, 16, 18, 30);
    await writeWorkerNotifiedAt({'pdd': at});

    final map = await readWorkerNotifiedAt();

    expect(map['pdd'], at);
  });

  test('主 isolate 可清除 worker 的失效提醒标记', () async {
    await writeWorkerNotifiedAt({'pdd': DateTime(2026, 11, 16)});

    await clearWorkerNotifiedAt('pdd');

    expect(await readWorkerNotifiedAt(), isEmpty);
  });

  test('多轮结果文件不会被后一轮覆盖', () async {
    await writeWorkerResults([
      WorkerHeartbeatResult(
        platform: 'taobao',
        kind: 'success',
        time: DateTime(2026, 11, 16, 18),
      ),
    ]);
    await Future.delayed(const Duration(milliseconds: 2));
    await writeWorkerResults([
      WorkerHeartbeatResult(
        platform: 'jd',
        kind: 'networkFailure',
        time: DateTime(2026, 11, 16, 19),
      ),
    ]);

    final all = await readAndClearWorkerResults();

    expect(all.map((r) => r.platform), containsAll(['taobao', 'jd']));
  });

  test('worker 闸门可往返读写', () async {
    final at = DateTime(2026, 11, 17, 8);
    await writeWorkerGates({'taobao': at});

    final gates = await readWorkerGates();

    expect(gates['taobao'], at);
  });

  test('无文件时返回可变 Map（worker 会直接写入）', () async {
    final notifiedAt = await readWorkerNotifiedAt();
    final gates = await readWorkerGates();

    // 真机回归：曾返回 const {}，worker 成功后 remove/赋值抛 UnsupportedError
    expect(() => notifiedAt['jd'] = DateTime(2026, 11, 20), returnsNormally);
    expect(() => gates['jd'] = DateTime(2026, 11, 20), returnsNormally);
  });
}
