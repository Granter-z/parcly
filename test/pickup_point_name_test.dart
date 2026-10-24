import 'package:flutter_test/flutter_test.dart';
import 'package:pickup_app/core/parser/pickup_point_name.dart';
import 'package:pickup_app/core/parser/taobao_trace_parser.dart';

void main() {
  group('extractPickupPointName P28-c 非驿站取件点', () {
    test('丰巢柜机（无「驿站」字样）写入取件点名', () {
      const text = '快件已放入绿城诚园北门丰巢，请凭取件码取件';
      expect(extractPickupPointName(text), '绿城诚园北门丰巢');
      expect(TaobaoTraceParser.extractStationName(text), '绿城诚园北门丰巢');
    });

    test('自提柜写入取件点名', () {
      const text = '包裹已存放至幸福里南门自提柜，请及时领取';
      expect(extractPickupPointName(text), '幸福里南门自提柜');
    });

    test('物业代收点写入取件点名', () {
      const text = '已派送至【阳光花园物业代收点】，请凭取件码领取';
      expect(extractPickupPointName(text), '阳光花园物业代收点');
    });

    test('便利店门店写入取件点名', () {
      const text = '投递至学府路全家便利店，营业时间 07:00-23:00';
      expect(extractPickupPointName(text), '学府路全家便利店');
    });

    test('【】内兔喜生活品牌点写入取件点名', () {
      const text = '已到达【测试小区东门兔喜生活】，请取件';
      expect(extractPickupPointName(text), '测试小区东门兔喜生活');
    });

    test('纯转运文案不误提取件点', () {
      expect(extractPickupPointName('快件已到达【广州转运中心】'), '');
      expect(extractPickupPointName('运输中，下一站杭州分拨中心'), '');
    });
  });
}
