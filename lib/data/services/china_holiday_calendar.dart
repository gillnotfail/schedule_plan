import 'package:schedule_plan/core/utils/date_utils.dart';
import 'package:schedule_plan/data/models/china_holiday.dart';

/// 一段连续放假区间（国务院通知里就是按"X 月 X 日至 X 月 X 日放假"写的）。
class _Range {
  const _Range(this.from, this.to, this.name);

  final String from;
  final String to;
  final HolidayName name;
}

/// 调休上班日（"X 月 X 日上班"）。
class _Makeup {
  const _Makeup(this.date, this.name);

  final String date;
  final HolidayName name;
}

/// 中国法定节假日与调休上班日表。
///
/// ## 两条数据来路，一主一备
///
/// 1. **内置常量表**（本文件，[_ranges] / [_makeup]）：逐条抄自国务院办公厅的
///    年度通知，不做推算。完全离线、永远算得对，是**出厂兜底**。
/// 2. **联网取回的年度缓存**（`holiday_sync_service.dart` → `holiday_day` 表）：
///    启动时通过 [overrideWith] 灌进来，用来补内置表还没有的年份。
///
/// 查表时**远程优先、内置兜底**：同一天两边都有时听远程的（它是官方数据的
/// 结构化搬运，比手抄的常量更容易更新）。远程没有该日期就回落内置表。
///
/// ## 为什么还要留内置表
///
/// 联网保鲜解决的是"每年得改代码发版"这个痛点，但它引入了新的失败面：
/// 没网、接口关门、用户不想联网。内置表是这些情况下的下限——
/// 哪怕上面全挂，最近两个年度的假期照旧算得对，功能不会变坏。
///
/// ## 覆盖之外的年份
///
/// 两边都查不到就按"周六周日休息、周一~周五上班"处理（[coveredYears]
/// 用来让 UI 说明这一点，别假装数据是全的）。
/// 内置表这边补新年度的办法：等国务院通知出来（一般每年 11 月），
/// 在 [_ranges] / [_makeup] 里加一个年度块，别的地方一行都不用改。
abstract final class ChinaHolidayCalendar {
  static const List<_Range> _ranges = <_Range>[
    // ------------------------------------------------------------------ 2025
    _Range('2025-01-01', '2025-01-01', HolidayName.newYear),
    _Range('2025-01-28', '2025-02-04', HolidayName.springFestival),
    _Range('2025-04-04', '2025-04-06', HolidayName.qingming),
    _Range('2025-05-01', '2025-05-05', HolidayName.labourDay),
    _Range('2025-05-31', '2025-06-02', HolidayName.dragonBoat),
    _Range('2025-10-01', '2025-10-08', HolidayName.nationalDayMidAutumn),
    // ------------------------------------------------------------------ 2026
    _Range('2026-01-01', '2026-01-03', HolidayName.newYear),
    _Range('2026-02-15', '2026-02-23', HolidayName.springFestival),
    _Range('2026-04-04', '2026-04-06', HolidayName.qingming),
    _Range('2026-05-01', '2026-05-05', HolidayName.labourDay),
    _Range('2026-06-19', '2026-06-21', HolidayName.dragonBoat),
    _Range('2026-09-25', '2026-09-27', HolidayName.midAutumn),
    _Range('2026-10-01', '2026-10-07', HolidayName.nationalDay),
  ];

  static const List<_Makeup> _makeup = <_Makeup>[
    // ------------------------------------------------------------------ 2025
    _Makeup('2025-01-26', HolidayName.springFestival),
    _Makeup('2025-02-08', HolidayName.springFestival),
    _Makeup('2025-04-27', HolidayName.labourDay),
    _Makeup('2025-09-28', HolidayName.nationalDayMidAutumn),
    _Makeup('2025-10-11', HolidayName.nationalDayMidAutumn),
    // ------------------------------------------------------------------ 2026
    _Makeup('2026-01-04', HolidayName.newYear),
    _Makeup('2026-02-14', HolidayName.springFestival),
    _Makeup('2026-02-28', HolidayName.springFestival),
    _Makeup('2026-05-09', HolidayName.labourDay),
    _Makeup('2026-09-20', HolidayName.nationalDay),
    _Makeup('2026-10-10', HolidayName.nationalDay),
  ];

  /// **内置常量表**覆盖的年份（不含联网取回的，那部分见 [coveredYears]）。
  static const Set<int> builtinYears = <int>{2025, 2026};

  /// 出厂常量表展开后的查表：key = "YYYY-MM-DD"。
  static final Map<String, ChinaHoliday> _builtin = _expand();

  /// 运行期注入的年度缓存（来自 `holiday_day` 表）。进程内有效，
  /// 重启后由 `HolidaySyncService.bootstrap()` 重新灌一次。
  static Map<String, ChinaHoliday> _remote = const <String, ChinaHoliday>{};

  /// 缓存里出现过哪些年份（由 [overrideWith] 一并算好，免得每次查表都解析 key）。
  static Set<int> _remoteYears = const <int>{};

  /// 内置表原样导出（单测用它检验"通知有没有抄错"）。
  static Map<String, ChinaHoliday> get builtinTable => _builtin;

  /// 目前"有官方数据"的年份 = 内置覆盖的 + 缓存里已有的。
  static Set<int> get coveredYears => <int>{...builtinYears, ..._remoteYears};

  /// 注入联网取回的年度缓存（覆盖优先于内置表）。
  ///
  /// 传空表等于"清掉覆盖"，行为回到纯内置；缓存里没有的日期会自动回落内置表，
  /// 所以不用担心"只取到 2027、反而把 2026 弄丢了"。
  static void overrideWith(Map<String, ChinaHoliday> table) {
    _remote = Map<String, ChinaHoliday>.unmodifiable(table);
    final years = <int>{};
    for (final key in table.keys) {
      final year = int.tryParse(key.length >= 4 ? key.substring(0, 4) : '');
      if (year != null) {
        years.add(year);
      }
    }
    _remoteYears = Set<int>.unmodifiable(years);
  }

  /// 撤掉覆盖，回到纯内置表（单测收尾 + 设置页「恢复内置数据」）。
  static void resetOverride() => overrideWith(const <String, ChinaHoliday>{});

  /// 官方数据里这一天是什么（远程优先，都没有则返回 null）。
  static ChinaHoliday? infoOf(DateTime date) {
    final key = DateUtils.formatDate(date);
    return _remote[key] ?? _builtin[key];
  }

  /// 这一天的日历属性。没有官方数据就按"周末休息"回落。
  ///
  /// 注意：**只看法定安排，不看"今天有没有课"**——周五没课依然是 workday。
  static CalendarDayKind kindOf(DateTime date) {
    final info = infoOf(date);
    if (info != null) {
      return info.kind;
    }
    return _isWeekend(date.weekday)
        ? CalendarDayKind.weekend
        : CalendarDayKind.workday;
  }

  static bool isHoliday(DateTime date) =>
      kindOf(date) == CalendarDayKind.holiday;

  static bool isMakeupWorkday(DateTime date) =>
      kindOf(date) == CalendarDayKind.makeupWorkday;

  /// 试穿一下改数据：给单测确认内置表抄对了（生产代码不用）。
  static int get holidayDayCount => _builtin.values
      .where((item) => item.kind == CalendarDayKind.holiday)
      .length;

  static int get makeupDayCount => _builtin.values
      .where((item) => item.kind == CalendarDayKind.makeupWorkday)
      .length;

  static Map<String, ChinaHoliday> _expand() {
    final table = <String, ChinaHoliday>{};
    for (final range in _ranges) {
      final from = DateUtils.tryParseDate(range.from);
      final to = DateUtils.tryParseDate(range.to);
      if (from == null || to == null) {
        continue;
      }
      for (var day = from;
          !day.isAfter(to);
          day = day.add(const Duration(days: 1))) {
        table[DateUtils.formatDate(day)] = ChinaHoliday(
          date: DateUtils.formatDate(day),
          kind: CalendarDayKind.holiday,
          name: range.name,
        );
      }
    }
    for (final makeup in _makeup) {
      if (DateUtils.tryParseDate(makeup.date) == null) {
        continue;
      }
      table[makeup.date] = ChinaHoliday(
        date: makeup.date,
        kind: CalendarDayKind.makeupWorkday,
        name: makeup.name,
      );
    }
    return table;
  }

  static bool _isWeekend(int weekday) =>
      weekday == DateTime.saturday || weekday == DateTime.sunday;
}
