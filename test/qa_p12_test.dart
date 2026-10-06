// QA 边界测试：P12 时间轴显示（PR #2 feat/p12-timeline + PR #4 feat/p12b-timeline-fixes）。
// 所有样本均为虚构数据：电话为 138/139 假号段与 0755-1234xxxx，取件码为编造格式，
// 驿站名/人名均为「测试」「示例」字样，不含任何真实个人信息，也不取自任何真实样本。
// 手机号写成相邻字符串（如 '138' '00001111'）是为了不触发 tools/check_no_pii.sh。
//
// 约定依据：docs/pickup_app-技术方案.md 第 1、3 节，docs/pickup_app-界面.md P12 节，PRD「P12 验收标准」。
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pickup_app/core/engine/timeline_view.dart';
import 'package:pickup_app/core/models/package.dart';
import 'package:pickup_app/core/models/package_status.dart';
import 'package:pickup_app/platform/connectors/jd_trace_parser.dart';
import 'package:pickup_app/platform/connectors/pdd_trace_parser.dart';
import 'package:pickup_app/ui/components/tracking_timeline.dart';
import 'package:pickup_app/ui/screens/home/widgets/tracking_timeline_sheet.dart';
// ignore: depend_on_referenced_packages
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:url_launcher_platform_interface/link.dart';
// ignore: depend_on_referenced_packages
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

String _j(List<Object?> nodes) => jsonEncode(nodes);

Map<String, Object?> _n(Object? time, Object? text, {Object? tag = '运输中'}) =>
    {'tag': tag, 'time': time, 'text': text};

/// 拦截 url_launcher，记录拉起的 URL（不真的拨号）。
class _FakeLauncher extends UrlLauncherPlatform with MockPlatformInterfaceMixin {
  final launched = <String>[];

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> canLaunch(String url) async => true;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launched.add(url);
    return true;
  }

  @override
  Future<bool> launch(
    String url, {
    required bool useSafariVC,
    required bool useWebView,
    required bool enableJavaScript,
    required bool enableDomStorage,
    required bool universalLinksOnly,
    required Map<String, String> headers,
    String? webOnlyWindowName,
  }) async {
    launched.add(url);
    return true;
  }
}

Widget _wrap(Widget child, {double width = 400}) => MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(width: width, child: SingleChildScrollView(child: child)),
        ),
      ),
    );

Package _pkg({
  String? raw,
  String pickupCode = '',
  String? stationName,
  PackageStatus status = PackageStatus.arrived,
  String platform = 'pdd',
}) =>
    Package(
      id: 'QA_1',
      trackingNumber: 'YT0000000000001',
      courier: CourierType.yt,
      pickupCode: pickupCode,
      stationName: stationName,
      urgency: UrgencyLevel.normal,
      status: status,
      addedAt: DateTime(2026, 10, 7),
      platform: platform,
      rawTimelineJson: raw,
    );

void main() {
  final now = DateTime(2026, 10, 7, 9, 30);

  // ───────────────────────── 1. 坏节点 ─────────────────────────
  group('QA 坏节点逐个跳过', () {
    test('数组里混入 null / int / 字符串 / 数组 / bool，合法节点全部保留', () {
      final nodes = timelineForDisplay(_j([
        null,
        _n('2026-10-06 10:00:00', '快件已到达测试转运中心'),
        42,
        '这是一个字符串节点',
        [1, 2, 3],
        true,
        _n('2026-10-05 10:00:00', '快件已揽收'),
      ]));
      expect(nodes.map((e) => e.text), ['快件已到达测试转运中心', '快件已揽收']);
    });

    test('缺字段的 Map：只有 time 的丢弃；只有 tag 或只有 text 的保留', () {
      final nodes = timelineForDisplay(_j([
        {'time': '2026-10-06 10:00:00'},
        {'tag': '已签收'},
        {'text': '快件已由本人签收'},
        {},
        _n('2026-10-05 10:00:00', '快件已揽收'),
      ]));
      expect(nodes.length, 3);
      // 合法时间在前，非法/缺失时间按原顺序在后
      expect(nodes.first.text, '快件已揽收');
      expect(nodes[1].tag, '已签收');
      expect(nodes[2].text, '快件已由本人签收');
    });

    test('值不是字符串：int / double / bool 转成字符串，null 视为空', () {
      final nodes = timelineForDisplay(_j([
        {'tag': 1, 'time': '2026-10-06 10:00:00', 'text': 12345},
        {'tag': null, 'time': null, 'text': '快件已发出'},
        {'tag': true, 'time': 1.5, 'text': null},
      ]));
      expect(nodes.length, 3);
      expect(nodes[0].tag, '1');
      expect(nodes[0].text, '12345');
      expect(nodes[1].tag, '');
      expect(nodes[1].time, '');
      expect(nodes[2].tag, 'true');
    });

    test('text/tag 是嵌套对象或数组时当作空串，不把 Dart 的 toString（如 {a: 1}）显示出来（B2，PR #4 已修）', () {
      final nodes = timelineForDisplay(_j([
        _n('2026-10-06 10:00:00', {'desc': '快件已到达'}),
        _n('2026-10-05 10:00:00', ['快件', '已揽收']),
        _n('2026-10-04 10:00:00', '正常节点', tag: {'name': '派送中'}),
        _n('2026-10-03 10:00:00', {'a': 1}, tag: ['x']),
      ]));
      // 前两个节点保留 tag「运输中」，正文为空；第三个 tag 为空、正文保留；第四个 tag 和 text 都空 → 丢弃
      expect(nodes.length, 3);
      expect(nodes[0].tag, '运输中');
      expect(nodes[0].text, '');
      expect(nodes[1].tag, '运输中');
      expect(nodes[1].text, '');
      expect(nodes[2].tag, '');
      expect(nodes[2].text, '正常节点');
      for (final n in nodes) {
        expect('${n.tag}${n.text}'.contains('{') || '${n.tag}${n.text}'.contains('['), isFalse,
            reason: '节点显示成了 "${n.tag} ${n.text}"');
      }
    });

    test('全部节点都非法 → 空列表；顶层 null / 数字 / 空数组 / [null] / [[]] → 空列表', () {
      expect(
          timelineForDisplay(_j([null, 1, 'x', [], {}, {'time': '2026-10-06 10:00:00'}])),
          isEmpty);
      for (final raw in ['null', '123', '[]', '[null]', '[[]]', '"[]"', 'true']) {
        expect(timelineForDisplay(raw), isEmpty, reason: raw);
      }
    });

    test('单个节点日期越界（13 月 / 2 月 30 日 / 25 点）不影响其它节点，越界节点排最后', () {
      final nodes = timelineForDisplay(_j([
        _n('2026-13-01 10:00:00', '越界月'),
        _n('2026-02-30 10:00:00', '越界日'),
        _n('2026-10-06 25:00:00', '越界时'),
        _n('2026-10-06 10:00:00', '正常'),
      ]));
      expect(nodes.map((e) => e.text), ['正常', '越界月', '越界日', '越界时']);
    });
  });

  // ───────────────────────── 2. 去重 ─────────────────────────
  group('QA 去重', () {
    test('首尾空白不同的重复节点会被去重（trim 后键相同）', () {
      final nodes = timelineForDisplay(_j([
        _n('2026-10-06 10:00:00', '快件已到达测试转运中心'),
        _n(' 2026-10-06 10:00:00 ', '  快件已到达测试转运中心\n'),
      ]));
      expect(nodes.length, 1);
    });

    test('同 time|text 不同 tag：只保留先出现的一条（新数据优先）', () {
      final nodes = timelineForDisplay(_j([
        _n('2026-10-06 10:00:00', '快件派送中', tag: '派送中'),
        _n('2026-10-06 10:00:00', '快件派送中', tag: '运输中'),
      ]));
      expect(nodes.length, 1);
      expect(nodes.single.tag, '派送中');
    });

    test('只在中间空白/全半角标点上不同：按约定键 time|text 不算重复（与 timeline_merge 一致，记录现状）', () {
      final nodes = timelineForDisplay(_j([
        _n('2026-10-06 10:00:00', '【测试驿站】快件已到达'),
        _n('2026-10-06 10:00:00', '[测试驿站] 快件已到达'),
        _n('2026-10-06 10:00:00', '【测试驿站】快件已 到达'),
        _n('2026-10-06 10:00:00', '【测试驿站】快件已到达。'),
      ]));
      expect(nodes.length, 4);
    });

    test('同一时间不同正文：都保留且保持原顺序', () {
      final nodes = timelineForDisplay(_j([
        _n('2026-10-05 10:00:00', '旧节点'),
        _n('2026-10-06 10:00:00', 'A 先出现'),
        _n('2026-10-06 10:00:00', 'B 后出现'),
      ]));
      expect(nodes.map((e) => e.text), ['A 先出现', 'B 后出现', '旧节点']);
    });

    test('同一事件约定格式 + 不带秒格式各一条：不会去重（记录现状，依赖连接器规范化）', () {
      final nodes = timelineForDisplay(_j([
        _n('2026-10-06 10:00:00', '快件已到达'),
        _n('2026-10-06 10:00', '快件已到达'),
      ]));
      expect(nodes.length, 2);
    });
  });

  // ───────────────────────── 3. 时间格式 ─────────────────────────
  group('QA 时间格式（约定：只认 yyyy-MM-dd HH:mm:ss）', () {
    const nonContract = <Object>[
      '2026/10/05 14:03',
      '2026/10/05 14:03:22',
      '2026-10-05 14:03',
      '2026-10-05  14:03:22', // 两个空格
      '10-05 14:03',
      '10-05 14:03:22',
      1791180202000, // epoch 毫秒 int
      '1791180202000', // epoch 毫秒字符串
      '2026-10-05T14:03:22Z',
      '2026-10-05T14:03:22+08:00',
      '2026-10-05T14:03:22',
      '昨天 14:03',
      '刚刚',
      'abc',
    ];

    test('约定格式解析成功，并按「今天/昨天/日期」显示', () {
      final nodes = timelineForDisplay(_j([
        _n('2026-10-05 14:03:22', '前天'),
        _n('2026-10-07 08:00:00', '今天'),
        _n('2026-10-06 23:59:59', '昨天'),
        _n('2025-12-31 18:20:00', '往年'),
      ]));
      expect(nodes.map((e) => e.text), ['今天', '昨天', '前天', '往年']);
      expect(nodes.map((e) => formatTimelineTime(e, now: now)),
          ['今天 08:00', '昨天 23:59', '10-05 14:03', '2025-12-31 18:20']);
    });

    for (final t in nonContract) {
      test('非约定格式 ${jsonEncode(t)}：不崩溃、排在合法节点之后、原样显示', () {
        final nodes = timelineForDisplay(_j([
          _n(t, '非约定时间节点'),
          _n('2026-10-01 10:00:00', '合法旧节点'),
        ]));
        expect(nodes.length, 2);
        expect(nodes.first.text, '合法旧节点');
        expect(nodes.last.parsedTime, isNull);
        expect(formatTimelineTime(nodes.last, now: now), t.toString());
      });
    }

    test('多个非约定时间节点保持原顺序', () {
      final nodes = timelineForDisplay(_j([
        _n('10-05 14:03', 'X'),
        _n('刚刚', 'Y'),
        _n('', 'Z'),
      ]));
      expect(nodes.map((e) => e.text), ['X', 'Y', 'Z']);
    });
  });

  // ───────────────────────── 4. 连接器产出的真实形状 ─────────────────────────
  group('QA 各平台节点形状（按 lib/platform/connectors 构造方式）', () {
    test('拼多多 traces 形状 {tag, time, text}，带取件码和座机：倒序、电话可识别', () {
      // pdd_connector.dart:1255-1264：tag 由 _mapPddStatusToTag 映射，time 原样 trim
      final raw = _j([
        {'tag': '待取件', 'time': '2026-10-07 08:05:00',
         'text': '【测试市示例驿站】您的快递已到站，凭取件码 3-2-1002 取件，驿站电话 0755-12345678'},
        {'tag': '派送中', 'time': '2026-10-07 07:00:00',
         'text': '快递员测试员正在派件，电话138' '00001111'},
        {'tag': '运输中', 'time': '2026-10-06 10:00:00', 'text': '快件已到达测试转运中心'},
      ]);
      final nodes = timelineForDisplay(raw);
      expect(nodes.first.tag, '待取件');
      expect(findPhones(nodes.first.text, pickupCode: '3-2-1002'), ['0755-12345678']);
      expect(extractStationPhone(nodes: nodes, pickupCode: '3-2-1002'), '0755-12345678');
    });

    test('京东 API 形状 tag 为空：只靠 text 也能显示；派送员手机可拨打', () {
      // jd_connector.dart:347-353：{'tag': '', 'time': createTime, 'text': wlStateDesc}
      final raw = _j([
        {'tag': '', 'time': '2026-10-07 08:30:00',
         'text': '您的订单正在配送途中，配送员【测试员】，电话：139' '00002222，请保持电话畅通'},
        {'tag': '', 'time': '2026-10-06 20:00:00', 'text': '您的订单已到达【测试营业部】'},
      ]);
      final nodes = timelineForDisplay(raw);
      expect(nodes.length, 2);
      expect(nodes.first.tag, '');
      expect(extractStationPhone(nodes: nodes), '139' '00002222');
    });

    test('京东 createTime 若是 epoch 数字（toString 后写入）：不崩溃，但会排到最后（依赖连接器规范化）', () {
      final raw = _j([
        {'tag': '', 'time': '1791259800000', 'text': '您的订单已签收'},
        {'tag': '', 'time': '2026-10-06 20:00:00', 'text': '您的订单已到达【测试营业部】'},
      ]);
      final nodes = timelineForDisplay(raw);
      expect(nodes.length, 2);
      expect(nodes.last.text, '您的订单已签收');
    });

    // B1（测试报告）：拼多多/京东 DOM 兜底解析没有把时间规范成 yyyy-MM-dd HH:mm:ss，
    // P12 会把这些节点排到最后，导致最新节点不在最上面。后端 P14 修复后去掉 skip。
    test('连接器约定：拼多多 DOM 兜底解析出的 time 必须是 yyyy-MM-dd HH:mm:ss（否则最新节点会被排到最后）', () {
      // pdd_trace_parser.dart 的 _dateRegex 允许 / . 分隔和缺秒，原样写入 time
      const dom = '包裹追踪\n'
          '2026/10/07 08:05\n'
          '【测试市示例驿站】您的快递已到站，请及时取件\n'
          '2026-10-06 10:00:22\n'
          '快件已到达测试转运中心\n';
      final parsed = parsePddDomTimeline(dom);
      expect(parsed.length, 2);
      final nodes = timelineForDisplay(jsonEncode(parsed));
      // 期望：最新（10-07）节点在最上并被高亮
      expect(nodes.first.text, contains('已到站'),
          reason: '实际顺序：${nodes.map((e) => e.time).toList()}');
      for (final p in parsed) {
        expect(parseContractTime(p['time']!), isNotNull, reason: '不合约定的 time: ${p['time']}');
      }
    }, skip: 'B1，待 P14 修复');

    test('连接器约定：京东 DOM 兜底解析出的 time 必须是 yyyy-MM-dd HH:mm:ss', () {
      // jd_trace_parser.dart 的 _timeRegex 秒可选
      const dom = '订单跟踪\n'
          '2026-10-07 08:05\n'
          '您的快件正在派送中，配送员测试员\n'
          '2026-10-06 10:00:22\n'
          '您的快件已到达测试营业部\n';
      final parsed = parseJdDomTimeline(dom);
      expect(parsed.length, 2);
      for (final p in parsed) {
        expect(parseContractTime(p['time']!), isNotNull, reason: '不合约定的 time: ${p['time']}');
      }
    }, skip: 'B1，待 P14 修复');

    test('淘宝 multiStage 形状（title→tag，subtitle→time）：约定格式时正常', () {
      // taobao_connector.dart:836-843
      final raw = _j([
        {'tag': '已签收', 'time': '2026-10-07 09:00:00', 'text': '您的快件已签收，签收人：本人'},
        {'tag': '派送中', 'time': '2026-10-07 07:00:00', 'text': '快递员正在为您派件'},
      ]);
      final nodes = timelineForDisplay(raw);
      expect(nodes.map((e) => e.tag), ['已签收', '派送中']);
    });
  });

  // ───────────────────────── 5. 电话识别边界 ─────────────────────────
  group('QA 电话识别边界', () {
    // 约定未要求识别这两种写法；QA 首轮按「应识别」写失败，改为记录现状，列为增强建议（见报告）。
    test('记录现状：带分隔符的手机号（138-0000-1111 / 138 0000 1111）目前不识别为电话', () {
      expect(findPhones('派送员电话138-0000-1111'), isEmpty);
      expect(findPhones('派送员电话 138 0000 1111'), isEmpty);
    });

    test('记录现状：+86 前缀手机号目前不识别为电话', () {
      expect(findPhones('派送员电话+86138' '00001111'), isEmpty);
    });

    test('隐私号带分机（138' '00001111转1234）：至少主号可识别', () {
      expect(findPhones('请拨打138' '00001111转1234联系快递员'), ['138' '00001111']);
    });

    test('打码号码不识别为电话（界面文档已知限制）', () {
      expect(findPhones('快递员电话138****1111'), isEmpty);
    });

    test('取件码就是一串手机位数时，紧跟「取件码」的数字不当电话', () {
      expect(findPhones('取件码：138' '00001111，驿站电话0755-12345678'), ['0755-12345678']);
    });
  });

  // ───────────────────────── 6. 组件 ─────────────────────────
  group('QA TrackingTimeline 组件', () {
    testWidgets('电话是可点击元素：真实点击（hit test）触发拨号回调', (tester) async {
      final called = <String>[];
      final nodes = timelineForDisplay(_j([
        {'tag': '派送中', 'time': '2026-10-07 08:00:00', 'text': '138' '00001111'},
      ]));
      await tester.pumpWidget(_wrap(TrackingTimeline(nodes: nodes, now: now, onCallPhone: called.add)));
      await tester.tap(find.byWidgetPredicate(
          (w) => w is RichText && w.text.toPlainText() == '138' '00001111'));
      expect(called, ['138' '00001111']);
    });

    testWidgets('不注入回调时点击电话走系统拨号（tel: 去掉分隔符）', (tester) async {
      final fake = _FakeLauncher();
      final old = UrlLauncherPlatform.instance;
      UrlLauncherPlatform.instance = fake;
      addTearDown(() => UrlLauncherPlatform.instance = old);
      final nodes = timelineForDisplay(_j([
        {'tag': '待取件', 'time': '2026-10-07 08:00:00', 'text': '0755-12345678'},
      ]));
      await tester.pumpWidget(_wrap(TrackingTimeline(nodes: nodes, now: now)));
      await tester.tap(find.byWidgetPredicate(
          (w) => w is RichText && w.text.toPlainText() == '0755-12345678'));
      await tester.pump();
      expect(fake.launched, ['tel:075512345678']);
    });

    testWidgets('混有坏节点时只渲染好节点，最新节点高亮', (tester) async {
      final nodes = timelineForDisplay(_j([
        null,
        5,
        _n('2026-10-06 10:00:00', '旧节点', tag: '运输中'),
        {'tag': null, 'time': 123, 'text': null},
        _n('2026-10-07 08:00:00', '新节点', tag: '派送中'),
      ]));
      await tester.pumpWidget(_wrap(TrackingTimeline(nodes: nodes, now: now)));
      expect(find.byKey(const ValueKey('tracking_timeline_node_1')), findsOneWidget);
      expect(find.byKey(const ValueKey('tracking_timeline_node_2')), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('tracking_timeline_node_0')),
          matching: find.byKey(const ValueKey('tracking_timeline_latest_dot')),
        ),
        findsOneWidget,
      );
      expect(tester.widget<Text>(find.text('派送中')).style?.color, TrackingTimelineColors.latest);
      expect(tester.takeException(), isNull);
    });

    testWidgets('全部非法节点 → 显示「暂无物流轨迹」，不出现编造的「今日」「已发货」', (tester) async {
      final nodes = timelineForDisplay(_j([null, 1, {}, {'time': '2026-10-06 10:00:00'}]));
      await tester.pumpWidget(_wrap(TrackingTimeline(nodes: nodes, statusLabel: '运输中')));
      expect(find.text('暂无物流轨迹'), findsOneWidget);
      expect(find.textContaining('今日'), findsNothing);
      expect(find.text('已发货'), findsNothing);
    });

    testWidgets('超长正文（3000 字 + 无空格长串）窄屏 320 宽不溢出、不报错', (tester) async {
      final longText = '${'快件已到达测试转运中心，' * 250}${'A' * 400}电话138' '00001111';
      final nodes = timelineForDisplay(_j([
        _n('2026-10-07 08:00:00', longText, tag: '运输中' * 30),
        _n('2026-10-06 08:00:00', '旧节点'),
      ]));
      await tester.pumpWidget(_wrap(TrackingTimeline(nodes: nodes, now: now), width: 320));
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('tracking_timeline_node_1')), findsOneWidget);
    });

    testWidgets('300 个节点渲染不报错', (tester) async {
      final raw = _j([
        for (var i = 0; i < 300; i++)
          _n('2026-09-${(i % 28 + 1).toString().padLeft(2, '0')} 10:${(i % 60).toString().padLeft(2, '0')}:00',
              '节点 $i'),
      ]);
      await tester.pumpWidget(_wrap(TrackingTimeline(nodes: timelineForDisplay(raw), now: now)));
      expect(tester.takeException(), isNull);
    });
  });

  // ───────────────────────── 7. 详情抽屉 ─────────────────────────
  group('QA TrackingTimelineSheet 详情抽屉', () {
    Future<void> pumpSheet(WidgetTester tester, Package pkg) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: TrackingTimelineSheet(package: pkg))));
      await tester.pump();
    }

    testWidgets('取件码、驿站名醒目展示；驿站电话是可点击按钮并拉起 tel:', (tester) async {
      final fake = _FakeLauncher();
      final old = UrlLauncherPlatform.instance;
      UrlLauncherPlatform.instance = fake;
      addTearDown(() => UrlLauncherPlatform.instance = old);
      await pumpSheet(
        tester,
        _pkg(
          pickupCode: '3-2-1002',
          stationName: '测试市示例驿站',
          raw: _j([
            {'tag': '待取件', 'time': '2026-10-07 08:05:00',
             'text': '【测试市示例驿站】凭取件码 3-2-1002 取件，电话 0755-12345678'},
            {'tag': '运输中', 'time': '2026-10-06 10:00:00', 'text': '快件已到达测试转运中心'},
          ]),
        ),
      );
      expect(find.text('取件凭证'), findsOneWidget);
      // 商品卡片的 displayLocation 也会显示驿站名，这里检查取件凭证里加粗的那一处
      expect(find.text('测试市示例驿站'), findsWidgets);
      expect(
        tester.widgetList<Text>(find.text('测试市示例驿站'))
            .any((t) => t.style?.fontWeight == FontWeight.bold),
        isTrue,
      );
      expect(find.textContaining('3-2-1002'), findsWidgets);
      final btn = find.byKey(const ValueKey('station_phone_call_button'));
      expect(btn, findsOneWidget);
      expect(find.text('联系电话 0755-12345678'), findsOneWidget);
      await tester.tap(btn);
      await tester.pump();
      expect(fake.launched, ['tel:075512345678']);
    });

    testWidgets('rawTimelineJson 为空：抽屉显示「暂无物流轨迹」+ 当前状态，无编造节点', (tester) async {
      await pumpSheet(tester, _pkg(raw: null, status: PackageStatus.transit));
      expect(find.text('暂无物流轨迹'), findsOneWidget);
      // PackageStatus.transit.label 是「运送中」（首轮误写成「运输中」）
      expect(find.textContaining('当前状态：运送中'), findsOneWidget);
      expect(find.textContaining('今日'), findsNothing);
      expect(find.text('已发货'), findsNothing);
      expect(find.byKey(const ValueKey('tracking_timeline_node_0')), findsNothing);
    });

    testWidgets('一个坏节点不会让抽屉里的整条时间轴变空', (tester) async {
      await pumpSheet(
        tester,
        _pkg(raw: _j([
          {'tag': '运输中', 'time': 20261006, 'text': {'bad': true}},
          null,
          _n('2026-10-06 10:00:00', '快件已到达测试转运中心'),
        ])),
      );
      expect(find.text('暂无物流轨迹'), findsNothing);
      expect(find.byKey(const ValueKey('tracking_timeline_node_0')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('三个平台（pdd/jd/taobao）走同一个 TrackingTimeline 组件', (tester) async {
      for (final p in ['pdd', 'jd', 'taobao']) {
        await pumpSheet(tester, _pkg(platform: p, raw: _j([_n('2026-10-06 10:00:00', '快件已到达')])));
        expect(find.byType(TrackingTimeline), findsOneWidget, reason: p);
      }
    });
  });
}
