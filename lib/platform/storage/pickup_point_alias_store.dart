/// 取件点别名表持久化（P28-d）
///
/// `alias → canonical` 多对一。生产默认空表：不把嘉豪样例写进 release。
/// 真机在设置「取件点合并」里声明。与 KeepAliveStore 一样用明文 Hive box。
library;

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

/// 别名表 Box 名称（main.dart 预打开）
const String kPickupPointAliasesBox = 'pickup_point_aliases';

class PickupPointAliasStore {
  static const String _boxName = kPickupPointAliasesBox;
  static const String _entriesKey = 'entries';
  static const int _schemaVersion = 1;

  Box? _box;

  /// 启动时预打开（main.dart）
  static Future<void> initialize() async {
    if (!Hive.isBoxOpen(_boxName)) {
      try {
        await Hive.openBox(_boxName);
      } catch (e) {
        debugPrint('[PickupPointAliasStore] open box failed: $e');
      }
    }
  }

  Box? get _safeBox {
    if (_box != null && _box!.isOpen) return _box;
    try {
      if (Hive.isBoxOpen(_boxName)) {
        _box = Hive.box(_boxName);
        return _box;
      }
    } catch (e) {
      debugPrint('[PickupPointAliasStore] safeBox: $e');
    }
    return null;
  }

  Future<void> _ensureInit() async {
    if (_safeBox != null) return;
    try {
      _box = Hive.isBoxOpen(_boxName)
          ? Hive.box(_boxName)
          : await Hive.openBox(_boxName);
    } catch (e) {
      debugPrint('[PickupPointAliasStore] ensureInit failed: $e');
    }
  }

  /// 当前全部别名（alias → canonical）。无数据时返回空 map。
  Map<String, String> readAll() {
    final box = _safeBox;
    if (box == null) return const {};
    final raw = box.get(_entriesKey);
    return _decode(raw);
  }

  Future<Map<String, String>> loadAll() async {
    await _ensureInit();
    return readAll();
  }

  /// 声明「[alias] 与 [canonical] 是同一取件点」。
  ///
  /// 若 alias 与 canonical 规范化后相同则忽略；会覆盖同 alias 的旧映射。
  Future<void> setAlias(String alias, String canonical) async {
    final a = alias.trim();
    final c = canonical.trim();
    if (a.isEmpty || c.isEmpty) return;
    await _ensureInit();
    final map = Map<String, String>.from(readAll());
    map[a] = c;
    await _persist(map);
  }

  /// 按别名原文精确删除一条。
  Future<void> removeAlias(String alias) async {
    final target = alias.trim();
    if (target.isEmpty) return;
    await _ensureInit();
    final map = Map<String, String>.from(readAll());
    map.remove(target);
    await _persist(map);
  }

  /// 用规范化键删除（设置页传入展示用的别名原文）。
  Future<void> removeAliasNormalized(
    String alias, {
    required String Function(String) normalize,
  }) async {
    final key = normalize(alias.trim());
    if (key.isEmpty) return;
    await _ensureInit();
    final map = Map<String, String>.from(readAll());
    map.removeWhere((k, _) => normalize(k) == key);
    await _persist(map);
  }

  Future<void> clear() async {
    await _ensureInit();
    await _persist({});
  }

  Future<void> ensureSchemaVersion() async {
    await _ensureInit();
    final box = _safeBox;
    if (box == null) return;
    if (box.get('schema_version') != _schemaVersion) {
      await box.put('schema_version', _schemaVersion);
    }
  }

  Future<void> _persist(Map<String, String> map) async {
    final box = _safeBox;
    if (box == null) return;
    final entries = [
      for (final e in map.entries) {'alias': e.key, 'canonical': e.value},
    ];
    await box.put(_entriesKey, entries);
  }

  static Map<String, String> _decode(Object? raw) {
    if (raw is! List) return const {};
    final out = <String, String>{};
    for (final item in raw) {
      if (item is Map) {
        final a = (item['alias'] ?? '').toString().trim();
        final c = (item['canonical'] ?? '').toString().trim();
        if (a.isNotEmpty && c.isNotEmpty) out[a] = c;
      }
    }
    return out;
  }
}
