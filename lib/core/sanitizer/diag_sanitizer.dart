/// 诊断原始返回脱敏（纯 Dart，无 Flutter 依赖）
///
/// 用于「淘宝原始返回采集」落盘前的脱敏，规则：
/// - 11 位手机号（字符串内嵌也算）→ `1**********`
/// - 收件人姓名、详细地址类字段（按 JSON key 宽松识别）→ `***`；文本里「收件人：张三」这类显式标注也处理
/// - 运单号保留前 4 位和后 4 位，中间换成 `*`（同一文档内其它字符串里出现的同一运单号一并替换）
/// - 取件码保留格式、数字全部换成 9（`3-2-1002` → `9-9-9999`）
/// - Cookie / token / session 类字段 → `***`
///
/// 字符串值本身是 JSON（如 mtop 的 `data.result`）时会递归解析脱敏后再编码回去。
library;

import 'dart:convert';

class DiagSanitizer {
  DiagSanitizer._();

  static const String masked = '***';
  static const String maskedPhone = '1**********';

  /// 前后都不是数字的 11 位手机号
  static final RegExp _phoneReg = RegExp(r'(?<!\d)1[3-9]\d{9}(?!\d)');

  /// 文本里「取件码 3-2-1002」这类写法
  static final RegExp _codeInTextReg =
      RegExp(r'((?:取件码|提货码|取货码|凭码|货架码)[:：\s]*)([A-Za-z0-9\-]+)');

  /// 文本里独立出现的货架码形态（如 16-1-7002），前后不能紧挨数字或连字符，避免误伤日期
  static final RegExp _shelfInTextReg =
      RegExp(r'(?<![\d\-])\d{1,3}-\d{1,3}-\d{2,5}(?![\d\-])');

  /// 文本里「收件人：张三」这类显式标注的人名（无标注的人名无法可靠识别，不处理）
  static final RegExp _personInTextReg =
      RegExp(r'((?:收件人|收货人|签收人|联系人|寄件人)[:：]\s*)([\u4e00-\u9fa5·]{1,6})');

  /// 文本里「运单号 YT1234567890」/ URL 参数 mailNo=xxx 这类写法
  static final RegExp _mailNoInTextReg = RegExp(
      r'((?:运单号|快递单号|物流单号|单号|mailNo|mailno|waybillNo)[:：=\s"]*)([A-Za-z0-9]{8,})');

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
    final mailNos = <String>{};
    _collectMailNos(node, mailNos);
    return _walk(node, null, mailNos);
  }

  /// 对普通字符串做文本级脱敏：手机号、取件码、运单号。
  static String sanitizeText(String text, [Set<String> knownMailNos = const {}]) {
    if (text.isEmpty) return text;
    var s = text.replaceAll(_phoneReg, maskedPhone);
    for (final m in knownMailNos) {
      if (m.isNotEmpty && s.contains(m)) s = s.replaceAll(m, maskMailNo(m));
    }
    s = s.replaceAllMapped(_personInTextReg, (m) => '${m.group(1)}$masked');
    s = s.replaceAllMapped(
        _mailNoInTextReg, (m) => '${m.group(1)}${maskMailNo(m.group(2)!)}');
    s = s.replaceAllMapped(
        _codeInTextReg, (m) => '${m.group(1)}${maskPickupCode(m.group(2)!)}');
    s = s.replaceAllMapped(_shelfInTextReg, (m) => maskPickupCode(m.group(0)!));
    return s;
  }

  /// 运单号：保留前 4 位和后 4 位，中间换成 *；不足 9 位全部换成 *。
  static String maskMailNo(String v) {
    final s = v.trim();
    if (s.isEmpty) return s;
    if (s.length <= 8) return '*' * s.length;
    return '${s.substring(0, 4)}${'*' * (s.length - 8)}${s.substring(s.length - 4)}';
  }

  /// 取件码：保留格式，数字全部换成 9。
  static String maskPickupCode(String v) => v.replaceAll(RegExp(r'\d'), '9');

  // ───────────────────────── key 识别 ─────────────────────────

  static String _norm(String key) =>
      key.toLowerCase().replaceAll(RegExp(r'[_\-\s]'), '');

  static const _secretKeyParts = ['cookie', 'token', 'mh5tk', 'session', 'password', 'passwd', 'authorization'];

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

  static bool _containsAny(String s, List<String> parts) => parts.any(s.contains);

  static bool _isSecretKey(String k) => k == 'sid' || _containsAny(k, _secretKeyParts);

  static bool _isMailNoKey(String k) =>
      _mailNoKeys.contains(k) ||
      k.contains('mailno') ||
      (k.contains('waybill') && (k.endsWith('no') || k.endsWith('code') || k.endsWith('number')));

  static bool _isPickupCodeKey(String k) => _pickupCodeKeys.contains(k);

  /// 人名/地址字段判断；parentKey 用于区分 `logisticCompany.name` 这类业务名称。
  static bool _isPersonOrAddressKey(String k, String? parentKey) {
    if (_containsAny(k, _addressParts)) {
      // 驿站、站点、门店、快递公司的地址不是个人信息，保留（解析驿站名要用）
      return !_containsAny(k, const ['station', 'site', 'shop', 'store', 'company', 'cp']);
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

  // ───────────────────────── 遍历 ─────────────────────────

  static void _collectMailNos(dynamic node, Set<String> out) {
    if (node is Map) {
      node.forEach((k, v) {
        final isMail = _isMailNoKey(_norm(k.toString()));
        if (isMail && (v is String || v is num)) {
          final s = v.toString().trim();
          if (s.length >= 8) out.add(s);
        } else if (isMail && v is List) {
          for (final e in v) {
            final s = e is String || e is num ? e.toString().trim() : '';
            if (s.length >= 8) out.add(s);
          }
        } else {
          _collectMailNos(v, out);
        }
      });
    } else if (node is List) {
      for (final v in node) {
        _collectMailNos(v, out);
      }
    } else if (node is String) {
      final nested = _tryDecodeNested(node);
      if (nested != null) _collectMailNos(nested, out);
    }
  }

  static dynamic _walk(dynamic node, String? parentKey, Set<String> mailNos) {
    if (node is Map) {
      final out = <String, dynamic>{};
      node.forEach((rawKey, v) {
        final key = rawKey.toString();
        out[key] = _sanitizeEntry(_norm(key), parentKey, v, mailNos);
      });
      return out;
    }
    if (node is List) {
      return [for (final v in node) _walk(v, parentKey, mailNos)];
    }
    return _sanitizeScalar(node, mailNos);
  }

  static dynamic _sanitizeEntry(String k, String? parentKey, dynamic v, Set<String> mailNos) {
    if (v == null || v is bool) return v;
    if (_isSecretKey(k) || _isPersonOrAddressKey(k, parentKey)) {
      return _maskAllLeaves(v);
    }
    if (v is String || v is num) {
      if (_isMailNoKey(k)) return maskMailNo(v.toString());
      if (_isPickupCodeKey(k)) {
        if (v is num) return num.tryParse(maskPickupCode(v.toString())) ?? v;
        return sanitizeText(maskPickupCode(v), mailNos);
      }
      return _sanitizeScalar(v, mailNos);
    }
    if (v is List && _isMailNoKey(k)) {
      return [for (final e in v) e is String || e is num ? maskMailNo(e.toString()) : _walk(e, k, mailNos)];
    }
    return _walk(v, k, mailNos);
  }

  static dynamic _sanitizeScalar(dynamic v, Set<String> mailNos) {
    if (v is String) {
      final nested = _tryDecodeNested(v);
      if (nested != null) {
        return jsonEncode(_walk(nested, null, mailNos));
      }
      return sanitizeText(v, mailNos);
    }
    if (v is int && _phoneReg.hasMatch(v.toString())) return maskedPhone;
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

  /// 无法解析为 JSON 时的文本兜底：按 `"key":"value"` 形态处理敏感 key，再做文本级脱敏
  static String _sanitizeUnparsedText(String text) {
    final kv = RegExp(r'''(["']?)([A-Za-z_][\w\-]*)\1(\s*[:=]\s*)(["'])((?:\\.|(?!\4).)*)\4''');
    final mailNos = <String>{};
    for (final m in kv.allMatches(text)) {
      if (_isMailNoKey(_norm(m.group(2)!)) && m.group(5)!.trim().length >= 8) {
        mailNos.add(m.group(5)!.trim());
      }
    }
    final s = text.replaceAllMapped(kv, (m) {
      final k = _norm(m.group(2)!);
      final v = m.group(5)!;
      String nv;
      if (_isSecretKey(k) || _isPersonOrAddressKey(k, null)) {
        nv = v.isEmpty ? v : masked;
      } else if (_isMailNoKey(k)) {
        nv = maskMailNo(v);
      } else if (_isPickupCodeKey(k)) {
        nv = maskPickupCode(v);
      } else {
        return m.group(0)!;
      }
      return '${m.group(1)}${m.group(2)}${m.group(1)}${m.group(3)}${m.group(4)}$nv${m.group(4)}';
    });
    return sanitizeText(s, mailNos);
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
