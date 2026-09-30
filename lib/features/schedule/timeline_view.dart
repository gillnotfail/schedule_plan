import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:schedule_plan/core/constants/app_constants.dart';
import 'package:schedule_plan/core/l10n/l10n_extensions.dart';
import 'package:schedule_plan/core/theme/app_colors.dart';
import 'package:schedule_plan/core/theme/app_motion.dart';
import 'package:schedule_plan/core/utils/color_utils.dart';
import 'package:schedule_plan/core/utils/date_utils.dart' as app_dates;
import 'package:schedule_plan/core/utils/time_utils.dart';
import 'package:schedule_plan/data/models/lesson.dart';
import 'package:schedule_plan/data/models/schedule_event.dart';
import 'package:schedule_plan/data/models/schedule_template.dart';
import 'package:schedule_plan/features/schedule/time_axis.dart';

/// 教师个人聚合时间轴视图（模块一 1.4 模式 B）。
///
/// 必须使用时间轴网格渲染，不能用固定节次行的网格 —— 因为聚合视图可能跨多个年级/模板，
/// 同一「第 N 节」在不同模板下对应不同的真实时钟时间。这也是"错峰作息"能一眼看出来的原因：
/// 高一的第 4 节（11:20 下课）和高二的第 4 节（12:00 下课）在同一个纵轴上错开排布。
///
/// **整条时间轴自适应铺满窗口**（用户规格：和课表格子一样，一屏放下、不需要滑动）：
/// - 列宽 = `(可用宽度 - 左侧刻度栏) / 7`，不再固定 `timeAxisDayMinWidth`；
/// - 像素密度 = `可用高度 / 实际跨度`（见 [TimeAxis.fitted]），
///   跨度短就长高、跨度长就压扁，两端有上下限兜底；
/// - 因此这里**没有横向也没有纵向的滚动视图**，打开就是完整的一周。
///   横向信息由"每天一列"承载，纵向信息由"时间刻度"承载，两者都在一屏内。
class TimelineView extends StatefulWidget {
  const TimelineView({
    super.key,
    required this.lessons,
    required this.breakPeriods,
    required this.weekStart,
    required this.tokens,
    this.weekdays = defaultWeekdays,
    this.events = const <ScheduleEvent>[],
    this.courseColors = const <int, String>{},
    this.onLessonTap,
    this.onLessonLongPress,
  });

  /// 参与渲染的星期（1 = 周一 … 7 = 周日），列宽按这里的天数均分。
  ///
  /// 用户规格（第 8 轮）："错峰课表这一块，如果放七天，字太小，
  /// 而且周六周日是浪费宽度的。最好与用户一键设置作息那里一样，
  /// 如果用户选择周几，这里就对应选择周几。"
  ///
  /// 也就是**只画用户在「一键生成作息」里勾了的星期**（页面侧从模板作息里推出来），
  /// 不勾的星期不再占一列 —— 5 天的表每列能宽 40%，字才看得清。
  /// 缺省仍是完整一周（直接渲染本组件而不经过课表页的场景，比如测试）。
  static const List<int> defaultWeekdays = <int>[1, 2, 3, 4, 5, 6, 7];
  final List<int> weekdays;

  final List<LessonWithTime> lessons;

  /// 日程安排活动（单次 / 每周 / 隔周 / 每月），在时间轴上用小方块标记。
  ///
  /// 用户规格（第 9 轮）："日程安排里的活动……如果是单次，联动到课表里，
  /// 下一周就没有了；隔周的话，就不用单独打开日程安排，直接在课表上就可以看到。
  /// 可以用小方块，在错峰课表上显示，区别去其他课表颜色。"
  final List<ScheduleEvent> events;

  /// 非 normal 类型的时段（午休 / 大课间），在背景以浅色条带标注，不可点击。
  final List<TemplatePeriod> breakPeriods;
  final DateTime weekStart;
  final AppColorTokens tokens;

  /// 课程自己挑过的颜色（`courseId → hex`），与课程管理里锁定的是同一个来源。
  ///
  /// 第 19 轮补上：这里以前只读 `lesson.classColor`（班级色），于是老师在课程
  /// 管理里改了课程色，**表格档跟着变、曲线档不变**。现在两个视图同一条口径。
  final Map<int, String> courseColors;

  final ValueChanged<LessonWithTime>? onLessonTap;
  final ValueChanged<LessonWithTime>? onLessonLongPress;

  @override
  State<TimelineView> createState() => _TimelineViewState();
}

class _TimelineViewState extends State<TimelineView> {
  Timer? _ticker;

  /// 当前被点开的日程（点一下在它右上角展开起止时间和内容，再点收起）。
  ///
  /// 用户规格（第 12 轮）："在错峰课表上，目前只是有日程，但很小，
  /// 看不出来大概时间和内容。要么将日程时间段显示、要么点击日程，
  /// 在日程的右上角小字显示具体时间和内容。"
  ///
  /// 选的是第三条：**点一下就在那个方块右上角弹出小字**。
  /// 理由是错峰课表上一屏要装一整天，方块本身的高度已经压到十几个像素，
  /// 常驻显示时间会把课块挤掉；点开看是按需展开，既不打乱布局又能看到具体信息。
  int? _openEventId;

  @override
  void initState() {
    super.initState();
    // 「现在时间线」随时间下移，每分钟刷新一次
    _ticker = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    // readme 第六章：Timer 必须在 dispose 中显式取消
    _ticker?.cancel();
    _ticker = null;
    super.dispose();
  }

  void _toggleEvent(ScheduleEvent event) {
    AppMotion.tap();
    setState(() {
      _openEventId = _openEventId == event.id ? null : event.id;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final nowMinutes = now.hour * 60 + now.minute;

    // 用户规格：时间轴也要像课表格子那样**自适应铺满窗口**，
    // 选完周几上课回来一打开就是完整的一周，不需要左右拖、也不需要上下滑。
    // 所以这里量出真实可用宽高：列宽按**实际勾选的星期数**均分，像素密度由高度反算。
    return LayoutBuilder(
      builder: (context, constraints) {
        final days = widget.weekdays.isEmpty
            ? TimelineView.defaultWeekdays
            : widget.weekdays;
        final gutter = math.min(
          AppConstants.timeAxisGutterWidth,
          constraints.maxWidth * AppConstants.timeAxisGutterMaxFraction,
        );
        final dayWidth = math.max(
          0.0,
          (constraints.maxWidth - gutter) / days.length,
        );
        final bodyHeight = math.max(
          0.0,
          constraints.maxHeight - AppConstants.timeAxisHeaderHeight,
        );
        final axis = TimeAxis.fitted(widget.lessons, bodyHeight);

        return Column(
          children: <Widget>[
            _buildHeader(theme, gutter, dayWidth, days),
            // 图例：只在真的有日程时出现，点一下同时说清"这个玫红块是什么"
            // 和"点它能看具体时间"。空着的时候不占地方。
            if (widget.events.isNotEmpty) _buildLegend(theme),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _buildGutter(axis, theme, gutter),
                  for (final weekday in days)
                    _buildDayColumn(
                      axis: axis,
                      weekday: weekday,
                      width: dayWidth,
                      theme: theme,
                      nowMinutes: nowMinutes,
                      isToday: app_dates.DateUtils.isSameDay(
                        widget.weekStart.add(Duration(days: weekday - 1)),
                        now,
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildHeader(
    ThemeData theme,
    double gutter,
    double dayWidth,
    List<int> days,
  ) {
    final weekDays = app_dates.DateUtils.weekDays(widget.weekStart);
    return Container(
      height: AppConstants.timeAxisHeaderHeight,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: theme.dividerTheme.color ?? theme.colorScheme.outline,
          ),
        ),
      ),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: gutter,
            child: Icon(
              Icons.schedule,
              size: 16,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          for (final weekday in days)
            SizedBox(
              width: dayWidth,
              // 天数均分后列可能很窄，星期文案整体等比缩小，绝不撑破
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    _weekdayLabel(context, weekday, weekDays[weekday - 1].day),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _weekdayLabel(BuildContext context, int weekday, int day) {
    final short = context.l10n.weekdayShort(weekday);
    return '$short\n$day';
  }

  /// 一行极简图例：`■ 日程 · 点一下看时间`。
  ///
  /// 用户规格（第 12 轮）给了三个选项（图例 / 常驻时间段 / 点开看时间），
  /// 这里把「图例」和「点开看时间」合起来用：图例负责**让玫红块有名字**，
  /// 点开负责**给出具体时间和内容**。高度压到 22，不挤占课表本身的空间。
  Widget _buildLegend(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.spaceS,
        3,
        AppConstants.spaceS,
        3,
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              color: _EventMarker._eventColor,
              borderRadius: BorderRadius.circular(2.5),
            ),
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              '${context.l10n.timelineEventLegend} · '
              '${context.l10n.timelineEventTapHint}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                fontSize: 10,
                color: _EventMarker._eventColor,
                fontWeight: FontWeight.w700,
                height: 1.1,
              ),
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildGutter(TimeAxis axis, ThemeData theme, double gutter) {
    return SizedBox(
      width: gutter,
      height: axis.height,
      child: Stack(
        children: <Widget>[
          for (final tick in axis.hourTicks)
            Positioned(
              top: axis.offsetOf(tick),
              left: 0,
              right: 4,
              child: Text(
                TimeUtils.formatMinutes(tick),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.right,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDayColumn({
    required TimeAxis axis,
    required int weekday,
    required double width,
    required ThemeData theme,
    required int nowMinutes,
    required bool isToday,
  }) {
    final dayLessons = widget.lessons
        .where((item) => item.lesson.weekday == weekday)
        .toList();
    final dayBreaks = widget.breakPeriods
        .where((item) => item.weekday == weekday && item.periodType.isBreak)
        .toList();

    return Container(
      width: width,
      height: axis.height,
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: (theme.dividerTheme.color ?? theme.colorScheme.outline)
                .withValues(alpha: 0.6),
          ),
        ),
      ),
      child: Stack(
        children: <Widget>[
          // 小时网格线
          for (final tick in axis.hourTicks)
            Positioned(
              top: axis.offsetOf(tick),
              left: 0,
              right: 0,
              child: Divider(
                height: 1,
                color: (theme.dividerTheme.color ?? theme.colorScheme.outline)
                    .withValues(alpha: 0.4),
              ),
            ),
          // 非 normal 时段背景条带（不可点击）
          for (final period in dayBreaks)
            Positioned(
              top: axis.offsetOf(period.startMinutes),
              height: axis.heightOf(period.startMinutes, period.endMinutes),
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    color: widget.tokens.breakBand,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
            ),
          // 课程色块
          for (final lesson in dayLessons)
            Positioned(
              top: axis.offsetOf(lesson.startMinutes),
              // 像素密度现在是按窗口高度反算的，块高可能比"一行字"还矮：
              // 不能再抬到 28，否则相邻两块会叠在一起（画面上就是课被压住了）。
              height: axis
                  .heightOf(lesson.startMinutes, lesson.endMinutes)
                  .clamp(14.0, double.infinity),
              left: 2,
              right: 2,
              child: _LessonBlock(
                lesson: lesson,
                // 文本宽度以这一列为准：先按列宽换行，放不下再整体等比缩小。
                // 不传的话 FittedBox 会按"一整行不换行"的固有宽度去缩，
                // 7 列时能把字缩到 4px（用户："看不清就没有意义了"）。
                maxWidth: width - 12,
                theme: theme,
                courseColors: widget.courseColors,
                onTap: widget.onLessonTap,
                onLongPress: widget.onLessonLongPress,
              ),
            ),
          // 日程活动小方块：颜色区别于课表课程色，一眼看出"这不是课"。
          // 点一下在它右上角展开起止时间 + 标题，再点收起（第 12 轮）。
          // **不套 IgnorePointer** —— 要能点，所以给它一个明确的高度，
          // 免得多出来的点击区盖住下面的课块。
          for (final event in widget.events)
            if (_eventOnThisDay(event, weekday))
              Positioned(
                top: axis.offsetOf(_eventMinutes(event)) -
                    _eventMarkerTopOffset,
                left: 2,
                right: 2,
                child: _EventMarker(
                  event: event,
                  theme: theme,
                  tokens: widget.tokens,
                  expanded: _openEventId == event.id,
                  onTap: () => _toggleEvent(event),
                ),
              ),
          // 现在时间线（红色细线，非上课时段降低透明度）
          if (isToday && nowMinutes >= axis.startMinute && nowMinutes <= axis.endMinute)
            Positioned(
              top: axis.offsetOf(nowMinutes),
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Container(
                  height: 2,
                  color: widget.tokens.nowLine.withValues(
                    alpha: _isInClass(dayLessons, nowMinutes) ? 1.0 : 0.45,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  bool _isInClass(List<LessonWithTime> lessons, int minutes) {
    for (final lesson in lessons) {
      if (minutes >= lesson.startMinutes && minutes <= lesson.endMinutes) {
        return true;
      }
    }
    return false;
  }

  /// 日程方块相对它开始时间往上抬的像素数。
  ///
  /// 方块代表"这一刻开始"，所以视觉中心要压在时间线上，而不是下沿贴着它。
  static const double _eventMarkerTopOffset = 8;

  /// 该活动在这一周的这一列里发不发生（重复周期 + 星期几都对得上）。
  bool _eventOnThisDay(ScheduleEvent event, int weekday) {
    if (!event.occursOnWeek(widget.weekStart)) {
      return false;
    }
    final start = DateTime.fromMillisecondsSinceEpoch(event.startAt);
    return start.weekday == weekday;
  }

  int _eventMinutes(ScheduleEvent event) {
    final start = DateTime.fromMillisecondsSinceEpoch(event.startAt);
    return start.hour * 60 + start.minute;
  }
}

/// 时间轴上的课程色块。
///
/// 色块内展示课程名、班级/年级名与**真实起止时间**，
/// 不展示裸的「第 N 节」编号（跨年级场景下编号没有可比较的意义）。
///
/// 配色与表格档**保持一致**（用户规格第 19 轮：整格铺满课程色 + 白色文字）：
/// 取色走「课程自选色 > 班级色 > 主题兜底」，再过 [solidFillColor] 压暗到
/// 白色文字看得清。曲线块比表格格子更矮、字更小，浅色课上不压暗会读不出课程名。
class _LessonBlock extends StatelessWidget {
  const _LessonBlock({
    required this.lesson,
    required this.theme,
    required this.maxWidth,
    this.courseColors = const <int, String>{},
    this.onTap,
    this.onLongPress,
  });

  final LessonWithTime lesson;

  /// 课程自己挑过的颜色（`courseId → hex`）——**与表格档同一个来源**。
  final Map<int, String> courseColors;

  /// 文本可用宽度：先在这个宽度内换行，再交给 FittedBox 整体等比缩小。
  ///
  /// 用户规格（第 8 轮）："现在字太小，表格太小，看不清。看不清就没有意义了。"
  /// 根因是以前 FittedBox 拿到的子节点是"一行不换行"的固有宽度
  /// （课程名 + 班级 + 起止时间约 130pt），7 列时列宽只有 ~48pt，
  /// 只能缩到 0.35 倍 → 字比系统最小字号还小。先约束宽度让它换行，
  /// 缩放系数就只取决于**高度**，一般都能保持 1:1 原字号。
  final double maxWidth;

  final ThemeData theme;
  final ValueChanged<LessonWithTime>? onTap;
  final ValueChanged<LessonWithTime>? onLongPress;

  Color get _fill {
    final own = courseColors[lesson.lesson.courseId];
    return solidFillColor(
      parseHexColor(
        own != null && own.isNotEmpty ? own : lesson.classColor,
        theme.colorScheme.primary,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fill = _fill;
    return GestureDetector(
      onTap: onTap == null ? null : () => onTap!(lesson),
      onLongPress: onLongPress == null ? null : () => onLongPress!(lesson),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(8),
        ),
        // 块高是自适应的（一屏要装下一整天），矮到放不下两行字时整体等比缩小，
        // 而不是溢出成"黑色条纹"——这也是"永远一屏放得下"的一部分。
        // 里面先按 [maxWidth] 换行，缩放才不会把字压没。
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  lesson.courseName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${lesson.className} ${lesson.timeRangeText}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.82),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 错峰课表上的**日程活动小方块**：颜色与课表课程色明显区分，一眼认出"这不是课"。
///
/// 用户规格（第 12 轮）："目前只是有日程，但很小，看不出来大概时间和内容。"
///
/// 所以这里给了两级信息密度：
/// - **收起态**（默认）：小色块 + 一行标题，尽量不占地方；
/// - **展开态**（点一下）：方块上方浮出一张玫红小卡，写清「起-止 时间」和标题，
///   再点一次（或点别的日程）收起。
///
/// 不用常驻显示：错峰课表要一屏装下一整天，时间文字常驻会把课块挤没，
/// 而"看具体几点"本来就是低频动作。
class _EventMarker extends StatelessWidget {
  const _EventMarker({
    required this.event,
    required this.theme,
    required this.tokens,
    required this.expanded,
    required this.onTap,
  });

  final ScheduleEvent event;
  final ThemeData theme;
  final AppColorTokens tokens;
  final bool expanded;
  final VoidCallback onTap;

  /// 活动专用色：玫红，和课程色的蓝绿橙紫拉开，避免被误认成某门课。
  static const Color _eventColor = Color(0xFFE91E63);

  static const double _dotSize = 10;

  /// 展开态的浮层锚在方块**右上角**（用户规格原话）。
  static const double _panelWidth = 118;

  String get _timeRange {
    final start = DateTime.fromMillisecondsSinceEpoch(event.startAt);
    final endAt = event.endAt;
    final end = endAt == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(endAt);
    return end == null
        ? TimeUtils.formatMinutes(start.hour * 60 + start.minute)
        : '${TimeUtils.formatMinutes(start.hour * 60 + start.minute)}'
            ' - ${TimeUtils.formatMinutes(end.hour * 60 + end.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        // 方块本体：整行都可点（只有 10pt 的点在手机上根本点不中）
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Row(
            children: <Widget>[
              // 展开时点加一圈光晕，视觉上告诉用户"现在摊开的是这一个"
              AnimatedContainer(
                duration: AppMotion.quick,
                width: _dotSize + (expanded ? 3 : 0),
                height: _dotSize + (expanded ? 3 : 0),
                decoration: BoxDecoration(
                  color: _eventColor,
                  borderRadius: BorderRadius.circular(3),
                  boxShadow: expanded
                      ? <BoxShadow>[
                          BoxShadow(
                            color: _eventColor.withValues(alpha: 0.45),
                            blurRadius: 7,
                            spreadRadius: 1,
                          ),
                        ]
                      : null,
                ),
              ),
              const SizedBox(width: 3),
              Expanded(
                child: Text(
                  event.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: _eventColor,
                    height: 1.0,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (expanded)
          Positioned(
            right: 0,
            bottom: 0,
            // 往上浮：贴着方块的右上角，但不遮住标题那一行
            child: FractionalTranslation(
              translation: const Offset(0, -0.95),
              child: _EventDetailPanel(
                timeRange: _timeRange,
                title: event.title,
                location: event.location,
              ),
            ),
          ),
      ],
    );
  }
}

/// 日程展开后右上角那张小卡：上行是起止时间，下行是标题（有地点就再缀一个）。
class _EventDetailPanel extends StatelessWidget {
  const _EventDetailPanel({
    required this.timeRange,
    required this.title,
    this.location,
  });

  final String timeRange;
  final String title;
  final String? location;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final place = (location ?? '').trim();
    return Material(
      color: Colors.transparent,
      child: Container(
        width: _EventMarker._panelWidth,
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
            color: _EventMarker._eventColor.withValues(alpha: 0.55),
          ),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.16),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(
                  Icons.schedule_rounded,
                  size: 10,
                  color: _EventMarker._eventColor,
                ),
                const SizedBox(width: 3),
                Expanded(
                  child: Text(
                    timeRange,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: _EventMarker._eventColor,
                      height: 1.1,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              place.isEmpty ? title : '$title · $place',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                fontSize: 10,
                height: 1.2,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
