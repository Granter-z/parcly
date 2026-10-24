import 'package:flutter_test/flutter_test.dart';
import 'package:pickup_app/ui/providers/pickup_point_alias_provider.dart';

void main() {
  test('preferredCanonicalName：较长优先', () {
    expect(preferredCanonicalName('北门店', '菜鸟驿站'), '菜鸟驿站');
    expect(preferredCanonicalName('菜鸟驿站北门店', '北门店'), '菜鸟驿站北门店');
  });
}
