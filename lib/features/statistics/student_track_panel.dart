import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:schedule_plan/core/constants/app_constants.dart';
import 'package:schedule_plan/core/l10n/l10n_extensions.dart';
import 'package:schedule_plan/core/logging/app_logger.dart';
import 'package:schedule_plan/core/theme/app_page_route.dart';
import 'package:schedule_plan/core/theme/theme_controller.dart';
import 'package:schedule_plan/core/utils/date_utils.dart' as app_dates;
import 'package:schedule_plan/core/widgets/app_card.dart';
import 'package:schedule_plan/core/widgets/app_snackbar.dart';
import 'package:schedule_plan/core/widgets/pulse_loading.dart';
import 'package:schedule_plan/data/models/china_holiday.dart';
import 'package:schedule_plan/data/models/class_course.dart';
import 'package:schedule_plan/data/repositories/attendance_repository.dart';
import 'package:schedule_plan/data/repositories/class_repository.dart';
import 'package:schedule_plan/data/repositories/course_repository.dart';
import 'package:schedule_plan/data/repositories/lesson_repository.dart';
import 'package:schedule_plan/data/repositories/student_repository.dart';
import 'package:schedule_plan/data/services/excel_service.dart';
import 'package:schedule_plan/data/services/holiday_service.dart';
import 'package:schedule_plan/data/services/share_service.dart';
import 'package:schedule_plan/features/statistics/attendance_analytics.dart';
import 'package:schedule_plan/features/statistics/attendance_ledger.dart';
import 'package:schedule_plan/features/statistics/student_track_detail_page.dart';

/// 时间区间预设（工具箱 · 学生追踪页自己的那一份）。
///
/// 和统计页的 `_RangePreset` 语义一致，但统计页那份是私有枚举，
/// 强行拉出来共用会把两个页面的状态机绑在一起。**共用的是口径**
/// （[schoolTermRange] / `DateUtils.startOfWeek`），不是这个枚举。
enum TrackRange { week, month, term, custom }

/// 工具箱第 3 页：**单个学生的数据追踪**（用户规格第 33 轮）。
///
/// 用户原话：*"选择时间，选择课程，自动跳出学生名单，学生名单下二级子菜单
/// 显示学生异常出勤次数。点开具体的学生姓名，新开一页……显示这名学生在
/// 选定日期内的出勤记录，格式为日期-课程-出勤情况，正常出勤也显示。
/// 每一页都有导出按钮，导出当前的显示状态。"*
///
/// 这一页刻意**不复用统计页的版式**：统计页是"概览 + 图表 + 排行"三合一，
/// 老师嫌乱；这里只回答一个问题 ——「这段时间里，这个孩子缺了几次、都是哪天」。
/// 所以只有三样东西：时间段、课程、名单。
///
/// 页内**没有** FAB、没有二级 Tab；名单按异常次数从多到少排（[sortLedgersForTrack]），
/// 全勤的孩子沉在最后但不隐藏 —— 老师随时可能要点进去看他的记录。
class StudentTrackPanel extends StatefulWidget {
  const StudentTrackPanel({
    super.key,
    this.holidayService,
    this.refreshToken = 0,
    this.clock = DateTime.now,
  });

  /// 测试可注入（生产留空，自己 new 一个）。
  final HolidayService? holidayService;

  /// 外部要求刷新的信号：切换 Tab 回到工具箱、或滑到本页时自增。
  ///
  /// `PageView` 里这一页会保持存活（[AutomaticKeepAliveClientMixin]），
  /// 不靠这个信号就永远看不到别处改过的考勤。
  final int refreshToken;

  /// 测试注入"今天"用；区间预设全按它算，别在测试里依赖真实日期。
  final DateTime Function() clock;

  @override
  State<StudentTrackPanel> createState() => _StudentTrackPanelState();
}

class _StudentTrackPanelState extends State<StudentTrackPanel>
    with AutomaticKeepAliveClientMixin {
  late final HolidayService _holidays =
      widget.holidayService ?? HolidayService();

  TrackRange _range = TrackRange.term;
  DateTimeRange? _customRange;
  int _courseFilter = 0;
  late Future<_TrackData> _future;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(covariant StudentTrackPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) {
      _reload();
    }
  }

  /// 区间解析：本周 / 本月 / 本学期 / 自定义。口径与统计页一致。
  DateTimeRange _resolveRange() {
    final now = widget.clock();
    final today = DateTime(now.year, now.month, now.day);
    switch (_range) {
      case TrackRange.week:
        final start = app_dates.DateUtils.startOfWeek(today);
        return DateTimeRange(
          start: start,
          end: DateTime(start.year, start.month, start.day + 6),
        );
      case TrackRange.month:
        return DateTimeRange(
          start: DateTime(now.year, now.month, 1),
          end: DateTime(now.year, now.month + 1, 0),
        );
      case TrackRange.term:
        final term = schoolTermRange(now);
        return DateTimeRange(start: term.start, end: term.end);
      case TrackRange.custom:
        final custom = _customRange;
        if (custom == null) {
          final term = schoolTermRange(now);
          return DateTimeRange(start: term.start, end: term.end);
        }
        return custom;
    }
  }

  Future<_TrackData> _load() async {
    final attendance = context.read<AttendanceRepository>();
    final lessonRepo = context.read<LessonRepository>();
    final studentRepo = context.read<StudentRepository>();
    final classRepo = context.read<ClassRepository>();
    final courseRepo = context.read<CourseRepository>();

    final range = _resolveRange();
    final from = range.start;
    final to = range.end;
    final fromDate = app_dates.DateUtils.formatDate(from);
    final toDate = app_dates.DateUtils.formatDate(to);
    final courseId = _courseFilter == 0 ? null : _courseFilter;

    final students = await studentRepo.listAll();
    final courses = await courseRepo.listCourses();
    final classes = await classRepo.listClasses();
    final rows = await attendance.ledger(
      fromDate: fromDate,
      toDate: toDate,
      courseId: courseId,
    );
    final statuses = await attendance.allCourseStatuses();
    final slots = await lessonRepo.weeklySlots();
    final enabled = await _holidays.isEnabled();
    final shifts = await _holidays.shiftMap(from: from, to: to);

    final analytics = AttendanceAnalytics.build(
      slots: slots,
      students: students,
      rows: rows,
      longTermStatuses: statuses,
      from: from,
      to: to,
      // 未来还没上的课不算"应上"，否则期中看到的出勤率全是六七成
      asOf: widget.clock(),
      labelWeekday: (date) => HolidayService.labelWeekdayOf(
        date,
        shifts[app_dates.DateUtils.formatDate(date)],
      ),
      isRestDay: (date) =>
          enabled && HolidayService.kindOf(date) == CalendarDayKind.holiday,
      classNames: <int, String>{
        for (final item in classes)
          if (item.id != null) item.id!: item.name,
      },
      courseId: courseId,
    );

    var ledgers = analytics.ledgers;
    if (courseId != null) {
      // 选了课程就只留这门课的学生：课表里排了这门课的班（合班也算），
      // 加上台账里真实出现过的班 —— 学生转班后老记录还认得出原来的班。
      final classIds = <int>{
        for (final slot in slots)
          if (slot.courseId == courseId) ...slot.classIds,
        for (final row in rows)
          if (row.classId != null) row.classId!,
      };
      ledgers = ledgers
          .where((ledger) => classIds.contains(ledger.student.classId))
          .toList(growable: false);
    }

    String? courseName;
    if (courseId != null) {
      for (final item in courses) {
        if (item.id == courseId) {
          courseName = item.name;
          break;
        }
      }
    }

    return _TrackData(
      ledgers: sortLedgersForTrack(ledgers),
      courses: courses,
      from: from,
      to: to,
      courseName: courseName,
    );
  }

  void _reload() {
    if (!mounted) {
      return;
    }
    setState(() {
      _future = _load();
    });
  }

  Future<void> _pickCustomRange() async {
    final now = widget.clock();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 3),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange:
          _customRange ??
          DateTimeRange(
            start: now.subtract(const Duration(days: 30)),
            end: now,
          ),
    );
    if (picked == null) {
      return;
    }
    setState(() {
      _customRange = picked;
      _range = TrackRange.custom;
    });
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final l10n = context.l10n;
    return FutureBuilder<_TrackData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return PulseLoading(message: l10n.loading);
        }
        final data = snapshot.data;
        if (data == null) {
          return Center(child: Text(l10n.noData));
        }
        return _buildBody(data);
      },
    );
  }

  Widget _buildBody(_TrackData data) {
    final l10n = context.l10n;
    return ListView(
      padding: const EdgeInsets.only(bottom: AppConstants.spaceXl),
      children: <Widget>[
        _buildFilters(data),
        if (data.ledgers.isEmpty)
          Padding(
            padding: const EdgeInsets.all(AppConstants.spaceL),
            child: AppCard(
              child: Text(
                l10n.trackListEmpty,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          )
        else ...<Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppConstants.spaceL,
              AppConstants.spaceM,
              AppConstants.spaceL,
              AppConstants.spaceS,
            ),
            child: Row(
              children: <Widget>[
                Icon(
                  Icons.sort_rounded,
                  size: 14,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: AppConstants.spaceXs),
                Expanded(
                  child: Text(
                    l10n.trackSortHint,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
                Text(
                  l10n.trackStudentCount(data.ledgers.length),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ),
          _buildList(data),
        ],
      ],
    );
  }

  Widget _buildFilters(_TrackData data) {
    final l10n = context.l10n;
    final range = _resolveRange();
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.spaceL,
        AppConstants.spaceM,
        AppConstants.spaceL,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<TrackRange>(
              showSelectedIcon: false,
              segments: <ButtonSegment<TrackRange>>[
                ButtonSegment<TrackRange>(
                  value: TrackRange.week,
                  label: Text(l10n.statRangeWeek),
                ),
                ButtonSegment<TrackRange>(
                  value: TrackRange.month,
                  label: Text(l10n.statRangeMonth),
                ),
                ButtonSegment<TrackRange>(
                  value: TrackRange.term,
                  label: Text(l10n.statRangeTerm),
                ),
                ButtonSegment<TrackRange>(
                  value: TrackRange.custom,
                  label: Text(l10n.statRangeCustom),
                ),
              ],
              selected: <TrackRange>{_range},
              onSelectionChanged: (selection) {
                final picked = selection.first;
                if (picked == TrackRange.custom) {
                  _pickCustomRange();
                  return;
                }
                setState(() => _range = picked);
                _reload();
              },
            ),
          ),
          const SizedBox(height: AppConstants.spaceS),
          Text(
            l10n.statRangeLabel(
              app_dates.DateUtils.formatDate(range.start),
              app_dates.DateUtils.formatDate(range.end),
            ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: AppConstants.spaceM),
          Row(
            children: <Widget>[
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: _courseFilter,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: l10n.courseFilterLabel,
                    isDense: true,
                  ),
                  items: <DropdownMenuItem<int>>[
                    DropdownMenuItem<int>(value: 0, child: Text(l10n.all)),
                    for (final Course item in data.courses)
                      if (item.id != null)
                        DropdownMenuItem<int>(
                          value: item.id,
                          child: Text(
                            item.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                  ],
                  onChanged: (value) {
                    setState(() => _courseFilter = value ?? 0);
                    _reload();
                  },
                ),
              ),
              const SizedBox(width: AppConstants.spaceS),
              IconButton.filledTonal(
                onPressed: data.ledgers.isEmpty
                    ? null
                    : () => _exportList(data),
                tooltip: l10n.trackExportList,
                icon: const Icon(Icons.ios_share_outlined),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildList(_TrackData data) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppConstants.spaceL),
      child: AppCard(
        padding: EdgeInsets.zero,
        child: Column(
          children: <Widget>[
            for (var i = 0; i < data.ledgers.length; i++) ...<Widget>[
              if (i > 0)
                Divider(
                  height: 1,
                  thickness: 1,
                  color: scheme.outlineVariant.withValues(alpha: 0.4),
                ),
              _buildStudentRow(data.ledgers[i], data),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStudentRow(StudentLedger ledger, _TrackData data) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tokens = context.watch<ThemeController>().tokens;
    final tally = ledger.tally;
    final abnormal = tally.abnormal;
    final accent = abnormal > 0 ? scheme.error : tokens.primary;
    final rate = ledger.attendanceRate;
    final initial = ledger.student.name.isEmpty
        ? '?'
        : ledger.student.name.substring(0, 1);

    return InkWell(
      onTap: () => _openDetail(ledger, data),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppConstants.spaceM,
          vertical: AppConstants.spaceM,
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: AppRadii.smallAll,
              ),
              child: Text(
                initial,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: accent,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: AppConstants.spaceM),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    ledger.student.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  // 二级行 = 异常次数的拆分（用户规格："学生名单下二级子菜单
                  // 显示学生异常出勤次数"）。请假单列，不混进异常合计。
                  Text(
                    l10n.trackTallyLine(
                      tally.absent,
                      tally.late,
                      tally.earlyLeave,
                      tally.lateAndEarly,
                      tally.leave,
                    ),
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
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Text(
                  abnormal == 0
                      ? l10n.trackAllPresent
                      : l10n.trackAbnormalTimes(abnormal),
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  rate == null
                      ? '—'
                      : l10n.trackRatePercent((rate * 100).toStringAsFixed(1)),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: scheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openDetail(StudentLedger ledger, _TrackData data) async {
    await pushAppPage<void>(
      context,
      StudentTrackDetailPage(
        studentId: ledger.student.id!,
        studentName: ledger.student.name,
        fromDate: app_dates.DateUtils.formatDate(data.from),
        toDate: app_dates.DateUtils.formatDate(data.to),
        courseId: _courseFilter == 0 ? null : _courseFilter,
        holidayService: widget.holidayService,
        clock: widget.clock,
      ),
    );
  }

  /// 导出**当前这一页显示的东西**：区间 + 课程筛选下的学生名单。
  Future<void> _exportList(_TrackData data) async {
    final l10n = context.l10n;
    try {
      final path = await ExcelService().exportTrackWorkbook(
        fromDate: app_dates.DateUtils.formatDate(data.from),
        toDate: app_dates.DateUtils.formatDate(data.to),
        courseName: data.courseName ?? l10n.statAllCourses,
        studentRows: <Map<String, Object?>>[
          for (final ledger in data.ledgers)
            <String, Object?>{
              'student_name': ledger.student.name,
              'student_no': ledger.student.studentNo ?? '',
              'class_name': ledger.className,
              'expected': ledger.expectedSessions,
              'absent': ledger.tally.absent,
              'late': ledger.tally.late,
              'early_leave': ledger.tally.earlyLeave,
              'late_early': ledger.tally.lateAndEarly,
              'leave': ledger.tally.leave,
              'abnormal': ledger.tally.abnormal,
              'rate': ledger.attendanceRate,
            },
        ],
        formulaNote: l10n.statFormulaLine1,
      );
      if (!mounted) {
        return;
      }
      showAppSnackBar(context, l10n.exportSuccess);
      await ShareService.shareFile(
        path: path,
        subject: l10n.trackTitle,
        text: l10n.trackTitle,
      );
    } catch (error, stack) {
      AppLogger.e('导出学生追踪列表失败', error: error, stack: stack);
      if (!mounted) {
        return;
      }
      showAppSnackBar(context, l10n.operationFailed('$error'));
    }
  }
}

class _TrackData {
  const _TrackData({
    required this.ledgers,
    required this.courses,
    required this.from,
    required this.to,
    required this.courseName,
  });

  final List<StudentLedger> ledgers;
  final List<Course> courses;
  final DateTime from;
  final DateTime to;

  /// 选了课程时用来在导出的表头写一句「课程：数学」；没选为 null。
  final String? courseName;
}
