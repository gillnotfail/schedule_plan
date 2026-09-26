import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_plan/core/utils/time_utils.dart';

void main() {
  group('TimeUtils.tryParseMinutes', () {
    test('正常时间字符串解析为分钟数', () {
      expect(TimeUtils.tryParseMinutes('00:00'), 0);
      expect(TimeUtils.tryParseMinutes('08:30'), 510);
      expect(TimeUtils.tryParseMinutes('23:59'), 1439);
    });

    test('非法格式返回 null', () {
      expect(TimeUtils.tryParseMinutes('24:00'), isNull);
      expect(TimeUtils.tryParseMinutes('08:60'), isNull);
      expect(TimeUtils.tryParseMinutes('8:30:00'), isNull);
      expect(TimeUtils.tryParseMinutes('abc'), isNull);
      expect(TimeUtils.tryParseMinutes(null), isNull);
    });
  });

  group('TimeUtils.parseMinutes', () {
    test('非法输入抛 FormatException', () {
      expect(() => TimeUtils.parseMinutes('25:00'), throwsA(isA<FormatException>()));
    });
  });

  group('TimeUtils.formatMinutes', () {
    test('分钟数零填充格式化', () {
      expect(TimeUtils.formatMinutes(0), '00:00');
      expect(TimeUtils.formatMinutes(510), '08:30');
      expect(TimeUtils.formatMinutes(1439), '23:59');
    });

    test('越界分钟数回绕到当日', () {
      expect(TimeUtils.formatMinutes(1440), '00:00');
      expect(TimeUtils.formatMinutes(1500), '01:00');
      expect(TimeUtils.formatMinutes(-60), '23:00');
    });
  });

  group('TimeUtils.overlaps', () {
    test('半开区间判定：首尾相接不算重叠', () {
      // [08:00, 08:45) 与 [08:45, 09:30) 不重叠
      expect(TimeUtils.overlaps(480, 525, 525, 570), isFalse);
    });

    test('真重叠判定为真', () {
      expect(TimeUtils.overlaps(480, 540, 500, 560), isTrue);
    });

    test('包含关系判定为真', () {
      expect(TimeUtils.overlaps(480, 720, 500, 520), isTrue);
      expect(TimeUtils.overlaps(500, 520, 480, 720), isTrue);
    });

    test('完全分离判定为假', () {
      expect(TimeUtils.overlaps(480, 525, 600, 645), isFalse);
    });
  });

  group('TimeUtils.snapToStep / snapTime', () {
    test('按 5 分钟刻度就近吸附', () {
      expect(TimeUtils.snapToStep(482), 480);
      expect(TimeUtils.snapToStep(483), 485);
      expect(TimeUtils.snapToStep(480), 480);
    });

    test('snapTime 不会产生非法时间', () {
      expect(TimeUtils.snapTime('23:58'), '23:55');
      expect(TimeUtils.snapTime('08:03'), '08:05');
      expect(TimeUtils.snapTime('非法'), '非法');
    });
  });
}
