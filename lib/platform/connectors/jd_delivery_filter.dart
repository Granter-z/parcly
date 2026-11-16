/// 京东快递（实物包裹）过滤器。
///
/// 只保留走传统物流的订单，其余（外卖/秒送/虚拟商品）一律过滤。
/// 判据是京东订单结构里的物流跟踪字段，而非商品文本：
/// 快递订单携带 progressInfo（progressId=logistics，指向 deal_wuliu 物流页），
/// 即时配送（specialDealList 含 isStore2Home）与虚拟商品没有该字段。
///
/// P45：部分秒送订单也会带 progressInfo=logistics，仅看 progressId 会漏，
/// 因此再加一道「即时配送结构标记 + 状态文案」兜底。
library;

/// 判断京东订单是否为快递包裹（有传统物流跟踪）。
bool isJdCourierDelivery(Map<String, dynamic> item) {
  if (hasJdInstantDeliveryMarker(item)) return false;
  final prog = item['progressInfo'] as Map<String, dynamic>?;
  return (prog?['progressId']?.toString() ?? '') == 'logistics';
}

/// 即时配送 / 外卖的结构标记。
bool hasJdInstantDeliveryMarker(Map<String, dynamic> item) {
  final deals = item['specialDealList'];
  if (deals is List) {
    for (final deal in deals) {
      if (deal is Map && _isTruthy(deal['isStore2Home'])) return true;
    }
  }

  final prog = item['progressInfo'];
  final detail = item['orderDetailLink'];
  final text = <String>[
    if (prog is Map) prog['progressLink']?.toString() ?? '',
    if (detail is Map) detail['url']?.toString() ?? '',
  ].join(' ').toLowerCase();
  return text.contains('store2home') ||
      text.contains('instant') ||
      text.contains('daojia');
}

/// 状态/进展文案里的即时配送信号（用于没有 JSON 结构的 DOM 兜底）。
///
/// 只检查状态与进展，不检查商品名——京东超市买的食品仍是快递包裹。
bool looksLikeJdInstantDeliveryText(String text) {
  const signals = ['骑手', '达达', '秒送', '京东到家', '小时达', '即时配送'];
  if (signals.any(text.contains)) return true;
  return RegExp(r'预计\s*\d+\s*分钟|分钟送达|分钟达').hasMatch(text);
}

bool _isTruthy(Object? value) {
  if (value is bool) return value;
  final s = value?.toString().toLowerCase() ?? '';
  return s == 'true' || s == '1';
}
