import 'package:schedule_plan/core/constants/app_constants.dart';

/// "HH:mm" 字符串与「当日分钟数」互转工具。
///
/// readme 第六章「日期时区偏移」规避策略明确要求：
/// 作息模板的时间统一以本地 "HH:mm" 字符串落库，而不是绝对时间戳，
/// 以避免时区/夏令时换算误差；只有需要参与区间运算时才转成分钟数。
abstract final class TimeUtils {
  /// 一天的总分钟数。
  static const int minutesPerDay = 24 * 60;

  /// 解析 "HH:mm" 为当日分钟数（0 ~ 1439）。非法格式返回 null。
  static int? tryParseMinutes(String? value) {
    if (value == null) {
      return null;
    }
    final parts = value.trim().split(':');
    if (parts.length != 2) {
      return null;
    }
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) {
      return null;
    }
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) {
      return null;
    }
    return hour * 60 + minute;
  }

  /// 解析 "HH:mm"，非法时抛出 [FormatException]。
  static int parseMinutes(String value) {
    final result = tryParseMinutes(value);
    if (result == null) {
      throw const FormatException('时间格式必须为 HH:mm');
    }
    return result;
  }

  /// 分钟数格式化为 "HH:mm"（零填充）。
  static String formatMinutes(int minutes) {
    final normalized = ((minutes % minutesPerDay) + minutesPerDay) % minutesPerDay;
    final hour = (normalized ~/ 60).toString().padLeft(2, '0');
    final minute = (normalized % 60).toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  /// 把分钟数吸附到最近的 [AppConstants.wheelSnapMinutes] 分钟刻度。
  static int snapToStep(int minutes, {int step = AppConstants.wheelSnapMinutes}) {
    if (step <= 1) {
      return minutes;
    }
    final remainder = minutes % step;
    final lower = minutes - remainder;
    final upper = lower + step;
    return (minutes - lower) >= (step / 2) ? upper : lower;
  }

  /// "HH:mm" 直接吸附到最近刻度后重新格式化。
  static String snapTime(String value, {int step = AppConstants.wheelSnapMinutes}) {
    final minutes = tryParseMinutes(value);
    if (minutes == null) {
      return value;
    }
    final snapped = snapToStep(minutes, step: step);
    if (snapped >= minutesPerDay) {
      return formatMinutes(minutesPerDay - step);
    }
    return formatMinutes(snapped);
  }

  /// 区间是否重叠（半开区间 [aStart, aEnd) 与 [bStart, bEnd)）。
  static bool overlaps(int aStart, int aEnd, int bStart, int bEnd) =>
      aStart < bEnd && bStart < aEnd;
}
