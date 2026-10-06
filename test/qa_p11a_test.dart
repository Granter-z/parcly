// QA 对抗用例：PR #3（P11-a 淘宝原始返回采集、脱敏与导出）
// 全部为假数据；手机号在运行时拼接，源码里不出现连续 11 位手机号（兼容 tools/check_no_pii.sh）。
// 约定：断言写的是「期望行为」，失败即发现；标「记录现状」的用例只记录当前策略，便于讨论。
// ignore_for_file: avoid_print, depend_on_referenced_packages
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:pickup_app/core/sanitizer/diag_sanitizer.dart';
import 'package:pickup_app/platform/diagnostics/taobao_raw_capture.dart';
import 'package:pickup_app/ui/screens/settings/diagnostics_screen.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

String _j(List<String> parts) => parts.join();

/// 假手机号 138·0000·1111（拼接）
final String p = _j(['138', '0000', '1111']);
final _acceptReg = RegExp(r'(?<!\d)1[3-9]\d{9}(?!\d)');

const fakeOrderId = '4012345678901234567';
const otherOrderId = '5012345678901234567';
const fakeTok = 'TkQa7Zx9Lp3Mv5Nw';
const pageUrl = 'https://pages-g.m.taobao.com/wow/z/app/mtb/logisticsV2/h5-detail?x-ssr=true&bizOrderId=$fakeOrderId';

String sj(Object v) => jsonEncode(DiagSanitizer.sanitizeJson(v));
String page(String html, {String url = pageUrl}) =>
    jsonEncode(DiagSanitizer.sanitizeHtmlPage(url: url, html: '<html><head><title>T</title></head>$html</html>'));

void expectNoFragment(String s, String secret, {int n = 5}) {
  for (var i = 0; i + n <= secret.length; i++) {
    expect(s, isNot(contains(secret.substring(i, i + n))), reason: 'fragment ${secret.substring(i, i + n)}');
  }
}

/// 只保留数字后（含全角转半角）不能出现手机号的后 8 位
void expectNoPhoneDigits(String s) {
  final half = s.replaceAllMapped(RegExp('[０-９]'), (m) => String.fromCharCode(m.group(0)!.codeUnitAt(0) - 0xFEE0));
  expect(half.replaceAll(RegExp(r'\D'), ''), isNot(contains('00001111')), reason: s);
}

class _FakePathProvider extends Fake with MockPlatformInterfaceMixin implements PathProviderPlatform {
  _FakePathProvider(this.root);
  final String root;
  @override
  Future<String?> getApplicationSupportPath() async => '$root/support';
  @override
  Future<String?> getTemporaryPath() async => '$root/tmp';
  @override
  Future<String?> getApplicationCachePath() async => '$root/cache';
}

void main() {
  // ───────────────────────── A. 手机号变体 ─────────────────────────
  group('A 手机号变体', () {
    test('A1 +86 紧贴号码（+86138…）应打码', () {
      final out = sj({'desc': '快递员电话 +86$p'});
      expectNoPhoneDigits(out);
    });
    test('A2 +86 空格 号码 应打码', () {
      expectNoPhoneDigits(sj({'desc': '电话 +86 $p'}));
    });
    test('A3 无加号 86 前缀（86138…）应打码', () {
      expectNoPhoneDigits(sj({'desc': '电话 86$p'}));
    });
    test('A4 空格分隔 138 ' '0000 1111 应打码', () {
      expectNoPhoneDigits(sj({'desc': '快递员电话 138 ' '0000 1111 请保持畅通'}));
    });
    test('A5 短横分隔 138-' '0000-1111 应打码', () {
      expectNoPhoneDigits(sj({'desc': '快递员电话 138-' '0000-1111'}));
    });
    test('A6 mobile/phone/tel 类 key 下任意格式都应打码', () {
      final out = sj({
        'mobile': '138 ' '0000 1111',
        'receiverPhone': '+86-138-' '0000-1111',
        'contactTel': '(138)0000-1111',
      });
      expectNoPhoneDigits(out);
    });
    test('A7 全角数字手机号应打码', () {
      expectNoPhoneDigits(sj({'desc': '电话１３８００００１１１１'}));
    });
    test('A8 URL 编码（%2B86）手机号应打码', () {
      expectNoPhoneDigits(sj({'link': 'https://h5.m.taobao.com/x?phone=%2B86$p'}));
    });
    test('A9 JSON 字符串里嵌套 JSON 的 mobile 能打码', () {
      final out = sj({'data': jsonEncode({'mobile': p, 'list': [{'desc': '电话$p'}]})});
      expect(_acceptReg.hasMatch(out), isFalse);
      expectNoPhoneDigits(out);
    });
    test('A10 转义 JSON 文本（\\"mobile\\":\\"…\\"）里能打码', () {
      final out = DiagSanitizer.sanitizeRaw('{"raw":"{\\"mobile\\":\\"$p\\"}"}');
      expectNoPhoneDigits(out);
    });
    test('A11 mobile 为整数（JSON number）时打码', () {
      expect(sj({'mobile': int.parse(p)}), isNot(contains(p)));
    });
    test('A12 JSONP 外壳 + sanitizeRaw 后，验收正则搜不到', () {
      final raw = 'mtopjsonp3(${jsonEncode({'data': {'result': jsonEncode({'m': p, 't': '联系$p，或$p'})}})})';
      expect(_acceptReg.hasMatch(DiagSanitizer.sanitizeRaw(raw)), isFalse);
    });
    test('A13 HTML 可见文本里的分隔写法电话应打码', () {
      expectNoPhoneDigits(page('<body>电话 +86-138-' '0000-1111 或 138 ' '0000 1111</body>'));
    });
    test('A14 记录现状：座机号（0571-88886666、010 12345678）不打码', () {
      final out = sj({'tel': '0571-88886666', 'desc': '驿站电话 010 12345678'});
      expect(out, contains('0571-88886666'));
      expect(out, contains('010 12345678'));
    });
    test('A15 不误伤：19 位订单号、13 位毫秒时间戳里的 11 位子串', () {
      final out = sj({'gmt': 1759812345678, 'x': 'ts=1759812345678'});
      expect(out, contains('1759812345678'));
    });
  });

  // ───────────────────────── B. 运单号 / 取件码 / 地址 / 人名 ─────────────────────────
  group('B 运单号、取件码、地址、人名', () {
    test('B1 key 识别的运单号打码（SF/JT/YT/78 开头纯数字）', () {
      final out = sj({
        'mailNo': 'SF1234567890123',
        'waybillNo': 'JT0001234567890',
        'trackingNumber': 'YT9876543210987',
        'outSid': '78123456789012',
      });
      for (final w in ['SF1234567890123', 'JT0001234567890', 'YT9876543210987', '78123456789012']) {
        expect(out, isNot(contains(w)), reason: w);
      }
      expect(out, contains('SF12*******0123'));
    });
    test('B2 文档里 key 出现过的运单号，在其它文本里同值替换', () {
      final out = sj({'mailNo': 'SF1234567890123', 'trace': [{'desc': '顺丰SF1234567890123已签收'}]});
      expect(out, isNot(contains('SF1234567890123')));
    });
    test('B3 记录现状：未经 key 出现、文本里也没有「运单号」标注的运单号不打码', () {
      final out = sj({'desc': '顺丰 SF1234567890123 极兔 JT0001234567890 圆通 YT9876543210987 中通 78123456789012'});
      expect(out, contains('SF1234567890123'));
      expect(out, contains('78123456789012'));
    });
    test('B4 带标注的取件码打码（取件码A12-3456、取件码 6-1-2034）', () {
      final out = sj({'desc': '取件码A12-3456，取件码 6-1-2034'});
      expect(out, isNot(contains('A12-3456')));
      expect(out, isNot(contains('6-1-2034')));
    });
    test('B5 记录现状：无标注的 6-1-2034 会打码，无标注的 A12-3456 不打码', () {
      final out = sj({'desc': '请到驿站凭 A12-3456 取件，货架 6-1-2034'});
      expect(out, contains('A12-3456'));
      expect(out, isNot(contains('6-1-2034')));
    });
    test('B6 记录现状：key 为 code 的字母型取件码不打码（6-1-2034 靠文本形态规则打码）', () {
      expect(sj({'code': 'A12-3456'}), contains('A12-3456'));
      expect(sj({'code': '6-1-2034'}), isNot(contains('6-1-2034')));
    });
    test('B7 地址类 key 打码（fullAddress/detailAddress/receiverAddress）', () {
      final out = sj({
        'fullAddress': '浙江省杭州市XX区XX小区3栋2单元501',
        'receiver': {'detailAddress': 'XX小区3栋2单元501'},
      });
      expect(out, isNot(contains('3栋2单元501')));
    });
    test('B8 记录现状：自由文本里的详细地址（XX小区3栋2单元501）不打码', () {
      expect(sj({'desc': '您的快递已送至 XX小区3栋2单元501 门口'}), contains('3栋2单元501'));
    });
    test('B9 驿站名、驿站地址、快递公司保留（扁平 key）', () {
      final out = sj({'stationName': 'XX路菜鸟驿站', 'stationAddress': 'XX路100号', 'cpName': '顺丰速运', 'logisticCompany': {'name': '圆通速递'}});
      for (final v in ['XX路菜鸟驿站', 'XX路100号', '顺丰速运', '圆通速递']) {
        expect(out, contains(v), reason: v);
      }
    });
    test('B10 驿站对象下的 address 字段也应保留（约定保留驿站地址）', () {
      final out = sj({'station': {'name': 'XX路菜鸟驿站', 'address': 'XX路100号'}, 'stationInfo': {'detailAddress': 'XX路100号底商'}});
      expect(out, contains('XX路菜鸟驿站'));
      expect(out, contains('XX路100号'));
      expect(out, contains('XX路100号底商'));
    });
    test('B11 带标注的人名打码；记录现状：无冒号、英文名不打码', () {
      final out = sj({'desc': '收件人：张三丰 签收人: 李四 收件人 王五 收件人：Tom Lee'});
      expect(out, isNot(contains('张三丰')));
      expect(out, isNot(contains('李四')));
      expect(out, contains('王五'));
      expect(out, contains('Tom Lee'));
    });
    test('B12 带标注的少数民族长名（含间隔号，超过 6 字）应整体打码', () {
      final out = sj({'desc': '签收人：阿依古丽·买买提 已签收'});
      expect(out, isNot(contains('买买提')));
      expect(out, isNot(contains('买提')));
    });
    test('B14 轨迹文本里「快递员/派送员/小哥」后的名字只留姓（CTO 定案 1）', () {
      final out = sj({'multiStage': [{'labelDesc': {'richContent': [{'text': '【XX市】快递员：王小明 正在派件，派送员 李大伟，小哥赵四'}]}}]});
      for (final v in ['小明', '大伟']) {
        expect(out, isNot(contains(v)), reason: v);
      }
      expect(out, contains('王**'));
      expect(out, contains('李**'));
      expect(out, contains('赵*'));
    });
    test('B15 已部分打码的手机号统一成 1**********（CTO 定案 2）', () {
      final out = sj({'desc': '派送员电话 138****1111，收件人 139****2222'});
      expect(out, isNot(contains('1111')));
      expect(out, isNot(contains('2222')));
      expect(out, isNot(contains('138*')));
      expect('1**********'.allMatches(out).length, 2, reason: out);
    });
    test('B13 courierName / deliveryManName 等快递员姓名 key 只留姓（CTO 定案 1）', () {
      final out = sj({'courierName': '王小明', 'deliveryManName': '李大伟'});
      expect(out, isNot(contains('小明')));
      expect(out, isNot(contains('大伟')));
      expect(out, contains('王**'));
    });
  });

  // ───────────────────────── C. 凭据（JSON 路径：4 个接口都走这里） ─────────────────────────
  group('C 凭据（sanitizeJson / sanitizeRaw）', () {
    test('C1 _m_h5_tk / cookie2 / sgcookie / tracknick / nick / token key 打码', () {
      final out = sj({'_m_h5_tk': fakeTok, 'cookie2': 'c2fakeval', 'sgcookie': 'sgfakeval', 'tracknick': 'tbfakenick', 'nick': 'fakenick', 'accessToken': 'acc$fakeTok'});
      for (final v in [fakeTok, 'c2fakeval', 'sgfakeval', 'tbfakenick', 'fakenick']) {
        expect(out, isNot(contains(v)), reason: v);
      }
    });
    test('C2 unb（淘宝用户数字 id Cookie）key 应打码', () {
      expect(sj({'unb': '2200000001'}), isNot(contains('2200000001')));
    });
    test('C3 userId / buyerId / uid key 应打码（HTML 路径会打码，JSON 路径应一致）', () {
      final out = sj({'userId': '2200000001', 'buyerId': '2200000002', 'uid': '2200000003'});
      for (final v in ['2200000001', '2200000002', '2200000003']) {
        expect(out, isNot(contains(v)), reason: v);
      }
    });
    test('C4 普通 key 下的 Cookie 串（unb=…; _m_h5_tk=…）值应打码', () {
      final out = sj({'ext': 'unb=2200000001; _m_h5_tk=$fakeTok; cookie2=c2fakeval; sgcookie=sgfakeval'});
      for (final v in ['2200000001', fakeTok, 'c2fakeval', 'sgfakeval']) {
        expect(out, isNot(contains(v)), reason: v);
      }
    });
    test('C5 普通 key 下的 JS 赋值（var _m_h5_tk="…"; token=\'…\'）值应打码', () {
      final out = sj({'script': 'var _m_h5_tk="$fakeTok";window.token=\'tokfakeval\';'});
      expect(out, isNot(contains(fakeTok)));
      expect(out, isNot(contains('tokfakeval')));
    });
    test('C6 JSON 字符串里的 URL：token/sid/_m_h5_tk 参数应去掉', () {
      final out = sj({'detailUrl': 'https://h5.m.taobao.com/mlapp/odetail.html?bizOrderId=$fakeOrderId&token=$fakeTok&sid=sidfakeval&_m_h5_tk=tkfakeval'});
      expect(out, isNot(contains(fakeTok)));
      expect(out, isNot(contains('sidfakeval')));
      expect(out, isNot(contains('tkfakeval')));
    });
    test('C7 无法解析的文本（_unparsed）里 unb 值与 URL 里的 token 应打码', () {
      final out = DiagSanitizer.sanitizeRaw('{"unb":"2200000001","url":"https://a.taobao.com/?token=$fakeTok"};');
      expect(out, contains('_unparsed'));
      expect(out, isNot(contains('2200000001')));
      expect(out, isNot(contains(fakeTok)));
    });
  });

  // ───────────────────────── D. 订单号 bizOrderId ─────────────────────────
  group('D 订单号 bizOrderId', () {
    test('D1 JSON key bizOrderId / orderId / mainOrderId（字符串）应打码', () {
      final out = sj({'bizOrderId': fakeOrderId, 'orderId': otherOrderId, 'mainOrderId': '6012345678901234567'});
      for (final v in [fakeOrderId, otherOrderId, '6012345678901234567']) {
        expect(out, isNot(contains(v)), reason: v);
      }
    });
    test('D2 JSON key bizOrderId 为数字时应打码', () {
      expect(sj({'bizOrderId': 4012345678901234567}), isNot(contains(fakeOrderId)));
    });
    test('D3 订单列表的 id 字段（mainOrders[].id）应打码', () {
      expect(sj({'mainOrders': [{'id': fakeOrderId, 'statusInfo': {'text': '卖家已发货'}}]}), isNot(contains(fakeOrderId)));
    });
    test('D4 JSON 里 URL 参数 bizOrderId 应打码', () {
      expect(sj({'url': 'https://h5.m.taobao.com/a?bizOrderId=$fakeOrderId'}), isNot(contains(fakeOrderId)));
    });
    test('D5 文本「订单号：…」会打码', () {
      expect(sj({'desc': '订单号：$fakeOrderId'}), isNot(contains(fakeOrderId)));
    });
    test('D6 HTML：页面 URL 的订单号在正文/URL 编码跳转地址里同值替换', () {
      final out = page('<a href="/login?redirect=https%3A%2F%2Fx%2F%3FbizOrderId%3D$fakeOrderId">登录</a><div>订单 $fakeOrderId</div>');
      expect(out, isNot(contains(fakeOrderId)));
    });
    test('D7 HTML：带 key 的其它订单号打码；记录现状：裸露的其它订单号不打码', () {
      final out = page('<script>var o={orderId:"$otherOrderId"}</script><div>订单 6012345678901234567</div>');
      expect(out, isNot(contains(otherOrderId)));
      expect(out, contains('6012345678901234567'));
    });
  });

  // ───────────────────────── E. HTML 页面（找不到数据标记） ─────────────────────────
  group('E HTML 页面凭据', () {
    test('E1 document.cookie 串（unb/_m_h5_tk/cookie2/sgcookie/tracknick/_tb_token_）全部去掉', () {
      final out = page('<script>document.cookie="unb=2200000001; _m_h5_tk=$fakeTok; cookie2=c2fakeval; sgcookie=sgfakeval; tracknick=tbfakenick; _tb_token_=tbtokfake";</script>');
      for (final v in ['2200000001', fakeTok, 'c2fakeval', 'sgfakeval', 'tbfakenick', 'tbtokfake']) {
        expect(out, isNot(contains(v)), reason: v);
      }
    });
    test('E2 脚本里转义的 JSON 字符串（\\"_m_h5_tk\\":\\"…\\"）中的 token 应去掉', () {
      final out = page('<script>var s="{\\"_m_h5_tk\\":\\"$fakeTok\\",\\"token\\":\\"tokfakeval\\",\\"nick\\":\\"nickfakeval\\"}";</script>');
      expect(out, isNot(contains(fakeTok)));
      expect(out, isNot(contains('tokfakeval')));
      expect(out, isNot(contains('nickfakeval')));
    });
    test('E3 URL 编码的跳转地址里 token%3D / sid%3D 应去掉', () {
      final out = page('<a href="/login?redirect=https%3A%2F%2Fx.taobao.com%2F%3Ftoken%3D$fakeTok%26sid%3Dsidfakeval">x</a>');
      expect(out, isNot(contains(fakeTok)));
      expect(out, isNot(contains('sidfakeval')));
    });
    test('E4 隐藏表单 <input name="_tb_token_" value="…"> / <meta name="csrf-token" content="…"> 的值应去掉', () {
      final out = page('<form><input type="hidden" name="_tb_token_" value="tbtokfakeval"><input type="hidden" name="umidToken" value="umidfakeval"></form>'
          '<meta name="csrf-token" content="csrffakeval">');
      expect(out, isNot(contains('tbtokfakeval')));
      expect(out, isNot(contains('umidfakeval')));
      expect(out, isNot(contains('csrffakeval')));
    });
    test('E5 普通 JSON 字段里的 Cookie 串 {"ext":"unb=…; cookie2=…"} 应去掉', () {
      final out = page('<script>var info = {"ext":"unb=2200000001; cookie2=c2fakeval; _m_h5_tk=$fakeTok"};</script>');
      for (final v in ['2200000001', 'c2fakeval', fakeTok]) {
        expect(out, isNot(contains(v)), reason: v);
      }
    });
    test('E6 &amp; 分隔的 URL、单引号、无引号、JSON.parse 单引号包裹、Cookie: 头文本', () {
      final out = page('<a href="https://x.taobao.com/a?b=1&amp;token=tokampfake">x</a>'
          "<script>var _m_h5_tk = 'tksinglefake'; var cfg = {sid: sidbarefake};"
          "window.__INIT__=JSON.parse('{\"accessToken\":\"accfake\",\"userId\":\"2200000001\"}');</script>"
          '<pre>Cookie: unb=2200000009; cookie2=c2hdrfake; sgcookie=sghdrfake</pre>');
      for (final v in ['tokampfake', 'tksinglefake', 'sidbarefake', 'accfake', '2200000001', '2200000009', 'c2hdrfake', 'sghdrfake']) {
        expect(out, isNot(contains(v)), reason: v);
      }
    });
    test('E7 页面 URL 本身：token/sid/_m_h5_tk 去掉，bizOrderId 打码', () {
      final m = DiagSanitizer.sanitizeHtmlPage(url: '$pageUrl&token=$fakeTok&sid=sidfake1&_m_h5_tk=tkfake1', html: '<html></html>');
      final u = m['url'] as String;
      expect(u, isNot(contains(fakeOrderId)));
      expect(u, isNot(contains(fakeTok)));
      expect(u, isNot(contains('sidfake1')));
      expect(u, isNot(contains('tkfake1')));
    });
  });

  // ───────────────────────── K. 10-07 真机样本里出现的写法（数据为假） ─────────────────────────
  group('K 真机样本形态', () {
    // 物流详情页脚本里是转义 JSON：\"globalUTParams\":{\"mailNo\":…,\"orderId\":…}
    String esc(Map<String, Object?> m) => jsonEncode(jsonEncode(m)).replaceAll(RegExp(r'^"|"$'), '');
    const seller = '2200000000001';
    const buyer = '2200000000002';
    test('K1 页面转义 JSON 里 globalUTParams 的 orderId / sellerId / buyerId 应打码', () {
      final out = page('<script>var d="${esc({'globalUTParams': {'mailNo': 'YT12*******5678', 'sellerId': seller, 'orderId': otherOrderId, 'buyerId': buyer}})}";</script>');
      for (final v in [otherOrderId, seller, buyer]) {
        expect(out, isNot(contains(v)), reason: v);
      }
    });
    test('K2 已部分遮挡的运单号（YT12*******5678）露出的位数也应去掉', () {
      final out = page('<script>var d="${esc({'globalUTParams': {'mailNo': 'YT12*******5678'}})}";</script>');
      expect(out, isNot(contains('5678')));
      final j = sj({'mailNo': 'YT12*******5678', 'desc': '运单号 7812*******9012'});
      expect(j, isNot(contains('5678')));
      expect(j, isNot(contains('9012')));
    });
    test('K3 JUMP_302 的 redirectUrl 里 URL 编码的 orderId%3D… 应打码（页面与 JSON 两条路径）', () {
      final url = 'https://m.duanqu.com?_ariver_appid=1000001&page=plugin-private%3A%2F%2F2021000000000001%2Fpages%2Fele-order-detail-tb%3ForderId%3D$otherOrderId';
      expect(page('<script>var d="${esc({'code': 'JUMP_302', 'redirectUrl': url})}";</script>'), isNot(contains(otherOrderId)));
      expect(sj({'code': 'JUMP_302', 'redirectUrl': url}), isNot(contains(otherOrderId)));
    });
    test('K4 JSON 路径 sellerId / buyerId key 应打码', () {
      final out = sj({'globalUTParams': {'sellerId': seller, 'buyerId': buyer, 'orderId': otherOrderId}});
      for (final v in [seller, buyer, otherOrderId]) {
        expect(out, isNot(contains(v)), reason: v);
      }
    });
    test('K5 不误伤：组件结构里的 name（containerType 旁的组件名）不应被打成 ***', () {
      final out = page('<script>var d="${esc({'container': {'data': [{'name': 'logistics_detail_h5', 'containerType': 'dinamicx'}]}})}";</script>');
      expect(out, contains('logistics_detail_h5'));
      expect(sj({'container': {'data': [{'name': 'logistics_detail_h5', 'containerType': 'dinamicx'}]}}), contains('logistics_detail_h5'));
    });
  });

  // ───────────────────────── F. 截断边界 ─────────────────────────
  group('F 截断边界', () {
    const tok = 'Zq8Kp3Vx7Lm2Nw9Rt4Yb6Hc1Jd5Gf0Se';
    test('F1 多种写法的 token 跨 4096 边界（逐位扫 4070..4100）都不留片段', () {
      final forms = <String Function(String)>[
        (v) => '<script>var c={"_m_h5_tk":"$v"};</script>',
        (v) => '<script>document.cookie="cookie2=$v; x=1";</script>',
        (v) => "<script>var sid = '$v';</script>",
        (v) => '<a href="https://x.taobao.com/a?token=$v&b=1">x</a>',
      ];
      for (final f in forms) {
        final sample = f(tok);
        final valueOffset = sample.indexOf(tok);
        for (var at = 4070; at <= 4100; at++) {
          final pad = at - valueOffset - 6;
          if (pad < 0) continue;
          final html = '<html>${'x' * pad}$sample<body>hi</body></html>';
          final m = DiagSanitizer.sanitizeHtmlPage(url: 'https://a.b/c', html: html);
          expectNoFragment(jsonEncode(m), tok);
          expect((m['snippet'] as String).length, lessThanOrEqualTo(4096));
        }
      }
    });
    test('F2 带标注人名跨 4096 边界不留名字片段', () {
      for (var at = 4085; at <= 4100; at++) {
        final html = '<html><body>${'x' * (at - 12 - 4)}收件人：欧阳小明 后续</body></html>';
        final m = DiagSanitizer.sanitizeHtmlPage(url: 'https://a.b/c', html: html);
        final s = jsonEncode(m);
        expect(s, isNot(contains('小明')), reason: '$at');
        expect(s, isNot(contains('欧阳')), reason: '$at');
      }
    });
    test('F3 订单号（页面 URL 同值）跨 4096 边界不留 ≥8 位原始片段', () {
      for (var at = 4080; at <= 4100; at++) {
        final html = '<html><body>${'x' * (at - 12)}$fakeOrderId</body></html>';
        final s = jsonEncode(DiagSanitizer.sanitizeHtmlPage(url: pageUrl, html: html));
        expectNoFragment(s, fakeOrderId, n: 8);
      }
    });
    test('F4 原页面未闭合的敏感值长度超过 1KB 时，截断后残值也应打码', () {
      final longTok = List.generate(200, (i) => 'Ab${i}Cd').join(); // 远大于 1KB
      final m = DiagSanitizer.sanitizeHtmlPage(url: 'https://a.b/c', html: '<script>var a = {"_m_h5_tk":"$longTok');
      expect(m['snippet'], isNot(contains('Ab150Cd')));
    });
    test('F5 emoji（代理对）恰好跨 4096：不抛异常，结果可编码为合法 UTF-8 JSON', () {
      final html = '<html><body>${'x' * (4096 - 12 - 1)}😀尾巴</body></html>';
      final m = DiagSanitizer.sanitizeHtmlPage(url: 'https://a.b/c', html: html);
      final bytes = utf8.encode(const JsonEncoder.withIndent('  ').convert(m));
      expect(() => jsonDecode(utf8.decode(bytes)), returnsNormally);
    });
    test('F6 长度正好 4096 / 4097', () {
      for (final n in [4096, 4097]) {
        final m = DiagSanitizer.sanitizeHtmlPage(url: 'https://a.b/c', html: 'y' * n);
        expect((m['snippet'] as String).length, 4096);
        expect(m['length'], n);
      }
    });
    test('F7 敏感值位于 256KB 窗口之外：不出现在结果里', () {
      final html = '<html>${'x' * 262200}<script>var _m_h5_tk="$tok";</script>$p</html>';
      final s = jsonEncode(DiagSanitizer.sanitizeHtmlPage(url: 'https://a.b/c', html: html));
      expectNoFragment(s, tok);
      expect(s, isNot(contains(p)));
    });
  });

  // ───────────────────────── G. 性能 / 回溯 ─────────────────────────
  group('G 性能', () {
    int ms(void Function() f) {
      final sw = Stopwatch()..start();
      f();
      return sw.elapsedMilliseconds;
    }

    test('G1 约 1MB 订单列表 JSON（mtop 外壳 + data.result 嵌套 JSON）', () {
      final orders = List.generate(3200, (i) => {
            'id': '40123456789${i.toString().padLeft(8, '0')}',
            'statusInfo': {'text': '卖家已发货'},
            'receiverName': '张三',
            'receiverMobile': p,
            'mailNo': 'YT${(9000000000000 + i)}',
            'desc': '您的快递 YT${(9000000000000 + i)} 已到 XX路菜鸟驿站，取件码 6-1-${1000 + i}，电话 $p，收件人：张三',
            'detailUrl': 'https://h5.m.taobao.com/a?bizOrderId=40123456789${i.toString().padLeft(8, '0')}',
          });
      final raw = 'mtopjsonp1(${jsonEncode({'ret': ['SUCCESS::调用成功'], 'data': {'result': jsonEncode({'mainOrders': orders})}})})';
      late String out;
      final t = ms(() => out = DiagSanitizer.sanitizeRaw(raw));
      print('G1 input=${raw.length} chars, sanitizeRaw=${t}ms');
      expect(raw.length, greaterThan(900000));
      expect(_acceptReg.hasMatch(out), isFalse);
      expect(t, lessThan(10000));
    });
    test('G2 约 1MB 无法解析的文本', () {
      final unit = '{"receiverName":"张三","mobile":"$p","token":"$fakeTok","desc":"收件人：李四 取件码 6-1-2034 运单号 YT9000000000001"}, ';
      final raw = 'garbage(${unit * (1000000 ~/ unit.length)}';
      late String out;
      final t = ms(() => out = DiagSanitizer.sanitizeRaw(raw));
      print('G2 input=${raw.length} chars, sanitizeRaw=${t}ms');
      expect(out, isNot(contains(fakeTok)));
      expect(t, lessThan(10000));
    });
    test('G3 约 1MB 普通 HTML 页面（只处理头部 256KB）', () {
      final block = '<div class="c">物流信息 电话 $p 收件人：张三</div><script>var _m_h5_tk="$fakeTok";var a=1<2;</script>\n';
      final html = '<html><head><title>物流详情</title></head><body>${block * (1000000 ~/ block.length)}</body></html>';
      late Map<String, dynamic> m;
      final t = ms(() => m = DiagSanitizer.sanitizeHtmlPage(url: pageUrl, html: html));
      print('G3 input=${html.length} chars, sanitizeHtmlPage=${t}ms');
      expect(jsonEncode(m), isNot(contains(fakeTok)));
      expect(t, lessThan(5000));
    });
    test('G4 回溯：常见病态串（各 256KB）都应在 2 秒内', () {
      final cases = <String, String>{
        'a= 重复': 'a=' * 131072,
        '"a":" 重复（未闭合引号）': '"a":"' * 52428,
        '反斜杠转义链': 'k:"${'k:\\"' * 65536}',
        'https://a? 重复': 'https://a?' * 26214,
        'URL & 参数 6.5 万个': 'https://a?${'b=1&' * 65536}',
        '收件人： 重复': '收件人：' * 65536,
        '数字 1 串': '1' * 262144,
        '<script> 未闭合 重复': '<script>' * 32768,
      };
      cases.forEach((name, html) {
        final t = ms(() => DiagSanitizer.sanitizeHtmlPage(url: pageUrl, html: html));
        final t2 = ms(() => DiagSanitizer.sanitizeRaw(html));
        print('G4 $name: html=${t}ms raw=${t2}ms');
        expect(t, lessThan(2000), reason: name);
        expect(t2, lessThan(2000), reason: name);
      });
    });
    test('G5 回溯：大量 "<" 且无 ">"（32KB）应在 2 秒内（可见文本去标签正则为平方复杂度）', () {
      final t = ms(() => DiagSanitizer.sanitizeHtmlPage(url: pageUrl, html: '<' * 32768));
      print('G5 "<"x32768: ${t}ms');
      expect(t, lessThan(2000));
    });
    test('G6 回溯：大量 "<title>" 且无闭合（32KB）应在 2 秒内', () {
      final t = ms(() => DiagSanitizer.sanitizeHtmlPage(url: pageUrl, html: '<title>' * 4681));
      print('G6 "<title>"x4681: ${t}ms');
      expect(t, lessThan(2000));
    });
  });

  // ───────────────────────── H. Unicode ─────────────────────────
  group('H Unicode', () {
    test('H1 中文/emoji/扩展区汉字混排不抛异常且手机号打码', () {
      final out = DiagSanitizer.sanitizeRaw(jsonEncode({'desc': '😀包裹📦已到𠀀驿站，电话$p，收件人：𠀀明'}));
      expect(_acceptReg.hasMatch(out), isFalse);
    });
    test('H2 扩展区汉字人名（收件人：王𬌗）应整体打码', () {
      final out = sj({'desc': '收件人：王𬌗 已签收'});
      expect(out, isNot(contains('𬌗')));
    });
    test('H3 零宽字符插在手机号中间（138\\u200b00001111）应打码', () {
      expectNoPhoneDigits(sj({'desc': '电话 138\u200b00001111'}));
    });
  });

  // ───────────────────────── I. 采集开关 / 落盘 / 导出 ─────────────────────────
  group('I 采集开关与落盘', () {
    late Directory root;
    final errors = <Object>[];
    // CTO 定案：采集文件存缓存目录（getApplicationCacheDirectory），子路径沿用 diag/taobao
    Directory diagDir() => Directory('${root.path}/cache/diag/taobao');
    Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 800));

    setUpAll(() async {
      root = Directory.systemTemp.createTempSync('qa_p11a_');
      Hive.init('${root.path}/hive');
      PathProviderPlatform.instance = _FakePathProvider(root.path);
    });
    tearDownAll(() async {
      await Hive.close();
      root.deleteSync(recursive: true);
    });

    test('I1 全新安装开关默认关闭', () async {
      expect(await TaobaoRawCapture.instance.loadEnabled(), isFalse);
    });

    test('I2 关闭时 capture / captureSsrNoMarker 不落盘、不抛异常', () async {
      await runZonedGuarded(() async {
        TaobaoRawCapture.instance.capture(TaobaoDiagEndpoint.orderList, jsonEncode({'mobile': p}));
        TaobaoRawCapture.instance.captureSsrNoMarker(url: pageUrl, html: '<html>$p</html>', statusCode: 200);
        await settle();
      }, (e, _) => errors.add(e));
      expect(diagDir().existsSync() ? diagDir().listSync() : [], isEmpty);
      expect(await TaobaoRawCapture.instance.fileCount(), 0);
      expect(errors, isEmpty);
    });

    test('I3 打开后落盘内容已脱敏；zip 里也搜不到原值', () async {
      await TaobaoRawCapture.instance.setEnabled(true);
      final raw = 'mtopjsonp1(${jsonEncode({'data': {'result': jsonEncode({'mainOrders': [{'receiverName': '张三', 'receiverMobile': p, 'mailNo': 'YT9000000000001', 'receiverAddress': 'XX小区3栋2单元501'}]})}})})';
      TaobaoRawCapture.instance.capture(TaobaoDiagEndpoint.orderList, raw);
      TaobaoRawCapture.instance.captureSsrNoMarker(url: '$pageUrl&sid=sidfake9', html: '<html><title>登录</title><script>var _m_h5_tk="$fakeTok"</script>电话 $p</html>', statusCode: 200);
      await settle();
      final files = diagDir().listSync().whereType<File>().toList();
      expect(files.length, 2);
      final support = Directory('${root.path}/support');
      expect(support.existsSync() ? support.listSync(recursive: true).whereType<File>().where((f) => f.path.contains('diag')) : [], isEmpty,
          reason: '采集文件不应再写进 support 目录（会被系统备份带走）');
      final zip = ZipDecoder().decodeBytes(DiagFileStore.zipDirectory(diagDir().path));
      expect(zip.files.length, 2);
      for (final f in zip.files) {
        final text = utf8.decode(f.content as List<int>);
        for (final v in [p, '张三', 'YT9000000000001', '3栋2单元501', fakeTok, 'sidfake9', fakeOrderId]) {
          expect(text, isNot(contains(v)), reason: '${f.name}: $v');
        }
      }
    });

    test('I4 再关闭后采集不新增文件；开关状态已持久化到 Hive', () async {
      await TaobaoRawCapture.instance.setEnabled(false);
      final before = await TaobaoRawCapture.instance.fileCount();
      TaobaoRawCapture.instance.capture(TaobaoDiagEndpoint.byMailNo, '{"a":1}');
      await settle();
      expect(await TaobaoRawCapture.instance.fileCount(), before);
      final box = await Hive.openBox('diag_settings');
      expect(box.get('taobao_raw_capture_enabled'), false);
    });

    test('I5 落盘失败（目录被同名文件占住）不抛给调用方', () async {
      await TaobaoRawCapture.instance.setEnabled(true);
      diagDir().deleteSync(recursive: true);
      File(diagDir().path).writeAsStringSync('occupied');
      errors.clear();
      await runZonedGuarded(() async {
        expect(() => TaobaoRawCapture.instance.capture(TaobaoDiagEndpoint.orderList, '{"a":1}'), returnsNormally);
        await settle();
      }, (e, _) => errors.add(e));
      expect(errors, isEmpty);
      File(diagDir().path).deleteSync();
      await TaobaoRawCapture.instance.setEnabled(false);
    });

    test('I6 关闭开关时自动清空已采集文件（S4）', () async {
      await TaobaoRawCapture.instance.setEnabled(true);
      TaobaoRawCapture.instance.capture(TaobaoDiagEndpoint.byMailNo, '{"a":1}');
      await settle();
      expect(await TaobaoRawCapture.instance.fileCount(), greaterThan(0));
      await TaobaoRawCapture.instance.setEnabled(false);
      await settle();
      expect(await TaobaoRawCapture.instance.fileCount(), 0);
    });
  });

  group('J 诊断页', () {
    testWidgets('J1 诊断页有「淘宝原始返回采集」开关，关闭状态下显示为关、有导出按钮和文件数', (tester) async {
      // 依赖 I 组之前对单例的状态；单独跑时 Hive 未初始化 -> loadEnabled 兜底 false
      final reported = <String>[];
      final prev = FlutterError.onError;
      FlutterError.onError = (d) => reported.add(d.exceptionAsString());
      await tester.runAsync(() async {
        await tester.pumpWidget(const MaterialApp(home: DiagnosticsScreen()));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();
      FlutterError.onError = prev;
      print('J1 FlutterError reported: ${reported.map((e) => e.split('\n').first).toList()}');
      // 只允许出现 debug 期 ListTile 背景提示（见报告 S 类），不允许其它异常
      expect(reported.where((e) => !e.contains('ink splashes may be invisible')), isEmpty);
      expect(find.text('淘宝原始返回采集'), findsOneWidget);
      final sw = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
      expect(sw.value, isFalse);
      expect(find.text('导出'), findsOneWidget);
      expect(find.textContaining('已采集'), findsWidgets);
      expect(find.text('清空已采集'), findsOneWidget, reason: 'S4：诊断页应有「清空已采集」按钮');
    });
  });
}
