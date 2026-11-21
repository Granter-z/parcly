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

  group('looksLikeJdMealText（外卖餐品强特征）', () {
    test('真机三张外卖卡的标题都能识别', () {
      expect(
        looksLikeJdMealText('福利6选 1 单人餐｜闭眼点不亏标准单人餐'),
        isTrue,
      );
      expect(
        looksLikeJdMealText('【性价之王】牛肉大汉堡单人6件爆款套餐 1人份'),
        isTrue,
      );
      expect(
        looksLikeJdMealText('招牌炸蛋螺蛳粉+撒尿肉丸2个 一人份'),
        isTrue,
      );
    });

    test('普通快递商品不误伤', () {
      expect(looksLikeJdMealText('蓝月亮洗衣液 3kg 家庭装'), isFalse);
      expect(looksLikeJdMealText('iPhone 15 手机壳'), isFalse);
      expect(looksLikeJdMealText('京东在途商品'), isFalse);
    });
  });
}
