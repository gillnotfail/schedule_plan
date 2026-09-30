import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:schedule_plan/core/constants/app_constants.dart';
import 'package:schedule_plan/core/l10n/l10n_extensions.dart';
import 'package:schedule_plan/core/theme/app_motion.dart';
import 'package:schedule_plan/core/utils/color_utils.dart';
import 'package:schedule_plan/core/utils/date_utils.dart' as app_dates;
import 'package:schedule_plan/core/utils/time_utils.dart';
// 只用它的纯函数 generatePeriodRows（出厂作息唯一来源），不碰数据库
import 'package:schedule_plan/data/db/schema.dart';
import 'package:schedule_plan/data/models/lesson.dart';
import 'package:schedule_plan/data/models/schedule_event.dart';
import 'package:schedule_plan/data/models/schedule_template.dart';

/// 「表格课表」视图（模块一 1.4 模式 A + 用户规格）。
///
/// 版式严格按用户要求：
/// - **第一行**是星期几；**第一列**是节次与上课时间；
/// - 点第一列的某一节 → 修改该节次时间（可级联顺延后续节次）；
/// - 点空格子 → 交给课表页判断（课程管理里没有课程才引导去建课，
///   有课程就直接滑动挑选）；
/// - 长按课程进入交换模式，拖到另一格完成互换。
///
/// **整表自适应一屏**（用户规格："自动缩放表格，使得课表在同一个页面上显示，
/// 不需要缩放"）：
/// 不再固定列宽 + 横向滚动，而是用 [LayoutBuilder] 量出真实可用宽高后
/// 「宽度按天均分、行高等比压缩」，宽度或高度不够时才允许纵向滚动兜底。
/// 因此打开课表页永远是一整张表，老师不需要左右拖、也不用双指缩放。
///
/// **横向手风琴**（用户规格："默认等宽窄条，点击某节课展开变宽显示课程详情，
/// 其余同步收窄，内容延迟淡入"）：
/// - 默认所有天等宽，格子里**只显示课程名称**；
/// - 点某节课 → 它所在的那一列变宽，其余列同步收窄；
/// - 展开列里被点开的那一格延后淡入「人数 · 班级」，形成"先展开、后出内容"的层次；
/// - 再点同一格 → 打开课程详情弹层（去点名 / 换课 / 移出）；
/// - 点展开列的星期表头 → 收回等宽。
///
/// 配色：**课程自己挑的颜色优先**（见 [courseColors]，与课程管理里锁定的颜色
/// 是同一个来源），没挑过才回落成所属班级的颜色。
///
/// 注意：一周内各工作日的节次数量**不一定相同**，
/// 因此每一列都按 (template_id, weekday) 单独取节次列表渲染，
/// 行数以「节次最多的那天」为准，节次较少的那天多出来的行渲染为占位格。
///
/// 该视图**不要求已经选中班级**：节次骨架来自作息模板，
/// 没有班级时课表页依然要显示这张表（只是格子都是空的）。
class ClassGridView extends StatefulWidget {
  const ClassGridView({
    super.key,
    required this.templateId,
    required this.periodsByWeekday,
    required this.lessons,
    required this.onEmptyCellTap,
    required this.onLessonTap,
    required this.onPeriodTap,
    this.courseStudentCounts = const <int, int>{},
    this.courseColors = const <int, String>{},
    this.events = const <ScheduleEvent>[],
    this.weekStart,
    this.todayWeekday,
    this.makeupHints = const <int, String>{},
    this.onSwap,
  });

  /// 当前展示的作息模板；节次列与时间列都来自它。
  final int templateId;

  /// key = weekday(1~7)，value = 该工作日的节次列表（已按 period_index 升序）
  final Map<int, List<TemplatePeriod>> periodsByWeekday;
  final List<LessonWithTime> lessons;

  /// 日程安排活动（单次 / 每周 / 隔周 / 每月）：落在某节次时间范围内的格子，
  /// 右上角叠一个小方块标记（颜色区别于课程色，见第 10 轮规格）。
  final List<ScheduleEvent> events;

  /// 当前这一周的周一，用来判定隔周 / 隔月活动在这一周发不发生。
  /// 缺省按 `DateTime.now()` 取本周（测试不传 events 时根本用不到）。
  final DateTime? weekStart;

  /// 表头的「今天」圆点画在哪一列 —— 取今天**实际执行的星期几**。
  ///
  /// 调休上班日会与 `DateTime.now().weekday` 不同：今天周六却要上星期三的课，
  /// 圆点就该落在「周三」那一列（那才是今天要照着上的课表），
  /// 而不是落在周六 —— 周六往往压根没排课，点在那儿等于指着一列空表格。
  ///
  /// 不传时按天然星期几取，测试和「没接节假日的调用方」行为不变。
  final int? todayWeekday;

  /// 列（weekday）→ 表头角标提示。
  ///
  /// 本周的调休日会标在**它实际上课的那一列**上（周六补周三的课 → 标在周三列），
  /// 让老师一眼看出"这周哪天要补班、补的是哪一天的课"。空 map = 不标。
  final Map<int, String> makeupHints;

  /// 课程 id → 人数（合班课为各班人数之和），展开时显示这个数
  final Map<int, int> courseStudentCounts;

  /// 课程 id → 课程色。**只包含老师给课程单独挑过颜色的那些**；
  /// 没挑过的课程取不到值，格子里回落成 `lesson.classColor`（班级色）。
  final Map<int, String> courseColors;

  /// 点空格子（课表页据此判断"有没有课程"并决定下一步）
  final void Function(int weekday, int periodIndex) onEmptyCellTap;

  /// 已展开的格子再次被点击：打开课程详情对话框（去点名 / 换课 / 移出）。
  ///
  /// 返回 [Future]，课表页关掉对话框后才算完成 —— 手风琴据此把列宽收回默认，
  /// 保证「取消」退出后看到的是等宽课表（用户规格）。
  final Future<void> Function(LessonWithTime lesson) onLessonTap;

  /// 点击左侧节次/时间列
  final void Function(int weekday, int periodIndex) onPeriodTap;
  final void Function(LessonWithTime source, LessonWithTime target)? onSwap;

  @override
  State<ClassGridView> createState() => _ClassGridViewState();
}

class _ClassGridViewState extends State<ClassGridView>
    with SingleTickerProviderStateMixin {
  bool _swapMode = false;

  /// 手风琴状态：哪一列被展开（weekday），以及展开列里被点开的那一节。
  int? _expandedDay;
  int? _focusedPeriod;

  /// 0 = 完全等宽，1 = 展开列到位。用它驱动列宽插值 + 详情淡入，
  /// 保证"其余列同步收窄"和"内容延迟淡入"始终同一条时间轴。
  late final AnimationController _expand;
  late final Animation<double> _expandCurve;

  @override
  void initState() {
    super.initState();
    _expand = AnimationController(vsync: this, duration: AppMotion.standard);
    _expandCurve = CurvedAnimation(
      parent: _expand,
      curve: AppMotion.expressive,
      reverseCurve: AppMotion.exit,
    );
  }

  @override
  void dispose() {
    _expand.dispose();
    super.dispose();
  }

  /// 实际用于渲染的节次表：优先模板作息，整份为空时退回出厂作息骨架。
  ///
  /// 出厂骨架只用于**渲染**，不落库——补写作息是
  /// `TemplateRepository.ensureFactorySchedule` 的职责（课表页加载时调用）。
  /// 这一层兜底的唯一目的是：任何情况下都不能渲染出一张第一列空白的表
  /// ——那在用户眼里就是「课表页没有课表」。
  Map<int, List<TemplatePeriod>> get _periods {
    if (widget.periodsByWeekday.values.any((list) => list.isNotEmpty)) {
      return widget.periodsByWeekday;
    }
    final rows = DatabaseSchema.generatePeriodRows(
      startTime: AppConstants.defaultDayStartTime,
      lessonMinutes: AppConstants.defaultLessonMinutes,
      breakMinutes: AppConstants.defaultBreakMinutes,
      count: AppConstants.defaultDayPeriodCount,
    );
    return <int, List<TemplatePeriod>>{
      for (var day = 1; day <= AppConstants.defaultWorkdayCount; day++)
        day: <TemplatePeriod>[
          for (var i = 0; i < rows.length; i++)
            TemplatePeriod(
              templateId: widget.templateId,
              weekday: day,
              periodIndex: i + 1,
              startTime: rows[i].$1,
              endTime: rows[i].$2,
            ),
        ],
    };
  }

  /// 只展示「配置过节次」的星期；一个都没有时回落到周一~周五。
  List<int> get _days {
    final periods = _periods;
    final list = <int>[
      for (var day = 1; day <= AppConstants.weekdayCount; day++)
        if ((periods[day] ?? const <TemplatePeriod>[]).isNotEmpty) day,
    ];
    return list.isEmpty ? <int>[1, 2, 3, 4, 5] : list;
  }

  /// 行数 = 节次最多的那天的节次数。
  int get _rowCount {
    var max = 0;
    for (final day in _days) {
      final count = _periods[day]?.length ?? 0;
      if (count > max) {
        max = count;
      }
    }
    return max == 0 ? AppConstants.defaultDayPeriodCount : max;
  }

  /// 左侧时间列取「节次最多的一天」的时间，作为整行的显示基准。
  int get _referenceDay {
    var best = _days.first;
    var bestCount = -1;
    for (final day in _days) {
      final count = _periods[day]?.length ?? 0;
      if (count > bestCount) {
        best = day;
        bestCount = count;
      }
    }
    return best;
  }

  TemplatePeriod? _periodAt(int weekday, int index) {
    final periods = _periods[weekday];
    if (periods == null || index >= periods.length) {
      return null;
    }
    return periods[index];
  }

  LessonWithTime? _lessonAt(int weekday, int periodIndex) {
    for (final lesson in widget.lessons) {
      if (lesson.lesson.weekday == weekday &&
          lesson.lesson.periodIndex == periodIndex) {
        return lesson;
      }
    }
    return null;
  }

  /// 落在 (weekday, period) 这一节次时间范围内的日程活动。
  ///
  /// 判定链：活动在这一周发生（重复周期）→ 星期几对上 →
  /// 起止时间落进这一节的 `[start, end)`。与错峰课表上的小方块同一口径。
  List<ScheduleEvent> _eventsAt(int weekday, TemplatePeriod period) {
    if (widget.events.isEmpty) {
      return const <ScheduleEvent>[];
    }
    // weekStart 可空：缺省按今天取本周（schedule_page 总会传真实值）
    final week =
        widget.weekStart ?? app_dates.DateUtils.startOfWeek(DateTime.now());
    return <ScheduleEvent>[
      for (final event in widget.events)
        if (event.occursOnWeek(week) &&
            _eventWeekday(event) == weekday &&
            _eventMinutes(event) >= period.startMinutes &&
            _eventMinutes(event) < period.endMinutes)
          event,
    ];
  }

  int _eventWeekday(ScheduleEvent event) =>
      DateTime.fromMillisecondsSinceEpoch(event.startAt).weekday;

  int _eventMinutes(ScheduleEvent event) {
    final start = DateTime.fromMillisecondsSinceEpoch(event.startAt);
    return start.hour * 60 + start.minute;
  }

  void _toggleSwapMode() {
    AppMotion.confirm();
    setState(() => _swapMode = !_swapMode);
  }

  /// 点有课的格子：该列展开变宽、其余同步收窄，**随后**弹出课程详情对话框。
  ///
  /// 用户规格："点击某个具体课程，变大，然后弹窗"。所以这里刻意先让列宽动画
  /// 走完再弹窗 —— 遮罩只有 32% 黑，老师能看见是自己点的这一列变宽了，
  /// 而不是莫名其妙盖了张dialog上来（[AppMotion.standard] 与列宽动画同时长）。
  ///
  /// 对话框无论怎么关闭（取消 / 点遮罩 / 去点名）都会把列宽**收回默认等宽**，
  /// 这就是之前缺的那一步"恢复默认大小"。
  Future<void> _onLessonCellTap(
    int weekday,
    int periodIndex,
    LessonWithTime lesson,
  ) async {
    if (_swapMode) {
      await widget.onLessonTap(lesson);
      return;
    }
    AppMotion.select();
    setState(() {
      _expandedDay = weekday;
      _focusedPeriod = periodIndex;
    });
    _expand.forward();
    await Future<void>.delayed(AppMotion.standard);
    if (!mounted) {
      return;
    }
    await widget.onLessonTap(lesson);
    if (!mounted) {
      return;
    }
    _collapse();
  }

  /// 收回等宽（点展开列的星期表头 / 点其它格子 / 对话框关闭时触发）。
  void _collapse() {
    if (_expandedDay == null) {
      return;
    }
    AppMotion.tap();
    setState(() {
      _expandedDay = null;
      _focusedPeriod = null;
    });
    _expand.reverse();
  }

  /// 点空格子：先把手风琴收回默认，再交给课表页处理（选课面板 / 提示建课）。
  void _onEmptyCellTap(int weekday, int periodIndex) {
    _collapse();
    widget.onEmptyCellTap(weekday, periodIndex);
  }

  /// 手风琴列宽：等宽 → 展开列变宽、其余列同步收窄。
  ///
  /// 任意时刻所有列宽之和恒等于 [dayArea]（两端都等于它，插值自然也是），
  /// 所以整表宽度不变、永远不会横向溢出——这是"一屏显示"的前提。
  List<double> _columnWidths(double dayArea, List<int> days) {
    final count = days.length;
    if (count == 0 || dayArea <= 0) {
      return const <double>[];
    }
    final base = dayArea / count;
    final expandedDay = _expandedDay;
    if (expandedDay == null || count == 1) {
      return List<double>.filled(count, base);
    }
    final shrinkFloor = base * AppConstants.gridAccordionShrinkFactor;
    var expandedTarget = base * AppConstants.gridAccordionExpandFactor;
    // 其余列最多收窄到下限：展开列能吃掉的最大宽度由此封顶
    final ceiling = dayArea - shrinkFloor * (count - 1);
    expandedTarget = math.max(base, math.min(expandedTarget, ceiling));
    final restTarget = (dayArea - expandedTarget) / (count - 1);
    // AppMotion.expressive 是带过冲的曲线（值会越过 1），
    // 列宽必须夹住：过冲一帧就是横向溢出，整表会闪一下。
    final t = _expandCurve.value.clamp(0.0, 1.0);
    return <double>[
      for (final day in days)
        lerpDouble(base, day == expandedDay ? expandedTarget : restTarget, t)!,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final days = _days;

    return Column(
      children: <Widget>[
        // 顶部：交换模式提示条
        AnimatedSize(
          duration: AppMotion.standard,
          curve: AppMotion.expressive,
          child: _swapMode ? _buildSwapBanner(theme) : const SizedBox.shrink(),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // 左侧节次/时间列：窄屏按比例收一点，保证课表还有地方站
              final gutter = math.min(
                AppConstants.gridGutterWidth,
                constraints.maxWidth * AppConstants.gridGutterMaxFraction,
              );
              final dayArea = math.max(0.0, constraints.maxWidth - gutter);
              // 底部留一点点呼吸感也要算进"一屏"里，否则最后一行会被挤出视口
              // 让表格变成可滚动的——用户要的是"同一页面上显示，不需要缩放"。
              final rowsHeight =
                  constraints.maxHeight -
                  AppConstants.gridHeaderHeight -
                  AppConstants.spaceS;
              // 行高等比压缩到"刚好放得下"，节数很少时允许长高铺满一屏，
              // 但都收在 [gridRowMinHeight, gridRowStretchMaxHeight] 之间。
              final rowHeight = (rowsHeight / _rowCount).clamp(
                AppConstants.gridRowMinHeight,
                AppConstants.gridRowStretchMaxHeight,
              );

              return AnimatedBuilder(
                animation: _expandCurve,
                builder: (context, _) {
                  final widths = _columnWidths(dayArea, days);
                  return Column(
                    children: <Widget>[
                      _buildHeader(days, gutter, widths, theme),
                      Expanded(
                        child: SingleChildScrollView(
                          child: Column(
                            children: <Widget>[
                              for (var row = 0; row < _rowCount; row++)
                                _buildRow(
                                  row,
                                  days,
                                  gutter,
                                  widths,
                                  rowHeight,
                                  theme,
                                ),
                              const SizedBox(height: AppConstants.spaceS),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSwapBanner(ThemeData theme) {
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.spaceL,
        0,
        AppConstants.spaceL,
        AppConstants.spaceS,
      ),
      child: ClipRRect(
        borderRadius: AppRadii.stadiumAll,
        child: Container(
          color: scheme.primaryContainer.withValues(alpha: 0.7),
          padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.spaceM,
            vertical: 6,
          ),
          child: Row(
            children: <Widget>[
              Icon(
                Icons.swap_horiz,
                size: 15,
                color: scheme.onPrimaryContainer,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  context.l10n.swapModeHint,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onPrimaryContainer,
                  ),
                ),
              ),
              TextButton(
                onPressed: _toggleSwapMode,
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppConstants.spaceS,
                  ),
                ),
                child: Text(context.l10n.close),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(
    List<int> days,
    double gutter,
    List<double> widths,
    ThemeData theme,
  ) {
    final l10n = context.l10n;
    final scheme = theme.colorScheme;
    // 「今天」按**实际执行的星期几**取：调休日今天周六上星期三的课，
    // 圆点就落在周三那一列（见 [todayWeekday]）。
    final today = widget.todayWeekday ?? DateTime.now().weekday;
    return Container(
      height: AppConstants.gridHeaderHeight,
      decoration: BoxDecoration(
        // 表头给一层淡底：整张表才有"顶带 + 网格"的结构感（用户规格：加点底色）
        color: scheme.surfaceContainer,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppRadii.cell),
        ),
        border: Border(
          bottom: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.8),
          ),
        ),
      ),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: gutter,
            child: InkWell(
              onTap: _toggleSwapMode,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Icon(
                    Icons.swap_horiz_rounded,
                    size: 18,
                    color: _swapMode ? scheme.primary : scheme.onSurfaceVariant,
                  ),
                  Text(
                    l10n.gridPeriodHeader,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          ),
          for (var i = 0; i < days.length; i++)
            _DayHeaderCell(
              width: widths[i],
              weekday: days[i],
              isToday: days[i] == today,
              makeupHint: widget.makeupHints[days[i]],
              expanded: days[i] == _expandedDay,
              onTap: _collapse,
            ),
        ],
      ),
    );
  }

  Widget _buildRow(
    int row,
    List<int> days,
    double gutter,
    List<double> widths,
    double rowHeight,
    ThemeData theme,
  ) {
    final scheme = theme.colorScheme;
    final reference = _periodAt(_referenceDay, row);
    final isBreak = reference?.periodType.isBreak ?? false;

    return Container(
      height: rowHeight,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
      ),
      child: Row(
        children: <Widget>[
          // 第一列：节次 + 时间，点击可改时间
          SizedBox(
            width: gutter,
            child: reference == null
                ? const SizedBox.shrink()
                : _GutterCell(
                    index: row + 1,
                    start: TimeUtils.formatMinutes(reference.startMinutes),
                    end: TimeUtils.formatMinutes(reference.endMinutes),
                    isBreak: isBreak,
                    onTap: () => widget.onPeriodTap(_referenceDay, row + 1),
                  ),
          ),
          for (var i = 0; i < days.length; i++)
            SizedBox(
              width: widths[i],
              child: _buildCell(
                days[i],
                row,
                rowHeight,
                theme,
                // 隔行换色：整张表才有"表格底"，而不是一片白纸贴几块色片
                zebra: row.isEven,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCell(
    int weekday,
    int row,
    double rowHeight,
    ThemeData theme, {
    required bool zebra,
  }) {
    final scheme = theme.colorScheme;
    final period = _periodAt(weekday, row);
    // 该星期没有这一节（各工作日节次数不同）：渲染为占位格，不可交互
    if (period == null) {
      return Center(
        child: Text(
          '—',
          style: theme.textTheme.labelSmall?.copyWith(
            color: scheme.outlineVariant,
          ),
        ),
      );
    }
    final lesson = _lessonAt(weekday, period.periodIndex);
    final focused =
        _expandedDay == weekday && _focusedPeriod == period.periodIndex;
    // 「内容延迟淡入」：列宽先走完大半，详情再出现，层次才分得开。
    // 同样要夹住——expressive 曲线的过冲会让 Interval.transform 直接断言失败。
    final detailOpacity = focused
        ? Interval(
            AppConstants.gridAccordionDetailFadeBegin,
            1,
          ).transform(_expandCurve.value.clamp(0.0, 1.0)).clamp(0.0, 1.0)
        : 0.0;
    // 格子铺满整格：底色才连成一张表（否则每格都缩成图标大小，中间全是空白）
    final cell = SizedBox.expand(
      child: _buildCellBody(
        weekday,
        period,
        lesson,
        theme,
        zebra: zebra,
        focused: focused,
        detailOpacity: detailOpacity,
      ),
    );

    if (lesson == null || !_swapMode) {
      return cell;
    }
    return Draggable<LessonWithTime>(
      data: lesson,
      feedback: Material(
        color: Colors.transparent,
        child: SizedBox(
          width: math.max(48.0, AppConstants.gridDayMinWidth - 8),
          height: math.max(38.0, rowHeight - 10),
          child: _buildLessonCell(lesson, theme, dragging: true, onTap: () {}),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.32, child: cell),
      child: DragTarget<LessonWithTime>(
        onWillAcceptWithDetails: (details) => LessonConflictDetector.canSwap(
          source: details.data,
          target: lesson,
        ),
        onAcceptWithDetails: (details) {
          AppMotion.confirm();
          widget.onSwap?.call(details.data, lesson);
        },
        builder: (context, candidateData, rejectedData) {
          final highlighted = candidateData.isNotEmpty;
          return AnimatedScale(
            scale: highlighted ? 1.03 : 1.0,
            duration: AppMotion.quick,
            curve: AppMotion.expressive,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: AppRadii.cellAll,
                border: Border.all(
                  color: highlighted ? scheme.primary : Colors.transparent,
                  width: 2,
                ),
              ),
              child: cell,
            ),
          );
        },
      ),
    );
  }

  Widget _buildCellBody(
    int weekday,
    TemplatePeriod period,
    LessonWithTime? lesson,
    ThemeData theme, {
    required bool zebra,
    bool focused = false,
    double detailOpacity = 0,
  }) {
    final Widget body;
    if (lesson != null) {
      body = _buildLessonCell(
        lesson,
        theme,
        focused: focused,
        detailOpacity: detailOpacity,
        onTap: () {
          // ignore: discarded_futures — 展开→弹窗→收回由 _onLessonCellTap 内部自洽
          _onLessonCellTap(weekday, period.periodIndex, lesson);
        },
      );
    } else {
      final scheme = theme.colorScheme;
      final isBreak = period.periodType.isBreak;
      // 交换模式下空格子不参与点击：这时候用户的意图是"把课拖过来"
      body = GestureDetector(
        onTap: (isBreak || _swapMode)
            ? null
            : () => _onEmptyCellTap(weekday, period.periodIndex),
        child: Container(
          margin: const EdgeInsets.all(AppConstants.gridCellGap),
          decoration: BoxDecoration(
            color: _emptyCellFill(
              scheme: scheme,
              weekday: weekday,
              zebra: zebra,
              isBreak: isBreak,
            ),
            borderRadius: AppRadii.cellAll,
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.55),
            ),
          ),
          child: Center(
            child: Icon(
              isBreak ? Icons.local_cafe_outlined : Icons.add,
              size: 14,
              color: isBreak
                  ? scheme.onSurfaceVariant.withValues(alpha: 0.5)
                  : scheme.outline.withValues(alpha: 0.75),
            ),
          ),
        ),
      );
    }

    // 日程活动小方块：这一节的时间范围里有活动就在右上角叠一个（颜色区别于课程色）
    final events = _eventsAt(weekday, period);
    if (events.isEmpty) {
      return body;
    }
    return Stack(
      children: <Widget>[
        body,
        Positioned(
          top: AppConstants.gridCellGap + 2,
          right: AppConstants.gridCellGap + 2,
          child: IgnorePointer(child: _GridEventMarker(events: events)),
        ),
      ],
    );
  }

  /// 空格子的底色：休息节次用一条中性色带，今天那一列泛一点主色，
  /// 其余隔行深浅交替 —— 用户反馈"颜色太单调"，这些是最省笔墨的底色层次。
  ///
  /// 只取 `colorScheme` 里被 token 显式赋过值的两个 surface 档位
  /// （`surface` / `surfaceContainer`）：`surfaceContainerLow` 那几档属于
  /// Flutter 默认基线色（带一点紫灰），换到"樱花粉""晨曦暖橙"里会脏。
  Color _emptyCellFill({
    required ColorScheme scheme,
    required int weekday,
    required bool zebra,
    required bool isBreak,
  }) {
    if (isBreak) {
      return scheme.surfaceContainerHighest.withValues(alpha: 0.62);
    }
    if (weekday == DateTime.now().weekday) {
      return scheme.primaryContainer.withValues(alpha: 0.20);
    }
    return zebra ? scheme.surfaceContainer : scheme.surface;
  }

  /// 课程格子。折叠态**只显示课程名称**（居中）；展开态（[focused]）才淡入
  /// 「人数 · 班级」——用户规格："不点击的话默认显示课程名称，不显示其他"。
  ///
  /// 配色（用户规格："课表、对话框最好加个底色，目前颜色太单调"）：
  /// 以课程色为基调做**斜向渐变底 + 左侧色脊 + 同色描边 + 展开时投影**，
  /// 折叠时是一枚清爽的色片，展开时明显"立起来"，层次全靠课程色本身撑，
  /// 不需要额外引入别的颜色（六套主题切换后依旧成立）。
  Widget _buildLessonCell(
    LessonWithTime lesson,
    ThemeData theme, {
    required VoidCallback onTap,
    bool focused = false,
    double detailOpacity = 0,
    bool dragging = false,
  }) {
    final own = widget.courseColors[lesson.lesson.courseId];
    // 课程管理里给课程锁定的颜色优先，没锁过才回落成班级色
    final color = _colorOf(
      own != null && own.isNotEmpty ? own : lesson.classColor,
      theme,
    );
    final detailText = _detailTextOf(lesson);
    final strong = dragging ? 0.34 : (focused ? 0.26 : 0.17);
    final soft = dragging ? 0.20 : (focused ? 0.13 : 0.07);

    return GestureDetector(
      onTap: onTap,
      onLongPress: () {
        if (!_swapMode) {
          _toggleSwapMode();
        }
      },
      child: AnimatedContainer(
        duration: AppMotion.quick,
        curve: AppMotion.effects,
        margin: const EdgeInsets.all(AppConstants.gridCellGap),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[
              color.withValues(alpha: strong),
              color.withValues(alpha: soft),
            ],
          ),
          borderRadius: AppRadii.cellAll,
          border: Border.all(
            color: color.withValues(alpha: focused ? 0.85 : 0.42),
            width: focused ? 1.6 : 1,
          ),
          boxShadow: focused
              ? <BoxShadow>[
                  BoxShadow(
                    color: color.withValues(alpha: 0.30),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: ClipRRect(
          borderRadius: AppRadii.cellAll,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // 左侧色脊：一眼把"这节课是哪门课"和颜色对上
              Container(
                width: focused ? 4 : 3,
                color: color.withValues(alpha: focused ? 1 : 0.75),
              ),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: focused ? 6 : 3,
                    vertical: 4,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    // 用户规格：课表页的课程名称要居中
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: <Widget>[
                      Text(
                        lesson.courseName,
                        textAlign: TextAlign.center,
                        maxLines: focused ? 1 : 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: color,
                          fontSize: focused ? 12.5 : 11.5,
                          height: 1.15,
                        ),
                      ),
                      if (focused && detailText.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Opacity(
                            opacity: detailOpacity,
                            child: Text(
                              detailText,
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontSize: 9.5,
                                height: 1.1,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 展开后淡入的详情：人数 + 上课班级（与课程详情弹层同一口径）。
  String _detailTextOf(LessonWithTime lesson) {
    final count = widget.courseStudentCounts[lesson.lesson.courseId];
    return <String>[
      if (count != null) context.l10n.cellStudentCount(count),
      if (lesson.className.trim().isNotEmpty) lesson.className,
    ].join(' · ');
  }

  Color _colorOf(String hex, ThemeData theme) =>
      parseHexColor(hex, theme.colorScheme.primary);
}

/// 表头星期格。点展开列的星期格可以把手风琴收回来。
///
/// 两种角标，都是星期文字**右边**的一个 5px 小圆点（不额外占列宽）：
/// - **今天是这一列** → primary 点 + `primaryContainer` 胶囊底（原有表现）；
/// - **本周有调休落在这列** → tertiary 点 + 淡 `tertiaryContainer` 底，
///   长按可见"哪天调休、补的是哪一天的课"。与工具箱日历同一套颜色口径。
///
/// 两者同时成立时（今天恰好就是要补的那一天）以「今天」的样式为准，
/// 但长按提示仍带着调休说明。
class _DayHeaderCell extends StatelessWidget {
  const _DayHeaderCell({
    required this.width,
    required this.weekday,
    required this.isToday,
    required this.onTap,
    this.makeupHint,
    this.expanded = false,
  });

  final double width;
  final int weekday;
  final bool isToday;

  /// 非空 = 本周有调休日「上这一天的课」，内容是长按可见的说明文案。
  final String? makeupHint;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final label = l10n.weekdayShort(weekday);
    final hinted = makeupHint != null;
    // 优先级：今天 > 调休角标 > 展开列
    final Color background;
    final Color? textColor;
    if (isToday) {
      background = scheme.primaryContainer.withValues(alpha: 0.85);
      textColor = scheme.onPrimaryContainer;
    } else if (hinted) {
      background = scheme.tertiaryContainer.withValues(alpha: 0.7);
      textColor = scheme.onTertiaryContainer;
    } else {
      background = expanded
          ? scheme.secondaryContainer.withValues(alpha: 0.7)
          : Colors.transparent;
      textColor = null;
    }

    final cell = AnimatedContainer(
      duration: AppMotion.standard,
      curve: AppMotion.effects,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: AppRadii.stadiumAll,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            label,
            maxLines: 1,
            softWrap: false,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: isToday || expanded || hinted
                  ? FontWeight.w800
                  : FontWeight.w600,
              color: textColor,
            ),
          ),
          if (isToday) ...<Widget>[
            const SizedBox(width: 4),
            _headerDot(scheme.primary),
          ] else if (hinted) ...<Widget>[
            const SizedBox(width: 4),
            _headerDot(scheme.tertiary),
          ],
        ],
      ),
    );

    // 列宽是自适应的：窄列上把胶囊整体等比缩小，绝不撑破
    return SizedBox(
      width: width,
      child: Center(
        child: GestureDetector(
          onTap: expanded ? onTap : null,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: makeupHint == null
                ? cell
                : Tooltip(
                    message: makeupHint!,
                    waitDuration: const Duration(milliseconds: 400),
                    child: cell,
                  ),
          ),
        ),
      ),
    );
  }

  static Widget _headerDot(Color color) => Container(
    width: 5,
    height: 5,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

/// 左侧节次 / 时间格。
class _GutterCell extends StatelessWidget {
  const _GutterCell({
    required this.index,
    required this.start,
    required this.end,
    required this.isBreak,
    required this.onTap,
  });

  final int index;
  final String start;
  final String end;
  final bool isBreak;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final indexStyle = theme.textTheme.labelSmall?.copyWith(
      fontWeight: FontWeight.w800,
      color: scheme.primary,
      fontSize: 10,
      letterSpacing: 0,
    );
    final startStyle = theme.textTheme.labelSmall?.copyWith(
      fontSize: 9,
      height: 1.2,
      letterSpacing: 0,
      color: scheme.onSurfaceVariant,
    );
    final endStyle = theme.textTheme.labelSmall?.copyWith(
      fontSize: 9,
      height: 1.2,
      letterSpacing: 0,
      color: scheme.outline,
    );
    return Padding(
      padding: const EdgeInsets.all(3),
      child: Material(
        color: isBreak
            ? scheme.surfaceContainerHigh.withValues(alpha: 0.5)
            : scheme.surfaceContainer.withValues(alpha: 0.6),
        borderRadius: AppRadii.cellAll,
        child: InkWell(
          borderRadius: AppRadii.cellAll,
          onTap: () {
            AppMotion.tap();
            onTap();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
            // 行高是自适应的，所以这里必须保证三行文字永远放得下：
            // 文字一律不许折行，再套一层 scaleDown，行高变矮时整体等比缩小。
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    l10n.periodIndexLabel(index),
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.clip,
                    style: indexStyle,
                  ),
                  Text(
                    start,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.clip,
                    style: startStyle,
                  ),
                  Text(
                    end,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.clip,
                    style: endStyle,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 跨模板/跨班级拖拽被拒绝时的反馈（震动 + 文案）。
void showAppSnackBarRejection(BuildContext context, String message) {
  HapticFeedback.heavyImpact();
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text(message), duration: AppConstants.snackBarDuration),
    );
}

/// 常规课表格子右上角的**日程活动小方块**：颜色与课程色明显区分，
/// 一眼认出"这里还有日程（不是课）"。多节活动挤在同一节时给个数。
class _GridEventMarker extends StatelessWidget {
  const _GridEventMarker({required this.events});

  final List<ScheduleEvent> events;

  /// 活动专用色：玫红，和课程色的蓝绿橙紫拉开（与错峰课表的小方块同色）。
  static const Color _eventColor = Color(0xFFE91E63);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 3.5, vertical: 2.5),
      decoration: BoxDecoration(
        color: _eventColor,
        borderRadius: AppRadii.stadiumAll,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.event, size: 8.5, color: Colors.white),
          if (events.length > 1) ...<Widget>[
            const SizedBox(width: 1.5),
            Text(
              '${events.length}',
              style: const TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                height: 1.0,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
