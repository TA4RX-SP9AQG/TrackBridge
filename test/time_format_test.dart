import 'package:flutter_test/flutter_test.dart';
import 'package:trackbridge/core/time_format.dart';

void main() {
  test('pads hours, minutes and seconds', () {
    final t = DateTime(2026, 1, 2, 3, 4, 5);
    expect(formatClock(t), '03:04');
    expect(formatClockSeconds(t), '03:04:05');
    expect(formatClockSeconds(DateTime(2026, 1, 2, 23, 59, 59)), '23:59:59');
  });
}
