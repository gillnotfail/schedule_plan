import 'package:schedule_plan/core/constants/setting_keys.dart';
import 'package:schedule_plan/core/utils/date_utils.dart';
import 'package:schedule_plan/data/models/china_holiday.dart';
import 'package:schedule_plan/data/repositories/settings_repository.dart';
import 'package:schedule_plan/data/services/china_holiday_calendar.dart';

/// 节假日 / 调休服务：把「官方放假表」（联网取回的年度缓存优先、
/// 内置常量表兜底，见 `china_holiday_calendar.dart`）和「老师自己确认的
/// 『调休那天上周几的课』」缝在一起，对上层只暴露一个问题：
///
/// > 这一天到底按**星期几**的课表上课？
///
/// ## 为什么"上周几的课"必须由老师确认，而不是我们替他猜
///
/// 国务院通知只说了哪天放假、哪天上班，**没说**补班那天上星期几的课——
/// 那是各校自己的通知（同一个省的不同学校都可能不一样：有上周三的、
/// 也有上周四的）。所以这里：
///
/// 1. 默认 **不调整**（`labelWeekday == date.weekday`），也就是"当天的课表"；
/// 2. 老师在日历页或课表页的提醒条上自己选一次，落库到 `app_settings`
///    （键 = `holiday_shift_YYYY-MM-DD`，一天一条，可随时改）；
/// 3. 选过之后课时结算、课表提醒都按这个映射走。
///
/// 宁可多问一句，也不要按"看起来合理"的规则替老师改课表——
/// 猜错了就是某一天的课凭空多出来或少掉，比不问严重得多。
class HolidayService {
  HolidayService({SettingsRepository? settings})
    : _settings = settings ?? SettingsRepository();

  final SettingsRepository _settings;

  /// [SettingKeys.holidayAwareEnabled] 的内存缓存：一页渲染只读一次。
  /// 设置页改完开关会重建页面 → 新实例 → 缓存自然失效。
  bool? _enabledCache;

  /// 一天的日历属性（纯函数，不读库——单测直接用这个）。
  static CalendarDayKind kindOf(DateTime date) =>
      ChinaHolidayCalendar.kindOf(date);

  static ChinaHoliday? infoOf(DateTime date) =>
      ChinaHolidayCalendar.infoOf(date);

  static bool isHoliday(DateTime date) => ChinaHolidayCalendar.isHoliday(date);

  static bool isMakeupWorkday(DateTime date) =>
      ChinaHolidayCalendar.isMakeupWorkday(date);

  /// 节假日总开关是否开启（关闭后一律"周六周日休息"）。
  Future<bool> isEnabled() async => _enabledCache ??= await _settings.readBool(
    SettingKeys.holidayAwareEnabled,
  );

  /// 掉线重连用：设置页改完开关后调用，下次读库。
  void invalidate() => _enabledCache = null;

  /// 某一天该按星期几的课表上课（纯函数，便于单测）。
  ///
  /// [overrideWeekday] 是老师确认过的映射；为空表示"不调整"。
  /// 只有调休上班日才允许被改到别的星期几——法定假日和普通工作日
  /// 即使传了覆盖值也一律忽略，避免脏数据把课时算飞。
  static int labelWeekdayOf(DateTime date, int? overrideWeekday) {
    if (ChinaHolidayCalendar.kindOf(date) != CalendarDayKind.makeupWorkday) {
      return date.weekday;
    }
    if (overrideWeekday == null) {
      return date.weekday;
    }
    return overrideWeekday.clamp(DateTime.monday, DateTime.sunday);
  }

  /// 这一天的完整执行信息（含库里的覆盖值 + 总开关）。
  Future<HolidayDay> dayOf(DateTime date) async {
    final day = DateUtils.dateOnly(date);
    if (!await isEnabled()) {
      return HolidayDay(
        date: day,
        kind: _naturalKind(day),
        labelWeekday: day.weekday,
      );
    }
    final info = ChinaHolidayCalendar.infoOf(day);
    int? override;
    if (info?.kind == CalendarDayKind.makeupWorkday) {
      override = await shiftOf(day);
    }
    return HolidayDay(
      date: day,
      kind: info?.kind ?? _naturalKind(day),
      labelWeekday: labelWeekdayOf(day, override),
      name: info?.name,
      shiftOverridden: override != null,
    );
  }

  /// 一周（周一起）的执行方案。只对调休上班日读一次覆盖值，
  /// 普通日子不碰数据库（一次翻月 42 格也只有几天是调休日）。
  Future<HolidayWeek> weekOf(DateTime weekStart) async {
    final start = DateUtils.startOfWeek(weekStart);
    final days = <HolidayDay>[];
    for (var i = 0; i < 7; i++) {
      days.add(await dayOf(start.add(Duration(days: i))));
    }
    return HolidayWeek(weekStart: start, days: days);
  }

  /// 老师为这个调休日确认过的映射（null = 还没确认，按不调整处理）。
  Future<int?> shiftOf(DateTime date) async {
    final raw = await _settings.read(_shiftKey(date));
    final parsed = int.tryParse(raw);
    if (parsed == null ||
        parsed < DateTime.monday ||
        parsed > DateTime.sunday) {
      return null;
    }
    return parsed;
  }

  /// 一段日期区间里，老师**确认过**的调休日映射。
  ///
  /// key = `"YYYY-MM-DD"`，value = 这天实际该按星期几的课表上课。
  /// 只包含「是调休上班日 **且** 老师选过」的日子 —— 其余日期不在表里，
  /// 调用方一律按 `map[key] ?? date.weekday` 解析，语义与 [labelWeekdayOf] 一致。
  ///
  /// 存在的意义是**一次 IO 覆盖一整段**：考勤页的圆环一次要算 42 天，
  /// 逐天调 [shiftOf] 就是 42 次 query。总开关关掉时直接返回空表
  /// （关掉之后调休一律不作数，和 [dayOf] 的口径保持一致）。
  Future<Map<String, int>> shiftMap({
    required DateTime from,
    required DateTime to,
  }) async {
    if (!await isEnabled()) {
      return const <String, int>{};
    }
    final raw = await _settings.readByPrefix(SettingKeys.holidayShiftPrefix);
    if (raw.isEmpty) {
      return const <String, int>{};
    }
    final start = DateUtils.dateOnly(from);
    final end = DateUtils.dateOnly(to);
    final result = <String, int>{};
    for (final entry in raw.entries) {
      final date = DateUtils.tryParseDate(
        entry.key.substring(SettingKeys.holidayShiftPrefix.length),
      );
      if (date == null || date.isBefore(start) || date.isAfter(end)) {
        continue;
      }
      // 只有调休上班日允许被改：别把脏数据（手工写错日期的键）当回事
      if (ChinaHolidayCalendar.kindOf(date) != CalendarDayKind.makeupWorkday) {
        continue;
      }
      final parsed = int.tryParse(entry.value);
      if (parsed == null ||
          parsed < DateTime.monday ||
          parsed > DateTime.sunday) {
        continue;
      }
      result[DateUtils.formatDate(date)] = parsed;
    }
    return result;
  }

  /// 确认 / 修改调休日"上周几的课"。传 null 表示恢复"不调整"。
  Future<void> setShift(DateTime date, int? weekday) async {
    if (weekday == null) {
      await _settings.write(_shiftKey(date), '');
      return;
    }
    final safe = weekday.clamp(DateTime.monday, DateTime.sunday);
    await _settings.write(_shiftKey(date), '$safe');
    // 记住上次的选择：下次遇到新的调休日时预选它，老师少点几下
    await _settings.write(SettingKeys.holidayLastShift, '$safe');
  }

  /// 上次为别的调休日选过的星期几（用来给新调休日做预选）。
  Future<int?> lastShift() async {
    final parsed = int.tryParse(
      await _settings.read(SettingKeys.holidayLastShift),
    );
    if (parsed == null ||
        parsed < DateTime.monday ||
        parsed > DateTime.sunday) {
      return null;
    }
    return parsed;
  }

  /// 今天是不是"调休上班日"，是的话连带把映射一起给出来。
  ///
  /// 两处都要查：先看总开关（关掉之后调休不该再提醒），
  /// 再看 [dayOf] 的结论（而不是直接信静态表），否则开关关掉、
  /// 静态表命中的情况下会弹出一条"按当天上课"的假提醒。
  Future<HolidayDay?> todayMakeupWorkday({DateTime? now}) async {
    final today = now ?? DateTime.now();
    if (!await isEnabled() || !isMakeupWorkday(today)) {
      return null;
    }
    final day = await dayOf(today);
    return day.kind == CalendarDayKind.makeupWorkday ? day : null;
  }

  static String _shiftKey(DateTime date) =>
      '${SettingKeys.holidayShiftPrefix}${DateUtils.formatDate(date)}';

  /// 脱离法定安排的"天生属性"：周六周日休息，其余上班。
  static CalendarDayKind _naturalKind(DateTime date) {
    final weekday = date.weekday;
    return weekday == DateTime.saturday || weekday == DateTime.sunday
        ? CalendarDayKind.weekend
        : CalendarDayKind.workday;
  }
}
