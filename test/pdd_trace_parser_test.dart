import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pickup_app/platform/connectors/pdd_trace_parser.dart';

void main() {
  group('parsePddWindowNameCaptures', () {
    test('含 /logistics 的业务 URL 不被 /log 埋点黑名单误杀，独立 /log /event /analytics 被过滤', () {
      final raw = jsonEncode([
        {
          'u': 'https://mobile.yangkeduo.com/api/logistics/detail?order=1',
          'b': '{"traces":[]}',
        },
        {
          'u': 'https://mobile.yangkeduo.com/proxy/api/order/shipping/track',
          'b': '{"list":[]}',
        },
        {
          'u': 'https://mobile.yangkeduo.com/api/log?from=order',
          'b': '{"ok":true}',
        },
        {
          'u': 'https://mobile.yangkeduo.com/logs/report/order',
          'b': '{"ok":true}',
        },
        {
          'u': 'https://mobile.yangkeduo.com/event/track?id=1',
          'b': '{"ok":true}',
        },
        {
          'u': 'https://mobile.yangkeduo.com/analytics/order',
          'b': '{"ok":true}',
        },
      ]);

      final captures = parsePddWindowNameCaptures(raw);
      expect(captures.map((c) => c.url).toList(), [
        'https://mobile.yangkeduo.com/api/logistics/detail?order=1',
        'https://mobile.yangkeduo.com/proxy/api/order/shipping/track',
      ]);
    });
  });

  group('extractPddTimelineFromJson', () {
    test('小写/驼峰键 formatTime + statusDesc 与下划线键均可提取轨迹节点', () {
      final now = DateTime.utc(2026, 10, 7, 12);
      final root = {
        'result': {
          'traces': [
            {
              'formatTime': '2026-10-06 14:20:00',
              'statusDesc': '快件已到达【测试转运中心】',
            },
            {
              'formattime': '2026-10-06 18:05:00',
              'statusdesc': '快件已存入菜鸟驿站，取件码 1-1-1111',
            },
            {
              'format_time': '2026-10-07 09:00',
              'status_desc': '已签收',
            },
          ],
        },
      };

      final nodes = extractPddTimelineFromJson(root, now: now);
      expect(nodes, hasLength(3));
      expect(nodes[0], {
        'tag': '',
        'time': '2026-10-06 14:20:00',
        'text': '快件已到达【测试转运中心】',
      });
      expect(nodes[1], {
        'tag': '',
        'time': '2026-10-06 18:05:00',
        'text': '快件已存入菜鸟驿站，取件码 1-1-1111',
      });
      expect(nodes[2], {
        'tag': '',
        'time': '2026-10-07 09:00:00',
        'text': '已签收',
      });
    });
  });

  group('parsePddDomTimeline', () {
    test('日期行后的多行状态描述正确合并续行，并在推荐流前截断', () {
      final now = DateTime.utc(2026, 10, 7, 12);
      const rawText = '''
2026-10-06 14:20:00
快件已到达【测试转运中心】
准备发往测试市北门店分部
2026-10-06 08:00:00
快递已揽收（单号 YT0000000000001）
推荐商品
''';

      final nodes = parsePddDomTimeline(rawText, now: now);
      expect(nodes, hasLength(2));
      expect(nodes[0], {
        'tag': '',
        'time': '2026-10-06 14:20:00',
        'text': '快件已到达【测试转运中心】 准备发往测试市北门店分部',
      });
      expect(nodes[1], {
        'tag': '',
        'time': '2026-10-06 08:00:00',
        'text': '快递已揽收（单号 YT0000000000001）',
      });
    });
  });
}
