/// 首页「待取件」按快递取件点分组（P4 / P28，见 docs/pickup_app-界面.md 第 3 节）。
///
/// 纯 Dart，不依赖 Flutter，方便单测。
library;

import '../models/package.dart';
import '../models/package_status.dart';

/// 到站超过这个时长就标「快过期」。
const Duration nearlyOverdueAfter = Duration(days: 3);

/// 没有取件点信息时的组名（P28：原「未知驿站」）。
const String unknownStationName = '未知取件点';

/// 旧版未知组文案，合并/分组时与 [unknownStationName] 同等对待，避免拆组。
const String legacyUnknownStationName = '未知驿站';

/// 是否为「未知取件点」标签（空串 / 新旧文案）。
bool isUnknownStationLabel(String? name) {
  final n = (name ?? '').trim();
  return n.isEmpty || n == unknownStationName || n == legacyUnknownStationName;
}

/// 一个取件点分组：显示名 + 组内包裹（到站从早到晚，不知道到站时间的排后面）。
class StationGroup {
  final String name;
  final List<Package> packages;

  const StationGroup({required this.name, required this.packages});

  /// 组里最早到站的时间，用来给组排序；组里都不知道到站时间时为 null。
  DateTime? get earliestArrival => arrivalTimeOf(packages.first);
}

/// 包裹真实的到站时间，不知道就返回 null。
///
/// 只读 [Package.arrivedAt]（P16）。绝不拿 addedAt 顶替：连接器每次同步都会刷新 addedAt。
DateTime? arrivalTimeOf(Package p) => p.arrivedAt;

/// 到站超过 [nearlyOverdueAfter] 就算快过期；不知道到站时间的不标。
bool isNearlyOverdue(Package p, DateTime now) {
  final arrived = arrivalTimeOf(p);
  return arrived != null && now.difference(arrived) > nearlyOverdueAfter;
}

/// 包裹的取件点组名：只用 stationName，没有返回空串（归进「未知取件点」）。
///
/// 不用 location：京东的 location 可能是收货地址，不能显示在首页（技术负责人 10-07 定）。
String stationLabelOf(Package p) => (p.stationName ?? '').trim();

/// 算不算「待取件」：已到达，或者还没完成但已经拿到取件码（和首页原来的排序口径一致）。
bool isAwaitingPickup(Package p) {
  if (p.status == PackageStatus.arrived) return true;
  return p.status.isPending && p.status != PackageStatus.pendingShipment && p.pickupCode.trim().isNotEmpty;
}

/// 比较用的取件点名：去掉所有空白，全角字符转半角，英文转小写。
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

/// 把待取件（见 [isAwaitingPickup]）的包裹按取件点分组。
///
/// - 规范化后同名的算同一个取件点，显示名用组里第一个出现的写法；
/// - 组内按到站时间从早到晚；
/// - 组按最早到站时间从早到晚（等得越久越靠前）；
/// - 没有取件点信息的放进「未知取件点」，永远排最后；
/// - 不是待取件的包裹不参与分组。
List<StationGroup> groupPackagesByStation(List<Package> packages) {
  final named = <String, List<Package>>{};
  final labels = <String, String>{};
  final unknown = <Package>[];

  for (final p in packages) {
    if (!isAwaitingPickup(p)) continue;
    final label = stationLabelOf(p);
    // 空串 / 「未知取件点」/ 旧「未知驿站」一律进未知组，避免字面量残留拆组（P28-b）
    if (isUnknownStationLabel(label)) {
      unknown.add(p);
      continue;
    }
    final key = normalizeStationName(label);
    if (key.isEmpty) {
      unknown.add(p);
      continue;
    }
    named.putIfAbsent(key, () => []).add(p);
    labels.putIfAbsent(key, () => label);
  }

  int byArrival(Package a, Package b) => _compareArrival(arrivalTimeOf(a), arrivalTimeOf(b));

  final groups = <StationGroup>[
    for (final e in named.entries)
      StationGroup(name: labels[e.key]!, packages: _stableSorted(e.value, byArrival)),
  ];
  // 稳定排序：最早到站相同的组保持出现顺序。
  final indexed = groups.asMap().entries.toList()
    ..sort((a, b) {
      final c = _compareArrival(a.value.earliestArrival, b.value.earliestArrival);
      return c != 0 ? c : a.key.compareTo(b.key);
    });
  final result = [for (final e in indexed) e.value];

  if (unknown.isNotEmpty) {
    result.add(StationGroup(name: unknownStationName, packages: _stableSorted(unknown, byArrival)));
  }
  return result;
}

/// 早的在前，不知道到站时间（null）的排最后。
int _compareArrival(DateTime? a, DateTime? b) {
  if (a == null) return b == null ? 0 : 1;
  if (b == null) return -1;
  return a.compareTo(b);
}

List<Package> _stableSorted(List<Package> list, int Function(Package, Package) cmp) {
  final indexed = list.asMap().entries.toList()
    ..sort((a, b) {
      final c = cmp(a.value, b.value);
      return c != 0 ? c : a.key.compareTo(b.key);
    });
  return [for (final e in indexed) e.value];
}

/// 「X天前到 / X小时前到 …」；[arrived] 不应为 null（调用方先判断）。
String arrivedAgoText(DateTime arrived, DateTime now) {
  final d = now.difference(arrived);
  if (d.isNegative || d.inMinutes < 1) return '刚到';
  if (d.inDays >= 1) return '${d.inDays}天前到';
  if (d.inHours >= 1) return '${d.inHours}小时前到';
  return '${d.inMinutes}分钟前到';
}

/// 到站时长文案；[arrivedAt] 为空时返回 null（不显示「X天前到」）。
String? arrivedAgoLabelOf(Package p, DateTime now) {
  final arrived = arrivalTimeOf(p);
  if (arrived == null) return null;
  return arrivedAgoText(arrived, now);
}
