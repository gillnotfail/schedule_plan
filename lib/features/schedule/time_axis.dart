import 'package:schedule_plan/core/constants/app_constants.dart';
import 'package:schedule_plan/core/utils/time_utils.dart';
import 'package:schedule_plan/data/models/lesson.dart';

/// 时间轴的上下界与像素密度。
///
/// 抽成纯对象便于单独测试：
/// - 上下界取所有课程真实时间的最小起始值与最大结束值，
///   分别向下/向上取整到最近的整点或半点，并各预留至少 30 分钟余量；
/// - pxPerMinute 自适应缩小，保证单屏总高度不超过设定上限。
class TimeAxis {
  const TimeAxis({
    required this.startMinute,
    required this.endMinute,
    required this.pxPerMinute,
  });

  final int startMinute;
  final int endMinute;
  final double pxPerMinute;

  int get totalMinutes => endMinute - startMinute;

  double get height => totalMinutes * pxPerMinute;

  double offsetOf(int minutes) => (minutes - startMinute) * pxPerMinute;

  double heightOf(int startMinutes, int endMinutes) =>
      (endMinutes - startMinutes) * pxPerMinute;

  /// 每小时的刻度分钟值列表（用于绘制小时标签与网格线）。
  List<int> get hourTicks {
    final first = ((startMinute + 59) ~/ 60) * 60;
    final ticks = <int>[];
    for (var minute = first; minute <= endMinute; minute += 60) {
      ticks.add(minute);
    }
    return ticks;
  }

  /// 上下界：取所有课程真实时间的 min/max，向下/向上取整到半小时刻度，
  /// 各预留至少 30 分钟余量，并夹在一天之内。
  ///
  /// 抽出来是因为 [compute]（按像素密度上限）和 [fitted]（按可用高度反算）
  /// 必须共用同一套区间口径，否则「错峰」跨模板聚合时两个视图的上下界会不一致。
  static (int, int) _span(List<LessonWithTime> lessons) {
    if (lessons.isEmpty) {
      // 没有课时给一个合理的默认跨度：08:00 - 18:00
      return (8 * 60, 18 * 60);
    }
    var min = 1 << 30;
    var max = -1;
    for (final lesson in lessons) {
      final start = lesson.startMinutes;
      final end = lesson.endMinutes > lesson.startMinutes
          ? lesson.endMinutes
          : lesson.startMinutes + 45;
      if (start < min) {
        min = start;
      }
      if (end > max) {
        max = end;
      }
    }
    final step = AppConstants.timeAxisRoundingMinutes;
    final startMinute = ((min - AppConstants.timeAxisMarginMinutes) ~/ step) * step;
    var endMinute = ((max + AppConstants.timeAxisMarginMinutes + step - 1) ~/ step) * step;
    if (endMinute <= startMinute) {
      endMinute = startMinute + 60;
    }
    if (endMinute > TimeUtils.minutesPerDay) {
      endMinute = TimeUtils.minutesPerDay;
    }
    return (startMinute < 0 ? 0 : startMinute, endMinute);
  }

  /// 依据课程列表计算时间轴（纯函数）。
  ///
  /// [lessons] 为本周全部课程（已联查模板解析出真实时间）。
  static TimeAxis compute(List<LessonWithTime> lessons) {
    final (startMinute, endMinute) = _span(lessons);
    if (lessons.isEmpty) {
      return TimeAxis(
        startMinute: startMinute,
        endMinute: endMinute,
        pxPerMinute: AppConstants.pxPerMinuteDefault,
      );
    }
    final rawSpan = endMinute - startMinute;
    // 自适应：跨度过大时缩小像素密度，但不得小于下限
    final fitted = AppConstants.timeAxisMaxHeight / rawSpan;
    final px = fitted < AppConstants.pxPerMinuteDefault
        ? fitted.clamp(AppConstants.pxPerMinuteMin, AppConstants.pxPerMinuteDefault)
        : AppConstants.pxPerMinuteDefault;
    return TimeAxis(
      startMinute: startMinute,
      endMinute: endMinute,
      pxPerMinute: px,
    );
  }

  /// 按**可用的窗口高度**反算像素密度：整条时间轴刚好铺满一屏（用户规格）。
  ///
  /// 时间轴视图不再有纵向滚动条 —— 老师要的是"打开就是整周的样子"，
  /// 而不是滑半天才看到下午。所以像素密度不再是固定值，
  /// 而是 `可用高度 ÷ 实际跨度`，跨度短就长高、跨度长就压扁；
  /// 两端用 [AppConstants.pxPerMinuteFloor] / [AppConstants.pxPerMinuteCeiling] 兜底，
  /// 避免极端尺寸下算出 0（除零）或把一节课拉成一整屏。
  ///
  /// [availableHeight] 非正（首帧约束还没量出来）时退回 [compute]，保证有合理默认。
  static TimeAxis fitted(List<LessonWithTime> lessons, double availableHeight) {
    final (startMinute, endMinute) = _span(lessons);
    if (availableHeight <= 0) {
      return TimeAxis(
        startMinute: startMinute,
        endMinute: endMinute,
        pxPerMinute: AppConstants.pxPerMinuteDefault,
      );
    }
    final span = endMinute - startMinute;
    final px = (availableHeight / span).clamp(
      AppConstants.pxPerMinuteFloor,
      AppConstants.pxPerMinuteCeiling,
    );
    return TimeAxis(
      startMinute: startMinute,
      endMinute: endMinute,
      pxPerMinute: px,
    );
  }
}
