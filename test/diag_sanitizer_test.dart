import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pickup_app/core/sanitizer/diag_sanitizer.dart';
import 'package:pickup_app/platform/diagnostics/taobao_raw_capture.dart';

final _phoneAnywhere = RegExp(r'1[3-9][0-9]{9}');
final _phoneStandalone = RegExp(r'(?<!\d)1[3-9]\d{9}(?!\d)');

void main() {
  group('手机号', () {
    test('独立字段值', () {
      final out = DiagSanitizer.sanitizeJson({'mobile': '138' '12345678', 'phone': int.parse('159' '00001111')});
      expect(out['mobile'], '1**********');
      expect(out['phone'], '1**********');
    });

    test('字符串内嵌手机号', () {
      final out = DiagSanitizer.sanitizeJson({
        'desc': '快递员王师傅(电话:138' '12345678)正在派送，有问题请联系186' '00001234。',
      });
      // 定案 1：快递员名字只留姓
      expect(out['desc'], '快递员王**(电话:1**********)正在派送，有问题请联系1**********。');
    });

    test('不误伤长订单号和毫秒时间戳', () {
      final out = DiagSanitizer.sanitizeJson({
        'id': '3891234567890123456',
        'ts': 1759812345678,
        'tsStr': '1759812345678',
      });
      expect(out['id'], '3891234567890123456');
      expect(out['ts'], 1759812345678);
      expect(out['tsStr'], '1759812345678');
    });

    test('文本里显式标注的人名', () {
      expect(DiagSanitizer.sanitizeText('已签收，签收人：张三。'), '已签收，签收人：***。');
    });

    test('座机号不处理', () {
      expect(DiagSanitizer.sanitizeText('驿站电话 0571-88886666'), '驿站电话 0571-88886666');
    });
  });

  group('姓名和地址', () {
    test('常见 key 置为 ***', () {
      final out = DiagSanitizer.sanitizeJson({
        'name': '张三',
        'receiverName': '李四',
        'fullName': '王五',
        'buyerNick': 'tb_abc',
        'contact_name': '赵六',
        'address': '浙江省杭州市西湖区某某路1号',
        'detailAddress': '某某小区3幢2单元501',
        'receiverAddress': '某某路2号',
        'receiver_address_detail': '某某路3号',
        'fullAddress': '某某路4号',
      });
      for (final v in out.values) {
        expect(v, '***');
      }
    });

    test('地址对象整体打码但保留结构', () {
      final out = DiagSanitizer.sanitizeJson({
        'receiverAddress': {'province': '浙江省', 'detail': '某某路1号', 'empty': ''},
      });
      expect(out['receiverAddress'], {'province': '***', 'detail': '***', 'empty': ''});
    });

    test('快递公司、驿站、商品名称保留（解析要用）', () {
      final out = DiagSanitizer.sanitizeJson({
        'logisticCompany': {'name': '中通快递', 'mailNo': '78901234567890'},
        'stationName': '菜鸟驿站(西湖店)',
        'siteAddrName': '西湖区文三路驿站',
        'cpName': '圆通速递',
        'itemInfo': {'title': '纸巾 10 包'},
      });
      expect(out['logisticCompany']['name'], '中通快递');
      expect(out['stationName'], '菜鸟驿站(西湖店)');
      expect(out['siteAddrName'], '西湖区文三路驿站');
      expect(out['cpName'], '圆通速递');
      expect(out['itemInfo']['title'], '纸巾 10 包');
    });

    test('Cookie / token 字段打码', () {
      final out = DiagSanitizer.sanitizeJson({'cookie': 'a=b', '_m_h5_tk': 'xxx', 'sid': 'abc'});
      expect(out, {'cookie': '***', '_m_h5_tk': '***', 'sid': '***'});
    });
  });

  group('运单号', () {
    test('保留前 4 后 4', () {
      expect(DiagSanitizer.maskMailNo('YT0712583482621'), 'YT07*******2621');
      expect(DiagSanitizer.maskMailNo('78901234567890'), '7890******7890');
      expect(DiagSanitizer.maskMailNo('12345678'), '********');
    });

    test('按 key 识别，且同一运单号在其它文本里一并替换', () {
      final out = DiagSanitizer.sanitizeJson({
        'mailNo': 'YT0712583482621',
        'waybillNo': 'JT5531234567890',
        'trackingNumber': '432112345678901',
        'tip': '您的包裹 YT0712583482621 已到站',
        'url': 'https://example.com/detail?mailNo=SF1234567890123&x=1',
      });
      expect(out['mailNo'], 'YT07*******2621');
      expect(out['waybillNo'], 'JT55*******7890');
      expect(out['trackingNumber'], '4321*******8901');
      expect(out['tip'], '您的包裹 YT07*******2621 已到站');
      expect(out['url'], 'https://example.com/detail?mailNo=SF12*******0123&x=1');
    });

    test('文本里的「运单号 XXX」', () {
      expect(DiagSanitizer.sanitizeText('中通快递 运单号：78901234567890'), '中通快递 运单号：7890******7890');
    });
  });

  group('取件码', () {
    test('保留格式数字换 9', () {
      expect(DiagSanitizer.maskPickupCode('3-2-1002'), '9-9-9999');
      expect(DiagSanitizer.maskPickupCode('A-108'), 'A-999');
    });

    test('按 key 识别（字符串和数字）', () {
      final out = DiagSanitizer.sanitizeJson({'takeCode': '16-1-7002', 'fetchCode': 8899, 'pickupCode': 'A108'});
      expect(out, {'takeCode': '99-9-9999', 'fetchCode': 9999, 'pickupCode': 'A999'});
    });

    test('文本里的取件码和独立货架码', () {
      expect(
        DiagSanitizer.sanitizeText('【XX驿站】您的快递已到，取件码 3-2-1002，请凭 9-4-1006 取件'),
        '【XX驿站】您的快递已到，取件码 9-9-9999，请凭 9-9-9999 取件',
      );
    });

    test('不误伤日期时间', () {
      expect(DiagSanitizer.sanitizeText('2026-10-06 14:23:05'), '2026-10-06 14:23:05');
    });
  });

  group('嵌套与原始文本', () {
    test('深层嵌套 + 字符串里嵌 JSON（mtop data.result）', () {
      final inner = jsonEncode({
        'mainOrders': [
          {
            'id': '3891234567890123456',
            'receiver': {'name': '张三', 'mobile': '138' '12345678'},
            'logistics': [
              {'mailNo': 'YT0712583482621', 'desc': '取件码 3-2-1002，电话 139' '00001111'}
            ],
          }
        ]
      });
      final out = DiagSanitizer.sanitizeJson({
        'data': {'result': inner}
      });
      final decoded = jsonDecode(out['data']['result'] as String) as Map<String, dynamic>;
      final order = decoded['mainOrders'][0] as Map<String, dynamic>;
      // K1：订单列表 mainOrders[].id 是订单号，保留前 4 后 4
      expect(order['id'], '3891***********3456');
      expect(order['receiver'], {'name': '***', 'mobile': '***'});
      expect(order['logistics'][0]['mailNo'], 'YT07*******2621');
      expect(order['logistics'][0]['desc'], '取件码 9-9-9999，电话 1**********');
    });

    test('sanitizeRaw 处理 JSONP 外壳', () {
      final raw = 'mtopjsonp3(${jsonEncode({
        'ret': ['SUCCESS::调用成功'],
        'data': {'mobile': '138' '12345678', 'takeCode': '3-2-1002'}
      })})';
      final out = jsonDecode(DiagSanitizer.sanitizeRaw(raw)) as Map<String, dynamic>;
      expect(out['data'], {'mobile': '1**********', 'takeCode': '9-9-9999'});
      expect(out['ret'], ['SUCCESS::调用成功']);
    });

    test('无法解析的文本按 key:value 兜底', () {
      const raw = "{receiverName:'张三', mailNo:\"YT0712583482621\", tel: 138" "12345678, x: 1";
      final out = jsonDecode(DiagSanitizer.sanitizeRaw(raw)) as Map<String, dynamic>;
      expect(out['_unparsed'], true);
      final s = out['raw'] as String;
      expect(s, contains("receiverName:'***'"));
      expect(s, contains('"YT07*******2621"'));
      expect(_phoneAnywhere.hasMatch(s), isFalse);
      expect(s, isNot(contains('张三')));
    });

    test('不修改入参', () {
      final input = {'mobile': '138' '12345678'};
      DiagSanitizer.sanitizeJson(input);
      expect(input['mobile'], '138' '12345678');
    });
  });

  group('SSR 页面找不到数据标记', () {
    const fakeToken = 'a1b2c3d4e5f6deadbeef_1759812345678';
    const fakeOrderId = '4012345678901234567';

    test('URL：bizOrderId 保留前 4 后 4，token/sid 类置 ***', () {
      final out = DiagSanitizer.sanitizeUrl(
          'https://pages-g.m.taobao.com/wow/z/app/mtb/logisticsV2/h5-detail?x-ssr=true&bizOrderId=$fakeOrderId'
          '&sid=abc123&_m_h5_tk=$fakeToken&mailNo=YT0712583482621&orderId=3891234567890123456&cookie2=zzz&mobile=138' '12345678');
      expect(out, contains('x-ssr=true'));
      expect(out, contains('bizOrderId=4012***********4567'));
      expect(out, contains('sid=***'));
      expect(out, contains('_m_h5_tk=***'));
      expect(out, contains('mailNo=YT07*******2621'));
      expect(out, contains('orderId=3891***********3456'));
      expect(out, contains('cookie2=***'));
      expect(out, contains('mobile=1**********'));
      expect(out, isNot(contains(fakeOrderId)));
      expect(out, isNot(contains(fakeToken)));
    });

    test('登录页片段：保留 title 和可见文本', () {
      const html = '<!DOCTYPE html><html><head><meta charset="utf-8"><title>手机淘宝网 - 登录</title>'
          '<style>.a{color:red}</style></head><body><div class="tip">您需要登录才能继续访问</div>'
          '<script>window.__redirect = "https://login.m.taobao.com/login.htm?redirectURL=x&ssid=s1234567";</script>'
          '</body></html>';
      final page = DiagSanitizer.sanitizeHtmlPage(
          url: 'https://pages-g.m.taobao.com/wow/z/app/mtb/logisticsV2/h5-detail?bizOrderId=$fakeOrderId',
          html: html,
          statusCode: 200);
      expect(page['title'], '手机淘宝网 - 登录');
      expect(page['length'], html.length);
      expect(page['status'], 200);
      expect(page['text'], '手机淘宝网 - 登录 您需要登录才能继续访问');
      expect(page['snippet'], contains('您需要登录才能继续访问'));
      expect(page['snippet'], contains('ssid=***'));
      expect(page['url'], contains('bizOrderId=4012***********4567'));
    });

    test('含手机号、姓名地址、假 token、假订单号的 HTML：存下来的结果里搜不到原值', () {
      const html = '<html><head><title>物流详情</title><script>'
          'var _m_h5_tk = "$fakeToken"; window.cfg = {token: "$fakeToken", csrf: \'csrf998877\', '
          '"_tb_token_":"tbtok123456", bizOrderId: "$fakeOrderId"};'
          'document.cookie = "cookie2=c2secret987; sgcookie=sgsecret654; unb=2201234567";'
          'var data = {"receiverName":"张三","receiverMobile":"138' '12345678","detailAddress":"文三路100号"};'
          '</script></head><body>收件人：李四 电话 139' '00001111，订单 $fakeOrderId，'
          '取件码 3-2-1002，运单号 YT0712583482621</body></html>';
      final page = DiagSanitizer.sanitizeHtmlPage(
          url: 'https://pages-g.m.taobao.com/wow/z/app/mtb/logisticsV2/h5-detail?x-ssr=true&bizOrderId=$fakeOrderId',
          html: html);
      final saved = jsonEncode(page);
      for (final raw in [
        fakeToken, fakeOrderId, 'csrf998877', 'tbtok123456', 'c2secret987', 'sgsecret654', '2201234567',
        '张三', '李四', '文三路100号', '3-2-1002', 'YT0712583482621',
      ]) {
        expect(saved, isNot(contains(raw)), reason: raw);
      }
      expect(_phoneStandalone.hasMatch(saved), isFalse);
      expect(page['title'], '物流详情');
      expect(page['snippet'], contains('4012***********4567'));
      expect(page['text'], contains('取件码 9-9-9999'));
    });

    /// token 任何长度 > 4 的原始片段都不能出现在 s 里
    void expectNoTokenFragment(String s, String token) {
      for (var i = 0; i + 5 <= token.length; i++) {
        expect(s, isNot(contains(token.substring(i, i + 5))), reason: token.substring(i, i + 5));
      }
    }

    test('token 值跨 4096 边界：先脱敏再截断，不留半截 token', () {
      const token = 'Zq8Kp3Vx7Lm2Nw9Rt4Yb6Hc1Jd5Gf0Se';
      const before = '<html><head><script>/*';
      const keyPart = '*/var cfg = {"_m_h5_tk":"';
      // token 第一个字符分别落在 4080（切在 token 中间）、4090、4095、4096（恰好在边界）
      for (final startAt in [4080, 4090, 4095, 4096]) {
        final pad = 'x' * (startAt - before.length - keyPart.length);
        final html = '$before$pad$keyPart$token"};</script></head><body>hi</body></html>';
        expect(html.indexOf(token), startAt);
        final page = DiagSanitizer.sanitizeHtmlPage(url: 'https://a.b/c', html: html);
        final snippet = page['snippet'] as String;
        expect(snippet.length, lessThanOrEqualTo(DiagSanitizer.htmlSnippetLength));
        expectNoTokenFragment(jsonEncode(page), token);
      }
    });

    test('原页面里本身未闭合的敏感字段，截断后末尾残值也置 ***', () {
      const token = 'Zq8Kp3Vx7Lm2Nw9Rt4Yb6Hc1Jd5Gf0Se';
      final page = DiagSanitizer.sanitizeHtmlPage(url: 'https://a.b/c', html: '<script>var a = {"_m_h5_tk":"$token');
      expect(page['snippet'], '<script>var a = {"_m_h5_tk":"***');
      // 右引号缺失、后面也没有引号：完整脱敏匹配不上，靠截断后的残值处理
      final html = '${'x' * 4070}{"_m_h5_tk":"$token${' more text' * 20}';
      final cut = DiagSanitizer.sanitizeHtmlPage(url: 'https://a.b/c', html: html);
      expect(cut['snippet'], endsWith('"_m_h5_tk":"***'));
      expectNoTokenFragment(jsonEncode(cut), token);
    });

    test('手机号跨 4096 边界：截断后不留原始号码片段', () {
      for (final startAt in [4088, 4090, 4093, 4095]) {
        final html = '<html><body>${'x' * (startAt - 12)}138' '12345678 后续文字</body></html>';
        final page = DiagSanitizer.sanitizeHtmlPage(url: 'https://a.b/c', html: html);
        final snippet = page['snippet'] as String;
        expect(snippet, isNot(contains('13812')), reason: '$startAt');
        expect(snippet, isNot(contains('2345678'.substring(0, 5))), reason: '$startAt');
        expect(RegExp(r'\d{5,}').hasMatch(snippet), isFalse, reason: '$startAt');
        expect(page['text'], isNot(contains('13812')));
      }
    });

    test('超过 4KB 只保留前 4KB', () {
      final html = '<html><title>t</title>${'x' * 10000}</html>';
      final page = DiagSanitizer.sanitizeHtmlPage(url: 'https://a.b/c', html: html);
      expect((page['snippet'] as String).length, DiagSanitizer.htmlSnippetLength);
      expect(page['length'], html.length);
    });
  });

  group('K1 JSON 里的订单号', () {
    const oid = '4012345678901234567';
    test('bizOrderId / orderId / mainOrderId（字符串和数字）前 4 后 4', () {
      final out = DiagSanitizer.sanitizeJson({
        'bizOrderId': oid,
        'orderId': 5012345678901234567,
        'mainOrderId': '6012345678901234567',
        'subOrderIds': ['7012345678901234567'],
      });
      expect(out['bizOrderId'], '4012***********4567');
      expect(out['orderId'], '5012***********4567');
      expect(out['mainOrderId'], '6012***********4567');
      expect(out['subOrderIds'], ['7012***********4567']);
    });

    test('订单列表 mainOrders[].id 打码；其它对象下的 id 不动', () {
      final out = DiagSanitizer.sanitizeJson({
        'mainOrders': [
          {'id': oid, 'item': {'id': '600000000001'}}
        ],
        'id': 'req-1',
      });
      expect(out['mainOrders'][0]['id'], '4012***********4567');
      expect(out['mainOrders'][0]['item']['id'], '600000000001');
      expect(out['id'], 'req-1');
    });

    test('JSON 字符串里链接的 bizOrderId= 参数、同文档其它文本里的同一订单号', () {
      final out = DiagSanitizer.sanitizeJson({
        'orderId': oid,
        'detailUrl': 'https://h5.m.taobao.com/mlapp/odetail.html?bizOrderId=6012345678901234567&spm=a1',
        'tip': '订单$oid已发货',
      });
      expect(out['detailUrl'], 'https://h5.m.taobao.com/mlapp/odetail.html?bizOrderId=6012***********4567&spm=a1');
      expect(out['tip'], '订单4012***********4567已发货');
    });
  });

  group('K2 JSON / 兜底文本里的 URL', () {
    const tok = 'TkFake7Zx9Lp3Mv5';
    test('token / sid / _m_h5_tk / cookie / csrf 参数值换 ***，订单号 4+4，其它参数保留', () {
      final out = DiagSanitizer.sanitizeJson({
        'url': 'https://h5.m.taobao.com/a?bizOrderId=4012345678901234567&token=$tok&sid=sidfake1'
            '&_m_h5_tk=tkfake1&cookie2=c2fake1&_tb_token_=tbfake1&csrfToken=csfake1&spm=a2.b3',
      });
      final u = out['url'] as String;
      for (final v in [tok, 'sidfake1', 'tkfake1', 'c2fake1', 'tbfake1', 'csfake1', '4012345678901234567']) {
        expect(u, isNot(contains(v)), reason: v);
      }
      expect(u, contains('bizOrderId=4012***********4567'));
      expect(u, contains('token=***'));
      expect(u, contains('spm=a2.b3'));
    });

    test('hash 路由里的参数、嵌套跳转地址也处理', () {
      final out = DiagSanitizer.sanitizeJson({
        'a': 'https://m.taobao.com/#/detail?token=$tok&x=1',
        'b': 'https://login.m.taobao.com/login.htm?redirectURL=${Uri.encodeComponent('https://h5.m.taobao.com/a?sid=sidfake2&bizOrderId=4012345678901234567')}',
      });
      final s = jsonEncode(out);
      for (final v in [tok, 'sidfake2', '4012345678901234567']) {
        expect(s, isNot(contains(v)), reason: v);
      }
    });

    test('解析失败走兜底文本时同样处理 URL 和订单号', () {
      final out = DiagSanitizer.sanitizeRaw(
          '{"url":"https://a.taobao.com/x?bizOrderId=4012345678901234567&_m_h5_tk=$tok&cookie=ck1", "orderId":"5012345678901234567" broken');
      expect(out, contains('_unparsed'));
      for (final v in [tok, 'ck1', '4012345678901234567', '5012345678901234567']) {
        expect(out, isNot(contains(v)), reason: v);
      }
      expect(out, contains('4012***********4567'));
      expect(out, contains('5012***********4567'));
    });
  });

  group('K3 页面片段里的 4 种凭据写法', () {
    const url = 'https://pages-g.m.taobao.com/wow/z/app/mtb/logisticsV2/h5-detail?bizOrderId=4012345678901234567';
    String page(String body) => jsonEncode(DiagSanitizer.sanitizeHtmlPage(url: url, html: '<html><head><title>T</title></head>$body</html>'));

    test('① 脚本里转义的 JSON', () {
      final out = page(r'<script>var s="{\"_m_h5_tk\":\"tkesc1\",\"unb\":\"2200000001\",\"bizOrderId\":5012345678901234567}";</script>');
      expect(out, isNot(contains('tkesc1')));
      expect(out, isNot(contains('2200000001')));
      expect(out, isNot(contains('5012345678901234567')));
    });

    test('② URL 编码的跳转地址', () {
      final out = page('<a href="/login?redirect=https%3A%2F%2Fx.taobao.com%2F%3Ftoken%3Dtokenc1%26sid%3Dsidenc1%26_m_h5_tk%3Dtkenc1">x</a>'
          '<script>location.href="/l?u=" + "https%253A%252F%252Fa.b%252F%253Fcookie2%253Dc2dbl1";</script>');
      for (final v in ['tokenc1', 'sidenc1', 'tkenc1', 'c2dbl1']) {
        expect(out, isNot(contains(v)), reason: v);
      }
      // 普通参数名保留，便于诊断
      expect(out, contains('redirect='));
    });

    test('③ 隐藏表单和 csrf meta：打 value / content，name 保留', () {
      final out = page('<form><input type="hidden" name="_tb_token_" value="tbform1">'
          "<input value='umform1' name='umidToken' type='hidden'><input name=\"receiverName\" value=\"张三\"></form>"
          '<meta name="csrf-token" content="csrfmeta1"><meta charset="utf-8">');
      for (final v in ['tbform1', 'umform1', 'csrfmeta1', '张三']) {
        expect(out, isNot(contains(v)), reason: v);
      }
      expect(out, contains(r'name=\"_tb_token_\"'));
      expect(out, contains(r'name=\"csrf-token\"'));
    });

    test('④ 普通字段里夹着的 Cookie 串', () {
      final out = page('<script>var info = {"ext":"unb=2200000001; cookie2=c2mix1; sgcookie=sgmix1", "cfg": "a=1&tracknick=nickmix1"};'
          'var raw = "lang=zh; _m_h5_tk=tkmix1";</script><div>ext=unb=2200000002</div>');
      for (final v in ['2200000001', '2200000002', 'c2mix1', 'sgmix1', 'nickmix1', 'tkmix1']) {
        expect(out, isNot(contains(v)), reason: v);
      }
    });
  });

  group('S1 手机号变体', () {
    const p = '138' '00001111';
    String half(String s) =>
        s.replaceAllMapped(RegExp('[０-９]'), (m) => String.fromCharCode(m.group(0)!.codeUnitAt(0) - 0xFEE0));
    void expectNoPhone(String s) => expect(half(s).replaceAll(RegExp(r'\D'), ''), isNot(contains('00001111')), reason: s);

    test('+86 / 86 / 空格 / 横杠 / 括号 / 全角 / 零宽 都打码', () {
      final samples = [
        '+86$p', '+86 $p', '86$p', '＋86-$p',
        '138 ' '0000 1111', '138-' '0000-1111', '(138)' '0000-1111', '138\u200b0000\u200c1111',
        '１３８' '００００１１１１', '%2B86$p',
      ];
      for (final v in samples) {
        final out = DiagSanitizer.sanitizeText('电话：$v，请保持畅通');
        expectNoPhone(out);
        expect(out, contains(DiagSanitizer.maskedPhone), reason: v);
      }
    });

    test('mobile / phone / receiverMobile 字段按字段名整体打码；tel 字段里有手机号才打码', () {
      final out = DiagSanitizer.sanitizeJson({
        'mobile': '138 ' '0000 1111',
        'receiverMobile': '+86-138-' '0000-1111',
        'phone': 'tel:(138)' '00001111',
        'contactTel': '138****1111',
        'stationTel': '0571-88886666',
      });
      expect(out['mobile'], DiagSanitizer.maskedPhone);
      expect(out['receiverMobile'], DiagSanitizer.maskedPhone);
      expect(out['phone'], DiagSanitizer.maskedPhone);
      expect(out['contactTel'], DiagSanitizer.maskedPhone);
      expect(out['stationTel'], '0571-88886666'); // 座机号不在本次范围（P15）
    });

    test('不误伤：19 位订单号、13 位时间戳、日期、货架码', () {
      const s = '订单 4138000011112222333 时间 1759812345678 2026-10-07 13:45 货架 13-2-1001';
      expect(DiagSanitizer.sanitizeText(s), '订单 4138000011112222333 时间 1759812345678 2026-10-07 13:45 货架 99-9-9999');
    });
  });

  group('S2 凭据清单统一', () {
    test('unb / userId / buyerId / uid 在 JSON、兜底文本、页面里都打码', () {
      final json = DiagSanitizer.sanitizeJson({'unb': '2200000001', 'userId': 2200000002, 'buyerId': '2200000003', 'uid': '2200000004', 'tracknick': 'nk1', 'csrfToken': 'cs1'});
      expect(json.values.toSet(), {'***'});
      final raw = DiagSanitizer.sanitizeRaw("{unb: '2200000001', userId: 2200000002, buyerId:\"2200000003\", x");
      final html = jsonEncode(DiagSanitizer.sanitizeHtmlPage(url: 'https://a.b/c', html: '<script>var c={unb:"2200000001",userId:2200000002,buyerId:"2200000003"}</script>'));
      for (final out in [raw, html]) {
        for (final v in ['2200000001', '2200000002', '2200000003']) {
          expect(out, isNot(contains(v)), reason: v);
        }
      }
    });

    test('运单号 outSid 仍按运单号打码（不会被当成 sid 置 ***）', () {
      expect(DiagSanitizer.sanitizeJson({'outSid': '78123456789012'})['outSid'], '7812******9012');
    });
  });

  group('S3 驿站地址保留', () {
    test('station / stationInfo / cpInfo 下的地址保留，收件人地址照旧打码', () {
      final out = DiagSanitizer.sanitizeJson({
        'station': {'name': 'XX路菜鸟驿站', 'address': 'XX路100号'},
        'stationInfo': {'stationName': 'YY驿站', 'detailAddress': 'YY路8号底商'},
        'receiver': {'detailAddress': 'XX小区3栋2单元501'},
        'receiverInfo': {'address': 'ZZ小区1栋'},
        'address': 'WW小区2栋',
      });
      expect(out['station'], {'name': 'XX路菜鸟驿站', 'address': 'XX路100号'});
      expect(out['stationInfo'], {'stationName': 'YY驿站', 'detailAddress': 'YY路8号底商'});
      expect(out['receiver'], {'detailAddress': '***'});
      expect(out['receiverInfo'], {'address': '***'});
      expect(out['address'], '***');
    });
  });

  group('定案 1/2 快递员姓名、部分打码手机号', () {
    test('快递员 / 派送员 / 小哥后面的名字只留姓', () {
      expect(DiagSanitizer.sanitizeText('快递员张三丰正在派件'), '快递员张**正在派件');
      expect(DiagSanitizer.sanitizeText('派送员：李大伟，小哥赵四'), '派送员：李**，小哥赵*');
      expect(DiagSanitizer.sanitizeText('快递小哥 王师傅 已揽收'), '快递小哥 王** 已揽收');
    });

    test('后面不是名字时不动', () {
      for (final s in ['快递员正在派件', '快递员已签收', '请联系快递员', '快递员电话', '小哥会尽快送达']) {
        expect(DiagSanitizer.sanitizeText(s), s);
      }
    });

    test('courierName / deliveryManName / courier.name 字段只留姓；快递公司名不动', () {
      final out = DiagSanitizer.sanitizeJson({
        'courierName': '王小明',
        'deliveryManName': '李大伟',
        'courier': {'name': '赵四', 'mobile': '138' '00001111'},
        'courierCompanyName': '顺丰速运',
      });
      expect(out['courierName'], '王**');
      expect(out['deliveryManName'], '李**');
      expect(out['courier'], {'name': '赵*', 'mobile': DiagSanitizer.maskedPhone});
      expect(out['courierCompanyName'], '顺丰速运');
    });

    test('已部分打码的手机号统一换成 1**********', () {
      expect(DiagSanitizer.sanitizeText('电话 138****1111，备用 139*****22'), '电话 1**********，备用 1**********');
    });
  });

  group('L2 / L3', () {
    test('原页面未闭合的敏感值超过 1KB，截断后残值也打码', () {
      final longTok = List.generate(300, (i) => 'Ab${i}Cd').join();
      final page = DiagSanitizer.sanitizeHtmlPage(url: 'https://a.b/c', html: '<script>var a = {"_m_h5_tk":"$longTok');
      expect(page['snippet'], '<script>var a = {"_m_h5_tk":"***');
    });

    test('带间隔号的长名、扩展区汉字人名整体打码', () {
      expect(DiagSanitizer.sanitizeText('签收人：阿依古丽·买买提 已签收'), '签收人：*** 已签收');
      expect(DiagSanitizer.sanitizeText('收件人：王\u{2C317} 已签收'), '收件人：*** 已签收');
    });
  });

  group('真机采集形态补充（10-07，数据为假）', () {
    const oid = '5012345678901234567';
    const seller = '2200000000001';
    const buyer = '2200000000002';
    String esc(Object m) {
      final once = jsonEncode(jsonEncode(m));
      return once.substring(1, once.length - 1);
    }

    test('页面脚本转义 JSON 的 globalUTParams：orderId 4+4，sellerId / buyerId 置 ***，半遮运单号整体遮住', () {
      final page = jsonEncode(DiagSanitizer.sanitizeHtmlPage(
          url: 'https://a.b/c',
          html: '<script>var d="${esc({'globalUTParams': {'mailNo': 'YT12*******5678', 'sellerId': seller, 'orderId': oid, 'buyerId': buyer}})}";</script>'
              '<img src="//img.alicdn.com/imgextra/i1/$seller/O1CNfake_!!$seller.jpg">'));
      for (final v in [oid, seller, buyer, '5678']) {
        expect(page, isNot(contains(v)), reason: v);
      }
      expect(page, contains('5012***********4567'));
    });

    test('JSON 里 sellerId / buyerId / seller.id 置 ***，同一 id 在店铺链接、图片路径里同值替换', () {
      final out = DiagSanitizer.sanitizeJson({
        'mainOrders': [
          {
            'id': oid,
            'extra': {'id': int.parse(oid)},
            'seller': {'id': int.parse(seller), 'shopUrl': 'https://shop.taobao.com/view_shop.htm?user_number_id=$seller'},
            'subOrders': [
              {'itemInfo': {'pic': '//img.alicdn.com/imgextra/i3/$seller/O1CNfake_!!$seller.jpg'}}
            ],
          }
        ],
        'globalUTParams': {'sellerId': seller, 'buyerId': buyer},
      });
      final s = jsonEncode(out);
      for (final v in [oid, seller, buyer]) {
        expect(s, isNot(contains(v)), reason: v);
      }
      expect(out['mainOrders'][0]['seller']['id'], '***');
      expect(out['mainOrders'][0]['extra']['id'], '5012***********4567');
      expect(out['globalUTParams'], {'sellerId': '***', 'buyerId': '***'});
    });

    test('JUMP_302 redirectUrl 里 URL 编码 / 嵌套的 orderId（JSON 与兜底文本两条路径）', () {
      const url = 'https://m.duanqu.com?_ariver_appid=1000001&page=plugin-private%3A%2F%2F2021000000000001%2Fpages%2Fdetail%3ForderId%3D$oid';
      final json = jsonEncode(DiagSanitizer.sanitizeJson({'code': 'JUMP_302', 'redirectUrl': url, 'data': jsonEncode({'redirectUrl': url})}));
      final raw = DiagSanitizer.sanitizeRaw('{"code":"JUMP_302","redirectUrl":"$url" broken');
      for (final out in [json, raw]) {
        expect(out, isNot(contains(oid)));
        expect(out, contains('_ariver_appid=1000001'));
      }
    });

    test('已部分遮挡的运单号露出位去掉；本脱敏器自己的 4+4 不受影响', () {
      final out = DiagSanitizer.sanitizeJson({
        'mailNo': 'YT12*******5678',
        'cpMailNo': 'SF1234567890123',
        'desc': '运单号 7812*******9012，电话 138****1111',
      });
      expect(out['mailNo'], '*' * 15);
      expect(out['cpMailNo'], 'SF12*******0123');
      expect(out['desc'], '运单号 ${'*' * 15}，电话 1**********');
    });

    test('组件名这类机器标识的 name 保留；人名上下文和中文 name 照旧打码', () {
      final out = DiagSanitizer.sanitizeJson({
        'container': {'data': [{'name': 'logistics_detail_h5', 'containerType': 'dinamicx'}]},
        'buyer': {'name': 'zhang_san'},
        'name': '张三',
      });
      expect(out['container']['data'][0]['name'], 'logistics_detail_h5');
      expect(out['buyer']['name'], '***');
      expect(out['name'], '***');
    });
  });

  group('L1 性能：去标签 / title / script 线性复杂度', () {
    int ms(void Function() f) {
      final sw = Stopwatch()..start();
      f();
      return sw.elapsedMilliseconds;
    }

    const url = 'https://pages-g.m.taobao.com/wow/z/app/mtb/logisticsV2/h5-detail?bizOrderId=4012345678901234567';
    final cases = <String, String>{
      '"<" x 32K': '<' * 32768,
      '"<" x 1M': '<' * (1 << 20),
      '"<title>" 未闭合 x 1M': '<title>' * ((1 << 20) ~/ 7),
      '"<script" 未闭合 x 1M': '<script' * ((1 << 20) ~/ 7),
      '"<style>a" x 1M': '<style>a' * ((1 << 20) ~/ 8),
      '"<a " 无 ">" x 1M': '<a ' * ((1 << 20) ~/ 3),
    };
    cases.forEach((name, html) {
      test('$name 在 1 秒内', () {
        final t = ms(() => DiagSanitizer.sanitizeHtmlPage(url: url, html: html));
        expect(t, lessThan(1000), reason: '$name: ${t}ms');
      });
    });

    test('sanitizeRaw：1MB 病态文本在 1 秒内', () {
      for (final raw in ['<' * (1 << 20), 'k=' * (1 << 19), '%2' * ((1 << 20) ~/ 2), 'a%41' * (1 << 18)]) {
        final t = ms(() => DiagSanitizer.sanitizeRaw(raw));
        expect(t, lessThan(1000), reason: '${raw.substring(0, 4)}: ${t}ms');
      }
    });

    test('去标签、title、未闭合 script 的结果不变', () {
      final page = DiagSanitizer.sanitizeHtmlPage(
          url: 'https://a.b/c',
          html: '<html><head><TITLE lang="zh"> 物流详情 </TITLE><style>.a{}</style></head>'
              '<body><div class="x">您的包裹</div><p>已到站</p><script>var a = 1 < 2;');
      expect(page['title'], '物流详情');
      expect(page['text'], '物流详情 您的包裹 已到站');
    });
  });

  group('DiagFileStore', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('diag_store_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('序号递增，每个接口只保留最近 20 份，接口之间互不影响', () async {
      final store = DiagFileStore(Directory('${tmp.path}/diag/taobao'));
      for (var i = 0; i < 25; i++) {
        await store.write(TaobaoDiagEndpoint.orderList, '{"i":$i}');
      }
      await store.write(TaobaoDiagEndpoint.byMailNo, '{}');
      final names = store.listFiles().map((f) => f.uri.pathSegments.last).toList();
      final orders = names.where((n) => n.startsWith('queryboughtlistv2_')).toList();
      expect(orders.length, 20);
      expect(orders.first, 'queryboughtlistv2_0006.json');
      expect(orders.last, 'queryboughtlistv2_0025.json');
      expect(names, contains('wapquerylogisticpackagebymailno_0001.json'));
    });

    test('clear 删掉全部采集文件、保留目录，之后还能继续写', () async {
      final store = DiagFileStore(Directory('${tmp.path}/diag/taobao'));
      await store.write(TaobaoDiagEndpoint.orderList, '{}');
      await store.write(TaobaoDiagEndpoint.byMailNo, '{}');
      expect(await store.clear(), 2);
      expect(store.listFiles(), isEmpty);
      expect(store.dir.existsSync(), isTrue);
      await store.write(TaobaoDiagEndpoint.orderList, '{}');
      expect(store.listFiles().length, 1);
      expect(await DiagFileStore(Directory('${tmp.path}/none')).clear(), 0);
    });

    test('打包 zip', () async {
      final store = DiagFileStore(Directory('${tmp.path}/diag/taobao'));
      await store.write(TaobaoDiagEndpoint.ssrDetail, '{"a":1}');
      await store.write(TaobaoDiagEndpoint.stationList, '{"b":2}');
      final zip = ZipDecoder().decodeBytes(DiagFileStore.zipDirectory(store.dir.path));
      expect(zip.files.map((f) => f.name).toList(),
          ['taobao/logisticsV2_h5detail_0001.json', 'taobao/queryMultiStaPackages4Xy_0001.json']);
    });
  });

  // 生成样例文件：DIAG_SAMPLE_OUT=<目录> flutter test test/diag_sanitizer_test.dart
  test('样例文件里搜不到手机号', () async {
    final outDir = Platform.environment['DIAG_SAMPLE_OUT'];
    final dir = outDir != null && outDir.isNotEmpty
        ? Directory(outDir)
        : Directory.systemTemp.createTempSync('diag_sample_');
    final store = DiagFileStore(dir);
    final samples = _samples();
    for (final e in samples.entries) {
      await store.write(e.key, DiagSanitizer.sanitizeRaw(e.value));
    }
    await store.write(
      TaobaoDiagEndpoint.ssrNoMarker,
      const JsonEncoder.withIndent('  ').convert(DiagSanitizer.sanitizeHtmlPage(
        url: 'https://pages-g.m.taobao.com/wow/z/app/mtb/logisticsV2/h5-detail?x-ssr=true&bizOrderId=4012345678901234567&sid=abc',
        html: '<html><head><title>登录</title><script>var _m_h5_tk="tk_fake_123";var u={"receiverName":"张三","mobile":"138' '12345678"};</script></head>'
            '<body>您需要登录才能继续访问 客服 186' '00001234 收件人：张三 地址 {"detailAddress":"文三路100号"}</body></html>',
      )),
    );
    for (final f in store.listFiles()) {
      final text = f.readAsStringSync();
      expect(_phoneStandalone.hasMatch(text), isFalse, reason: f.path);
      expect(text, isNot(contains('张三')));
      expect(text, isNot(contains('文三路100号')));
    }
    if (outDir == null || outDir.isEmpty) dir.deleteSync(recursive: true);
  });
}

/// 假数据样例（结构只用于演示脱敏，不代表淘宝真实字段）
Map<String, String> _samples() => {
      TaobaoDiagEndpoint.orderList: 'mtopjsonp1(${jsonEncode({
        'ret': ['SUCCESS::调用成功'],
        'data': {
          'result': jsonEncode({
            'mainOrders': [
              {
                'id': '3891234567890123456',
                'statusInfo': {'text': '卖家已发货'},
                'receiverName': '张三',
                'receiverMobile': '138' '12345678',
                'receiverAddress': '浙江省杭州市西湖区文三路100号',
              }
            ]
          })
        }
      })})',
      TaobaoDiagEndpoint.ssrDetail: jsonEncode({
        'result': {
          'data': {
            'newLogistics': {
              'fields': {
                'mailNo': 'YT0712583482621',
                'logisticCompany': {'name': '圆通速递', 'mailNo': 'YT0712583482621'},
                'multiStage': [
                  {
                    'title': '待取件',
                    'subtitle': '10-06 14:23',
                    'labelDesc': {
                      'richContent': [
                        {'text': '【文三路菜鸟驿站】您的快递已到，取件码 3-2-1002，电话 139' '00001111'}
                      ]
                    }
                  }
                ],
                'receiver': {'name': '张三', 'phone': '138' '12345678', 'address': '文三路100号'},
              }
            }
          }
        }
      }),
      TaobaoDiagEndpoint.stationList: jsonEncode({
        'data': {
          'packages': [
            {'mailNo': 'JT5531234567890', 'takeCode': '16-1-7002', 'stationName': '文三路菜鸟驿站', 'mobile': '138' '12345678'}
          ]
        }
      }),
      TaobaoDiagEndpoint.byMailNo: jsonEncode({
        'data': {'mailNo': '78901234567890', 'fetchCode': '9-4-1006', 'desc': '请凭取件码 9-4-1006 取件，收件人：张三 138' '12345678'}
      }),
    };
