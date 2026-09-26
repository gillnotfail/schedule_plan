import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_plan/core/utils/date_utils.dart';

void main() {
  group('DateUtils.formatDate', () {
    test('零填充为 YYYY-MM-DD', () {
      expect(DateUtils.formatDate(DateTime(2026, 3, 5)), '2026-03-05');
      expect(DateUtils.formatDate(DateTime(2026, 12, 31)), '2026-12-31');
    });
  });

  group('DateUtils.tryParseDate', () {
    test('合法日期解析成功', () {
      final parsed = DateUtils.tryParseDate('2026-03-05');
      expect(parsed, isNotNull);
      expect(parsed!.year, 2026);
      expect(parsed.month, 3);
      expect(parsed.day, 5);
    });

    test('非法日期或格式返回 null', () {
      expect(DateUtils.tryParseDate('2026-02-30'), isNull);
      expect(DateUtils.tryParseDate('2026/03/05'), isNull);
      expect(DateUtils.tryParseDate(''), isNull);
      expect(DateUtils.tryParseDate(null), isNull);
    });
  });

  group('周计算', () {
    test('startOfWeek 固定回到周一（与 weekday=1 语义一致）', () {
      // 2026-09-18 是周五
      final friday = DateTime(2026, 9, 18);
      expect(DateUtils.isoWeekday(friday), 5);
      final monday = DateUtils.startOfWeek(friday);
      expect(DateUtils.formatDate(monday), '2026-09-14');
      expect(DateUtils.isoWeekday(monday), 1);
    });

    test('周日不会被算到下一周', () {
      // 2026-09-20 是周日
      final sunday = DateTime(2026, 9, 20);
      final monday = DateUtils.startOfWeek(sunday);
      expect(DateUtils.formatDate(monday), '2026-09-14');
    });

    test('weekDays 返回周一到周日共 7 天', () {
      final days = DateUtils.weekDays(DateTime(2026, 9, 18));
      expect(days.length, 7);
      expect(DateUtils.formatDate(days.first), '2026-09-14');
      expect(DateUtils.formatDate(days.last), '2026-09-20');
      for (var i = 0; i < days.length; i++) {
        expect(DateUtils.isoWeekday(days[i]), i + 1);
      }
    });
  });

  group('月计算', () {
    test('startOfNextMonth 跨年正确', () {
      expect(
        DateUtils.formatDate(DateUtils.startOfNextMonth(DateTime(2026, 12, 5))),
        '2027-01-01',
      );
      expect(
        DateUtils.formatDate(DateUtils.startOfNextMonth(DateTime(2026, 3, 5))),
        '2026-04-01',
      );
    });
  });

  group('日期比较', () {
    test('isSameDay 忽略时分秒', () {
      expect(
        DateUtils.isSameDay(DateTime(2026, 3, 5, 8, 0), DateTime(2026, 3, 5, 23, 59)),
        isTrue,
      );
      expect(
        DateUtils.isSameDay(DateTime(2026, 3, 5), DateTime(2026, 3, 6)),
        isFalse,
      );
    });

    test('daysBetween 按自然日计算', () {
      expect(
        DateUtils.daysBetween(DateTime(2026, 3, 5, 23, 0), DateTime(2026, 3, 6, 1, 0)),
        1,
      );
      expect(
        DateUtils.daysBetween(DateTime(2026, 3, 6), DateTime(2026, 3, 5)),
        -1,
      );
    });
  });

  group('DateUtils.shiftMonth', () {
    test('普通日期按月平移', () {
      expect(
        DateUtils.formatDate(DateUtils.shiftMonth(DateTime(2026, 3, 15), -1)),
        '2026-02-15',
      );
      expect(
        DateUtils.formatDate(DateUtils.shiftMonth(DateTime(2026, 3, 15), 1)),
        '2026-04-15',
      );
    });

    test('月末日期收敛到目标月最后一天，不溢出进位', () {
      // 3/31 往前一个月是 2/28，而不是 Dart 原生算法给出的 3/3
      expect(
        DateUtils.formatDate(DateUtils.shiftMonth(DateTime(2026, 3, 31), -1)),
        '2026-02-28',
      );
      // 闰年 2 月
      expect(
        DateUtils.formatDate(DateUtils.shiftMonth(DateTime(2028, 3, 31), -1)),
        '2028-02-29',
      );
      // 1/31 往前一个月 = 去年 12/31（该月正好有 31 天，不用收敛）
      expect(
        DateUtils.formatDate(DateUtils.shiftMonth(DateTime(2026, 1, 31), -1)),
        '2025-12-31',
      );
      // 5/31 往后一个月 = 6/30
      expect(
        DateUtils.formatDate(DateUtils.shiftMonth(DateTime(2026, 5, 31), 1)),
        '2026-06-30',
      );
    });

    test('跨年平移', () {
      expect(
        DateUtils.formatDate(DateUtils.shiftMonth(DateTime(2026, 12, 10), 1)),
        '2027-01-10',
      );
      expect(
        DateUtils.formatDate(DateUtils.shiftMonth(DateTime(2026, 1, 10), -1)),
        '2025-12-10',
      );
    });
  });

  group('DateUtils.addDays', () {
    test('字符串日期加偏移', () {
      expect(DateUtils.addDays('2026-02-28', 1), '2026-03-01');
      expect(DateUtils.addDays('2026-03-01', -1), '2026-02-28');
    });

    test('非法输入原样返回（不抛异常）', () {
      expect(DateUtils.addDays('非法日期', 3), '非法日期');
    });
  });

  group('DateUtils.nearestWeekdayDate（课表「去点名」定位）', () {
    // 2026-09-16 是周三
    final wednesday = DateTime(2026, 9, 16);

    test('本周还没到的日子用本周', () {
      expect(
        DateUtils.formatDate(DateUtils.nearestWeekdayDate(wednesday, 5)),
        '2026-09-18',
      );
    });

    test('本周已经过去的过日子顺延到下周', () {
      expect(
        DateUtils.formatDate(DateUtils.nearestWeekdayDate(wednesday, 1)),
        '2026-09-21',
      );
    });

    test('当天就是这一天时直接用它', () {
      expect(
        DateUtils.formatDate(DateUtils.nearestWeekdayDate(wednesday, 3)),
        '2026-09-16',
      );
    });

    test('周日（7）也能正确定位', () {
      expect(
        DateUtils.formatDate(DateUtils.nearestWeekdayDate(wednesday, 7)),
        '2026-09-20',
      );
      // 周日在周三之后，所以取本周；若参考日是周一则同样取本周日
      expect(
        DateUtils.formatDate(
          DateUtils.nearestWeekdayDate(DateTime(2026, 9, 14), 7),
        ),
        '2026-09-20',
      );
    });
  });
}
