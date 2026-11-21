import 'package:flutter_test/flutter_test.dart';
import 'package:pickup_app/platform/connectors/jd_delivery_filter.dart';

void main() {
  group('isJdCourierDelivery', () {
    test('progressInfo=logistics 的订单是快递包裹', () {
      expect(
        isJdCourierDelivery({
          'orderId': '1',
          'progressInfo': {'progressId': 'logistics', 'content': '运输中'},
        }),
        isTrue,
      );
    });

    test('秒送订单即使带 progressInfo=logistics 也排除', () {
      expect(
        isJdCourierDelivery({
          'orderId': '2',
          'progressInfo': {'progressId': 'logistics', 'content': '骑手正在配送'},
          'specialDealList': [
            {'isStore2Home': true},
          ],
        }),
        isFalse,
      );
    });

    test('progressLink 含 store2home 的秒送单排除', () {
      expect(
        isJdCourierDelivery({
          'orderId': '3',
          'progressInfo': {
            'progressId': 'logistics',
            'progressLink': 'https://trade.m.jd.com/store2home/track',
          },
        }),
        isFalse,
      );
    });

    test('无物流结构的终态订单排除（虚拟商品/历史外卖）', () {
      expect(
        isJdCourierDelivery({'orderId': '4', 'orderStatusName': 'Accomplish'}),
        isFalse,
      );
      expect(isJdCourierDelivery({'orderId': '4b'}), isFalse);
    });

    test('未发货的新快递保留（不能因缺 progressInfo 丢单）', () {
      expect(
        isJdCourierDelivery({'orderId': '5', 'orderStatusName': '待发货'}),
        isTrue,
      );
      expect(
        isJdCourierDelivery({'orderId': '6', 'orderStatusName': 'WaitDeliver'}),
        isTrue,
      );
      expect(
        isJdCourierDelivery({'orderId': '7', 'orderStatus': '待出库'}),
        isTrue,
      );
    });

    test('骑手文案的即时单即使状态活跃也排除', () {
      expect(
        isJdCourierDelivery({
          'orderId': '8',
          'orderStatusName': 'WaitReceive',
          'message': '骑手已将包裹送达',
        }),
        isFalse,
      );
    });
  });

  group('looksLikeJdInstantDeliveryText', () {
    test('骑手/达达/分钟送达是即时配送', () {
      expect(looksLikeJdInstantDeliveryText('骑手已接单，正在赶来'), isTrue);
      expect(looksLikeJdInstantDeliveryText('达达配送中'), isTrue);
      expect(looksLikeJdInstantDeliveryText('预计 30 分钟送达'), isTrue);
    });

    test('普通快递文案不误伤', () {
      expect(looksLikeJdInstantDeliveryText('快件已到达菜鸟驿站'), isFalse);
      expect(looksLikeJdInstantDeliveryText('预计明天送达'), isFalse);
      expect(looksLikeJdInstantDeliveryText('派件中'), isFalse);
    });
  });
}
