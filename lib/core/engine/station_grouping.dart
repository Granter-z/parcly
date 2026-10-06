/// 首页「待取件」按驿站分组（P4，见 docs/pickup_app-界面.md 第 3 节）。
///
/// 纯 Dart，不依赖 Flutter，方便单测。
library;

import '../models/package.dart';
import '../models/package_status.dart';

/// 到站超过这个时长就标「快过期」。
const Duration nearlyOverdueAfter = Duration(days: 3);

/// 没有驿站信息时的组名。
const String unknownStationName = '未知驿站';

/// 一个驿站分组：显示名 + 组内包裹（到站从早到晚）。
class StationGroup {
  final String name;
  final List<Package> packages;

  const StationGroup({required this.name, required this.packages});

  /// 组里最早到站的时间，用来给组排序。
  DateTime get earliestArrival => arrivalTimeOf(packages.first);
}

/// 包裹到站时间：取状态历史里最后一次变成 arrived 的时间，没有就用 addedAt。
DateTime arrivalTimeOf(Package p) {
  for (final t in p.statusHistory.reversed) {
    if (t.to == PackageStatus.arrived) return t.timestamp;
  }
  return p.addedAt;
}

/// 到站超过 [nearlyOverdueAfter] 就算快过期。
bool isNearlyOverdue(Package p, DateTime now) =>
    now.difference(arrivalTimeOf(p)) > nearlyOverdueAfter;

/// 包裹的驿站显示名：优先 stationName，其次 location，都没有返回空串。
String stationLabelOf(Package p) {
  final s = (p.stationName ?? '').trim();
  if (s.isNotEmpty) return s;
  return p.location.trim();
}

/// 比较用的驿站名：去掉所有空白，全角字符转半角，英文转小写。
String normalizeStationName(String raw) {
  final buf = StringBuffer();
  for (final rune in raw.runes) {
    var c = rune;
    if (c == 0x3000) continue; // 全角空格
    if (c >= 0xFF01 && c <= 0xFF5E) c -= 0xFEE0; // 全角 ASCII → 半角
    final ch = String.fromCharCode(c);
    if (ch.trim().isEmpty) continue;
    buf.write(ch);
  }
  return buf.toString().toLowerCase();
}

/// 把待取件（status == arrived）的包裹按驿站分组。
///
/// - 规范化后同名的算同一个驿站，显示名用组里第一个出现的写法；
/// - 组内按到站时间从早到晚；
/// - 组按最早到站时间从早到晚（等得越久越靠前）；
/// - 没有驿站信息的放进「未知驿站」，永远排最后；
/// - 其他状态的包裹不参与分组。
List<StationGroup> groupPackagesByStation(List<Package> packages) {
  final named = <String, List<Package>>{};
  final labels = <String, String>{};
  final unknown = <Package>[];

  for (final p in packages) {
    if (p.status != PackageStatus.arrived) continue;
    final label = stationLabelOf(p);
    final key = normalizeStationName(label);
    if (key.isEmpty) {
      unknown.add(p);
      continue;
    }
    named.putIfAbsent(key, () => []).add(p);
    labels.putIfAbsent(key, () => label);
  }

  int byArrival(Package a, Package b) => arrivalTimeOf(a).compareTo(arrivalTimeOf(b));

  final groups = <StationGroup>[
    for (final e in named.entries)
      StationGroup(name: labels[e.key]!, packages: _stableSorted(e.value, byArrival)),
  ];
  // 稳定排序：最早到站相同的组保持出现顺序。
  final indexed = groups.asMap().entries.toList()
    ..sort((a, b) {
      final c = a.value.earliestArrival.compareTo(b.value.earliestArrival);
      return c != 0 ? c : a.key.compareTo(b.key);
    });
  final result = [for (final e in indexed) e.value];

  if (unknown.isNotEmpty) {
    result.add(StationGroup(name: unknownStationName, packages: _stableSorted(unknown, byArrival)));
  }
  return result;
}

List<Package> _stableSorted(List<Package> list, int Function(Package, Package) cmp) {
  final indexed = list.asMap().entries.toList()
    ..sort((a, b) {
      final c = cmp(a.value, b.value);
      return c != 0 ? c : a.key.compareTo(b.key);
    });
  return [for (final e in indexed) e.value];
}
