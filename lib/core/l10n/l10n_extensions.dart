import 'package:flutter/widgets.dart';

import 'package:schedule_plan/data/models/china_holiday.dart';
import 'package:schedule_plan/l10n/generated/app_localizations.dart';

/// i18n 快捷入口。
///
/// 规范 12：国际化文案严禁在组件代码中拼接字符串，统一走 i18n key 引用。
extension L10nContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

/// 周几 / 节次的组合文案。
///
/// 「周一」这个映射原本在课表表格、时间轴、快速排课、作息设置、考勤日历里各抄了
/// 一份（5 处 switch），任何一处漏改都会出现"同一个星期几在不同页面叫法不同"。
/// 统一收到这里，页面只准调这两个方法。
extension L10nWeekday on AppLocalizations {
  /// 周几简称：周一 … 周日。weekday 取 1~7（[DateTime.weekday] 的口径）。
  String weekdayShort(int weekday) => switch (weekday) {
    1 => mon,
    2 => tue,
    3 => wed,
    4 => thu,
    5 => fri,
    6 => sat,
    _ => sun,
  };

  /// 「周一 · 第 3 节」：提示"正在操作哪一格"时用（挑课程、快排等）。
  String weekdayPeriodLabel(int weekday, int periodIndex) =>
      '${weekdayShort(weekday)} · ${periodIndexLabel(periodIndex)}';

  /// 节日名：元旦 / 春节 / …（`null` 表示只有"放假"没有具体节日名）。
  ///
  /// 与 [weekdayShort] 同样的收敛理由：工具箱日历与工具箱总览各抄过一份，
  /// 现在放假提示、调休说明三处都走这里。
  String holidayName(HolidayName? name) => switch (name) {
    HolidayName.newYear => holidayNameNewYear,
    HolidayName.springFestival => holidayNameSpringFestival,
    HolidayName.qingming => holidayNameQingming,
    HolidayName.labourDay => holidayNameLabourDay,
    HolidayName.dragonBoat => holidayNameDragonBoat,
    HolidayName.midAutumn => holidayNameMidAutumn,
    HolidayName.nationalDay => holidayNameNationalDay,
    HolidayName.nationalDayMidAutumn => holidayNameNationalDayMidAutumn,
    null => '',
  };
}
