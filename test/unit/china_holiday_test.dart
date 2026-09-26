import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:schedule_plan/core/theme/app_colors.dart';
import 'package:schedule_plan/data/models/china_holiday.dart';
import 'package:schedule_plan/data/services/china_holiday_calendar.dart';
import 'package:schedule_plan/data/services/holiday_service.dart';

/// 中国节假日 / 调休的数据层单测（第 13 轮）。
///
/// 这些用例的意义不只是"函数算对了"，更是**把国务院通知抄进了测试里**：
/// 内置表的每一条数据都对应通知里的一句话，抄错一个日期就有一条挂掉。
/// 数据来源：
/// - 2025 年：国办发明电〔2024〕12 号
/// - 2026 年：2025-11-04 发布的通知（放假日历共 33 天）
void main() {
  group('内置放假表（抄的是国务院通知，不是推算）', () {
    test('2026 年元旦：1/1-1/3 放假、1/4（周日）上班', () {
      expect(ChinaHolidayCalendar.isHoliday(DateTime(2026, 1, 1)), isTrue);
      expect(ChinaHolidayCalendar.isHoliday(DateTime(2026, 1, 3)), isTrue);
      expect(ChinaHolidayCalendar.isMakeupWorkday(DateTime(2026, 1, 4)), isTrue);
      final info = ChinaHolidayCalendar.infoOf(DateTime(2026, 1, 1));
      expect(info?.name, HolidayName.newYear);
    });

    test('2026 年春节：2/15-2/23 放假、2/14 与 2/28 上班', () {
      expect(ChinaHolidayCalendar.isHoliday(DateTime(2026, 2, 15)), isTrue);
      expect(ChinaHolidayCalendar.isHoliday(DateTime(2026, 2, 23)), isTrue);
      expect(ChinaHolidayCalendar.isHoliday(DateTime(2026, 2, 14)), isFalse);
      expect(ChinaHolidayCalendar.isHoliday(DateTime(2026, 2, 24)), isFalse);
      expect(ChinaHolidayCalendar.isMakeupWorkday(DateTime(2026, 2, 14)), isTrue);
      expect(ChinaHolidayCalendar.isMakeupWorkday(DateTime(2026, 2, 28)), isTrue);
      expect(
        ChinaHolidayCalendar.infoOf(DateTime(2026, 2, 20))?.name,
        HolidayName.springFestival,
      );
    });

    test('2026 年清明 / 端午 / 中秋：连续三天，不调休', () {
      for (final day in <DateTime>[
        DateTime(2026, 4, 4),
        DateTime(2026, 4, 5),
        DateTime(2026, 4, 6),
      ]) {
        expect(ChinaHolidayCalendar.isHoliday(day), isTrue, reason: '$day 应放假');
      }
      expect(ChinaHolidayCalendar.isHoliday(DateTime(2026, 6, 19)), isTrue);
      expect(ChinaHolidayCalendar.isHoliday(DateTime(2026, 6, 21)), isTrue);
      expect(ChinaHolidayCalendar.isHoliday(DateTime(2026, 9, 25)), isTrue);
      // 2026-09-27 是周日，但它是中秋假期的最后一天 —— 属于"放假"而不是"周末"
      expect(ChinaHolidayCalendar.kindOf(DateTime(2026, 9, 27)),
          CalendarDayKind.holiday);
    });

    test('2026 年国庆：10/1-10/7 放假、9/20 与 10/10 上班', () {
      expect(ChinaHolidayCalendar.isHoliday(DateTime(2026, 10, 1)), isTrue);
      expect(ChinaHolidayCalendar.isHoliday(DateTime(2026, 10, 7)), isTrue);
      expect(ChinaHolidayCalendar.isHoliday(DateTime(2026, 10, 8)), isFalse);
      expect(ChinaHolidayCalendar.isMakeupWorkday(DateTime(2026, 9, 20)), isTrue);
      expect(ChinaHolidayCalendar.isMakeupWorkday(DateTime(2026, 10, 10)), isTrue);
      expect(
        ChinaHolidayCalendar.infoOf(DateTime(2026, 10, 10))?.name,
        HolidayName.nationalDay,
        reason: '调休日的名字要指向它补的那个节日',
      );
    });

    test('2025 年春节 / 劳动节 / 国庆中秋', () {
      expect(ChinaHolidayCalendar.isHoliday(DateTime(2025, 1, 28)), isTrue);
      expect(ChinaHolidayCalendar.isHoliday(DateTime(2025, 2, 4)), isTrue);
      expect(ChinaHolidayCalendar.isMakeupWorkday(DateTime(2025, 1, 26)), isTrue);
      expect(ChinaHolidayCalendar.isMakeupWorkday(DateTime(2025, 4, 27)), isTrue);
      expect(ChinaHolidayCalendar.isMakeupWorkday(DateTime(2025, 9, 28)), isTrue);
      // 2025 元旦只有 1 天，1/2 正常上班
      expect(ChinaHolidayCalendar.isHoliday(DateTime(2025, 1, 1)), isTrue);
      expect(ChinaHolidayCalendar.isHoliday(DateTime(2025, 1, 2)), isFalse);
      expect(
        ChinaHolidayCalendar.infoOf(DateTime(2025, 10, 5))?.name,
        HolidayName.nationalDayMidAutumn,
      );
    });

    test('普通工作日 / 周末的回落口径', () {
      // 2026-09-23 是周三，不是假日
      expect(ChinaHolidayCalendar.kindOf(DateTime(2026, 9, 23)),
          CalendarDayKind.workday);
      // 2026-09-19 是周六，且不在中秋假期（9/25-9/27）里
      expect(ChinaHolidayCalendar.kindOf(DateTime(2026, 9, 19)),
          CalendarDayKind.weekend);
      expect(ChinaHolidayCalendar.infoOf(DateTime(2026, 9, 23)), isNull);
      // 反例：9/26 也是周六，但它在中秋假期里 —— 这类日子最容易被写错
      expect(ChinaHolidayCalendar.kindOf(DateTime(2026, 9, 26)),
          CalendarDayKind.holiday);
    });

    test('天数与通知里公布的「放假调休共 33 天」对得上', () {
      // 2026：3+9+3+5+3+3+7 = 33；2025：1+8+3+5+3+8 = 28；合计 61
      expect(ChinaHolidayCalendar.holidayDayCount, 61);
      // 2025 五次调休 + 2026 六次 = 11
      expect(ChinaHolidayCalendar.makeupDayCount, 11);
    });

    test('覆盖年份之外的日期：只按周末回落，不假装有数据', () {
      final future = DateTime(2031, 3, 4); // 周二
      expect(ChinaHolidayCalendar.infoOf(future), isNull);
      expect(ChinaHolidayCalendar.kindOf(future), CalendarDayKind.workday);
      expect(ChinaHolidayCalendar.coveredYears.contains(2031), isFalse);
    });
  });

  group('"上周几的课"的解析规则', () {
    test('调休日没确认过 → 不调整（按当天自己的星期几）', () {
      final sunday = DateTime(2026, 9, 20); // 周日调休上班
      expect(HolidayService.labelWeekdayOf(sunday, null), DateTime.sunday);
    });

    test('调休日确认过 → 用老师选的星期几', () {
      final sunday = DateTime(2026, 9, 20);
      expect(HolidayService.labelWeekdayOf(sunday, 3), DateTime.wednesday);
      expect(HolidayService.labelWeekdayOf(sunday, 5), DateTime.friday);
    });

    test('非调休日忽略覆盖值（脏数据不能改课时）', () {
      final workday = DateTime(2026, 9, 23); // 周三
      final holiday = DateTime(2026, 10, 1); // 国庆
      expect(HolidayService.labelWeekdayOf(workday, 5), DateTime.wednesday);
      expect(HolidayService.labelWeekdayOf(holiday, 5), DateTime.thursday);
    });

    test('越界的覆盖值收敛到 1~7，不会算出"第 0 天"', () {
      final sunday = DateTime(2026, 9, 20);
      expect(HolidayService.labelWeekdayOf(sunday, 0), DateTime.monday);
      expect(HolidayService.labelWeekdayOf(sunday, 99), DateTime.sunday);
    });
  });

  group('一周的执行方案（课时结算的基础）', () {
    HolidayWeek weekOf(DateTime day) {
      // 直接构造，绕开数据库（覆盖值由测试自己给）
      final start = DateTime(day.year, day.month, day.day - (day.weekday - 1));
      return HolidayWeek(
        weekStart: start,
        days: <HolidayDay>[
          for (var i = 0; i < 7; i++)
            HolidayDay(
              date: start.add(Duration(days: i)),
              kind: ChinaHolidayCalendar.kindOf(start.add(Duration(days: i))),
              labelWeekday: HolidayService.labelWeekdayOf(
                start.add(Duration(days: i)),
                null,
              ),
            ),
        ],
      );
    }

    test('中秋那一周：9/25-9/27 放假 → 只剩周一到周四要上课', () {
      final week = weekOf(DateTime(2026, 9, 23)); // 周三 → 本周 9/21-9/27
      expect(week.classDays.length, 4);
      expect(week.holidayDaysCount, 3);
      expect(week.hasAdjustment, isTrue);
      expect(week.makeupDay, isNull);
    });

    test('9/14-9/20 那一周：周日调休上班 → 上课天数反而变成 6 天', () {
      final week = weekOf(DateTime(2026, 9, 16)); // 周三 → 9/14-9/20
      expect(week.classDays.length, 6);
      expect(week.makeupDay?.date, DateTime(2026, 9, 20));
      expect(week.makeupDay?.kind, CalendarDayKind.makeupWorkday);
    });

    test('国庆那一周（10/5-10/11）：三天假 + 周六补班 → 只剩周四、周五、周六', () {
      final week = weekOf(DateTime(2026, 10, 7));
      expect(
        week.classDays.map((day) => day.date.day).toList(),
        <int>[8, 9, 10],
      );
      expect(week.makeupDay?.date, DateTime(2026, 10, 10));
    });

    test('普通一周：五天上课、没有调整', () {
      final week = weekOf(DateTime(2026, 6, 10));
      expect(week.classDays.length, 5);
      expect(week.hasAdjustment, isFalse);
    });
  });

  group('工具箱卡片色板（低饱和但要"配得好看"）', () {
    double luminance(Color color) {
      double channel(double raw) {
        final c = raw / 255;
        return c <= 0.03928
            ? c / 12.92
            : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
      }

      return 0.2126 * channel(color.r * 255) +
          0.7152 * channel(color.g * 255) +
          0.0722 * channel(color.b * 255);
    }

    test('六个色相：明度锁在一个很窄的区间里（深浅一致才像一套）', () {
      final values = ToolCardTone.all
          .map((tone) => luminance(tone.light))
          .toList(growable: false);
      final min = values.reduce((a, b) => a < b ? a : b);
      final max = values.reduce((a, b) => a > b ? a : b);
      expect(max - min, lessThan(0.04), reason: '明度差太大就会有的亮有的闷');
      expect(min, greaterThan(0.14));
      expect(max, lessThan(0.20));
    });

    test('白字压上去的对比度都在 4.5:1 上下', () {
      for (final tone in ToolCardTone.all) {
        final contrast = 1.05 / (luminance(tone.light) + 0.05);
        expect(contrast, greaterThan(4.4), reason: '${tone.key} 的白字太糊了');
      }
    });

    test('六个色相互不相同，且每张卡的两端色不一样（卡面有光）', () {
      final keys = ToolCardTone.all.map((tone) => tone.key).toSet();
      expect(keys.length, ToolCardTone.all.length);
      for (final tone in ToolCardTone.all) {
        expect(tone.light, isNot(equals(tone.deep)));
      }
    });

    test('暗色主题下提亮，避免卡片在暗底上"陷进去"', () {
      final tone = ToolCardTone.blue;
      final dark = tone.gradientFor(Brightness.dark);
      final light = tone.gradientFor(Brightness.light);
      expect(luminance(dark.first), greaterThan(luminance(light.first)));
      expect(luminance(dark.last), greaterThan(luminance(light.last)));
    });
  });
}
