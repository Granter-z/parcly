/// 后台保活 worker 与主 isolate 的通信桥。
///
/// 为什么不用 Hive：WorkManager 的 FlutterEngine 与主 App 在同一进程的不同 isolate
/// 里打开同一个 box。POSIX 文件锁按进程生效，两个 isolate 会各自缓存写偏移；
/// 主 isolate 崩溃恢复截断文件后，另一个 isolate 仍按旧偏移写入，box 会被反复损坏
///（真机已复现每次冷启动都打印 "Recovering corrupted box."）。
///
/// 因此约定：
/// - 主 isolate 只写「配置」（开关 / 闸门 / 失败计数），worker 只读；
/// - worker 只写「结果」与「已提醒时间」，主 isolate 下次启动时合并；
/// - 两边都用临时文件 + rename 原子替换，避免读到半截 JSON。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

const _configFile = 'keep_alive_worker_config.json';
const _resultPrefix = 'keep_alive_worker_result_';
const _legacyResultFile = 'keep_alive_worker_result.json';
const _notifyFile = 'keep_alive_worker_notify.json';
const _gateFile = 'keep_alive_worker_gate.json';

/// 主 isolate 下发给 worker 的单平台配置
class WorkerPlatformConfig {
  final bool enabled;
  final DateTime? nextKeepAliveAt;
  final int failureCount;

  const WorkerPlatformConfig({
    required this.enabled,
    this.nextKeepAliveAt,
    this.failureCount = 0,
  });
}

/// 主 isolate 下发给 worker 的完整配置
class WorkerKeepAliveConfig {
  final bool enabled;
  final Map<String, WorkerPlatformConfig> platforms;

  const WorkerKeepAliveConfig({required this.enabled, required this.platforms});
}

/// worker 上报给主 isolate 的心跳结果（不包含任何凭据）
class WorkerHeartbeatResult {
  final String platform;
  final String kind;
  final String? error;
  final DateTime time;
  final DateTime? nextKeepAliveAt;

  const WorkerHeartbeatResult({
    required this.platform,
    required this.kind,
    required this.time,
    this.error,
    this.nextKeepAliveAt,
  });

  Map<String, dynamic> toJson() => {
        'platform': platform,
        'kind': kind,
        'error': error,
        'time': time.millisecondsSinceEpoch,
        'next': nextKeepAliveAt?.millisecondsSinceEpoch,
      };

  factory WorkerHeartbeatResult.fromJson(Map<String, dynamic> json) =>
      WorkerHeartbeatResult(
        platform: json['platform'] as String? ?? '',
        kind: json['kind'] as String? ?? '',
        error: json['error'] as String?,
        time: DateTime.fromMillisecondsSinceEpoch(
          json['time'] as int? ?? DateTime.now().millisecondsSinceEpoch,
        ),
        nextKeepAliveAt: json['next'] is int
            ? DateTime.fromMillisecondsSinceEpoch(json['next'] as int)
            : null,
      );
}

/// 单测用：覆盖通信文件目录（生产环境为应用文档目录）
@visibleForTesting
Directory? debugBridgeDirOverride;

Future<File> _file(String name) async {
  final dir =
      debugBridgeDirOverride ?? await getApplicationDocumentsDirectory();
  return File('${dir.path}/$name');
}

Future<void> _writeJson(File file, Object data) async {
  final tmp = File('${file.path}.tmp');
  await tmp.writeAsString(jsonEncode(data), flush: true);
  await tmp.rename(file.path);
}

Map<String, dynamic>? _decodeMap(String raw) {
  try {
    final decoded = jsonDecode(raw);
    return decoded is Map<String, dynamic> ? decoded : null;
  } catch (_) {
    return null;
  }
}

/// 主 isolate 调用：把当前调度状态同步给 worker
Future<void> writeWorkerConfig(WorkerKeepAliveConfig config) async {
  try {
    final file = await _file(_configFile);
    await _writeJson(file, {
      'enabled': config.enabled,
      'writtenAt': DateTime.now().millisecondsSinceEpoch,
      'platforms': {
        for (final entry in config.platforms.entries)
          entry.key: {
            'enabled': entry.value.enabled,
            'next': entry.value.nextKeepAliveAt?.millisecondsSinceEpoch,
            'failures': entry.value.failureCount,
          },
      },
    });
  } catch (e) {
    debugPrint('[KeepAliveBridge] write config failed: $e');
  }
}

/// worker 调用：读取主 isolate 下发的配置；文件不存在/损坏时返回 null
Future<WorkerKeepAliveConfig?> readWorkerConfig() async {
  try {
    final file = await _file(_configFile);
    if (!await file.exists()) return null;
    final map = _decodeMap(await file.readAsString());
    if (map == null) return null;
    final rawPlatforms = map['platforms'];
    final platforms = <String, WorkerPlatformConfig>{};
    if (rawPlatforms is Map) {
      for (final entry in rawPlatforms.entries) {
        final value = entry.value;
        if (value is! Map) continue;
        platforms[entry.key.toString()] = WorkerPlatformConfig(
          enabled: value['enabled'] as bool? ?? true,
          nextKeepAliveAt: value['next'] is int
              ? DateTime.fromMillisecondsSinceEpoch(value['next'] as int)
              : null,
          failureCount: value['failures'] as int? ?? 0,
        );
      }
    }
    return WorkerKeepAliveConfig(
      enabled: map['enabled'] as bool? ?? true,
      platforms: platforms,
    );
  } catch (e) {
    debugPrint('[KeepAliveBridge] read config failed: $e');
    return null;
  }
}

/// worker 调用：写入本轮结果，供主 isolate 下次启动时合并。
///
/// 每次运行写独立文件，避免 App 长时间不打开时后一轮覆盖前一轮的结果。
Future<void> writeWorkerResults(List<WorkerHeartbeatResult> results) async {
  if (results.isEmpty) return;
  try {
    final name = '$_resultPrefix${DateTime.now().microsecondsSinceEpoch}.json';
    final file = await _file(name);
    await _writeJson(file, {
      'writtenAt': DateTime.now().millisecondsSinceEpoch,
      'results': results.map((r) => r.toJson()).toList(),
    });
  } catch (e) {
    debugPrint('[KeepAliveBridge] write results failed: $e');
  }
}

/// 主 isolate 调用：读出并删除所有 worker 结果文件（含旧版单文件）
Future<List<WorkerHeartbeatResult>> readAndClearWorkerResults() async {
  try {
    final dir =
        debugBridgeDirOverride ?? await getApplicationDocumentsDirectory();
    final files = <File>[];
    final legacy = File('${dir.path}/$_legacyResultFile');
    if (await legacy.exists()) files.add(legacy);
    if (await dir.exists()) {
      await for (final entity in dir.list()) {
        if (entity is File &&
            entity.uri.pathSegments.last.startsWith(_resultPrefix) &&
            entity.path.endsWith('.json')) {
          files.add(entity);
        }
      }
    }
    if (files.isEmpty) return const [];
    files.sort((a, b) => a.path.compareTo(b.path));

    final results = <WorkerHeartbeatResult>[];
    for (final file in files) {
      try {
        final map = _decodeMap(await file.readAsString());
        final raw = map?['results'];
        if (raw is List) {
          results.addAll(raw
              .whereType<Map>()
              .map((e) =>
                  WorkerHeartbeatResult.fromJson(Map<String, dynamic>.from(e)))
              .where((r) => r.platform.isNotEmpty && r.kind.isNotEmpty));
        }
        await file.delete();
      } catch (e) {
        debugPrint('[KeepAliveBridge] read result failed: $e');
      }
    }
    return results;
  } catch (e) {
    debugPrint('[KeepAliveBridge] read results failed: $e');
    return const [];
  }
}

/// worker 调用：读取 last-notified 去重表
Future<Map<String, DateTime>> readWorkerNotifiedAt() async {
  try {
    final file = await _file(_notifyFile);
    // 必须返回可变 Map：worker 会直接增删去重标记
    if (!await file.exists()) return <String, DateTime>{};
    final map = _decodeMap(await file.readAsString());
    if (map == null) return <String, DateTime>{};
    return {
      for (final entry in map.entries)
        if (entry.value is int)
          entry.key: DateTime.fromMillisecondsSinceEpoch(entry.value as int),
    };
  } catch (_) {
    return <String, DateTime>{};
  }
}

/// worker 调用：更新 last-notified 去重表
Future<void> writeWorkerNotifiedAt(Map<String, DateTime> notifiedAt) async {
  try {
    final file = await _file(_notifyFile);
    await _writeJson(file, {
      for (final entry in notifiedAt.entries)
        entry.key: entry.value.millisecondsSinceEpoch,
    });
  } catch (e) {
    debugPrint('[KeepAliveBridge] write notify mark failed: $e');
  }
}

/// 主 isolate 调用：清除某平台的 worker 失效提醒标记。
///
/// 前台心跳成功后调用，避免「重登后很快再次失效」被 worker 的 7 天窗口压掉。
Future<void> clearWorkerNotifiedAt(String platform) async {
  try {
    final current = await readWorkerNotifiedAt();
    if (!current.containsKey(platform)) return;
    current.remove(platform);
    await writeWorkerNotifiedAt(current);
  } catch (e) {
    debugPrint('[KeepAliveBridge] clear notify mark failed: $e');
  }
}

/// worker 调用：读取 worker 自己的保活闸门（主 isolate 从不写）
Future<Map<String, DateTime>> readWorkerGates() async {
  try {
    final file = await _file(_gateFile);
    // 必须返回可变 Map：worker 会写入本轮算出的下一次保活时间
    if (!await file.exists()) return <String, DateTime>{};
    final map = _decodeMap(await file.readAsString());
    if (map == null) return <String, DateTime>{};
    return {
      for (final entry in map.entries)
        if (entry.value is int)
          entry.key: DateTime.fromMillisecondsSinceEpoch(entry.value as int),
    };
  } catch (_) {
    return <String, DateTime>{};
  }
}

/// worker 调用：持久化自己的下次保活时间，避免 App 长期不打开时每 4 小时重发
Future<void> writeWorkerGates(Map<String, DateTime> gates) async {
  try {
    final file = await _file(_gateFile);
    await _writeJson(file, {
      for (final entry in gates.entries)
        entry.key: entry.value.millisecondsSinceEpoch,
    });
  } catch (e) {
    debugPrint('[KeepAliveBridge] write gate failed: $e');
  }
}
