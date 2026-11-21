/// 跨进程稳定的字符串哈希（纯 Dart）
///
/// Dart 的 `String.hashCode` 不保证跨 isolate / 进程稳定：通知 id 在主线程序列化，
/// 而取消 / 24h 提醒可能发生在冷启动后的新进程，用 `hashCode` 会算出不同 id，
/// 导致取消不到旧通知或同 id 覆盖别的包裹。这里用 FNV-1a，结果只依赖输入字节。
library;

/// FNV-1a 32 位哈希，返回非负 int。
///
/// [bits] 控制取低多少位（默认 27）。通知 id = base + 哈希，必须保证
/// 「到件 base + 最大哈希 < 提醒 base」，否则两个号段会重叠、互相覆盖。
/// 到件 base=1000000、提醒 base=200000000，27 位（最大 134217727）满足：
/// 1000000 + 134217727 = 135217727 < 200000000。
int stableHash32(String input, {int bits = 27}) {
  const int fnvPrime = 0x01000193;
  const int offsetBasis = 0x811c9dc5;
  var hash = offsetBasis;
  for (final unit in input.codeUnits) {
    hash ^= unit;
    // 保持在 32 位内，避免 Dart int 无限增长
    hash = (hash * fnvPrime) & 0xFFFFFFFF;
  }
  final mask = (1 << bits) - 1;
  return hash & mask;
}
