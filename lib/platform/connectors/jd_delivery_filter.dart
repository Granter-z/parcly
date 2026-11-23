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
///
/// 判定顺序：
/// 1. 结构/文案带即时配送标记 → 不是快递；
/// 2. `progressInfo.progressId=logistics` → 是快递；
/// 3. 活跃生命周期但尚未产生 progressInfo（如下单未发货、待出库）→ 先按快递保留，
///    否则新下单未发货的包裹会在详情出现前被静默丢掉。
/// 4. 其余（终态且无物流结构，如历史虚拟商品/已完成外卖单）→ 不是快递。
final RegExp _jdInstantMinutesReg = RegExp(r'预计\s*\d+\s*分钟|分钟送达|分钟达');

bool isJdCourierDelivery(Map<String, dynamic> item) {
  if (hasJdInstantDeliveryMarker(item)) return false;
  final progRaw = item['progressInfo'];
  final prog = progRaw is Map ? progRaw : null;

  // 骑手/即时配送文案：即使没有 progressInfo 也不是快递。
  final instantText =
      '${item['message'] ?? ''} ${item['messageTitle'] ?? ''} '
      '${prog?['content'] ?? ''} ${prog?['tip'] ?? ''}';
  if (looksLikeJdInstantDeliveryText(instantText)) return false;

  if ((prog?['progressId']?.toString() ?? '') == 'logistics') return true;

  // 活跃生命周期：不能因为没有 progressInfo 就丢单。
  final statusInfoRaw = item['orderStatusInfo'];
  final statusInfo = statusInfoRaw is Map ? statusInfoRaw : null;
  final status =
      '${statusInfo?['orderStatusName'] ?? ''} '
      '${item['orderStatusName'] ?? ''} ${item['orderStatus'] ?? ''}';
  const activeCn = [
    '待发货', '等待发货', '待出库', '待收货', '运输中', '派送中', '已出库', '正在出库',
  ];
  if (activeCn.any(status.contains)) return true;
  final s = status.toLowerCase();
  return s.contains('waitdeliver') ||
      s.contains('waitreceive') ||
      s.contains('shipping') ||
      s.contains('delivering');
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
  return _jdInstantMinutesReg.hasMatch(text);
}

bool _isTruthy(Object? value) {
  if (value is bool) return value;
  final s = value?.toString().toLowerCase() ?? '';
  return s == 'true' || s == '1';
}
