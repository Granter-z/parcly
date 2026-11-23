/// 纯 Dart 字符串安全截断工具（按 Unicode 码点截取，避免劈裂 UTF-16 代理对）。
library;

/// 按 Unicode 码点数（runes）截断 [text]，最多保留 [maxRunes] 个码点。
/// 若发生截断且指定了 [ellipsis]，在其后追加省略号。
String truncateRunes(String text, int maxRunes, {String ellipsis = ''}) {
  if (maxRunes <= 0) return ellipsis;
  final runes = text.runes;
  if (runes.length <= maxRunes) return text;
  return '${String.fromCharCodes(runes.take(maxRunes))}$ellipsis';
}
