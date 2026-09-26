/// 日期工具。
///
/// readme 第六章「日期时区偏移」规避策略要求：日期统一存 "YYYY-MM-DD" 字符串，
/// 避免时区换算误差。所有考勤日期的读写都必须经过本文件。
abstract final class DateUtils {
  /// 格式化为 "YYYY-MM-DD"。
  static String formatDate(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  /// 解析 "YYYY-MM-DD"，非法返回 null。
  static DateTime? tryParseDate(String? value) {
    if (value == null) {
      return null;
    }
    final parts = value.split('-');
    if (parts.length != 3) {
      return null;
    }
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (y == null || m == null || d == null) {
      return null;
    }
    final parsed = DateTime.tryParse('${parts[0].padLeft(4, '0')}-'
        '${parts[1].padLeft(2, '0')}-${parts[2].padLeft(2, '0')}');
    if (parsed == null) {
      return null;
    }
    // DateTime.tryParse 会把 2026-02-30 这类不存在的日期「进位」成 2026-03-02，
    // 考勤日期必须严格拒绝，否则会写入一个用户没选过的日期。
    if (parsed.year != y || parsed.month != m || parsed.day != d) {
      return null;
    }
    return parsed;
  }

  /// 取当天 00:00。
  static DateTime dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  /// ISO weekday：周一 = 1 ... 周日 = 7。与 template_period.weekday 语义一致。
  static int isoWeekday(DateTime date) => date.weekday;

  /// 本周一 00:00。
  static DateTime startOfWeek(DateTime date) {
    final d = dateOnly(date);
    return d.subtract(Duration(days: d.weekday - 1));
  }

  /// 本周七天的 DateTime 列表（周一起）。
  static List<DateTime> weekDays(DateTime date) {
    final monday = startOfWeek(date);
    return List<DateTime>.generate(
      7,
      (index) => monday.add(Duration(days: index)),
      growable: false,
    );
  }

  /// 本月第一天。
  static DateTime startOfMonth(DateTime date) => DateTime(date.year, date.month, 1);

  /// 下月第一天（用于月末边界）。
  static DateTime startOfNextMonth(DateTime date) =>
      date.month == 12 ? DateTime(date.year + 1, 1, 1) : DateTime(date.year, date.month + 1, 1);

  /// 按月平移 [delta] 个月，并把「日」收敛到目标月的最后一天。
  ///
  /// 日历翻页必须走这里，不能直接 `DateTime(y, m ± 1, d)`——
  /// Dart 的 DateTime 会**溢出进位**：3 月 31 日往前一个月会得到 3 月 3 日
  /// （`DateTime(2026, 2, 31)` → 2026-03-03），点「上一月」反而往后跳。
  static DateTime shiftMonth(DateTime date, int delta) {
    final base = DateTime(date.year, date.month + delta);
    // 目标月最后一天：下个月的第 0 天
    final lastDay = DateTime(base.year, base.month + 1, 0).day;
    return DateTime(base.year, base.month, date.day <= lastDay ? date.day : lastDay);
  }

  /// 本周（周一起算）里某个 weekday 对应的日期。
  ///
  /// 课表页点课程格子跳考勤时用它定位："当周的就是周内最近的课"。
  /// [weekday] 采用 ISO 语义（周一 = 1 ... 周日 = 7）。
  static DateTime weekdayOfWeek(DateTime reference, int weekday) {
    final safe = weekday.clamp(1, 7);
    return startOfWeek(reference).add(Duration(days: safe - 1));
  }

  /// 距离 [reference] 最近的、星期为 [weekday] 的日期。
  ///
  /// 与 [weekdayOfWeek] 的差别：本周还没到的那一天直接用本周（含今天），
  /// 本周已经过去的则顺延到下周 —— 也就是「周内最近的课」。
  /// 课表页「去点名」用它决定该打开哪一天。
  static DateTime nearestWeekdayDate(DateTime reference, int weekday) {
    final candidate = weekdayOfWeek(reference, weekday);
    return candidate.isBefore(dateOnly(reference))
        ? candidate.add(const Duration(days: 7))
        : candidate;
  }

  /// 是否为同一天（只比较年月日）。
  static bool isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// 相隔天数（b - a，按自然日计算）。
  static int daysBetween(DateTime a, DateTime b) =>
      dateOnly(b).difference(dateOnly(a)).inDays;

  /// 把时间轴上的分钟数叠加到某个日期上，得到具体时刻。
  static DateTime atMinutes(DateTime date, int minutes) =>
      dateOnly(date).add(Duration(minutes: minutes));

  /// "YYYY-MM-DD" 加上天数偏移。
  ///
  /// 用日历构造 `DateTime(y, m, d + days)` 而不是 `add(Duration(days: days))`：
  /// 后者是"加 24 小时的整数倍"，跨夏令时切换那一周会落在前一天的 23:00，
  /// 格式化回 "YYYY-MM-DD" 就少了一天（休学 / 免修的 180 天区间正好会踩到）。
  /// 日历构造由 DateTime 自己做溢出进位，跨月跨年都正确。
  static String addDays(String date, int days) {
    final parsed = tryParseDate(date);
    if (parsed == null) {
      return date;
    }
    return formatDate(
      DateTime(parsed.year, parsed.month, parsed.day + days),
    );
  }
}
