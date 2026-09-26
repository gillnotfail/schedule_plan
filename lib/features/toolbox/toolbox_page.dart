import 'package:flutter/material.dart';

import 'package:schedule_plan/core/constants/app_constants.dart';
import 'package:schedule_plan/core/l10n/l10n_extensions.dart';
import 'package:schedule_plan/core/logging/app_logger.dart';
import 'package:schedule_plan/core/theme/app_colors.dart';
import 'package:schedule_plan/core/theme/app_motion.dart';
import 'package:schedule_plan/core/theme/app_page_route.dart';
import 'package:schedule_plan/core/utils/date_utils.dart' as app_dates;
import 'package:schedule_plan/core/widgets/app_card.dart';
import 'package:schedule_plan/core/widgets/heart_burst.dart';
import 'package:schedule_plan/core/widgets/squishy_tap.dart';
import 'package:schedule_plan/core/widgets/staggered_entrance.dart';
import 'package:schedule_plan/data/models/attendance.dart';
import 'package:schedule_plan/data/models/china_holiday.dart';
import 'package:schedule_plan/data/models/schedule_event.dart';
import 'package:schedule_plan/data/services/teaching_insight_service.dart';
import 'package:schedule_plan/features/statistics/statistics_page.dart';
import 'package:schedule_plan/features/toolbox/calendar_page.dart';
import 'package:schedule_plan/features/toolbox/focus_timer_page.dart';
import 'package:schedule_plan/features/toolbox/general_todo_page.dart';
import 'package:schedule_plan/features/toolbox/note_list_page.dart';
import 'package:schedule_plan/features/todo/todo_page.dart';
import 'package:schedule_plan/l10n/generated/app_localizations.dart';

/// 教师工具箱（模块五 + 用户规格第 9 / 10 / 13 轮）。
///
/// 版式：**两页**——第 1 页是所有工具卡片（2 列网格可滚动），第 2 页是教学成果。
/// 用户规格（第 10 轮）："不需要工具-教学成果这两个标题……提示用户直接滑动
/// 或者告知有2页即可，这个标题太丑了。" 所以顶部**不放文字 Tab**，
/// 用 PageView 左右滑动 + 底部圆点指示（圆点本身就在说"有 2 页"），
/// 圆点旁一句「左右滑动 · 共 2 页」做引导。
///
/// 第 13 轮两处改版：
/// 1. **工具卡片改成实色卡**（[ToolCardTone]）：参考图里是一排彩色卡片，
///    用户要求"有颜色，饱和度可以低一点，但是配合的好看一点" ——
///    六个色相统一明度/饱和度，配白字白图标；
/// 2. **教学成果改成「数据概览 + 今日回顾 + 分段展开卡片」**：
///    概览四张数据卡（本周上课 / 总课节数 / 专注次数 / 今天课节），
///    下面四段可展开卡片（课时分布 / 出勤情况 / 专注投入 / 额外事务），
///    收起时标题右侧给一行摘要，展开才展开细节 —— 信息密度和可读性兼顾。
///
/// 卡片按压用 [SquishyTap]（从手指按下点散开 + 压过头再弹回）；
/// 成果页用 [HeartBurst]（点哪儿爆一簇爱心）。
class ToolboxPage extends StatefulWidget {
  const ToolboxPage({super.key});

  @override
  State<ToolboxPage> createState() => _ToolboxPageState();
}

class _ToolboxPageState extends State<ToolboxPage> {
  final PageController _controller = PageController();
  int _page = 0;

  TeachingInsight? _insight;
  bool _loadingInsight = true;

  /// 展开的分段卡片 id（可多个同时展开，默认第一段展开）。
  final Set<String> _openSections = <String>{_InsightSectionId.lessons};

  @override
  void initState() {
    super.initState();
    _loadInsight();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadInsight() async {
    if (!mounted) {
      return;
    }
    setState(() => _loadingInsight = true);
    try {
      final insight = await TeachingInsightService().load();
      if (!mounted) {
        return;
      }
      setState(() {
        _insight = insight;
        _loadingInsight = false;
      });
    } catch (error, stack) {
      AppLogger.e('加载教学成果失败', error: error, stack: stack);
      if (!mounted) {
        return;
      }
      setState(() => _loadingInsight = false);
    }
  }

  void _toggleSection(String id) {
    AppMotion.select();
    setState(() {
      if (_openSections.contains(id)) {
        _openSections.remove(id);
      } else {
        _openSections.add(id);
      }
    });
  }

  /// 六个工具卡片。
  ///
  /// 色相取自 [ToolCardTone.all]，**按这个顺序**配：
  /// 逐行"一冷一暖"（蓝紫 / 玫橙 / 绿青），扫过去是一条连续的色相带，
  /// 而不是六个随手挑的颜色。
  List<_ToolEntry> _entries(BuildContext context) {
    final l10n = context.l10n;
    return <_ToolEntry>[
      _ToolEntry(
        icon: Icons.insights_outlined,
        label: l10n.toolStatistics,
        description: l10n.toolStatisticsDesc,
        tone: ToolCardTone.all[0],
        target: const StatisticsPage(),
      ),
      _ToolEntry(
        icon: Icons.checklist_rtl_outlined,
        label: l10n.toolTodo,
        description: l10n.toolTodoDesc,
        tone: ToolCardTone.all[1],
        target: const TodoPage(),
      ),
      _ToolEntry(
        icon: Icons.timer_outlined,
        label: l10n.toolFocus,
        description: l10n.toolFocusDesc,
        tone: ToolCardTone.all[2],
        target: const FocusTimerPage(),
      ),
      _ToolEntry(
        icon: Icons.edit_note_outlined,
        label: l10n.toolNote,
        description: l10n.toolNoteDesc,
        tone: ToolCardTone.all[3],
        target: const NoteListPage(),
      ),
      _ToolEntry(
        icon: Icons.event_available_outlined,
        label: l10n.toolCalendar,
        description: l10n.toolCalendarDesc,
        tone: ToolCardTone.all[4],
        target: const CalendarPage(),
      ),
      _ToolEntry(
        icon: Icons.done_all_outlined,
        label: l10n.toolPrivateTodo,
        description: l10n.toolPrivateTodoDesc,
        tone: ToolCardTone.all[5],
        target: const GeneralTodoPage(),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.toolboxTitle),
        actions: <Widget>[
          IconButton(
            tooltip: l10n.retry,
            icon: const Icon(Icons.refresh),
            onPressed: _loadInsight,
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: PageView(
              controller: _controller,
              onPageChanged: (index) {
                AppMotion.select();
                setState(() => _page = index);
              },
              children: <Widget>[
                _buildTools(context),
                _buildAchievements(context),
              ],
            ),
          ),
          _PageHint(current: _page, total: 2, l10n: l10n),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 第 1 页：所有工具卡片（2 列网格，可滚动）
  // ---------------------------------------------------------------------------

  Widget _buildTools(BuildContext context) {
    final entries = _entries(context);
    return ListView(
      padding: const EdgeInsets.only(bottom: AppConstants.spaceL),
      children: <Widget>[
        const SizedBox(height: AppConstants.spaceS),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.spaceL,
            vertical: AppConstants.spaceS,
          ),
          crossAxisCount: AppConstants.toolCardsPerRow,
          mainAxisSpacing: AppConstants.spaceM,
          crossAxisSpacing: AppConstants.spaceM,
          childAspectRatio: AppConstants.toolCardAspectRatio,
          children: <Widget>[
            for (var i = 0; i < entries.length; i++)
              StaggeredEntrance(
                index: i,
                child: _ToolCard(entry: entries[i]),
              ),
          ],
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // 第 2 页：教学成果
  // ---------------------------------------------------------------------------

  Widget _buildAchievements(BuildContext context) {
    return HeartBurst(
      child: RefreshIndicator(
        onRefresh: _loadInsight,
        child: ListView(
          padding: const EdgeInsets.only(bottom: AppConstants.spaceL),
          children: <Widget>[
            const SizedBox(height: AppConstants.spaceS),
            _buildInsight(context),
          ],
        ),
      ),
    );
  }

  Widget _buildInsight(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final insight = _insight;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppConstants.spaceL),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SectionHeader(
            title: l10n.toolboxOverviewTitle,
            icon: Icons.emoji_events_outlined,
            description: insight == null
                ? null
                : l10n.weekRange(
                    _formatMonthDay(insight.weekStart),
                    _formatMonthDay(insight.weekEnd),
                  ),
          ),
          if (_loadingInsight && insight == null)
            const _InsightSkeleton()
          else if (insight == null)
            AppCard(child: Text(l10n.noData, style: theme.textTheme.bodyMedium))
          else ...<Widget>[
            _CheerBanner(text: l10n.insightCheer(insight.doneLessons)),
            const SizedBox(height: AppConstants.spaceM),
            _OverviewCard(
              tone: ToolCardTone.blue,
              icon: Icons.event_available_outlined,
              label: l10n.insightWeekLessons,
              value: l10n.insightUnitDays(_teachingDayCount(insight)),
              caption: l10n.insightUnitLessons(insight.totalLessons),
            ),
            const SizedBox(height: AppConstants.spaceM),
            _OverviewCard(
              tone: ToolCardTone.green,
              icon: Icons.menu_book_outlined,
              label: l10n.insightTotalLessons,
              value: l10n.insightUnitPeriods(insight.totalLessons),
              caption: l10n.insightUnitCourses(insight.courseCount),
            ),
            const SizedBox(height: AppConstants.spaceM),
            _OverviewCard(
              tone: ToolCardTone.rose,
              icon: Icons.favorite_outline,
              label: l10n.insightFocusCount,
              value: l10n.insightUnitTimes(insight.focusSessions),
              caption: insight.focusSessions == 0
                  ? l10n.insightFocusNoRecord
                  : l10n.insightFocusMinutes(insight.focusMinutes),
            ),
            const SizedBox(height: AppConstants.spaceM),
            _OverviewCard(
              tone: ToolCardTone.amber,
              icon: Icons.today_outlined,
              label: l10n.insightTodayLessons,
              value: l10n.insightUnitPeriods(insight.todayLessons),
              caption: insight.todayLessons == 0
                  ? l10n.insightTodayNoLesson
                  : l10n.insightTodayEventsCount(insight.todayEvents.length),
            ),
            if (insight.holidayWeek.hasAdjustment) ...<Widget>[
              const SizedBox(height: AppConstants.spaceM),
              _HolidayStrip(insight: insight),
            ],
            SectionHeader(
              title: l10n.toolboxTodayTitle,
              icon: Icons.wb_sunny_outlined,
              description: _formatMonthDay(DateTime.now()),
            ),
            _TodayCard(insight: insight),
            const SizedBox(height: AppConstants.spaceS),
            _InsightSection(
              icon: Icons.calendar_view_week_outlined,
              tone: ToolCardTone.blue,
              title: l10n.insightSectionLessons,
              subtitle: l10n.insightSectionLessonsDesc,
              summary: l10n.insightDoneOfTotal(insight.doneLessons, insight.totalLessons),
              expanded: _openSections.contains(_InsightSectionId.lessons),
              onToggle: () => _toggleSection(_InsightSectionId.lessons),
              child: _LessonsDetail(insight: insight),
            ),
            const SizedBox(height: AppConstants.spaceM),
            _InsightSection(
              icon: Icons.fact_check_outlined,
              tone: ToolCardTone.green,
              title: l10n.insightSectionAttendance,
              subtitle: l10n.insightSectionAttendanceDesc,
              summary: insight.hasAttendanceData
                  ? '${insight.attendanceRatePercent}%'
                  : '--',
              expanded: _openSections.contains(_InsightSectionId.attendance),
              onToggle: () => _toggleSection(_InsightSectionId.attendance),
              child: _AttendanceDetail(insight: insight),
            ),
            const SizedBox(height: AppConstants.spaceM),
            _InsightSection(
              icon: Icons.timer_outlined,
              tone: ToolCardTone.rose,
              title: l10n.insightSectionFocus,
              subtitle: l10n.insightFocusMinutes(insight.focusMinutes),
              summary: l10n.insightUnitTimes(insight.focusSessions),
              expanded: _openSections.contains(_InsightSectionId.focus),
              onToggle: () => _toggleSection(_InsightSectionId.focus),
              child: _FocusDetail(insight: insight),
            ),
            const SizedBox(height: AppConstants.spaceM),
            _InsightSection(
              icon: Icons.push_pin_outlined,
              tone: ToolCardTone.amber,
              title: l10n.insightSectionEvents,
              subtitle: l10n.insightSectionEventsDesc,
              summary: l10n.insightUnitItems(insight.weekEvents.length),
              expanded: _openSections.contains(_InsightSectionId.events),
              onToggle: () => _toggleSection(_InsightSectionId.events),
              child: _EventsDetail(insight: insight),
            ),
            const SizedBox(height: AppConstants.spaceM),
            if (!insight.hasCourseData)
              Padding(
                padding: const EdgeInsets.only(top: AppConstants.spaceS),
                child: Text(
                  l10n.insightNoLessonThisWeek,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  /// 「本周上课 N 天」= 本周实际要上课的天数（已扣放假、已含调休上班日）。
  static int _teachingDayCount(TeachingInsight insight) =>
      insight.holidayWeek.classDays.length;

  static String _formatMonthDay(DateTime date) =>
      '${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

/// 分段卡片的 id（展开状态用字符串存，方便扩展）。
abstract final class _InsightSectionId {
  static const String lessons = 'lessons';
  static const String attendance = 'attendance';
  static const String focus = 'focus';
  static const String events = 'events';
}

/// 底部页指示：两个圆点（活动的是拉长的小胶囊）+ 一句「左右滑动 · 共 2 页」。
///
/// 用户规格：不放"工具 / 教学成果"这两个文字标题，用圆点 + 一句提示即可。
class _PageHint extends StatelessWidget {
  const _PageHint({
    required this.current,
    required this.total,
    required this.l10n,
  });

  final int current;
  final int total;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.spaceL,
        AppConstants.spaceS,
        AppConstants.spaceL,
        AppConstants.spaceM,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          for (var i = 0; i < total; i++)
            AnimatedContainer(
              duration: AppMotion.standard,
              curve: AppMotion.expressive,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: i == current ? 20 : 7,
              height: 7,
              decoration: BoxDecoration(
                color: i == current ? scheme.primary : scheme.outlineVariant,
                borderRadius: AppRadii.stadiumAll,
              ),
            ),
          const SizedBox(width: AppConstants.spaceS),
          Text(
            l10n.toolboxSwipeHint,
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// 教学成果的骨架占位：骨架条高度与真实内容一致（一句话 + 四张卡 + 月段）。
class _InsightSkeleton extends StatelessWidget {
  const _InsightSkeleton();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bar = scheme.onSurface.withValues(alpha: 0.08);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        AppCard(
          child: Row(
            children: <Widget>[
              _Bar(width: 20, height: 20, color: bar),
              const SizedBox(width: AppConstants.spaceM),
              Expanded(child: _Bar(height: 14, color: bar)),
            ],
          ),
        ),
        const SizedBox(height: AppConstants.spaceM),
        for (var i = 0; i < 4; i++) ...<Widget>[
          if (i > 0) const SizedBox(height: AppConstants.spaceM),
          AppCard(
            child: Row(
              children: <Widget>[
                _Bar(width: 52, height: 52, color: bar),
                const SizedBox(width: AppConstants.spaceM),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      _Bar(width: 72, height: 11, color: bar),
                      const SizedBox(height: 8),
                      _Bar(width: 110, height: 22, color: bar),
                      const SizedBox(height: 8),
                      _Bar(width: 84, height: 11, color: bar),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({this.width, required this.height, required this.color});

  final double? width;
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: color,
          borderRadius: AppRadii.stadiumAll,
        ),
      ),
    );
  }
}

/// 单个工具卡片（第 13 轮：**实色卡**）。
///
/// 用户参考图给的是"一屏彩色卡片"，要求饱和度低一点但配色协调。
/// 所以这里不再用 AppCard 的浅色底，而是自己铺一层同色系渐变：
/// 白字压在上面（六个色的相对亮度都在 0.16~0.19，对比度 4.5:1 上下），
/// 图标块用白色半透明蒙版而不是第二套颜色 —— 层次够，配色不散。
class _ToolCard extends StatelessWidget {
  const _ToolCard({required this.entry});

  final _ToolEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final gradient = entry.tone.gradientFor(brightness);
    return SquishyTap(
      onTap: () => pushAppPage(context, entry.target),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: gradient,
          ),
          borderRadius: BorderRadius.circular(AppRadii.squircel),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppConstants.spaceM),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  // 白色半透明图标块：不引入第二个色相也能拉出层次
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.22),
                      borderRadius: AppRadii.tileAll,
                    ),
                    child: Icon(entry.icon, color: Colors.white, size: 22),
                  ),
                  const Spacer(),
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 12,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Text(
                entry.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                entry.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.85),
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 情绪价值横幅（保留第 10 轮的要求：成果页要有一句"你看你今天又上了几节课"）。
class _CheerBanner extends StatelessWidget {
  const _CheerBanner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return AppCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.spaceL,
        vertical: AppConstants.spaceM,
      ),
      radius: AppRadii.squircel,
      child: Row(
        children: <Widget>[
          Icon(Icons.auto_awesome_outlined, size: 18, color: scheme.primary),
          const SizedBox(width: AppConstants.spaceM),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 「数据概览」的一张数据卡（参考图版式：左侧色块图标 + 小标签 + 大数字 + 副标题）。
class _OverviewCard extends StatelessWidget {
  const _OverviewCard({
    required this.tone,
    required this.icon,
    required this.label,
    required this.value,
    required this.caption,
  });

  final ToolCardTone tone;
  final IconData icon;
  final String label;
  final String value;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final accent = isDark ? tone.light : tone.deep;
    return AppCard(
      padding: const EdgeInsets.all(AppConstants.spaceM),
      child: Row(
        children: <Widget>[
          Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: tone.light.withValues(alpha: isDark ? 0.24 : 0.14),
              borderRadius: AppRadii.tileAll,
            ),
            child: Icon(icon, size: 24, color: accent),
          ),
          const SizedBox(width: AppConstants.spaceM),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: accent,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 本周节假日/调休一览条：只在有调整的这一周出现。
///
/// 用来回答"这周怎么少了 4 节课"——放假和调休都在这一行里说清楚。
class _HolidayStrip extends StatelessWidget {
  const _HolidayStrip({required this.insight});

  final TeachingInsight insight;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final holidays = insight.holidayDays;
    final makeup = insight.makeupDay;
    return AppCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.spaceM,
        vertical: AppConstants.spaceS,
      ),
      color: scheme.surfaceContainerHigh,
      elevated: false,
      child: Row(
        children: <Widget>[
          Icon(Icons.beach_access_outlined, size: 16, color: scheme.onSurfaceVariant),
          const SizedBox(width: AppConstants.spaceS),
          Expanded(
            child: Wrap(
              spacing: AppConstants.spaceM,
              runSpacing: 2,
              children: <Widget>[
                if (holidays.isNotEmpty)
                  Text(
                    l10n.holidayFreeCount(holidays.length),
                    style: theme.textTheme.labelSmall,
                  ),
                if (makeup != null)
                  Text(
                    l10n.holidayMakeupCount(1),
                    style: theme.textTheme.labelSmall,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 「今日回顾」：今天的课节 + 今天的日程。
class _TodayCard extends StatelessWidget {
  const _TodayCard({required this.insight});

  final TeachingInsight insight;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final today = insight.holidayWeek.days.firstWhere(
      (day) => app_dates.DateUtils.isSameDay(day.date, DateTime.now()),
      orElse: () => HolidayDay(
        date: app_dates.DateUtils.dateOnly(DateTime.now()),
        kind: DateTime.now().weekday == DateTime.saturday ||
                DateTime.now().weekday == DateTime.sunday
            ? CalendarDayKind.weekend
            : CalendarDayKind.workday,
        labelWeekday: DateTime.now().weekday,
      ),
    );
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.wb_sunny_outlined, size: 17, color: scheme.primary),
              const SizedBox(width: AppConstants.spaceS),
              Expanded(
                child: Text(
                  insight.todayLessons == 0
                      ? l10n.insightTodayNoLesson
                      : l10n.insightUnitPeriods(insight.todayLessons),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (today.kind == CalendarDayKind.holiday)
                _Tag(
                  text: l10n.holidayKindHoliday,
                  color: scheme.error,
                )
              else if (today.kind == CalendarDayKind.makeupWorkday)
                _Tag(
                  text: today.isShifted
                      ? l10n.holidayMakeupResolved(
                          l10n.weekdayShort(today.labelWeekday),
                        )
                      : l10n.holidayKindMakeup,
                  color: scheme.tertiary,
                ),
            ],
          ),
          const SizedBox(height: AppConstants.spaceM),
          if (insight.todayEvents.isEmpty)
            Text(
              l10n.insightEventsEmpty,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            )
          else
            for (final event in insight.todayEvents) _EventRow(event: event),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppConstants.spaceS, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: AppRadii.stadiumAll,
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

/// 一条日程（时间 + 标题 + 地点）。
class _EventRow extends StatelessWidget {
  const _EventRow({required this.event});

  final ScheduleEvent event;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final start = DateTime.fromMillisecondsSinceEpoch(event.startAt);
    final time = '${start.hour.toString().padLeft(2, '0')}:'
        '${start.minute.toString().padLeft(2, '0')}';
    final location = event.location;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppConstants.spaceS),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(
              color: ToolCardTone.rose.light,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: AppConstants.spaceS),
          SizedBox(
            width: 44,
            child: Text(
              time,
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              location == null || location.isEmpty
                  ? event.title
                  : l10n.insightEventWithLocation(event.title, location),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

/// 分段可展开卡片。
///
/// 收起态也在标题右侧留一行**摘要**（"已上 12/22 节"、"92%"、"2 次"），
/// 这样不展开也能扫到关键数字，展开只是看细节——避免"全收起等于信息全丢"。
class _InsightSection extends StatelessWidget {
  const _InsightSection({
    required this.icon,
    required this.tone,
    required this.title,
    required this.subtitle,
    required this.summary,
    required this.expanded,
    required this.onToggle,
    required this.child,
  });

  final IconData icon;
  final ToolCardTone tone;
  final String title;
  final String subtitle;
  final String summary;
  final bool expanded;
  final VoidCallback onToggle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final accent = isDark ? tone.light : tone.deep;
    return AppCard(
      padding: const EdgeInsets.all(AppConstants.spaceM),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          InkWell(
            borderRadius: AppRadii.innerAll,
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppConstants.spaceXs),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: tone.light.withValues(alpha: isDark ? 0.24 : 0.14),
                      borderRadius: AppRadii.smallAll,
                    ),
                    child: Icon(icon, size: 18, color: accent),
                  ),
                  const SizedBox(width: AppConstants.spaceM),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          title,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppConstants.spaceS),
                  Text(
                    summary,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: accent,
                    ),
                  ),
                  AnimatedRotation(
                    duration: AppMotion.standard,
                    curve: AppMotion.expressive,
                    turns: expanded ? 0.5 : 0,
                    child: Icon(
                      Icons.expand_more_rounded,
                      size: 20,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            duration: AppMotion.standard,
            sizeCurve: AppMotion.expressive,
            crossFadeState:
                expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            firstChild: const SizedBox(width: double.infinity, height: 0),
            secondChild: Padding(
              padding: const EdgeInsets.only(top: AppConstants.spaceM),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

/// 课时分布：本周每天几节 + 每门课几节 + 调休说明。
class _LessonsDetail extends StatelessWidget {
  const _LessonsDetail({required this.insight});

  final TeachingInsight insight;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    // 按**真实星期几**摆 7 列，但柱子高度取"这一天实际执行的课表"——
    // 调休日（比如周日上周三的课）的柱子会带一个「班」角标，
    // 一眼看出这天的课是从别的星期几挪过来的。
    final byRealWeekday = <int, HolidayDay>{
      for (final day in insight.holidayWeek.days) day.date.weekday: day,
    };
    final byLabelWeekday = <int, HolidayDay>{
      for (final day in insight.holidayWeek.days)
        if (day.kind == CalendarDayKind.makeupWorkday) day.labelWeekday: day,
    };
    final counts = insight.lessonsByWeekday;
    var maxCount = 1;
    for (final value in counts.values) {
      if (value > maxCount) {
        maxCount = value;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          l10n.insightPerDayTitle,
          style: theme.textTheme.labelMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppConstants.spaceS),
        SizedBox(
          height: 74,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              for (var weekday = 1; weekday <= 7; weekday++)
                Expanded(
                  child: _DayBar(
                    weekday: weekday,
                    count: counts[weekday] ?? 0,
                    maxCount: maxCount,
                    realDay: byRealWeekday[weekday],
                    shiftDay: byLabelWeekday[weekday],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppConstants.spaceL),
        if (insight.lessonsByCourse.isNotEmpty) ...<Widget>[
          Text(
            l10n.insightPerCourseTitle,
            style: theme.textTheme.labelMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppConstants.spaceS),
          for (final entry in insight.lessonsByCourse)
            Padding(
              padding: const EdgeInsets.only(bottom: AppConstants.spaceS),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      entry.key,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  const SizedBox(width: AppConstants.spaceS),
                  Text(
                    l10n.insightUnitPeriods(entry.value),
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
        ],
        if (insight.holidayWeek.hasAdjustment)
          Padding(
            padding: const EdgeInsets.only(top: AppConstants.spaceXs),
            child: Text(
              [
                for (final day in insight.holidayDays)
                  '${_formatMonthDay(day.date)} ${_holidayName(l10n, day.name)}',
                for (final day in insight.holidayWeek.days)
                  if (day.kind == CalendarDayKind.makeupWorkday)
                    '${_formatMonthDay(day.date)} '
                        '${l10n.holidayMakeupResolved(l10n.weekdayShort(day.labelWeekday))}',
              ].join(' · '),
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }

  static String _formatMonthDay(DateTime date) =>
      '${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

/// 一根柱子：高度 ∝ 节数，下面写星期，放假/调休带角标。
class _DayBar extends StatelessWidget {
  const _DayBar({
    required this.weekday,
    required this.count,
    required this.maxCount,
    required this.realDay,
    required this.shiftDay,
  });

  final int weekday;
  final int count;
  final int maxCount;
  final HolidayDay? realDay;
  final HolidayDay? shiftDay;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isMakeup = shiftDay != null;
    final isOff = realDay?.kind == CalendarDayKind.holiday ||
        realDay?.kind == CalendarDayKind.weekend;
    final barColor =
        isOff && !isMakeup ? scheme.outlineVariant : ToolCardTone.blue.light;
    final height = count == 0 ? 4.0 : 6.0 + 40.0 * count / maxCount;
    // 角标优先显示「班」：这一列的课是调休挪过来的，比"这天本来放假"更该被看见
    final badge = isMakeup
        ? l10n.holidayKindMakeup
        : (isOff ? l10n.holidayKindHoliday : null);
    final badgeColor = isMakeup ? scheme.tertiary : scheme.error;
    final labelColor = badge == null ? scheme.onSurfaceVariant : badgeColor;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: <Widget>[
          Text(
            count == 0 ? '' : '$count',
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 2),
          AnimatedContainer(
            duration: AppMotion.standard,
            curve: AppMotion.expressive,
            height: height,
            decoration: BoxDecoration(
              color: barColor,
              borderRadius: AppRadii.smallAll,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            l10n.weekdayShort(weekday),
            style: theme.textTheme.labelSmall?.copyWith(
              color: labelColor,
              fontWeight: badge == null ? FontWeight.w500 : FontWeight.w800,
            ),
          ),
          if (badge != null)
            Text(
              badge,
              style: theme.textTheme.labelSmall?.copyWith(
                fontSize: 9,
                height: 1.0,
                fontWeight: FontWeight.w800,
                color: badgeColor,
              ),
            ),
        ],
      ),
    );
  }
}

/// 出勤情况：出勤率 + 最好/最差的班 + 需要关注的学生。
class _AttendanceDetail extends StatelessWidget {
  const _AttendanceDetail({required this.insight});

  final TeachingInsight insight;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final best = insight.bestClass;
    final worst = insight.worstClass;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Text(
              insight.hasAttendanceData
                  ? '${insight.attendanceRatePercent}%'
                  : '--',
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: ToolCardTone.green.deep,
                letterSpacing: -0.6,
              ),
            ),
            const SizedBox(width: AppConstants.spaceS),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  l10n.insightAttendanceRate,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            Text(
              l10n.insightUnitStudents(insight.benefitedStudents),
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppConstants.spaceM),
        if (!insight.hasClassComparison)
          Text(
            insight.containsClassData ? l10n.insightSingleClass : l10n.insightNoClassData,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          )
        else ...<Widget>[
          _ClassRateRow(
            icon: Icons.emoji_events_outlined,
            label: l10n.insightBestClass,
            tone: ToolCardTone.green,
            item: best,
          ),
          const SizedBox(height: AppConstants.spaceS),
          _ClassRateRow(
            icon: Icons.priority_high_rounded,
            label: l10n.insightWorstClass,
            tone: ToolCardTone.amber,
            item: worst,
          ),
        ],
        const SizedBox(height: AppConstants.spaceM),
        Row(
          children: <Widget>[
            Icon(
              Icons.notifications_active_outlined,
              size: 16,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(width: AppConstants.spaceS),
            Text(
              l10n.insightAttention,
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppConstants.spaceS),
        if (insight.attention.isEmpty)
          Row(
            children: <Widget>[
              Icon(Icons.verified_outlined, size: 18, color: scheme.primary),
              const SizedBox(width: AppConstants.spaceS),
              Expanded(
                child: Text(
                  l10n.insightNoAttention,
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          )
        else
          for (final item in insight.attention) _AttentionRow(item: item),
      ],
    );
  }
}

extension on TeachingInsight {
  /// 只要点过名（哪怕只有一个班）就算有班级数据，用来区分
  /// "本周没点名"和"只点了一个班的名"两句提示。
  bool get containsClassData => classList.any((item) => item.hasData);
}

class _ClassRateRow extends StatelessWidget {
  const _ClassRateRow({
    required this.icon,
    required this.label,
    required this.tone,
    required this.item,
  });

  final IconData icon;
  final String label;
  final ToolCardTone tone;
  final ClassAttendanceRate? item;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final accent = isDark ? tone.light : tone.deep;
    return Row(
      children: <Widget>[
        Icon(icon, size: 16, color: accent),
        const SizedBox(width: AppConstants.spaceS),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: AppConstants.spaceS),
        Expanded(
          child: Text(
            item?.className ?? '--',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: AppConstants.spaceS),
        Text(
          item == null ? '' : l10n.insightClassRate(item!.ratePercent, item!.total),
          style: theme.textTheme.labelSmall?.copyWith(color: accent),
        ),
      ],
    );
  }
}

/// 专注投入：次数 / 累计分钟 / 平均一次多久。
class _FocusDetail extends StatelessWidget {
  const _FocusDetail({required this.insight});

  final TeachingInsight insight;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    if (insight.focusSessions == 0) {
      return Text(
        l10n.insightFocusNoRecord,
        style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
      );
    }
    final average = (insight.focusMinutes / insight.focusSessions).round();
    return Row(
      children: <Widget>[
        Expanded(
          child: _MiniStat(
            value: l10n.insightUnitTimes(insight.focusSessions),
            label: l10n.insightFocusCount,
            tone: ToolCardTone.rose,
          ),
        ),
        Expanded(
          child: _MiniStat(
            value: l10n.insightUnitMinutes(insight.focusMinutes),
            label: l10n.insightFocusTotal,
            tone: ToolCardTone.rose,
          ),
        ),
        Expanded(
          child: _MiniStat(
            value: l10n.insightUnitMinutes(average),
            label: l10n.insightFocusAverage,
            tone: ToolCardTone.rose,
          ),
        ),
      ],
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.value,
    required this.label,
    required this.tone,
  });

  final String value;
  final String label;
  final ToolCardTone tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    return Column(
      children: <Widget>[
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: isDark ? tone.light : tone.deep,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          textAlign: TextAlign.center,
          style: theme.textTheme.labelSmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// 额外事务：本周日程清单。
class _EventsDetail extends StatelessWidget {
  const _EventsDetail({required this.insight});

  final TeachingInsight insight;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    if (insight.weekEvents.isEmpty) {
      return Text(
        l10n.insightEventsEmpty,
        style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final event in insight.weekEvents) _WeekEventRow(event: event),
      ],
    );
  }
}

/// 一行"周几 + 时间 + 标题"（本周事务列表用）。
class _WeekEventRow extends StatelessWidget {
  const _WeekEventRow({required this.event});

  final ScheduleEvent event;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final start = DateTime.fromMillisecondsSinceEpoch(event.startAt);
    final location = event.location;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppConstants.spaceS),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 52,
            child: Text(
              l10n.weekdayShort(start.weekday),
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  event.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (location != null && location.isNotEmpty)
                  Text(
                    location,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppConstants.spaceS),
          Text(
            '${start.hour.toString().padLeft(2, '0')}:'
            '${start.minute.toString().padLeft(2, '0')}',
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// 成果统计小格（旧的 4 联排已改成 [_OverviewCard]）。
class _AttentionRow extends StatelessWidget {
  const _AttentionRow({required this.item});

  final RiskStudent item;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppConstants.spaceS),
      child: Row(
        children: <Widget>[
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: scheme.errorContainer.withValues(alpha: 0.7),
              borderRadius: AppRadii.smallAll,
            ),
            child: Text(
              item.student.name.isEmpty
                  ? '?'
                  : item.student.name.substring(0, 1),
              style: theme.textTheme.labelLarge?.copyWith(
                color: scheme.onErrorContainer,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: AppConstants.spaceM),
          Expanded(
            child: Text(
              l10n.insightStudentRisk(item.student.name, item.absentCount),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolEntry {
  const _ToolEntry({
    required this.icon,
    required this.label,
    required this.description,
    required this.tone,
    required this.target,
  });

  final IconData icon;
  final String label;
  final String description;
  final ToolCardTone tone;
  final Widget target;
}

/// 节日名的本地化（`HolidayName` → 文案）。
String _holidayName(AppLocalizations l10n, HolidayName? name) => switch (name) {
      HolidayName.newYear => l10n.holidayNameNewYear,
      HolidayName.springFestival => l10n.holidayNameSpringFestival,
      HolidayName.qingming => l10n.holidayNameQingming,
      HolidayName.labourDay => l10n.holidayNameLabourDay,
      HolidayName.dragonBoat => l10n.holidayNameDragonBoat,
      HolidayName.midAutumn => l10n.holidayNameMidAutumn,
      HolidayName.nationalDay => l10n.holidayNameNationalDay,
      HolidayName.nationalDayMidAutumn => l10n.holidayNameNationalDayMidAutumn,
      null => '',
    };
