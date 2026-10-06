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
      final out = DiagSanitizer.sanitizeJson({'mobile': '13812345678', 'phone': 15900001111});
      expect(out['mobile'], '1**********');
      expect(out['phone'], '1**********');
    });

    test('字符串内嵌手机号', () {
      final out = DiagSanitizer.sanitizeJson({
        'desc': '快递员王师傅(电话:13812345678)正在派送，有问题请联系18600001234。',
      });
      expect(out['desc'], '快递员王师傅(电话:1**********)正在派送，有问题请联系1**********。');
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
            'receiver': {'name': '张三', 'mobile': '13812345678'},
            'logistics': [
              {'mailNo': 'YT0712583482621', 'desc': '取件码 3-2-1002，电话 13900001111'}
            ],
          }
        ]
      });
      final out = DiagSanitizer.sanitizeJson({
        'data': {'result': inner}
      });
      final decoded = jsonDecode(out['data']['result'] as String) as Map<String, dynamic>;
      final order = decoded['mainOrders'][0] as Map<String, dynamic>;
      expect(order['id'], '3891234567890123456');
      expect(order['receiver'], {'name': '***', 'mobile': '***'});
      expect(order['logistics'][0]['mailNo'], 'YT07*******2621');
      expect(order['logistics'][0]['desc'], '取件码 9-9-9999，电话 1**********');
    });

    test('sanitizeRaw 处理 JSONP 外壳', () {
      final raw = 'mtopjsonp3(${jsonEncode({
        'ret': ['SUCCESS::调用成功'],
        'data': {'mobile': '13812345678', 'takeCode': '3-2-1002'}
      })})';
      final out = jsonDecode(DiagSanitizer.sanitizeRaw(raw)) as Map<String, dynamic>;
      expect(out['data'], {'mobile': '1**********', 'takeCode': '9-9-9999'});
      expect(out['ret'], ['SUCCESS::调用成功']);
    });

    test('无法解析的文本按 key:value 兜底', () {
      const raw = "{receiverName:'张三', mailNo:\"YT0712583482621\", tel: 13812345678, x: 1";
      final out = jsonDecode(DiagSanitizer.sanitizeRaw(raw)) as Map<String, dynamic>;
      expect(out['_unparsed'], true);
      final s = out['raw'] as String;
      expect(s, contains("receiverName:'***'"));
      expect(s, contains('"YT07*******2621"'));
      expect(_phoneAnywhere.hasMatch(s), isFalse);
      expect(s, isNot(contains('张三')));
    });

    test('不修改入参', () {
      final input = {'mobile': '13812345678'};
      DiagSanitizer.sanitizeJson(input);
      expect(input['mobile'], '13812345678');
    });
  });

  group('SSR 页面找不到数据标记', () {
    const fakeToken = 'a1b2c3d4e5f6deadbeef_1759812345678';
    const fakeOrderId = '4012345678901234567';

    test('URL：bizOrderId 保留前 4 后 4，token/sid 类置 ***', () {
      final out = DiagSanitizer.sanitizeUrl(
          'https://pages-g.m.taobao.com/wow/z/app/mtb/logisticsV2/h5-detail?x-ssr=true&bizOrderId=$fakeOrderId'
          '&sid=abc123&_m_h5_tk=$fakeToken&mailNo=YT0712583482621&orderId=3891234567890123456&cookie2=zzz&mobile=13812345678');
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
          'var data = {"receiverName":"张三","receiverMobile":"13812345678","detailAddress":"文三路100号"};'
          '</script></head><body>收件人：李四 电话 13900001111，订单 $fakeOrderId，'
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
        final html = '<html><body>${'x' * (startAt - 12)}13812345678 后续文字</body></html>';
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
        html: '<html><head><title>登录</title><script>var _m_h5_tk="tk_fake_123";var u={"receiverName":"张三","mobile":"13812345678"};</script></head>'
            '<body>您需要登录才能继续访问 客服 18600001234 收件人：张三 地址 {"detailAddress":"文三路100号"}</body></html>',
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
                'receiverMobile': '13812345678',
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
                        {'text': '【文三路菜鸟驿站】您的快递已到，取件码 3-2-1002，电话 13900001111'}
                      ]
                    }
                  }
                ],
                'receiver': {'name': '张三', 'phone': '13812345678', 'address': '文三路100号'},
              }
            }
          }
        }
      }),
      TaobaoDiagEndpoint.stationList: jsonEncode({
        'data': {
          'packages': [
            {'mailNo': 'JT5531234567890', 'takeCode': '16-1-7002', 'stationName': '文三路菜鸟驿站', 'mobile': '13812345678'}
          ]
        }
      }),
      TaobaoDiagEndpoint.byMailNo: jsonEncode({
        'data': {'mailNo': '78901234567890', 'fetchCode': '9-4-1006', 'desc': '请凭取件码 9-4-1006 取件，收件人：张三 13812345678'}
      }),
    };
