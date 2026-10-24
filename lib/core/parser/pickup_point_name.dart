/// 快递取件点名提取（P28-c）。
///
/// 柜机 / 门店 / 代收 / 自提 / 驿站等凡能识别出取件位置，都写入
/// [Package.stationName]；分组键仍只用该字段，不用 location。
library;

/// 取件点名常见后缀（长词优先，避免「驿站」抢先匹配「菜鸟驿站」）。
const String kPickupPointSuffixPattern =
    r'(?:菜鸟驿站|妈妈驿站|兔喜生活|中通快递超市|韵达超市|多多驿站|'
    r'丰巢柜|丰巢|快递柜|自提柜|智能柜|快递超市|'
    r'自提点|代收点|服务点|服务站|'
    r'便利店|门店|超市|驿站)';

final RegExp _bracketReg = RegExp(
  '【([^【】]{2,40}$kPickupPointSuffixPattern)】',
);

final RegExp _afterVerbReg = RegExp(
  r'(?:暂存至|存放至|放至|放入|已放入|已到达|到达|已在|送至|投递至|已由|已派送至|派送至|存入|已送达)\s*'
  '([\\u4e00-\\u9fa5A-Za-z0-9（）()·\\-]{2,40}$kPickupPointSuffixPattern)',
);

final RegExp _looseSuffixReg = RegExp(
  '([\\u4e00-\\u9fa5A-Za-z0-9（）()·\\-]{2,40}$kPickupPointSuffixPattern)',
);

/// 从一段轨迹 / 物流正文取取件点显示名；取不到返回空串。
String extractPickupPointName(String text) {
  if (text.trim().isEmpty) return '';
  final b = _bracketReg.firstMatch(text);
  if (b != null) return b.group(1)!.trim();
  final v = _afterVerbReg.firstMatch(text);
  if (v != null) return v.group(1)!.trim();
  // 仅当文案里出现取件点信号时再宽松扫后缀，避免把转运中心当取件点
  if (_hasPickupSignal(text)) {
    final m = _looseSuffixReg.firstMatch(text);
    if (m != null) return m.group(1)!.trim();
  }
  return '';
}

bool _hasPickupSignal(String text) {
  const signals = [
    '驿站',
    '丰巢',
    '快递柜',
    '自提',
    '代收',
    '服务点',
    '服务站',
    '门店',
    '便利店',
    '超市',
    '柜',
    '兔喜',
  ];
  for (final s in signals) {
    if (text.contains(s)) return true;
  }
  return false;
}
