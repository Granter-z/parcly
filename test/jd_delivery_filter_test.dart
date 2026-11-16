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

    test('虚拟商品没有快递跟踪字段，排除', () {
      expect(isJdCourierDelivery({'orderId': '4'}), isFalse);
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
