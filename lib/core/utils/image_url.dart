/// 图片 URL 规范化（纯 Dart）
///
/// 平台返回的商品图可能是协议相对地址（`//img.alicdn.com/...`），
/// 直接交给 Image.network 会加载失败；连接器写入与 UI 渲染兜底统一走这里。
String normalizeImageUrl(String raw) {
  final url = raw.trim();
  if (url.isEmpty) return url;
  return url.startsWith('//') ? 'https:$url' : url;
}
