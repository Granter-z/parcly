import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:pickup_app/core/engine/keep_alive_outcome.dart';
import 'package:pickup_app/platform/keep_alive/keep_alive_worker.dart';
import 'package:pickup_app/platform/keep_alive/platform_heartbeat.dart';
import 'package:pickup_app/platform/storage/keep_alive_store.dart';
import 'package:pickup_app/platform/storage/platform_auth_store.dart';

class _FakeAuthStore extends PlatformAuthStore {
  final Set<String> expired = {};

  @override
  bool isExpired(String platform) => expired.contains(platform);

  @override
  Future<void> setExpired(String platform, bool value) async {
    if (value) {
      expired.add(platform);
    } else {
      expired.remove(platform);
    }
  }
}

void main() {
  late Directory tempDir;
  late _FakeAuthStore auth;
  late KeepAliveStore store;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('keep_alive_worker_outcome');
    Hive.init(tempDir.path);
    await KeepAliveStore.initialize();
    auth = _FakeAuthStore();
    store = KeepAliveStore();
    await store.loadIntoCache();
  });

  tearDown(() async {
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('classifyHeartbeatResult', () {
    test('四分支', () {
      expect(
        classifyHeartbeatResult(HeartbeatResult.success()),
        KeepAliveOutcomeKind.success,
      );
      expect(
        classifyHeartbeatResult(
          HeartbeatResult.failure('x', isAuthFailure: true),
        ),
        KeepAliveOutcomeKind.authFailure,
      );
      expect(
        classifyHeartbeatResult(HeartbeatResult.failure('net')),
        KeepAliveOutcomeKind.networkFailure,
      );
      expect(
        classifyHeartbeatResult(HeartbeatResult.skipped('busy')),
        KeepAliveOutcomeKind.skipped,
      );
    });
  });

  group('applyHeartbeatOutcome', () {
    test('成功：清失效 + 失败计数归零 + 写 last', () async {
      auth.expired.add('taobao');
      await store.setFailureCount('taobao', 2);

      await applyHeartbeatOutcome(
        platform: 'taobao',
        plan: planKeepAliveOutcome(
          kind: KeepAliveOutcomeKind.success,
          currentFailureCount: 2,
        ),
        authStore: auth,
        store: store,
      );

      expect(auth.isExpired('taobao'), isFalse);
      expect(store.failureCount('taobao'), 0);
      expect(store.lastAt('taobao'), isNotNull);
      expect(store.lastNotifiedAt('taobao'), isNull);
    });

    test('登录失效：setExpired true', () async {
      await applyHeartbeatOutcome(
        platform: 'jd',
        plan: planKeepAliveOutcome(
          kind: KeepAliveOutcomeKind.authFailure,
          currentFailureCount: 0,
        ),
        authStore: auth,
        store: store,
      );

      expect(auth.isExpired('jd'), isTrue);
      expect(store.failureCount('jd'), 3);
      expect(store.lastAt('jd'), isNull);
    });

    test('跳过：不改失效与计数', () async {
      auth.expired.add('jd');
      await store.setFailureCount('jd', 1);

      await applyHeartbeatOutcome(
        platform: 'jd',
        plan: planKeepAliveOutcome(
          kind: KeepAliveOutcomeKind.skipped,
          currentFailureCount: 1,
        ),
        authStore: auth,
        store: store,
      );

      expect(auth.isExpired('jd'), isTrue);
      expect(store.failureCount('jd'), 1);
    });
  });

  group('后台心跳抛异常对齐前台', () {
    test('单次抛异常记失败次数, 不 setExpired', () async {
      // worker catch 会把异常收成 isAuthFailure:false 的 HeartbeatResult.failure
      final result = HeartbeatResult.failure('Bad state: boom', isAuthFailure: false);
      expect(classifyHeartbeatResult(result), KeepAliveOutcomeKind.networkFailure);

      await applyHeartbeatOutcome(
        platform: 'taobao',
        plan: planKeepAliveOutcome(
          kind: KeepAliveOutcomeKind.networkFailure,
          currentFailureCount: store.failureCount('taobao'),
        ),
        authStore: auth,
        store: store,
      );

      expect(store.failureCount('taobao'), 1);
      expect(auth.isExpired('taobao'), isFalse, reason: '网络类异常不得标需重登');
    });

    test('连续 3 次抛异常才 setExpired', () async {
      for (var i = 0; i < 3; i++) {
        await applyHeartbeatOutcome(
          platform: 'jd',
          plan: planKeepAliveOutcome(
            kind: KeepAliveOutcomeKind.networkFailure,
            currentFailureCount: store.failureCount('jd'),
          ),
          authStore: auth,
          store: store,
        );
      }
      expect(store.failureCount('jd'), 3);
      expect(auth.isExpired('jd'), isTrue);
    });

    test('明确 authFailure 一次即 setExpired', () async {
      final result = HeartbeatResult.failure('登录态已失效', isAuthFailure: true);
      expect(classifyHeartbeatResult(result), KeepAliveOutcomeKind.authFailure);

      await applyHeartbeatOutcome(
        platform: 'taobao',
        plan: planKeepAliveOutcome(
          kind: KeepAliveOutcomeKind.authFailure,
          currentFailureCount: 0,
        ),
        authStore: auth,
        store: store,
      );

      expect(auth.isExpired('taobao'), isTrue);
      expect(store.failureCount('taobao'), 3);
    });
  });
}
