/// 取件点别名表 Riverpod（P28-d）
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/engine/station_grouping.dart';
import '../../platform/storage/pickup_point_alias_store.dart';

final pickupPointAliasStoreProvider = Provider<PickupPointAliasStore>((ref) {
  return PickupPointAliasStore();
});

/// 内存中的 alias → canonical；变更后首页分组立即刷新。
class PickupPointAliasNotifier extends StateNotifier<Map<String, String>> {
  PickupPointAliasNotifier(this._store) : super(const {}) {
    state = _store.readAll();
  }

  final PickupPointAliasStore _store;

  Future<void> reload() async {
    state = await _store.loadAll();
  }

  Future<void> setAlias(String alias, String canonical) async {
    await _store.setAlias(alias, canonical);
    state = Map<String, String>.from(_store.readAll());
  }

  Future<void> removeAlias(String alias) async {
    await _store.removeAliasNormalized(alias, normalize: normalizeStationName);
    state = Map<String, String>.from(_store.readAll());
  }
}

final pickupPointAliasesProvider =
    StateNotifierProvider<PickupPointAliasNotifier, Map<String, String>>((ref) {
  return PickupPointAliasNotifier(ref.watch(pickupPointAliasStoreProvider));
});

/// 合并时默认规范名：较长者优先；一样长则字典序靠后（稳定）。
String preferredCanonicalName(String a, String b) {
  final ta = a.trim();
  final tb = b.trim();
  if (ta.length != tb.length) return ta.length >= tb.length ? ta : tb;
  return ta.compareTo(tb) >= 0 ? ta : tb;
}
