import 'package:flutter/foundation.dart';

/// 中国节假日 / 调休（模块五「日程安排」扩展）。
///
/// 用户规格（第 13 轮）："结合中国国情，中国有调休制度，所以接入日历的时候
/// 最好显示节假日和上班日，如果周六日轮到调休，最好有个功能，在调休那天
/// 提醒老师上周几的课。这样算每周课时数的时候最好也能结合调休一起结算了。"
///
/// 因此这里刻意把「日历属性」和「星期几」拆成两个正交的概念：
///
/// - [DateTime.weekday]：这一天**天然**是星期几（周一到周日，永远不变）；
/// - [CalendarDayKind]：这一天**按国家安排**算不算上班/上课日。
///
/// 周六调休上班这件事本身就是"两个维度不一致"的产物，
/// 任何把两者揉在一起的写法（比如"周六就是休息"）都必然算错课时。
enum CalendarDayKind {
  /// 普通工作日：周一~周五，且不是法定假日。
  workday,

  /// 普通周末：周六/周日，且不是调休上班日。
  weekend,

  /// 法定放假日：国家公布的假期（含调休拼出来的那几天）。
  holiday,

  /// 调休上班日：通常是周六/周日，但按国家安排要上班上课。
  makeupWorkday;

  /// 从库里存的字符串还原（`holiday_day.kind` 列）。
  ///
  /// 认不出来一律回落成普通工作日：缓存表坏了顶多是"少认出一个假日"，
  /// 要是错认成假日就会把当天的课凭空抹掉，两害相权取轻。
  static CalendarDayKind fromStorage(String? value) => values.firstWhere(
        (item) => item.name == value,
        orElse: () => CalendarDayKind.workday,
      );

  /// 这一天要不要按课表上课（放假就不用）。
  bool get hasClasses =>
      this == CalendarDayKind.workday || this == CalendarDayKind.makeupWorkday;

  /// 是不是"放假"（法定假日）——注意普通周末不算，周末本来就该歇。
  bool get isStatutoryHoliday => this == CalendarDayKind.holiday;
}

/// 节假日的名字。用枚举而不是字符串，是为了走 l10n（中英双语各一份文案），
/// 同时避免把"国庆节"这种业务词散落到各处判断里。
enum HolidayName {
  newYear,
  springFestival,
  qingming,
  labourDay,
  dragonBoat,
  midAutumn,
  nationalDay,

  /// 国庆与中秋合并放假（2025 年就是这样，2028 年还会再遇到）。
  nationalDayMidAutumn;

  static HolidayName fromStorage(String? value) => HolidayName.values.firstWhere(
        (item) => item.name == value,
        orElse: () => HolidayName.nationalDay,
      );
}

/// 某一个具体日期的节假日信息。
///
/// [date] 用 "YYYY-MM-DD" 存（与考勤、休学区间同一个口径：字典序即时间序，
/// 不受时区偏移影响）。
@immutable
class ChinaHoliday {
  const ChinaHoliday({
    required this.date,
    required this.kind,
    this.name,
  });

  final String date;
  final CalendarDayKind kind;

  /// 放假日的节日名；调休上班日就是它补的那个节日名。
  final HolidayName? name;

  bool get isMakeupWorkday => kind == CalendarDayKind.makeupWorkday;

  @override
  String toString() => 'ChinaHoliday($date, ${kind.name}, ${name?.name})';

  @override
  bool operator ==(Object other) =>
      other is ChinaHoliday &&
      other.date == date &&
      other.kind == kind &&
      other.name == name;

  @override
  int get hashCode => Object.hash(date, kind, name);
}

/// 一天在实际执行课表时的样子。
///
/// [labelWeekday] 是"这一天按**星期几**的课表上课"——
/// 普通日子就等于 `date.weekday`；调休上班日如果学校通知"按周三的课表"，
/// 这里就是 3。课时结算、点名定位都必须用这个字段，不能用 `date.weekday`。
@immutable
class HolidayDay {
  const HolidayDay({
    required this.date,
    required this.kind,
    required this.labelWeekday,
    this.name,
    this.shiftOverridden = false,
  });

  final DateTime date;
  final CalendarDayKind kind;
  final int labelWeekday;
  final HolidayName? name;

  /// 「上周几的课」是老师自己确认过的（而不是按默认规则推的）。
  final bool shiftOverridden;

  bool get hasClasses => kind.hasClasses;

  /// 调休上班日且映射到了别的星期几 —— 也就是"今天要上周三的课"这种情况。
  bool get isShifted => kind == CalendarDayKind.makeupWorkday && labelWeekday != date.weekday;
}

/// 一周的执行方案（周一~周日七天）。
@immutable
class HolidayWeek {
  const HolidayWeek({required this.weekStart, required this.days});

  final DateTime weekStart;
  final List<HolidayDay> days;

  /// 这一周实际要上课的日子（已排除放假、已含调休上班日）。
  List<HolidayDay> get classDays =>
      days.where((day) => day.hasClasses).toList(growable: false);

  /// 这一周有几天是法定放假日。
  int get holidayDaysCount =>
      days.where((day) => day.kind == CalendarDayKind.holiday).length;

  /// 这一周有"人为调整"（有放假或调休上班）——纯周末不算，
  /// 周末本来就该歇，那不是调整。
  bool get hasAdjustment => days.any(
        (day) =>
            day.kind == CalendarDayKind.holiday ||
            day.kind == CalendarDayKind.makeupWorkday,
      );

  HolidayDay? get makeupDay {
    for (final day in days) {
      if (day.kind == CalendarDayKind.makeupWorkday) {
        return day;
      }
    }
    return null;
  }
}
