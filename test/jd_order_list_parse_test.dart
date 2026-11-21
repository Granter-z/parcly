// 京东订单响应层级回归：真机根节点是 {code,msg,version,data,traceId}，
// 写死 body.orderList 会导致整包解析失败、退化成 DOM 兜底（脏标题 + 状态丢失）。
import 'package:flutter_test/flutter_test.dart';
import 'package:pickup_app/platform/connectors/jd_connector.dart';

void main() {
  group('isJdOrderListPayload', () {
    test('配置包里有 orderList 字样但不是订单数据', () {
      expect(
        isJdOrderListPayload(
          '{"data":{"navigation":{"orderListConfig":{}}}}',
        ),
        isFalse,
      );
    });

    test('带 orderId + wareInfoList 才是订单列表', () {
      expect(
        isJdOrderListPayload(
          '{"data":{"orderList":[{"orderId":"1","wareInfoList":[]}]}}',
        ),
        isTrue,
      );
    });
  });

  group('debugParseOrders（结构化源权威判定）', () {
    test('空 orderList 不当作权威（防一次钩子漏抓就清卡）', () {
      final connector = JdH5Connector();
      expect(connector.debugParseOrders('{"data":{"orderList":[]}}'), isFalse);
    });

    test('配置/埋点包不是权威', () {
      final connector = JdH5Connector();
      expect(
        connector.debugParseOrders(
          '{"data":{"navigation":{"orderListConfig":{}}}}',
        ),
        isFalse,
      );
    });

    test('真实订单数组（非空且带 orderId）才是权威', () {
      final connector = JdH5Connector();
      expect(
        connector.debugParseOrders(
          '{"data":{"orderList":[{"orderId":"1","wareInfoList":[]}]}}',
        ),
        isTrue,
      );
    });

    test('配置节点里的空 orderList 不能抢占真实订单数组', () {
      final connector = JdH5Connector();
      expect(
        connector.debugParseOrders(
          '{"config":{"orderList":[]},'
          '"data":{"orderList":[{"orderId":"1","wareInfoList":[]}]}}',
        ),
        isTrue,
      );
    });
  });

  group('debugFindJdOrderList', () {
    test('订单列表在 data 下（真机结构）', () {
      final root = {
        'code': 0,
        'msg': '',
        'version': '1',
        'data': {
          'orderList': [
            {'orderId': '1', 'orderStatusInfo': {}},
          ],
        },
        'traceId': 'x',
      };
      final list = JdH5Connector.debugFindJdOrderList(root);
      expect(list, isNotNull);
      expect((list!.first as Map)['orderId'], '1');
    });

    test('多层包裹也能找到', () {
      final root = {
        'data': {
          'body': {
            'orderList': [
              {'orderId': '2'},
            ],
          },
        },
      };
      final list = JdH5Connector.debugFindJdOrderList(root);
      expect((list!.first as Map)['orderId'], '2');
    });

    test('空 orderList 不命中，继续找真正的订单数组', () {
      expect(
        JdH5Connector.debugFindJdOrderList({
          'config': {'orderList': <dynamic>[]},
          'data': {
            'orderList': [
              {'orderId': '1', 'wareInfoList': <dynamic>[]},
            ],
          },
        }),
        isNotNull,
      );
      // 整包只有空数组 → 视为没有结构化订单列表
      expect(
        JdH5Connector.debugFindJdOrderList({
          'data': {'orderList': <dynamic>[]},
        }),
        isNull,
      );
    });

    test('没有订单数组时返回 null', () {
      expect(
        JdH5Connector.debugFindJdOrderList({'data': {'foo': 'bar'}}),
        isNull,
      );
      expect(
        JdH5Connector.debugFindJdOrderList([
          {'notOrderId': '1'},
        ]),
        isNull,
      );
    });
  });
}