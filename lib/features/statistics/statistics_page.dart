import 'package:fl_chart/fl_chart.dart';
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
import 'package:schedule_plan/core/widgets/scale_tap.dart';
import 'package:schedule_plan/data/models/attendance.dart';
import 'package:schedule_plan/data/models/china_holiday.dart';
import 'package:schedule_plan/data/models/class_course.dart';
import 'package:schedule_plan/data/models/student.dart';
import 'package:schedule_plan/data/repositories/attendance_repository.dart';
import 'package:schedule_plan/data/repositories/class_repository.dart';
import 'package:schedule_plan/data/repositories/course_repository.dart';
import 'package:schedule_plan/data/repositories/lesson_repository.dart';
import 'package:schedule_plan/data/repositories/student_repository.dart';
import 'package:schedule_plan/data/services/excel_service.dart';
import 'package:schedule_plan/data/services/holiday_service.dart';
import 'package:schedule_plan/data/services/share_service.dart';
import 'package:schedule_plan/data/settings_state.dart';
import 'package:schedule_plan/features/attendance/attendance_status_strip.dart';
import 'package:schedule_plan/features/statistics/attendance_analytics.dart';
import 'package:schedule_plan/features/statistics/attendance_formula_sheet.dart';
import 'package:schedule_plan/features/statistics/attendance_ledger.dart';
import 'package:schedule_plan/features/statistics/student_ledger_page.dart';

/// 考勤统计与导出（模块三，`docs/SPEC.md` 3.7 ~ 3.11）。
///
/// 这一版把统计拆成**两本台账**：
/// - 概览里的「高风险学生排名」是**干预台账**（加权分，回答"该找谁谈"）；
/// - 「班级排行」是**评价台账**（出勤率，回答"分怎么给"）。
///
/// 两者同源不同用，口径刻意不同（详见 SPEC 3.11），不要合并。
class StatisticsPage extends StatefulWidget {
  const StatisticsPage({super.key, this.holidayService});

  /// 测试可注入（生产留空，自己 new 一个）。
  final HolidayService? holidayService;

  @override
  State<StatisticsPage> createState() => _StatisticsPageState();
}

/// 统计页的两个视图。学生档案不在这里 —— 它是独立页，
/// 从排行点姓名或学生名单进（SPEC 3.8）。
enum _StatView { overview, ranking }

/// 时间区间预设。写死 90 天的老做法已经废掉（SPEC 3.7）。
enum _RangePreset { week, month, term, custom }

class _StatisticsPageState extends State<StatisticsPage> {
  late final HolidayService _holidays =
      widget.holidayService ?? HolidayService();

  _StatView _view = _StatView.overview;
  _RangePreset _preset = _RangePreset.term;
  DateTimeRange? _customRange;
  String _granularity = 'week';
  int _classFilter = 0;
  int _courseFilter = 0;
  AttendanceStatus? _statusFilter;
  late Future<_StatisticsData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  /// 区间解析：本周 / 本月 / 本学期 / 自定义。
  DateTimeRange _resolveRange() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (_preset) {
      case _RangePreset.week:
        final start = app_dates.DateUtils.startOfWeek(today);
        return DateTimeRange(
          start: start,
          end: DateTime(start.year, start.month, start.day + 6),
        );
      case _RangePreset.month:
        return DateTimeRange(
          start: DateTime(now.year, now.month, 1),
          end: DateTime(now.year, now.month + 1, 0),
        );
      case _RangePreset.term:
        final term = schoolTermRange(now);
        return DateTimeRange(start: term.start, end: term.end);
      case _RangePreset.custom:
        final custom = _customRange;
        if (custom == null) {
          return _resolveRangeFor(_RangePreset.term);
        }
        return custom;
    }
  }

  DateTimeRange _resolveRangeFor(_RangePreset preset) {
    final previous = _preset;
    _preset = preset;
    final range = _resolveRange();
    _preset = previous;
    return range;
  }

  Future<_StatisticsData> _load() async {
    final attendance = context.read<AttendanceRepository>();
    final lessonRepo = context.read<LessonRepository>();
    final studentRepo = context.read<StudentRepository>();
    final classRepo = context.read<ClassRepository>();
    final courseRepo = context.read<CourseRepository>();
    final settings = context.read<SettingsState>();

    final range = _resolveRange();
    final from = range.start;
    final to = range.end;
    final fromDate = app_dates.DateUtils.formatDate(from);
    final toDate = app_dates.DateUtils.formatDate(to);
    final classId = _classFilter == 0 ? null : _classFilter;
    final courseId = _courseFilter == 0 ? null : _courseFilter;

    final classes = await classRepo.listClasses();
    final courses = await courseRepo.listCourses();
    var students = await studentRepo.listAll();
    if (classId != null) {
      students = students
          .where((student) => student.classId == classId)
          .toList(growable: false);
    }

    final rows = await attendance.ledger(
      fromDate: fromDate,
      toDate: toDate,
      classId: classId,
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

    final abnormal = await attendance.abnormalDetails(
      fromDate: fromDate,
      toDate: toDate,
      classId: classId,
      courseId: courseId,
      status: _statusFilter,
    );
    final ranking = await attendance.riskRanking(
      classId: classId,
      courseId: courseId,
      fromDate: fromDate,
      toDate: toDate,
      weightAbsent: settings.riskWeightAbsent,
      weightLate: settings.riskWeightLate,
      weightEarlyLeave: settings.riskWeightEarlyLeave,
    );

    return _StatisticsData(
      analytics: analytics,
      classes: classes,
      courses: courses,
      abnormal: abnormal,
      ranking: ranking,
      from: from,
      to: to,
    );
  }

  void _reload() {
    setState(() {
      _future = _load();
    });
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 3),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: _customRange ??
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
      _preset = _RangePreset.custom;
    });
    _reload();
  }

  Future<void> _export(_StatisticsData data) async {
    final l10n = context.l10n;
    try {
      final courseId = _courseFilter == 0 ? null : _courseFilter;
      final classId = _classFilter == 0 ? null : _classFilter;
      final fromDate = app_dates.DateUtils.formatDate(data.from);
      final toDate = app_dates.DateUtils.formatDate(data.to);
      final summary = await context.read<AttendanceRepository>().exportSummary(
        fromDate: fromDate,
        toDate: toDate,
        classId: classId,
        courseId: courseId,
      );
      // 文件名：`20261112-2038-数学-出勤情况.xlsx`；没筛课程就写「全部课程」，
      // 筛了班级再接一段班级名，免得同分钟导出的几个班互相覆盖。
      var courseName = l10n.statAllCourses;
      if (courseId != null) {
        for (final course in data.courses) {
          if (course.id == courseId) {
            courseName = course.name;
            break;
          }
        }
      }
      var className = '';
      if (classId != null) {
        for (final item in data.classes) {
          if (item.id == classId) {
            className = item.name;
            break;
          }
        }
      }
      final path = await ExcelService().exportAttendanceWorkbook(
        summaryRows: summary,
        abnormalRows: data.abnormal,
        ranking: data.ranking,
        fromDate: fromDate,
        toDate: toDate,
        rateRows: <Map<String, Object?>>[
          for (final ledger in data.analytics.ledgers)
            <String, Object?>{
              'class_name': ledger.className,
              'student_name': ledger.student.name,
              'student_no': ledger.student.studentNo ?? '',
              'expected': ledger.expectedSessions,
              'absent': ledger.tally.absent,
              'late': ledger.tally.late,
              'early_leave': ledger.tally.earlyLeave,
              'late_early': ledger.tally.lateAndEarly,
              'leave': ledger.tally.leave,
              'rate': ledger.attendanceRate,
            },
        ],
        formulaNote: l10n.statFormulaLine1,
        fileSubject: className.isEmpty ? courseName : '$courseName-$className',
        fileKind: '出勤情况',
      );
      if (!mounted) {
        return;
      }
      showAppSnackBar(context, l10n.exportSuccess);
      await ShareService.shareFile(
        path: path,
        subject: l10n.statisticsTitle,
        text: l10n.statisticsTitle,
      );
    } catch (error, stack) {
      AppLogger.e('导出 Excel 失败', error: error, stack: stack);
      if (!mounted) {
        return;
      }
      showAppSnackBar(context, l10n.operationFailed('$error'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.statisticsTitle),
        actions: <Widget>[
          AttendanceFormulaButton(),
          IconButton(
            icon: const Icon(Icons.ios_share_outlined),
            tooltip: l10n.exportExcel,
            onPressed: () async {
              final data = await _future;
              if (!mounted) {
                return;
              }
              await _export(data);
            },
          ),
        ],
      ),
      body: FutureBuilder<_StatisticsData>(
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
          return ListView(
            padding: const EdgeInsets.only(bottom: AppConstants.spaceXl),
            children: <Widget>[
              _buildRangeBar(data, l10n),
              _buildFilters(data, l10n),
              _buildViewSwitch(l10n),
              if (_view == _StatView.overview) ...<Widget>[
                _buildEmotionCard(data, l10n),
                _buildLineChart(data, l10n),
                _buildBarChart(data, l10n),
                _buildAbnormalList(data, l10n),
                _buildRiskRanking(data, l10n),
              ] else
                _buildRateRanking(data, l10n),
            ],
          );
        },
      ),
    );
  }

  Widget _buildRangeBar(_StatisticsData data, dynamic l10n) {
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
            child: SegmentedButton<_RangePreset>(
              showSelectedIcon: false,
              segments: <ButtonSegment<_RangePreset>>[
                ButtonSegment<_RangePreset>(
                  value: _RangePreset.week,
                  label: Text(l10n.statRangeWeek),
                ),
                ButtonSegment<_RangePreset>(
                  value: _RangePreset.month,
                  label: Text(l10n.statRangeMonth),
                ),
                ButtonSegment<_RangePreset>(
                  value: _RangePreset.term,
                  label: Text(l10n.statRangeTerm),
                ),
                ButtonSegment<_RangePreset>(
                  value: _RangePreset.custom,
                  label: Text(l10n.statRangeCustom),
                ),
              ],
              selected: <_RangePreset>{_preset},
              onSelectionChanged: (selection) {
                final picked = selection.first;
                if (picked == _RangePreset.custom) {
                  _pickCustomRange();
                  return;
                }
                setState(() => _preset = picked);
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
        ],
      ),
    );
  }

  Widget _buildFilters(_StatisticsData data, dynamic l10n) {
    return Padding(
      padding: const EdgeInsets.all(AppConstants.spaceL),
      child: Row(
        children: <Widget>[
          Expanded(
            child: DropdownButtonFormField<int>(
              initialValue: _classFilter,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: l10n.statClassFilter,
                isDense: true,
              ),
              items: <DropdownMenuItem<int>>[
                DropdownMenuItem<int>(value: 0, child: Text(l10n.all)),
                for (final item in data.classes)
                  if (item.id != null)
                    DropdownMenuItem<int>(
                      value: item.id,
                      child: Text(item.name, overflow: TextOverflow.ellipsis),
                    ),
              ],
              onChanged: (value) {
                setState(() => _classFilter = value ?? 0);
                _reload();
              },
            ),
          ),
          const SizedBox(width: AppConstants.spaceM),
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
                for (final item in data.courses)
                  if (item.id != null)
                    DropdownMenuItem<int>(
                      value: item.id,
                      child: Text(item.name, overflow: TextOverflow.ellipsis),
                    ),
              ],
              onChanged: (value) {
                setState(() => _courseFilter = value ?? 0);
                _reload();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildViewSwitch(dynamic l10n) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppConstants.spaceL),
      child: Row(
        children: <Widget>[
          Expanded(
            child: SegmentedButton<_StatView>(
              showSelectedIcon: false,
              segments: <ButtonSegment<_StatView>>[
                ButtonSegment<_StatView>(
                  value: _StatView.overview,
                  label: Text(l10n.statOverview),
                ),
                ButtonSegment<_StatView>(
                  value: _StatView.ranking,
                  label: Text(l10n.statClassRanking),
                ),
              ],
              selected: <_StatView>{_view},
              onSelectionChanged: (selection) {
                setState(() => _view = selection.first);
              },
            ),
          ),
          const SizedBox(width: AppConstants.spaceS),
          if (_view == _StatView.overview)
            DropdownButton<String>(
              value: _granularity,
              underline: const SizedBox.shrink(),
              items: <DropdownMenuItem<String>>[
                DropdownMenuItem<String>(
                  value: 'day',
                  child: Text(l10n.granularityDay),
                ),
                DropdownMenuItem<String>(
                  value: 'week',
                  child: Text(l10n.granularityWeek),
                ),
                DropdownMenuItem<String>(
                  value: 'month',
                  child: Text(l10n.granularityMonth),
                ),
              ],
              onChanged: (value) {
                if (value == null) {
                  return;
                }
                setState(() => _granularity = value);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildEmotionCard(_StatisticsData data, dynamic l10n) {
    final tokens = context.watch<ThemeController>().tokens;
    final rate = data.analytics.overallRate;
    final text = rate == null
        ? l10n.statNoTimetable
        : switch (rate * 100) {
            >= 95 => l10n.emotionExcellent,
            >= 85 => l10n.emotionGood,
            >= 60 => l10n.emotionNormal,
            _ => l10n.emotionEncourage,
          };
    return Padding(
      padding: const EdgeInsets.all(AppConstants.spaceL),
      child: AppCard(
        color: tokens.primaryContainer,
        child: Row(
          children: <Widget>[
            Icon(Icons.emoji_emotions_outlined, color: tokens.primary),
            const SizedBox(width: AppConstants.spaceM),
            Expanded(child: Text(text)),
            if (rate != null)
              Text(
                '${(rate * 100).toStringAsFixed(1)}%',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: tokens.primary,
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 多条课程曲线轮转用的色板（无课程色时按顺序取）。
  static const List<Color> _linePalette = <Color>[
    Color(0xFF4FA8F5),
    Color(0xFF4FC3B0),
    Color(0xFFFFA94D),
    Color(0xFFB48CF0),
    Color(0xFFF06292),
    Color(0xFF64B5F6),
  ];

  Widget _buildLineChart(_StatisticsData data, dynamic l10n) {
    final series = _buildCourseSeries(data);
    if (series.isEmpty) {
      return const SizedBox.shrink();
    }
    final labels = series.first.labels;
    final bars = <LineChartBarData>[];
    final legend = <Widget>[];
    for (var i = 0; i < series.length; i++) {
      final color = _linePalette[i % _linePalette.length];
      bars.add(
        LineChartBarData(
          spots: series[i].spots,
          isCurved: true,
          color: color,
          barWidth: 3,
          dotData: const FlDotData(show: false),
        ),
      );
      legend.add(_LegendItem(name: series[i].name, color: color));
    }
    return Padding(
      padding: const EdgeInsets.all(AppConstants.spaceL),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: Text(l10n.attendanceRateChart)),
              AttendanceFormulaButton(),
            ],
          ),
          const SizedBox(height: AppConstants.spaceS),
          Wrap(
            spacing: AppConstants.spaceM,
            runSpacing: 6,
            children: legend,
          ),
          const SizedBox(height: AppConstants.spaceM),
          SizedBox(
            height: 200,
            child: LineChart(
              LineChartData(
                minY: 0,
                maxY: 100,
                gridData: const FlGridData(show: true),
                borderData: FlBorderData(show: false),
                lineBarsData: bars,
                titlesData: FlTitlesData(
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();
                        if (index < 0 || index >= labels.length) {
                          return const SizedBox.shrink();
                        }
                        // 桶太多时只画几个刻度，否则横轴糊成一团
                        final step = (labels.length / 5).ceil();
                        if (step > 1 && index % step != 0) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            labels[index],
                            style: const TextStyle(fontSize: 10),
                          ),
                        );
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 32,
                      interval: 25,
                      getTitlesWidget: (value, meta) => Text(
                        value.toInt().toString(),
                        style: const TextStyle(fontSize: 10),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 每门课一条曲线：横轴是"日期桶"（日 / 周 / 月），纵轴是该桶的出勤率。
  ///
  /// 分母来自课表推算、分子来自台账，所以只能在这里逐日算完再按桶合并，
  /// 不能像以前那样直接把 SQL 的两列相除（那算的是"标过名的人里出勤的比例"）。
  List<_CourseSeries> _buildCourseSeries(_StatisticsData data) {
    final buckets = <String>{};
    final byCourse = <int, Map<String, double>>{};

    for (var day = data.from;
        !day.isAfter(data.to);
        day = DateTime(day.year, day.month, day.day + 1)) {
      final date = app_dates.DateUtils.formatDate(day);
      for (final course in data.courses) {
        final id = course.id;
        if (id == null) {
          continue;
        }
        final rate = data.analytics.dateCourseRate(date, id);
        if (rate == null) {
          continue;
        }
        final key = _granularityKey(date);
        buckets.add(key);
        byCourse.putIfAbsent(id, () => <String, double>{})[key] = rate;
      }
    }
    if (buckets.isEmpty) {
      return const <_CourseSeries>[];
    }
    final keys = buckets.toList()..sort();
    final result = <_CourseSeries>[];
    for (final entry in byCourse.entries) {
      final spots = <FlSpot>[];
      for (var i = 0; i < keys.length; i++) {
        final value = entry.value[keys[i]];
        if (value == null) {
          continue;
        }
        spots.add(FlSpot(i.toDouble(), value * 100));
      }
      if (spots.isEmpty) {
        continue;
      }
      final course = data.courses.firstWhere(
        (item) => item.id == entry.key,
        orElse: () => data.courses.first,
      );
      result.add(
        _CourseSeries(
          name: course.name,
          spots: spots,
          labels: <String>[
            for (final key in keys) key.length > 5 ? key.substring(5) : key,
          ],
        ),
      );
    }
    return result;
  }

  String _granularityKey(String date) => switch (_granularity) {
        'week' => _weekKey(date),
        'month' => date.substring(0, 7),
        _ => date,
      };

  String _weekKey(String date) {
    final parsed = app_dates.DateUtils.tryParseDate(date);
    if (parsed == null) {
      return date;
    }
    return app_dates.DateUtils.formatDate(
      app_dates.DateUtils.startOfWeek(parsed),
    );
  }

  Widget _buildBarChart(_StatisticsData data, dynamic l10n) {
    final rows = <_CourseRate>[
      for (final course in data.courses)
        if (course.id != null)
          if (data.analytics.expectedOfCourse(course.id!) > 0)
            _CourseRate(
              name: course.name,
              rate: data.analytics.courseRate(course.id!) ?? 1,
            ),
    ];
    if (rows.isEmpty) {
      return const SizedBox.shrink();
    }
    final settings = context.watch<SettingsState>();
    final tokens = context.watch<ThemeController>().tokens;
    return Padding(
      padding: const EdgeInsets.all(AppConstants.spaceL),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(l10n.courseRateChart),
          const SizedBox(height: AppConstants.spaceM),
          SizedBox(
            height: 220,
            child: BarChart(
              BarChartData(
                maxY: 100,
                gridData: const FlGridData(show: true),
                borderData: FlBorderData(show: false),
                barGroups: <BarChartGroupData>[
                  for (var i = 0; i < rows.length; i++)
                    BarChartGroupData(
                      x: i,
                      barRods: <BarChartRodData>[
                        BarChartRodData(
                          toY: rows[i].rate * 100,
                          width: 14,
                          color: rows[i].rate * 100 <
                                  settings.attendanceWarnRate
                              ? tokens.chartWarn
                              : tokens.primary,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ],
                    ),
                ],
                titlesData: FlTitlesData(
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 32,
                      interval: 25,
                      getTitlesWidget: (value, meta) => Text(
                        value.toInt().toString(),
                        style: const TextStyle(fontSize: 10),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();
                        if (index < 0 || index >= rows.length) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            rows[index].name,
                            style: const TextStyle(fontSize: 9),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAbnormalList(_StatisticsData data, dynamic l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.all(AppConstants.spaceL),
          child: Row(
            children: <Widget>[
              Expanded(child: Text(l10n.abnormalList)),
              DropdownButton<AttendanceStatus?>(
                value: _statusFilter,
                items: <DropdownMenuItem<AttendanceStatus?>>[
                  DropdownMenuItem<AttendanceStatus?>(
                    value: null,
                    child: Text(l10n.all),
                  ),
                  for (final status in AttendanceStatus.values)
                    if (status.isAbnormal)
                      DropdownMenuItem<AttendanceStatus?>(
                        value: status,
                        child: Text(statusLabelOf(context, status)),
                      ),
                ],
                onChanged: (value) {
                  setState(() => _statusFilter = value);
                  _reload();
                },
              ),
            ],
          ),
        ),
        if (data.abnormal.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppConstants.spaceL),
            child: Text(l10n.noData),
          )
        else
          for (final row in data.abnormal.take(50))
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppConstants.spaceL,
                vertical: 4,
              ),
              child: AppCard(
                padding: const EdgeInsets.all(AppConstants.spaceM),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            '${row['student_name'] ?? ''} · '
                            '${row['course_name'] ?? ''}',
                          ),
                          Text(
                            '${row['date'] ?? ''} ${row['start_time'] ?? ''} '
                            '${row['class_name'] ?? ''}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    Text(
                      statusLabelOf(
                        context,
                        AttendanceStatus.fromStorage(row['status'] as String?),
                      ),
                    ),
                  ],
                ),
              ),
            ),
      ],
    );
  }

  /// 干预台账：加权分排序，回答"我该找谁谈谈"（SPEC 3.4，**保持原样**）。
  Widget _buildRiskRanking(_StatisticsData data, dynamic l10n) {
    if (data.ranking.isEmpty) {
      return const SizedBox.shrink();
    }
    final tokens = context.watch<ThemeController>().tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.all(AppConstants.spaceL),
          child: Text(l10n.riskRanking),
        ),
        for (var i = 0; i < data.ranking.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppConstants.spaceL,
              vertical: 4,
            ),
            child: ScaleTap(
              onTap: () => _openLedger(data, data.ranking[i].student, null),
              child: AppCard(
                color: data.ranking[i].riskScore > 0
                    ? tokens.riskHighlight
                    : null,
                padding: const EdgeInsets.all(AppConstants.spaceM),
                child: Row(
                  children: <Widget>[
                    Text('${i + 1}'),
                    const SizedBox(width: AppConstants.spaceM),
                    Expanded(child: Text(data.ranking[i].student.name)),
                    Text(l10n.riskScoreLabel(data.ranking[i].riskScore)),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// 评价台账：出勤率排行（SPEC 3.9）。按班级分节，班内出勤率升序。
  Widget _buildRateRanking(_StatisticsData data, dynamic l10n) {
    final groups = data.analytics.ledgersByClass;
    if (groups.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(AppConstants.spaceL),
        child: Text(l10n.noData),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppConstants.spaceL,
            AppConstants.spaceL,
            AppConstants.spaceL,
            AppConstants.spaceS,
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  l10n.statRankingHint,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
        for (final entry in groups) ...<Widget>[
          _buildClassHeader(entry.key, classAttendanceRate(entry.value), l10n),
          _buildRankingHeader(l10n),
          for (final ledger in entry.value)
            _buildRankingRow(data, ledger),
        ],
      ],
    );
  }

  Widget _buildClassHeader(String className, double? rate, dynamic l10n) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.spaceL,
        AppConstants.spaceL,
        AppConstants.spaceL,
        AppConstants.spaceS,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              className.isEmpty ? l10n.all : className,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          Text(
            '${l10n.statClassAverage} '
            '${rate == null ? '—' : '${(rate * 100).toStringAsFixed(1)}%'}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _buildRankingHeader(dynamic l10n) {
    final style = Theme.of(context).textTheme.bodySmall;
    Widget cell(String text, double width) => SizedBox(
          width: width,
          child: Text(text, textAlign: TextAlign.right, style: style),
        );
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.spaceL,
        vertical: AppConstants.spaceS,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Row(
              children: <Widget>[
                Text(l10n.statRate, style: style),
                AttendanceFormulaButton(size: 14),
              ],
            ),
          ),
          cell(l10n.statAbsent, 30),
          cell(l10n.statLate, 30),
          cell(l10n.statEarlyLeave, 30),
          cell(l10n.statLateAndEarly, 34),
          cell(l10n.statLeave, 30),
        ],
      ),
    );
  }

  Widget _buildRankingRow(_StatisticsData data, StudentLedger ledger) {
    final theme = Theme.of(context);
    final rate = ledger.attendanceRate;
    final rateText = rate == null ? '—' : '${(rate * 100).toStringAsFixed(1)}%';
    final warn = rate != null && rate * 100 < 85;
    Widget cell(int value, double width) => SizedBox(
          width: width,
          child: Text(
            value == 0 ? '·' : '$value',
            textAlign: TextAlign.right,
            style: theme.textTheme.bodySmall,
          ),
        );
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.spaceL,
        vertical: 2,
      ),
      child: ScaleTap(
        onTap: () => _openLedger(data, ledger.student, ledger.className),
        child: AppCard(
          padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.spaceM,
            vertical: AppConstants.spaceS,
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(ledger.student.name, style: theme.textTheme.bodyMedium),
                    if ((ledger.student.studentNo ?? '').isNotEmpty)
                      Text(
                        ledger.student.studentNo!,
                        style: theme.textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
              SizedBox(
                width: 56,
                child: Text(
                  rateText,
                  textAlign: TextAlign.right,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: warn ? theme.colorScheme.error : null,
                  ),
                ),
              ),
              cell(ledger.tally.absent, 30),
              cell(ledger.tally.late, 30),
              cell(ledger.tally.earlyLeave, 30),
              cell(ledger.tally.lateAndEarly, 34),
              cell(ledger.tally.leave, 30),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openLedger(
    _StatisticsData data,
    Student student,
    String? className,
  ) async {
    final id = student.id;
    if (id == null) {
      return;
    }
    await Navigator.of(context).push(
      AppPageRoute<void>(
        child: StudentLedgerPage(
          studentId: id,
          studentName: student.name,
          fromDate: app_dates.DateUtils.formatDate(data.from),
          toDate: app_dates.DateUtils.formatDate(data.to),
          courseId: _courseFilter == 0 ? null : _courseFilter,
        ),
      ),
    );
    if (!mounted) {
      return;
    }
    // 档案页里只是看，不改数据；但日期区间不在这里变，重载一次成本很低，
    // 而且能接住"以后档案页加了备注"这种情况。
    _reload();
  }
}

class _CourseSeries {
  const _CourseSeries({
    required this.name,
    required this.spots,
    required this.labels,
  });

  final String name;
  final List<FlSpot> spots;
  final List<String> labels;
}

class _CourseRate {
  const _CourseRate({required this.name, required this.rate});

  final String name;
  final double rate;
}

class _StatisticsData {
  const _StatisticsData({
    required this.analytics,
    required this.classes,
    required this.courses,
    required this.abnormal,
    required this.ranking,
    required this.from,
    required this.to,
  });

  final AttendanceAnalytics analytics;
  final List<ClassInfo> classes;
  final List<Course> courses;
  final List<Map<String, Object?>> abnormal;
  final List<RiskStudent> ranking;
  final DateTime from;
  final DateTime to;
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.name, required this.color});

  final String name;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(name, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
