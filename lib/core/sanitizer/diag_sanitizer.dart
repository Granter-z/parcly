/// 诊断原始返回脱敏（纯 Dart，无 Flutter 依赖）
///
/// 用于「淘宝原始返回采集」落盘前的脱敏，规则：
/// - 手机号 → `1**********`：11 位连写、+86/86 前缀、空格/短横分隔、括号、全角数字、中间夹零宽字符都识别；
///   已部分打码的（如 `138****1111`）也统一换成 `1**********`；
///   mobile/phone 类字段按字段名整体打码，tel 类字段里有手机号时整体打码（座机号不处理，归 P15）
/// - 收件人姓名、地址类字段（按 JSON key 宽松识别）→ `***`；文本里「收件人：张三」这类显式标注也处理；
///   驿站 / 站点 / 门店 / 快递公司的名称和地址保留（包括 `station.address` 这类嵌套写法）
/// - 快递员 / 派送员姓名只留姓（`快递员张三丰` → `快递员张**`，courierName 类字段同理）
/// - 运单号、订单号（bizOrderId / orderId / mainOrderId / 订单列表 `mainOrders[].id`）保留前 4 位和后 4 位，
///   中间换成 `*`；同一文档内其它字符串里出现的同一号码一并替换
/// - 取件码保留格式、数字全部换成 9（`3-2-1002` → `9-9-9999`）
/// - Cookie / token / session / csrf / unb / userId 类字段 → `***`，不论出现在 JSON key、URL 参数（含 URL 编码的跳转地址）、
///   脚本变量、转义 JSON、Cookie 串还是隐藏表单 / meta 标签里
///
/// 字符串值本身是 JSON（如 mtop 的 `data.result`）时会递归解析脱敏后再编码回去。
/// 所有正则都按线性复杂度设计（不对同一段文本做嵌套回溯），1MB 输入在秒级以内。
library;

import 'dart:convert';

/// 一次脱敏过程中共享的上下文：已知的运单号 / 订单号原值，用于在其它字符串里同值替换
class _Ctx {
  final Set<String> ids = {};
  List<String>? _sorted;
  int minLen = 1 << 30;

  void add(String raw) {
    final v = raw.trim();
    if (v.length < 8 || v.contains('*')) return;
    if (ids.add(v)) {
      _sorted = null;
      if (v.length < minLen) minLen = v.length;
    }
  }

  List<String> get sorted => _sorted ??= (ids.toList()..sort((a, b) => b.length.compareTo(a.length)));
}

class DiagSanitizer {
  DiagSanitizer._();

  static const String masked = '***';
  static const String maskedPhone = '1**********';

  /// 递归处理 URL 编码 / 嵌套 URL 的最大层数
  static const int _maxDepth = 4;

  // ───────────────────────── 手机号 ─────────────────────────

  /// 前后都不是数字的 11 位连写手机号（sanitizeRaw 最后兜底用）
  static final RegExp _phoneReg = RegExp(r'(?<!\d)1[3-9]\d{9}(?!\d)');

  static const String _d = '[0-9０-９]';
  static const String _z = '[\u200B-\u200D\u2060\uFEFF]*';
  static const String _gap = '$_z(?:[ \\-－\u00A0\u3000]{1,2}|\\)[ \\-－]?)?$_z';

  /// 各种写法的手机号：+86/86/%2B86 前缀，3-4-4 分组之间可有空格/短横/右括号，任意两位之间可夹零宽字符，全角数字
  static final RegExp _phoneAnyReg = RegExp('(?<![0-9０-９])'
      '(?:(?:\\+|＋|%2[Bb])?$_z(?:86|８６)$_z[ \\-－]{0,2}$_z)?'
      '(?:[(（]$_z)?'
      '[1１]$_z[3-9３-９]$_z$_d$_gap'
      '$_d$_z$_d$_z$_d$_z$_d$_gap'
      '$_d$_z$_d$_z$_d$_z$_d'
      '(?![0-9０-９])');

  /// 已部分打码的手机号（138****1111、139*****22 等）
  static final RegExp _partialPhoneReg = RegExp(r'(?<![0-9０-９*])(?:(?:\+|＋)?86[ \-]?)?'
      r'[1１][3-9３-９][0-9０-９][ \-]?\*{3,6}[ \-]?[0-9０-９]{2,4}(?![0-9０-９*])');

  static final RegExp _mobileDigitsReg = RegExp(r'1[3-9]\d{9}');

  /// 原始数据里已部分遮挡的号码（如运单号 `YT12*******5678`）：露出的位数也去掉，整体换成 *
  static final RegExp _partialMaskedReg =
      RegExp(r'(?<![A-Za-z0-9*])[A-Za-z0-9]{2,8}\*{3,}[A-Za-z0-9]{2,8}(?![A-Za-z0-9*])');

  /// 原始数据里已部分遮挡的值：手机号统一成 `1**********`，其它（运单号等）整体换成 *。
  /// 只在处理原始输入时调用（在本脱敏器自己的前 4 后 4 打码之前），不会误伤自己的输出。
  static String _maskPrePartial(String s) {
    if (!s.contains('***')) return s;
    return s
        .replaceAll(_partialPhoneReg, maskedPhone)
        .replaceAllMapped(_partialMaskedReg, (m) => '*' * m.group(0)!.length);
  }

  /// 字符串里是否含手机号（任意写法，含部分打码）
  static bool _containsMobile(String v) {
    final half = v.replaceAllMapped(RegExp('[０-９]'), (m) => String.fromCharCode(m.group(0)!.codeUnitAt(0) - 0xFEE0));
    return _mobileDigitsReg.hasMatch(half.replaceAll(RegExp(r'\D'), '')) || _partialPhoneReg.hasMatch(v);
  }

  // ───────────────────────── 文本标注 ─────────────────────────

  /// 文本里「取件码 3-2-1002」这类写法
  static final RegExp _codeInTextReg =
      RegExp(r'((?:取件码|提货码|取货码|凭码|货架码)[:：\s]*)([A-Za-z0-9\-]+)');

  /// 文本里独立出现的货架码形态（如 16-1-7002），前后不能紧挨数字或连字符，避免误伤日期
  static final RegExp _shelfInTextReg =
      RegExp(r'(?<![\d\-])\d{1,3}-\d{1,3}-\d{2,5}(?![\d\-])');

  static const String _cjk = r'[\u4e00-\u9fff\u3400-\u4dbf\u{20000}-\u{3134F}]';

  /// 文本里「收件人：张三」这类显式标注的人名（无标注的人名无法可靠识别，不处理）；
  /// 支持带间隔号的长名和扩展区汉字
  static final RegExp _personInTextReg = RegExp(
      '((?:收件人|收货人|签收人|联系人|寄件人)[:：]\\s*)($_cjk{1,6}(?:[·•・]$_cjk{1,8})*)',
      unicode: true);

  /// 文本里「快递员王小明」「派送员：李大伟」「小哥赵四」：名字只留姓
  static final RegExp _courierInTextReg = RegExp(
      '(快递小哥|快递员|派送员|配送员|派件员|收派员|送货员|小哥)([:：]?[ \\t]*)($_cjk{1,4})',
      unicode: true);

  /// 名字后面常见的动词 / 词语：遇到就认为名字结束
  static const _courierStopWords = [
    '正在', '已经', '将会', '电话', '手机', '联系', '派件', '派送', '配送', '送货', '为您', '给您', '马上', '稍后',
    '今天', '明天', '预计', '揽收', '揽件', '取件', '上门', '收件', '签收', '已签', '已派', '已到', '已送', '已取',
    '会在', '会把', '请您', '您的', '将在', '正派',
  ];
  static const _courierStopChars = {'已', '将', '的', '了', '您', '请', '在', '于', '正', '会'};

  /// 文本里「运单号 YT1234567890」/ URL 参数 mailNo=xxx 这类写法
  static final RegExp _mailNoInTextReg = RegExp(
      r'((?:运单号|快递单号|物流单号|单号|mailNo|mailno|waybillNo)[:：=\s"]*)([A-Za-z0-9]{8,})');

  // ───────────────────────── 结构化片段 ─────────────────────────

  static final RegExp _urlReg = RegExp(r'''https?://[^\s"'<>\\]+''');

  /// URL 编码过的一段（至少含一个 %XX），只在段首开始匹配，保证线性
  static final RegExp _pctRunReg =
      RegExp(r'(?<![A-Za-z0-9_.~+\-%])[A-Za-z0-9_.~+\-]*(?:%[0-9A-Fa-f]{2}[A-Za-z0-9_.~+\-]*)+');

  /// 表单 input / meta 标签（`[^<>]` 保证遇到下一个 `<` 就停，线性）
  static final RegExp _formTagReg = RegExp(r'<(?:input|meta)\b[^<>]*>', caseSensitive: false);
  static final RegExp _attrReg =
      RegExp(r'''([A-Za-z_:][\w:.\-]*)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'<>`]+))''');

  /// 脚本里转义过的 JSON 字段：`\"_m_h5_tk\":\"xxx\"`
  static final RegExp _escapedKvReg =
      RegExp(r'(\\+")([A-Za-z_][\w\-]*)(\\+"\s*:\s*\\+")((?:[^"\\]|\\+[^"\\])*)(\\+")');

  /// 无引号值：`name=value` / `name: value` / Cookie 串里的 `k=v`
  static final RegExp _bareKvReg = RegExp(
      r'''(?<![\w\-])(\\*["']?)([A-Za-z_][\w\-]*)\1(\s*[:=]\s*)([^"'&;,\s<>(){}\[\]\\]+)''');

  /// 有引号值：`"name":"value"` / `name='value'` / `name: "value"`（值内支持反斜杠转义）
  static final RegExp _quotedKvReg = RegExp(
      r'''(?<![\w\-])(["']?)([A-Za-z_][\w\-]*)\1(\s*[:=]\s*)(?:"((?:[^"\\]|\\.)*)"|'((?:[^'\\]|\\.)*)')''');

  static final RegExp _alnumRunReg = RegExp(r'[A-Za-z0-9]+');

  // ───────────────────────── 入口 ─────────────────────────

  /// 把一段原始返回（可能是 JSONP、JSON 或无法解析的文本）脱敏后返回可落盘的字符串。
  ///
  /// 能解析为 JSON 时输出格式化后的 JSON；不能解析时按文本规则脱敏，
  /// 并包成 `{"_unparsed": true, "raw": "..."}` 便于后续工具统一按 JSON 读。
  static String sanitizeRaw(String raw) {
    final body = _stripJsonp(raw);
    Object? decoded;
    try {
      decoded = jsonDecode(body);
    } catch (_) {
      decoded = null;
    }
    String out;
    if (decoded is Map || decoded is List) {
      out = const JsonEncoder.withIndent('  ').convert(sanitizeJson(decoded));
    } else {
      out = const JsonEncoder.withIndent('  ')
          .convert({'_unparsed': true, 'raw': _sanitizeUnparsedText(body)});
    }
    // 兜底：编码后的整段文本再过一遍手机号
    return out.replaceAll(_phoneReg, maskedPhone);
  }

  /// 对已解码的 JSON 结构做脱敏，返回新结构（不修改入参）。
  static dynamic sanitizeJson(dynamic node) {
    final ctx = _Ctx();
    _collectIds(node, null, ctx);
    return _walk(node, null, ctx);
  }

  /// 对普通字符串做文本级脱敏：URL、凭据字段、手机号、人名、取件码、运单号 / 订单号。
  static String sanitizeText(String text, [Set<String> knownMailNos = const {}]) {
    if (text.isEmpty) return text;
    final ctx = _Ctx();
    for (final m in knownMailNos) {
      ctx.add(m);
    }
    return _free(text, ctx);
  }

  /// HTML 片段默认保留的长度（字符）
  static const int htmlSnippetLength = 4096;

  /// 先对页面头部这么多字符做完整脱敏，再截 [htmlSnippetLength]，避免截断边界切在敏感值中间导致正则匹配不上
  static const int htmlSanitizeWindow = 262144;

  /// SSR 页面找不到数据标记时（页面改版 / 跳登录页）的落盘内容：
  /// `{url, title, status, length, snippet, text}`。
  ///
  /// - url：query 里的 token/sid/cookie 类参数值置 ***，订单号/运单号类参数保留前 4 后 4，其余参数值做文本脱敏；
  /// - title：`<title>` 文本；
  /// - snippet：页面源码脱敏后的前 [htmlSnippetLength] 字符；
  /// - text：去掉 script/style/标签后的可见文本，脱敏后的前 [htmlSnippetLength] 字符；
  /// - snippet/text 都是先对头部 [htmlSanitizeWindow] 字符（不足则全文）做完整脱敏再截断；
  ///   截断后末尾若残留未闭合的敏感字段（如 `"_m_h5_tk":"xxx`），残值也置为 ***。
  static Map<String, dynamic> sanitizeHtmlPage({required String url, required String html, int? statusCode}) {
    final ctx = _Ctx();
    final cleanUrl = _sanitizeUrl(url, ctx, 0);
    final head = html.length > htmlSanitizeWindow ? html.substring(0, htmlSanitizeWindow) : html;
    final title = _extractTitle(head);
    final visible = _stripTags(_removeBlocks(_removeBlocks(head, 'script'), 'style'))
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return {
      'url': cleanUrl,
      'title': _sanitizeHtmlText(title, ctx),
      if (statusCode != null) 'status': statusCode,
      'length': html.length,
      'snippet': _truncateSanitized(_sanitizeHtmlText(head, ctx)),
      'text': _truncateSanitized(_sanitizeHtmlText(visible, ctx)),
    };
  }

  /// `<title ...>…</title>` 的文本；没有闭合标签时返回空串（indexOf 实现，线性）
  static String _extractTitle(String html) {
    final lower = html.toLowerCase();
    final start = lower.indexOf('<title');
    if (start == -1) return '';
    final gt = lower.indexOf('>', start);
    if (gt == -1) return '';
    final end = lower.indexOf('</title', gt + 1);
    if (end == -1) return '';
    return html.substring(gt + 1, end).trim();
  }

  /// 去掉 `<tag …>…</tag>` 块；没有闭合时一直删到结尾（浏览器也这样处理未闭合的 script）。线性。
  static String _removeBlocks(String html, String tag) {
    final lower = html.toLowerCase();
    final open = '<$tag';
    final close = '</$tag';
    final sb = StringBuffer();
    var pos = 0;
    while (true) {
      final s = lower.indexOf(open, pos);
      if (s == -1) break;
      sb.write(html.substring(pos, s));
      sb.write(' ');
      final e = lower.indexOf(close, s + open.length);
      if (e == -1) {
        pos = html.length;
        break;
      }
      final gt = lower.indexOf('>', e);
      pos = gt == -1 ? html.length : gt + 1;
    }
    if (pos < html.length) sb.write(html.substring(pos));
    return sb.toString();
  }

  /// 去标签：`[^<>]` 让每次尝试最多扫到下一个 `<`，整体线性（原 `<[^>]+>` 在大量 `<` 无 `>` 时是平方复杂度）
  static String _stripTags(String s) => s.replaceAll(RegExp(r'<[^<>]*>'), ' ');

  /// 截到 [htmlSnippetLength]，并处理末尾残留的未闭合敏感字段
  static String _truncateSanitized(String sanitized) {
    final cut = sanitized.length > htmlSnippetLength ? sanitized.substring(0, htmlSnippetLength) : sanitized;
    return _maskTrailingResidue(cut);
  }

  static final RegExp _trailingKeyReg = RegExp(r'''(?<![\w\-])(\\*["']?)([A-Za-z_][\w\-]*)\1\s*[:=]\s*\\*$''');
  static final RegExp _trailingBareReg =
      RegExp(r'''(?<![\w\-])(["']?)([A-Za-z_][\w\-]*)\1(\s*[:=]\s*)([^"'&;,\s<>]+)$''');

  /// 文本末尾以「敏感 key + 分隔符 + 未闭合的值」结尾时，把残值换成 ***
  static String _maskTrailingResidue(String s) {
    // ① 引号值：最后一个引号是左引号、前面紧挨着「敏感 key + 分隔符」（不限残值长度）
    final q = s.lastIndexOf(RegExp(r'''["']'''));
    if (q != -1) {
      final value = s.substring(q + 1);
      final before = s.substring(q - 200 < 0 ? 0 : q - 200, q);
      final m = _trailingKeyReg.firstMatch(before);
      if (m != null && value.isNotEmpty && !RegExp(r'^\**$').hasMatch(value) && _isSensitiveKey(_norm(m.group(2)!))) {
        return '${s.substring(0, q + 1)}$masked';
      }
    }
    // ② 无引号值：只看末尾 1KB
    final offset = s.length > 1024 ? s.length - 1024 : 0;
    final m = _trailingBareReg.firstMatch(s.substring(offset));
    if (m != null) {
      final value = m.group(4)!;
      if (!RegExp(r'^\**$').hasMatch(value) && _isSensitiveKey(_norm(m.group(2)!))) {
        return '${s.substring(0, offset + m.end - value.length)}$masked';
      }
    }
    return s;
  }

  /// URL 脱敏：凭据类参数值置 ***，订单号/运单号类参数保留前 4 后 4，手机号参数打码，
  /// 其余参数值（含 URL 编码的跳转地址）递归做文本脱敏。被打码的订单号原值会加入 [idValuesOut]。
  static String sanitizeUrl(String url, [Set<String>? idValuesOut]) {
    final ctx = _Ctx();
    final out = _sanitizeUrl(url, ctx, 0);
    idValuesOut?.addAll(ctx.ids);
    return out;
  }

  static String _sanitizeUrl(String url, _Ctx ctx, int depth) {
    final qIdx = url.indexOf('?');
    if (qIdx == -1) {
      final h = url.indexOf('#');
      if (h == -1) return _textLevel(url, ctx);
      return '${_textLevel(url.substring(0, h), ctx)}${_free(url.substring(h), ctx, depth: depth + 1, skipUrls: true)}';
    }
    final base = url.substring(0, qIdx);
    var query = url.substring(qIdx + 1);
    var fragment = '';
    final hashIdx = query.indexOf('#');
    if (hashIdx != -1) {
      fragment = query.substring(hashIdx);
      query = query.substring(0, hashIdx);
    }
    final parts = query.split('&').map((pair) {
      final eq = pair.indexOf('=');
      if (eq <= 0) return pair;
      final key = pair.substring(0, eq);
      final value = pair.substring(eq + 1);
      if (value.isEmpty) return pair;
      var rawKey = key.startsWith('amp;') ? key.substring(4) : key;
      try {
        rawKey = Uri.decodeQueryComponent(rawKey);
      } catch (_) {}
      final k = _norm(rawKey);
      String decoded;
      try {
        decoded = Uri.decodeQueryComponent(value);
      } catch (_) {
        decoded = value;
      }
      if (_isMailNoKey(k) || _isOrderIdKey(k, null) || k == 'id' || k == 'bizid') {
        ctx.add(value);
        ctx.add(decoded);
        return '$key=${maskMailNo(value)}';
      }
      if (_isCredentialKey(k) || const {'sign', 'auth', 'authcode', 'code', 'st', 'sn'}.contains(k)) {
        return '$key=$masked';
      }
      if (_isPhoneKey(k) || (_isTelKey(k) && _containsMobile(decoded))) return '$key=$maskedPhone';
      if (_isCourierNameKey(k, null)) return '$key=${Uri.encodeQueryComponent(_maskSurname(decoded))}';
      if (_isPersonOrAddressKey(k, null)) return '$key=$masked';
      if (_isPickupCodeKey(k)) return '$key=${maskPickupCode(value)}';
      if (depth >= _maxDepth) return '$key=${_textLevel(value, ctx)}';
      if (decoded != value) {
        final clean = _free(decoded, ctx, depth: depth + 1);
        return clean == decoded ? pair : '$key=${Uri.encodeComponent(clean)}';
      }
      return '$key=${_free(value, ctx, depth: depth + 1)}';
    }).join('&');
    final cleanFragment = fragment.isEmpty ? '' : _free(fragment, ctx, depth: depth + 1, skipUrls: true);
    return '${_textLevel(base, ctx)}?$parts$cleanFragment';
  }

  static String _sanitizeHtmlText(String text, _Ctx ctx) {
    if (text.isEmpty) return text;
    _precollect(text, ctx);
    return _free(text, ctx);
  }

  /// 运单号 / 订单号：保留前 4 位和后 4 位，中间换成 *；不足 9 位全部换成 *。
  static String maskMailNo(String v) {
    final s = v.trim();
    if (s.isEmpty) return s;
    if (s.length <= 8) return '*' * s.length;
    return '${s.substring(0, 4)}${'*' * (s.length - 8)}${s.substring(s.length - 4)}';
  }

  /// 取件码：保留格式，数字全部换成 9。
  static String maskPickupCode(String v) => v.replaceAll(RegExp(r'\d'), '9');

  /// 只留第一个字（姓），其余换成 *
  static String _maskSurname(String v) {
    final runes = v.trim().runes.toList();
    if (runes.length <= 1) return v.trim();
    return '${String.fromCharCode(runes.first)}${'*' * (runes.length - 1)}';
  }

  // ───────────────────────── 自由文本 ─────────────────────────

  /// 任意字符串的完整脱敏（JSON 字符串值、无法解析的文本、HTML 都走这里）
  static String _free(String input, _Ctx ctx, {int depth = 0, bool skipUrls = false}) {
    if (input.isEmpty) return input;
    // ⓪ 原始数据里已部分遮挡的手机号 / 运单号
    var s = _maskPrePartial(input);
    // ① 内嵌 URL（接口地址、跳转地址）按 URL 规则处理
    if (!skipUrls && depth < _maxDepth && s.contains('://')) {
      s = s.replaceAllMapped(_urlReg, (m) => _sanitizeUrl(m.group(0)!, ctx, depth + 1));
    }
    // ② URL 编码的片段（如 redirect=https%3A%2F%2F…%3Ftoken%3D…）：解码后递归脱敏，有变化再编码回去
    if (depth < _maxDepth && s.contains('%')) {
      s = s.replaceAllMapped(_pctRunReg, (m) => _pctRun(m.group(0)!, ctx, depth));
    }
    // ③ 隐藏表单 input / meta：按 name 判断，打的是 value / content
    if (s.contains('<')) {
      s = s.replaceAllMapped(_formTagReg, (m) => _formTag(m.group(0)!));
    }
    // ④ 转义 JSON 字段
    if (s.contains('\\')) {
      s = s.replaceAllMapped(_escapedKvReg, (m) {
        final nv = _maskKv(_norm(m.group(2)!), m.group(4)!);
        if (nv == null) return m.group(0)!;
        return '${m.group(1)}${m.group(2)}${m.group(3)}$nv${m.group(5)}';
      });
    }
    if (s.contains(':') || s.contains('=')) {
      // ⑤ 无引号值（Cookie 串、脚本赋值、URL 参数）
      s = _bareKv(s, 1);
      // ⑥ 有引号值
      s = s.replaceAllMapped(_quotedKvReg, (m) {
        final quote = m.group(4) != null ? '"' : "'";
        final value = m.group(4) ?? m.group(5) ?? '';
        final nv = _maskKv(_norm(m.group(2)!), value);
        if (nv == null) return m.group(0)!;
        return '${m.group(1)}${m.group(2)}${m.group(1)}${m.group(3)}$quote$nv$quote';
      });
    }
    // ⑦ 文本级：同值替换、手机号、人名、运单号、取件码
    return _textLevel(s, ctx);
  }

  static String _bareKv(String s, int level) => s.replaceAllMapped(_bareKvReg, (m) {
        final value = m.group(4)!;
        final nv = _maskKv(_norm(m.group(2)!), value);
        if (nv != null) return '${m.group(1)}${m.group(2)}${m.group(1)}${m.group(3)}$nv';
        // 普通 key 的值里还夹着 k=v（如 ext=unb=…）时再看一层
        if (level > 0 && (value.contains('=') || value.contains(':'))) {
          final inner = _bareKv(value, level - 1);
          if (inner != value) return '${m.group(1)}${m.group(2)}${m.group(1)}${m.group(3)}$inner';
        }
        return m.group(0)!;
      });

  static String _pctRun(String run, _Ctx ctx, int depth) {
    String decoded;
    try {
      decoded = Uri.decodeComponent(run);
    } catch (_) {
      return run;
    }
    if (decoded == run) return run;
    final clean = _free(decoded, ctx, depth: depth + 1);
    return clean == decoded ? run : Uri.encodeComponent(clean);
  }

  static String _formTag(String tag) {
    String? field;
    for (final m in _attrReg.allMatches(tag)) {
      final a = m.group(1)!.toLowerCase();
      if (a == 'name' || a == 'id' || a == 'property' || a == 'http-equiv') {
        field ??= m.group(2) ?? m.group(3) ?? m.group(4);
      }
    }
    if (field == null) return tag;
    final k = _norm(field);
    return tag.replaceAllMapped(_attrReg, (m) {
      final a = m.group(1)!.toLowerCase();
      if (a != 'value' && a != 'content') return m.group(0)!;
      final v = m.group(2) ?? m.group(3) ?? m.group(4) ?? '';
      final nv = _maskKv(k, v);
      if (nv == null) return m.group(0)!;
      final q = m.group(2) != null ? '"' : (m.group(3) != null ? "'" : '');
      return '${m.group(1)}=$q$nv$q';
    });
  }

  /// 文本里 `key: value` 的打码决定；返回 null 表示不处理
  static String? _maskKv(String k, String v) {
    if (v.isEmpty || RegExp(r'^\**$').hasMatch(v)) return null;
    if (_isMailNoKey(k) || _isOrderIdKey(k, null)) {
      // 含 * 的是已经打过码的（第⓪步或 URL 那一步处理过），不再重复
      if (v.contains('*')) return null;
      return v.length >= 6 ? maskMailNo(v) : null;
    }
    if (_isCredentialKey(k)) return masked;
    if (_isCourierNameKey(k, null)) return _maskSurname(v);
    if (_isPersonOrAddressKey(k, null)) {
      // HTML 属性 name="_tb_token_"、组件名 name="logistics_detail_h5" 这类机器标识不是人名，保留便于诊断
      if (k == 'name' && _isMachineName(v)) return null;
      return masked;
    }
    if (_isPhoneKey(k)) return maskedPhone;
    if (_isTelKey(k) && _containsMobile(v)) return maskedPhone;
    if (_isPickupCodeKey(k)) return maskPickupCode(v);
    return null;
  }

  /// 文本级脱敏（不再识别 URL / key-value）
  static String _textLevel(String input, _Ctx ctx) {
    if (input.isEmpty) return input;
    var s = _replaceKnown(input, ctx);
    s = s.replaceAll(_phoneAnyReg, maskedPhone);
    s = s.replaceAll(_partialPhoneReg, maskedPhone);
    s = s.replaceAllMapped(_personInTextReg, (m) => '${m.group(1)}$masked');
    s = s.replaceAllMapped(_courierInTextReg, _maskCourierMatch);
    s = s.replaceAllMapped(
        _mailNoInTextReg, (m) => '${m.group(1)}${maskMailNo(m.group(2)!)}');
    s = s.replaceAllMapped(
        _codeInTextReg, (m) => '${m.group(1)}${maskPickupCode(m.group(2)!)}');
    s = s.replaceAllMapped(_shelfInTextReg, (m) => maskPickupCode(m.group(0)!));
    return s;
  }

  static String _maskCourierMatch(Match m) {
    final cand = m.group(3)!;
    final chars = cand.runes.map(String.fromCharCode).toList();
    var cut = chars.length;
    for (var i = 0; i < chars.length; i++) {
      final rest = chars.sublist(i).join();
      if (_courierStopWords.any(rest.startsWith) || (i == 0 || i >= 2) && _courierStopChars.contains(chars[i])) {
        cut = i;
        break;
      }
    }
    if (cut <= 1) return m.group(0)!; // 后面不是名字（如「快递员正在派件」）或只有姓
    return '${m.group(1)}${m.group(2)}${chars.first}${'*' * (cut - 1)}${chars.sublist(cut).join()}';
  }

  /// 已知运单号 / 订单号同值替换：按字母数字段查表，段比已知值长时才逐个 contains
  static String _replaceKnown(String s, _Ctx ctx) {
    if (ctx.ids.isEmpty || s.length < ctx.minLen) return s;
    return s.replaceAllMapped(_alnumRunReg, (m) {
      final run = m.group(0)!;
      if (run.length < ctx.minLen) return run;
      if (ctx.ids.contains(run)) return maskMailNo(run);
      if (run.length == ctx.minLen) return run;
      var out = run;
      for (final v in ctx.sorted) {
        if (v.length < run.length && out.contains(v)) out = out.replaceAll(v, maskMailNo(v));
      }
      return out;
    });
  }

  /// 文本里 `"mailNo":"…"` / `orderId: …` 的原值先收集起来，供同值替换
  static void _precollect(String text, _Ctx ctx) {
    for (final m in _quotedKvReg.allMatches(text)) {
      final k = _norm(m.group(2)!);
      if (_isMailNoKey(k) || _isOrderIdKey(k, null) || _isAccountIdKey(k, null)) ctx.add(m.group(4) ?? m.group(5) ?? '');
    }
    for (final m in _bareKvReg.allMatches(text)) {
      final k = _norm(m.group(2)!);
      if (_isMailNoKey(k) || _isOrderIdKey(k, null) || _isAccountIdKey(k, null)) ctx.add(m.group(4)!);
    }
    // 转义 JSON 里的（页面脚本常见）
    if (text.contains('\\')) {
      for (final m in _escapedKvReg.allMatches(text)) {
        final k = _norm(m.group(2)!);
        if (_isMailNoKey(k) || _isOrderIdKey(k, null) || _isAccountIdKey(k, null)) ctx.add(m.group(4)!);
      }
    }
  }

  // ───────────────────────── key 识别 ─────────────────────────

  static String _norm(String key) =>
      key.toLowerCase().replaceAll(RegExp(r'[_\-\s]'), '');

  static const _secretKeyParts = ['cookie', 'token', 'mh5tk', 'session', 'password', 'passwd', 'authorization'];

  /// 凭据 / 账号标识类字段名（已 _norm）。JSON、URL、脚本、表单共用这一份。
  static const _credentialKeys = {
    'sid', 'unb', 'munb', 'sgcookie', 'cookie2', 'tbtoken', 'mh5tk', 'mh5tkenc', 'cna', 'isg', 'tfstk',
    'umidtoken', 'lgc', 'tracknick', 'uc1', 'uc3', 'uc4', 'skt', 'dnk', 'existshop', 'nk',
    'uid', 'userid', 'buyerid', 'sellerid', 'havanaid', 'alipayuserid', 'usernumberid',
  };

  static const _mailNoKeys = {
    'mailno', 'mailnumber', 'waybillno', 'waybill', 'waybillnumber', 'waybillcode',
    'trackingno', 'trackingnumber', 'trackno', 'expressno', 'logisticsno',
    'logisticno', 'outsid', 'cpmailno',
  };

  static const _pickupCodeKeys = {
    'takecode', 'fetchcode', 'pickupcode', 'shelfcode', 'pickcode', 'pickupno',
    'takeno', 'fetchno', 'codevalue', 'pickupcodetext', 'verifycode', 'ticketcode',
    'pickcodetext', 'fetchnum', 'takecodetext', 'fetchcodetext',
  };

  /// 「人名」类 key 的修饰词：与 name/nick 同时出现即视为人名
  static const _personParts = [
    'receiver', 'consignee', 'recipient', 'buyer', 'sender', 'contact', 'linkman',
    'customer', 'user', 'full', 'real', 'nick', 'member', 'owner', 'addressee',
  ];

  static const _personExactKeys = {
    'name', 'fullname', 'realname', 'nick', 'nickname', 'receiver', 'consignee',
    'recipient', 'linkman', 'contact', 'contactname', 'addressee',
  };

  /// 非人名的 name 字段（快递公司、驿站、商品等，解析需要，保留）
  static const _businessParts = [
    'company', 'cp', 'express', 'station', 'site', 'shop', 'seller', 'store', 'item',
    'goods', 'sku', 'brand', 'logistic', 'tag', 'status', 'label', 'icon', 'button',
    'action', 'tab', 'title', 'node', 'stage', 'service', 'courier', 'delivery',
    'point', 'cabinet', 'locker', 'biz', 'template', 'component', 'module', 'file',
    'event', 'page', 'app', 'api', 'class', 'type', 'cate', 'prop', 'spec',
  ];

  static const _addressParts = [
    'address', 'addr', 'street', 'town', 'village', 'community', 'building',
    'doorplate', 'houseno', 'housenumber', 'roomno',
  ];

  /// 驿站、站点、门店、快递公司：它们的地址不是个人信息
  static const _placeParts = ['station', 'site', 'shop', 'store', 'company', 'cabinet', 'locker'];

  /// 快递员 / 派送员
  static const _courierParts = ['courier', 'deliveryman', 'deliverer', 'postman', 'expressman', 'dispatcher'];

  static bool _containsAny(String s, List<String> parts) => parts.any(s.contains);

  /// 账号 id 类字段（买家 / 卖家 / 用户 id、unb，以及 seller.id 这类父 key 是账号对象的 id）：
  /// 值按凭据置 ***，同时收集原值，在同一文档其它位置（店铺链接、图片路径等）同值替换
  static bool _isAccountIdKey(String k, String? parentKey) =>
      const {'unb', 'munb', 'uid', 'userid', 'buyerid', 'sellerid', 'havanaid', 'usernumberid'}.contains(k) ||
      k.endsWith('userid') ||
      k.endsWith('buyerid') ||
      k.endsWith('sellerid') ||
      (k == 'id' && parentKey != null && _containsAny(parentKey, const ['seller', 'buyer', 'user', 'shop']));

  /// `name` 字段的值是不是机器标识（组件名、字段名），而不是人名：
  /// 小写字母开头、由 `_` `-` `.` 分段（如 `logistics_detail_h5`），或本身就是敏感字段名（如 `_tb_token_`）
  static bool _isMachineName(String v) =>
      RegExp(r'^[a-z][a-z0-9]*(?:[_\-.][A-Za-z0-9]+)+$').hasMatch(v) ||
      (RegExp(r'^[A-Za-z_][\w\-]*$').hasMatch(v) && _isSensitiveKey(_norm(v)));

  /// `name` 所在对象的父 key 是人名上下文（收件人、买家等）
  static bool _isPersonContext(String parentKey) =>
      _containsAny(parentKey, _personParts) || _personExactKeys.contains(parentKey);

  static bool _isCredentialKey(String k) =>
      _credentialKeys.contains(k) ||
      _containsAny(k, _secretKeyParts) ||
      k.endsWith('sid') ||
      k.contains('csrf') ||
      k.contains('xsrf') ||
      k.contains('userid') ||
      k.contains('buyerid') ||
      k.contains('sellerid') ||
      (k.contains('ticket') && !_isPickupCodeKey(k));

  static bool _isMailNoKey(String k) =>
      _mailNoKeys.contains(k) ||
      k.contains('mailno') ||
      (k.contains('waybill') && (k.endsWith('no') || k.endsWith('code') || k.endsWith('number')));

  /// 订单号字段；`id` 只在父 key 是订单类（如 mainOrders[].id）时算
  static bool _isOrderIdKey(String k, String? parentKey) =>
      k.contains('orderid') ||
      k.contains('orderno') ||
      k.contains('tradeid') ||
      k.contains('tradeno') ||
      (k == 'id' && parentKey != null && parentKey.contains('order'));

  static bool _isPickupCodeKey(String k) => _pickupCodeKeys.contains(k);

  static bool _isPhoneKey(String k) =>
      (k.contains('mobile') || k.contains('phone')) &&
      !_containsAny(k, const ['iphone', 'type', 'model', 'brand', 'version', 'system', 'platform', 'enable', 'flag', 'switch']);

  /// tel 类字段：只有值里有手机号时才打码（座机号不处理）
  static bool _isTelKey(String k) =>
      k == 'tel' ||
      (k.endsWith('tel') && !k.endsWith('hotel')) ||
      k.endsWith('telephone') ||
      k.endsWith('telno') ||
      k.endsWith('telnum');

  static bool _isCourierNameKey(String k, String? parentKey) {
    final hasName = k.contains('name') || k.contains('nick');
    if (!hasName) return false;
    if (_containsAny(k, const ['company', 'corp', 'cpname', 'station', 'site'])) return false;
    if (_containsAny(k, _courierParts)) return true;
    return k == 'name' && parentKey != null && _containsAny(parentKey, _courierParts) &&
        !_containsAny(parentKey, const ['company', 'corp']);
  }

  /// 人名/地址字段判断；parentKey 用于区分 `logisticCompany.name`、`station.address` 这类业务字段。
  static bool _isPersonOrAddressKey(String k, String? parentKey) {
    if (_containsAny(k, _addressParts)) {
      // 驿站、站点、门店、快递公司的地址不是个人信息，保留（解析驿站名要用）
      if (_containsAny(k, [..._placeParts, 'cp'])) return false;
      if (parentKey != null && (_containsAny(parentKey, _placeParts) || parentKey.startsWith('cp'))) return false;
      return true;
    }
    final hasName = k.contains('name') || k.contains('nick');
    if (hasName && _containsAny(k, _personParts)) return true;
    if (_personExactKeys.contains(k)) {
      if (k == 'name' && parentKey != null && _containsAny(parentKey, _businessParts)) {
        return false;
      }
      return true;
    }
    return false;
  }

  static bool _isSensitiveKey(String k) =>
      _isCredentialKey(k) ||
      _isPersonOrAddressKey(k, null) ||
      _isMailNoKey(k) ||
      _isOrderIdKey(k, null) ||
      _isPickupCodeKey(k) ||
      _isPhoneKey(k) ||
      _isTelKey(k);

  // ───────────────────────── 遍历 ─────────────────────────

  static void _collectIds(dynamic node, String? parentKey, _Ctx ctx) {
    if (node is Map) {
      node.forEach((rawKey, v) {
        final k = _norm(rawKey.toString());
        final isId = _isMailNoKey(k) || _isOrderIdKey(k, parentKey) || _isAccountIdKey(k, parentKey);
        if (isId && (v is String || v is num)) {
          ctx.add(v.toString());
        } else if (isId && v is List) {
          for (final e in v) {
            if (e is String || e is num) ctx.add(e.toString());
          }
        } else {
          _collectIds(v, k, ctx);
        }
      });
    } else if (node is List) {
      for (final v in node) {
        _collectIds(v, parentKey, ctx);
      }
    } else if (node is String) {
      final nested = _tryDecodeNested(node);
      if (nested != null) {
        _collectIds(nested, null, ctx);
      } else if (node.length > 8 && (node.contains(':') || node.contains('='))) {
        // 字符串里的脚本 / 转义 JSON / URL 参数（如页面片段里的 globalUTParams）
        _precollect(node, ctx);
      }
    }
  }

  static dynamic _walk(dynamic node, String? parentKey, _Ctx ctx) {
    if (node is Map) {
      final out = <String, dynamic>{};
      node.forEach((rawKey, v) {
        final key = rawKey.toString();
        out[key] = _sanitizeEntry(_norm(key), parentKey, v, ctx);
      });
      return out;
    }
    if (node is List) {
      return [for (final v in node) _walk(v, parentKey, ctx)];
    }
    return _sanitizeScalar(node, ctx);
  }

  static dynamic _sanitizeEntry(String k, String? parentKey, dynamic v, _Ctx ctx) {
    if (v == null || v is bool) return v;
    final isScalar = v is String || v is num;
    if (_isMailNoKey(k) || _isOrderIdKey(k, parentKey)) {
      if (isScalar) return _maskIdValue(v.toString());
      if (v is List) {
        return [for (final e in v) e is String || e is num ? _maskIdValue(e.toString()) : _walk(e, k, ctx)];
      }
      return _walk(v, k, ctx);
    }
    if (_isCredentialKey(k) || _isAccountIdKey(k, parentKey)) return _maskAllLeaves(v);
    if (_isCourierNameKey(k, parentKey)) {
      return v is String ? _maskSurname(v) : _maskAllLeaves(v);
    }
    if (_isPersonOrAddressKey(k, parentKey)) {
      // 不在人名上下文里的 name，值是组件名这类机器标识时保留
      if (k == 'name' && v is String && _isMachineName(v) && (parentKey == null || !_isPersonContext(parentKey))) {
        return v;
      }
      return _maskAllLeaves(v);
    }
    if (_isPhoneKey(k) || (_isTelKey(k) && isScalar && _containsMobile(v.toString()))) {
      if (isScalar) return v.toString().isEmpty ? v : maskedPhone;
      return _maskAllLeaves(v);
    }
    if (isScalar) {
      if (_isPickupCodeKey(k)) {
        if (v is num) return num.tryParse(maskPickupCode(v.toString())) ?? v;
        return _free(maskPickupCode(v as String), ctx);
      }
      return _sanitizeScalar(v, ctx);
    }
    return _walk(v, k, ctx);
  }

  /// 运单号 / 订单号字段的值：原值已部分遮挡（含 *）时整体换成 *，否则前 4 后 4
  static String _maskIdValue(String v) {
    final t = v.trim();
    if (t.contains('*')) return '*' * t.length;
    return maskMailNo(t);
  }

  static dynamic _sanitizeScalar(dynamic v, _Ctx ctx) {
    if (v is String) {
      final nested = _tryDecodeNested(v);
      if (nested != null) {
        return jsonEncode(_walk(nested, null, ctx));
      }
      return _free(v, ctx);
    }
    if (v is int && _phoneReg.hasMatch(v.toString())) return maskedPhone;
    // 数字形式出现的已知订单号 / 账号 id（如 extra.id）
    if (v is int && ctx.ids.contains(v.toString())) return maskMailNo(v.toString());
    return v;
  }

  /// 敏感 key 下的值：标量置为 ***，容器保留结构、叶子全部置为 ***
  static dynamic _maskAllLeaves(dynamic v) {
    if (v == null || v is bool) return v;
    if (v is Map) return v.map((k, e) => MapEntry(k.toString(), _maskAllLeaves(e)));
    if (v is List) return [for (final e in v) _maskAllLeaves(e)];
    if (v is String && v.isEmpty) return v;
    return masked;
  }

  static dynamic _tryDecodeNested(String s) {
    final t = s.trim();
    if (t.length < 2) return null;
    final looksJson = (t.startsWith('{') && t.endsWith('}')) || (t.startsWith('[') && t.endsWith(']'));
    if (!looksJson) return null;
    try {
      final d = jsonDecode(t);
      return (d is Map || d is List) ? d : null;
    } catch (_) {
      return null;
    }
  }

  /// 无法解析为 JSON 时的文本兜底：和 JSON 字符串值、页面片段同一套规则
  static String _sanitizeUnparsedText(String text) {
    final ctx = _Ctx();
    _precollect(text, ctx);
    return _free(text, ctx);
  }

  static String _stripJsonp(String raw) {
    var s = raw.trim();
    final m = RegExp(r'^[A-Za-z_$][\w$]*\s*\(').firstMatch(s);
    if (m != null && s.endsWith(')')) {
      s = s.substring(m.end, s.length - 1).trim();
    }
    return s;
  }
}
