import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:schedule_plan/core/constants/app_constants.dart';
import 'package:schedule_plan/core/l10n/l10n_extensions.dart';
import 'package:schedule_plan/core/logging/app_logger.dart';
import 'package:schedule_plan/core/theme/app_colors.dart';
import 'package:schedule_plan/core/theme/theme_controller.dart';
import 'package:schedule_plan/core/utils/date_utils.dart' as app_dates;
import 'package:schedule_plan/core/widgets/app_card.dart';
import 'package:schedule_plan/core/widgets/app_snackbar.dart';
import 'package:schedule_plan/core/widgets/pulse_loading.dart';
import 'package:schedule_plan/core/widgets/scale_tap.dart';
import 'package:schedule_plan/data/models/attendance.dart';
import 'package:schedule_plan/data/models/class_course.dart';
import 'package:schedule_plan/data/repositories/attendance_repository.dart';
import 'package:schedule_plan/data/repositories/course_repository.dart';
import 'package:schedule_plan/data/services/excel_service.dart';
import 'package:schedule_plan/data/services/share_service.dart';
import 'package:schedule_plan/data/settings_state.dart';
import 'package:schedule_plan/features/attendance/attendance_status_strip.dart';

/// 考勤统计与导出（模块三）。
class StatisticsPage extends StatefulWidget {
  const StatisticsPage({super.key});

  @override
  State<StatisticsPage> createState() => _StatisticsPageState();
}

class _StatisticsPageState extends State<StatisticsPage> {
  String _granularity = 'week';
  int _courseFilter = 0;
  AttendanceStatus? _statusFilter;
  late Future<_StatisticsData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_StatisticsData> _load() async {
    // 仓储在 await 之前取好，避免跨异步间隙使用 context
    final attendance = context.read<AttendanceRepository>();
    final courseRepo = context.read<CourseRepository>();
    final settings = context.read<SettingsState>();
    final now = DateTime.now();
    final from = app_dates.DateUtils.formatDate(
      now.subtract(const Duration(days: 90)),
    );
    final to = app_dates.DateUtils.formatDate(now);
    // 用户规格：筛选条件按**课程**，不再按班级
    final courseId = _courseFilter == 0 ? null : _courseFilter;

    final seriesByCourse = await attendance.attendanceRateSeriesByCourse(
      fromDate: from,
      toDate: to,
      courseId: courseId,
    );
    final byCourse = await attendance.attendanceRateByCourse(
      fromDate: from,
      toDate: to,
      courseId: courseId,
    );
    final abnormal = await attendance.abnormalDetails(
      fromDate: from,
      toDate: to,
      courseId: courseId,
      status: _statusFilter,
    );
    final ranking = await attendance.riskRanking(
      courseId: courseId,
      fromDate: from,
      toDate: to,
      weightAbsent: settings.riskWeightAbsent,
      weightLate: settings.riskWeightLate,
      weightEarlyLeave: settings.riskWeightEarlyLeave,
    );
    final courses = await courseRepo.listCourses();
    return _StatisticsData(
      seriesByCourse: seriesByCourse,
      byCourse: byCourse,
      abnormal: abnormal,
      ranking: ranking,
      courses: courses,
      from: from,
      to: to,
    );
  }

  Future<void> _export(_StatisticsData data) async {
    final l10n = context.l10n;
    try {
      final courseId = _courseFilter == 0 ? null : _courseFilter;
      final summary = await context.read<AttendanceRepository>().exportSummary(
            fromDate: data.from,
            toDate: data.to,
            courseId: courseId,
          );
      final path = await ExcelService().exportAttendanceWorkbook(
        summaryRows: summary,
        abnormalRows: data.abnormal,
        ranking: data.ranking,
        fromDate: data.from,
        toDate: data.to,
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
    final tokens = context.watch<ThemeController>().tokens;
    final settings = context.watch<SettingsState>();
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.statisticsTitle),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.ios_share_outlined),
            tooltip: l10n.exportExcel,
            onPressed: () async {
              final data = await _future;
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
              _buildGranularitySwitch(l10n),
              _buildCourseFilter(data, l10n),
              _buildEmotionCard(data, l10n, tokens),
              _buildLineChart(data, l10n, tokens),
              _buildBarChart(data, l10n, tokens, settings),
              _buildAbnormalList(data, l10n),
              _buildRanking(data, l10n, tokens),
            ],
          );
        },
      ),
    );
  }

  Widget _buildGranularitySwitch(dynamic l10n) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppConstants.spaceL),
      child: SegmentedButton<String>(
        segments: <ButtonSegment<String>>[
          ButtonSegment<String>(value: 'day', label: Text(l10n.granularityDay)),
          ButtonSegment<String>(value: 'week', label: Text(l10n.granularityWeek)),
          ButtonSegment<String>(value: 'month', label: Text(l10n.granularityMonth)),
        ],
        selected: <String>{_granularity},
        onSelectionChanged: (selection) {
          // 切换粒度时保留当前选中的班级筛选条件（模块三 3.1）
          setState(() {
            _granularity = selection.first;
            _future = _load();
          });
        },
      ),
    );
  }

  Widget _buildCourseFilter(_StatisticsData data, dynamic l10n) {
    return Padding(
      padding: const EdgeInsets.all(AppConstants.spaceL),
      child: DropdownButtonFormField<int>(
        initialValue: _courseFilter,
        decoration: InputDecoration(labelText: l10n.courseFilterLabel),
        items: <DropdownMenuItem<int>>[
          DropdownMenuItem<int>(value: 0, child: Text(l10n.all)),
          for (final item in data.courses)
            if (item.id != null)
              DropdownMenuItem<int>(value: item.id, child: Text(item.name)),
        ],
        onChanged: (value) {
          setState(() {
            _courseFilter = value ?? 0;
            _future = _load();
          });
        },
      ),
    );
  }

  Widget _buildEmotionCard(
    _StatisticsData data,
    dynamic l10n,
    AppColorTokens tokens,
  ) {
    final rate = _overallRate(data);
    final text = switch (rate) {
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
          ],
        ),
      ),
    );
  }

  double _overallRate(_StatisticsData data) {
    var present = 0;
    var total = 0;
    for (final row in data.seriesByCourse) {
      present += (row['present_count'] as int?) ?? 0;
      total += (row['total_count'] as int?) ?? 0;
    }
    if (total == 0) {
      return 100;
    }
    return present * 100.0 / total;
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

  Widget _buildLineChart(
    _StatisticsData data,
    dynamic l10n,
    AppColorTokens tokens,
  ) {
    // 用户规格："出勤率折线图最好可以有多条曲线，多个课程同时展现。"
    final grouped = _groupSeriesByCourse(data.seriesByCourse);
    if (grouped.courses.isEmpty) {
      return const SizedBox.shrink();
    }
    final labels = grouped.labels;
    final bars = <LineChartBarData>[];
    final legend = <Widget>[];
    for (var i = 0; i < grouped.courses.length; i++) {
      final course = grouped.courses[i];
      final color = _linePalette[i % _linePalette.length];
      bars.add(
        LineChartBarData(
          spots: course.spots,
          isCurved: true,
          color: color,
          barWidth: 3,
          dotData: const FlDotData(show: false),
        ),
      );
      legend.add(_LegendItem(name: course.name, color: color));
    }
    return Padding(
      padding: const EdgeInsets.all(AppConstants.spaceL),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(l10n.attendanceRateChart),
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

  /// 按「课程 × 时间桶」聚合：一条课程一条曲线，横轴是所有课程共用的时间桶。
  _GroupedCourseSeries _groupSeriesByCourse(
    List<Map<String, Object?>> series,
  ) {
    final byCourse = <Object, _CourseAccum>{};
    final names = <Object, String>{};
    for (final row in series) {
      final date = row['date'] as String? ?? '';
      if (date.isEmpty) {
        continue;
      }
      final key = row['course_id'] ?? (row['course_name'] as String? ?? '?');
      names[key] = (row['course_name'] as String?) ?? '?';
      final present = (row['present_count'] as int?) ?? 0;
      final total = (row['total_count'] as int?) ?? 0;
      final acc = byCourse.putIfAbsent(key, () => _CourseAccum());
      final entry = acc.buckets.putIfAbsent(
        _granularityKey(date),
        () => <int>[0, 0],
      );
      entry[0] += present;
      entry[1] += total;
    }

    final allKeys = <String>{
      for (final acc in byCourse.values) ...acc.buckets.keys,
    }.toList()
      ..sort();

    final courses = <_CourseSeries>[];
    for (final entry in byCourse.entries) {
      final spots = <FlSpot>[];
      for (var i = 0; i < allKeys.length; i++) {
        final bucket = entry.value.buckets[allKeys[i]];
        if (bucket == null) {
          continue;
        }
        final rate = bucket[1] == 0 ? 100.0 : bucket[0] * 100.0 / bucket[1];
        spots.add(FlSpot(i.toDouble(), rate));
      }
      if (spots.isNotEmpty) {
        courses.add(_CourseSeries(name: names[entry.key] ?? '?', spots: spots));
      }
    }
    return _GroupedCourseSeries(
      courses: courses,
      labels: <String>[
        for (final key in allKeys) key.length > 5 ? key.substring(5) : key,
      ],
    );
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
    return app_dates.DateUtils.formatDate(app_dates.DateUtils.startOfWeek(parsed));
  }

  Widget _buildBarChart(
    _StatisticsData data,
    dynamic l10n,
    AppColorTokens tokens,
    SettingsState settings,
  ) {
    if (data.byCourse.isEmpty) {
      return const SizedBox.shrink();
    }
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
                  for (var i = 0; i < data.byCourse.length; i++)
                    _buildBarGroup(data.byCourse[i], i, tokens, settings),
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
                        if (index < 0 || index >= data.byCourse.length) {
                          return const SizedBox.shrink();
                        }
                        final row = data.byCourse[index];
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            '${row['course_name'] ?? ''}',
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

  BarChartGroupData _buildBarGroup(
    Map<String, Object?> row,
    int index,
    AppColorTokens tokens,
    SettingsState settings,
  ) {
    final present = (row['present_count'] as int?) ?? 0;
    final total = (row['total_count'] as int?) ?? 0;
    final rate = total == 0 ? 100.0 : present * 100.0 / total;
    // 低于设定阈值（默认 85%）的柱子变色警示（模块三 3.2）
    final color = rate < settings.attendanceWarnRate ? tokens.chartWarn : tokens.primary;
    return BarChartGroupData(
      x: index,
      barRods: <BarChartRodData>[
        BarChartRodData(
          toY: rate,
          width: 14,
          color: color,
          borderRadius: BorderRadius.circular(4),
        ),
      ],
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
                        child: Text(_statusLabel(status)),
                      ),
                ],
                onChanged: (value) {
                  setState(() {
                    _statusFilter = value;
                    _future = _load();
                  });
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
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: data.abnormal.length,
            itemBuilder: (context, index) {
              final row = data.abnormal[index];
              return Padding(
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
                            Text('${row['student_name'] ?? ''} · ${row['course_name'] ?? ''}'),
                            Text(
                              '${row['date'] ?? ''} ${row['start_time'] ?? ''} '
                              '${row['class_name'] ?? ''}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      Text(_statusLabel(
                        AttendanceStatus.fromStorage(row['status'] as String?),
                      )),
                    ],
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildRanking(
    _StatisticsData data,
    dynamic l10n,
    AppColorTokens tokens,
  ) {
    if (data.ranking.isEmpty) {
      return const SizedBox.shrink();
    }
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
              child: AppCard(
                color: data.ranking[i].riskScore > 0 ? tokens.riskHighlight : null,
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

  /// 状态文案统一走 `statusLabelOf`（与考勤页 / 设置页同一份映射）。
  String _statusLabel(AttendanceStatus status) => statusLabelOf(context, status);
}

class _StatisticsData {
  const _StatisticsData({
    required this.seriesByCourse,
    required this.byCourse,
    required this.abnormal,
    required this.ranking,
    required this.courses,
    required this.from,
    required this.to,
  });

  final List<Map<String, Object?>> seriesByCourse;
  final List<Map<String, Object?>> byCourse;
  final List<Map<String, Object?>> abnormal;
  final List<RiskStudent> ranking;
  final List<Course> courses;
  final String from;
  final String to;
}

/// 一条课程曲线（图例名 + 已对齐到共享横轴的点）。
class _CourseSeries {
  const _CourseSeries({required this.name, required this.spots});

  final String name;
  final List<FlSpot> spots;
}

/// 一次「日期 × 课程」聚合的累计器。
class _CourseAccum {
  final Map<String, List<int>> buckets = <String, List<int>>{};
}

/// 多课程曲线的聚合结果：所有课程 + 共享的横轴标签。
class _GroupedCourseSeries {
  const _GroupedCourseSeries({required this.courses, required this.labels});

  final List<_CourseSeries> courses;
  final List<String> labels;
}

/// 折线图右上角的一枚图例：色点 + 课程名。
class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.name, required this.color});

  final String name;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          name,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
