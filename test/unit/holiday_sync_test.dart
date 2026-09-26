import 'package:flutter_test/flutter_test.dart';

import 'package:schedule_plan/data/models/china_holiday.dart';
import 'package:schedule_plan/data/services/china_holiday_calendar.dart';
import 'package:schedule_plan/data/services/holiday_sync_service.dart';

void main() {
  // 覆盖层是进程级的静态状态，每个用例前后都得擦干净
  setUp(ChinaHolidayCalendar.resetOverride);
  tearDown(ChinaHolidayCalendar.resetOverride);

  group('HolidaySyncService 什么时候该去请求', () {
    final now = DateTime(2026, 9, 26, 10);

    bool shouldFetchAt(DateTime moment, Duration since, {required bool ok}) =>
        HolidaySyncService.shouldFetch(
          now: moment,
          lastAttemptMs: moment.subtract(since).millisecondsSinceEpoch,
          lastOk: ok,
          missingYears: const <int>{2027},
        );

    test('从来没检查过 → 该试', () {
      expect(
        HolidaySyncService.shouldFetch(
          now: now,
          lastAttemptMs: null,
          lastOk: false,
          missingYears: const <int>{2027},
        ),
        isTrue,
      );
    });

    test('该有的年份都齐了 → 不请求，除非过了 90 天的复查窗口', () {
      bool complete(Duration since) => HolidaySyncService.shouldFetch(
            now: now,
            lastAttemptMs: now.subtract(since).millisecondsSinceEpoch,
            lastOk: true,
            missingYears: const <int>{},
          );

      // 光看"缺不缺年份"就会一直返回 true，所以这里必须由节流兜住：
      // 否则每次冷启动都要发一次请求
      expect(complete(const Duration(days: 10)), isFalse);
      expect(complete(const Duration(days: 89)), isFalse);
      expect(complete(const Duration(days: 91)), isTrue);
    });

    test('上次失败 → 6 小时后才敢重试（别把网络打爆）', () {
      expect(shouldFetchAt(now, const Duration(hours: 5), ok: false), isFalse);
      expect(shouldFetchAt(now, const Duration(hours: 7), ok: false), isTrue);
    });

    test('上次成功但仍缺年份：公布窗口期（10 月起）3 天一次，窗口外 30 天一次', () {
      // 9 月，窗口外：一个月瞄一眼就够
      expect(shouldFetchAt(now, const Duration(days: 10), ok: true), isFalse);
      expect(shouldFetchAt(now, const Duration(days: 31), ok: true), isTrue);

      // 11 月，窗口内：国务院刚发的通知，勤快点看
      final november = DateTime(2026, 11, 10, 10);
      expect(shouldFetchAt(november, const Duration(days: 1), ok: true), isFalse);
      expect(shouldFetchAt(november, const Duration(days: 4), ok: true), isTrue);
    });

    test('缺的是"今年或更早"→ 不管几月都勤快重试（那数据早该公布了）', () {
      // 2027 年 1 月刚装上的 App：内置表只到 2026、缓存是空的，
      // 于是缺 2027（当前年）+ 2028。这时候如果按"窗口外 30 天"走，
      // 老师整个一月的课表都是错的——必须按 3 天的节奏追。
      final january = DateTime(2027, 1, 6, 10);
      bool check(Duration since) => HolidaySyncService.shouldFetch(
            now: january,
            lastAttemptMs: january.subtract(since).millisecondsSinceEpoch,
            lastOk: true,
            missingYears: const <int>{2027, 2028},
          );

      expect(check(const Duration(days: 1)), isFalse);
      expect(check(const Duration(days: 4)), isTrue);
    });

    test('系统时间被往回调过（负间隔）也要放行，否则会被永久卡住', () {
      expect(
        HolidaySyncService.shouldFetch(
          now: now,
          lastAttemptMs: now.add(const Duration(days: 5)).millisecondsSinceEpoch,
          lastOk: true,
          missingYears: const <int>{2027},
        ),
        isTrue,
      );
    });

    test('目标年份永远是"今年 + 明年"——跨年不能临时抱佛脚', () {
      expect(
        HolidaySyncService.targetYears(DateTime(2026, 1, 1)),
        <int>{2026, 2027},
      );
      expect(
        HolidaySyncService.targetYears(DateTime(2026, 12, 31)),
        <int>{2026, 2027},
        reason: '12 月 31 日才去取次年的安排，1 月的课表就要算错了',
      );
    });

    test('公布窗口从 10 月开始', () {
      expect(HolidaySyncService.inPublishWindow(DateTime(2026, 9, 30)), isFalse);
      expect(HolidaySyncService.inPublishWindow(DateTime(2026, 10, 1)), isTrue);
      expect(HolidaySyncService.inPublishWindow(DateTime(2026, 12, 1)), isTrue);
      expect(
        HolidaySyncService.inPublishWindow(DateTime(2027, 1, 1)),
        isFalse,
        reason: '1 月早过了次年安排的公布期——这种"缺数据"要靠 overdue 分支追，'
            '不是靠窗口期',
      );
    });
  });

  group('ChinaHolidayCalendar 的远程覆盖层', () {
    const newYear2027 = ChinaHoliday(
      date: '2027-01-01',
      kind: CalendarDayKind.holiday,
      name: HolidayName.newYear,
    );

    test('远程优先、内置兜底：只注入了 2027，2026 的内置数据照旧能查到', () {
      ChinaHolidayCalendar.overrideWith(const <String, ChinaHoliday>{
        '2027-01-01': newYear2027,
      });

      expect(
        ChinaHolidayCalendar.kindOf(DateTime(2027, 1, 1)),
        CalendarDayKind.holiday,
      );
      // 内置兜底：2026 国庆没被覆盖层带走
      expect(
        ChinaHolidayCalendar.kindOf(DateTime(2026, 10, 1)),
        CalendarDayKind.holiday,
      );
      expect(
        ChinaHolidayCalendar.coveredYears.containsAll(<int>[2026, 2027]),
        isTrue,
      );
      // 内置表本身不能被改脏（单测靠它验证通知抄录）
      expect(ChinaHolidayCalendar.holidayDayCount, 61);
      expect(ChinaHolidayCalendar.builtinYears, <int>{2025, 2026});
    });

    test('同一天两边冲突时听远程的（远程是官方数据的结构化搬运，更新更及时）', () {
      // 假设 2026 国庆安排被临时调整，内置表还写着 10/8 放假
      ChinaHolidayCalendar.overrideWith(const <String, ChinaHoliday>{
        '2026-10-08': ChinaHoliday(
          date: '2026-10-08',
          kind: CalendarDayKind.workday,
        ),
      });

      expect(
        ChinaHolidayCalendar.kindOf(DateTime(2026, 10, 8)),
        CalendarDayKind.workday,
      );
      expect(ChinaHolidayCalendar.isHoliday(DateTime(2026, 10, 8)), isFalse);
    });

    test('覆盖层能让内置表没有的年份"长出"官方数据', () {
      final before = ChinaHolidayCalendar.kindOf(DateTime(2027, 5, 1));
      expect(before, CalendarDayKind.weekend, reason: '2027-05-01 是周六');

      ChinaHolidayCalendar.overrideWith(const <String, ChinaHoliday>{
        '2027-05-01': ChinaHoliday(
          date: '2027-05-01',
          kind: CalendarDayKind.holiday,
          name: HolidayName.labourDay,
        ),
      });

      expect(
        ChinaHolidayCalendar.kindOf(DateTime(2027, 5, 1)),
        CalendarDayKind.holiday,
      );
    });

    test('清空覆盖后完全回到内置表', () {
      ChinaHolidayCalendar.overrideWith(const <String, ChinaHoliday>{
        '2027-01-01': newYear2027,
      });
      expect(ChinaHolidayCalendar.coveredYears.contains(2027), isTrue);

      ChinaHolidayCalendar.resetOverride();
      expect(ChinaHolidayCalendar.coveredYears.contains(2027), isFalse);
      expect(
        ChinaHolidayCalendar.coveredYears,
        equals(ChinaHolidayCalendar.builtinYears),
      );
    });
  });

  group('CalendarDayKind.fromStorage', () {
    test('四种都认得出', () {
      expect(CalendarDayKind.fromStorage('workday'), CalendarDayKind.workday);
      expect(CalendarDayKind.fromStorage('weekend'), CalendarDayKind.weekend);
      expect(CalendarDayKind.fromStorage('holiday'), CalendarDayKind.holiday);
      expect(
        CalendarDayKind.fromStorage('makeupWorkday'),
        CalendarDayKind.makeupWorkday,
      );
    });

    test('认不出来一律回落工作日——宁可少算一个假，也不要把当天课凭空抹掉', () {
      expect(CalendarDayKind.fromStorage('garbage'), CalendarDayKind.workday);
      expect(CalendarDayKind.fromStorage(null), CalendarDayKind.workday);
      expect(CalendarDayKind.fromStorage(''), CalendarDayKind.workday);
    });
  });
}
