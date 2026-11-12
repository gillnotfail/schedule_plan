import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:schedule_plan/core/constants/app_constants.dart';
import 'package:schedule_plan/core/l10n/l10n_extensions.dart';
import 'package:schedule_plan/core/logging/app_logger.dart';
import 'package:schedule_plan/core/theme/theme_controller.dart';
import 'package:schedule_plan/core/utils/date_utils.dart' as app_dates;
import 'package:schedule_plan/core/widgets/app_card.dart';
import 'package:schedule_plan/core/widgets/app_snackbar.dart';
import 'package:schedule_plan/core/widgets/pulse_loading.dart';
import 'package:schedule_plan/data/models/attendance_ledger.dart';
import 'package:schedule_plan/data/models/china_holiday.dart';
import 'package:schedule_plan/data/models/student.dart';
import 'package:schedule_plan/data/repositories/attendance_repository.dart';
import 'package:schedule_plan/data/repositories/class_repository.dart';
import 'package:schedule_plan/data/repositories/lesson_repository.dart';
import 'package:schedule_plan/data/repositories/student_repository.dart';
import 'package:schedule_plan/data/services/excel_service.dart';
import 'package:schedule_plan/data/services/holiday_service.dart';
import 'package:schedule_plan/data/services/share_service.dart';
import 'package:schedule_plan/features/attendance/attendance_status_strip.dart';
import 'package:schedule_plan/features/statistics/attendance_analytics.dart';
import 'package:schedule_plan/features/statistics/attendance_formula_sheet.dart';
import 'package:schedule_plan/features/statistics/attendance_ledger.dart';

/// 单个学生在选定区间内的出勤记录（工具箱第 3 页点姓名进来）。
///
/// 用户规格：*"显示这名学生在选定日期内的出勤记录，格式为日期-课程-出勤情况，
/// 正常出勤也显示。每一页都是导出按钮，导出当前的显示状态。"*
///
/// 所以这一页**不是**档案页那种"按状态分组"的看板，而是一张按日期倒序的大表：
/// 一行一节课，出勤、迟到、缺勤平铺在同一列里，让老师顺着日期往下读。
///
/// 和档案页的另一个差别：**出勤也列出来**（`present` 是真实记录，不是推算），
/// 没点名的课次仍然不伪造行，只在表下面用小字交代有多少节。
class StudentTrackDetailPage extends StatefulWidget {
  const StudentTrackDetailPage({
    super.key,
    required this.studentId,
    required this.studentName,
    required this.fromDate,
    required this.toDate,
    this.courseId,
    this.holidayService,
    this.clock = DateTime.now,
  });

  final int studentId;
  final String studentName;
  final String fromDate;
  final String toDate;
  final int? courseId;

  /// 测试可注入（生产留空，自己 new 一个）。
  final HolidayService? holidayService;

  /// 只在"没有应上课次"的判断里用得到，测试可注入。
  final DateTime Function() clock;

  @override
  State<StudentTrackDetailPage> createState() => _StudentTrackDetailPageState();
}

class _StudentTrackDetailPageState extends State<StudentTrackDetailPage> {
  late final HolidayService _holidays =
      widget.holidayService ?? HolidayService();
  late Future<_TrackDetail> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_TrackDetail> _load() async {
    final attendance = context.read<AttendanceRepository>();
    final lessonRepo = context.read<LessonRepository>();
    final studentRepo = context.read<StudentRepository>();
    final classRepo = context.read<ClassRepository>();

    final from =
        app_dates.DateUtils.tryParseDate(widget.fromDate) ?? widget.clock();
    final to = app_dates.DateUtils.tryParseDate(widget.toDate) ?? from;

    final students = await studentRepo.listAll();
    final student = students.firstWhere(
      (item) => item.id == widget.studentId,
      orElse: () => Student(
        id: widget.studentId,
        name: widget.studentName,
        classId: 0,
      ),
    );
    final rows = await attendance.ledger(
      fromDate: widget.fromDate,
      toDate: widget.toDate,
      studentId: widget.studentId,
      courseId: widget.courseId,
    );
    final statuses = await attendance.allCourseStatuses();
    final slots = await lessonRepo.weeklySlots();
    final classes = await classRepo.listClasses();
    final enabled = await _holidays.isEnabled();
    final shifts = await _holidays.shiftMap(from: from, to: to);

    final analytics = AttendanceAnalytics.build(
      slots: slots,
      students: <Student>[student],
      rows: rows,
      longTermStatuses: statuses
          .where((status) => status.studentId == widget.studentId)
          .toList(growable: false),
      from: from,
      to: to,
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
      courseId: widget.courseId,
      studentId: widget.studentId,
    );

    final ledger = analytics.ledgers.isEmpty
        ? StudentLedger(
            student: student,
            className: '',
            tally: const LedgerTally(),
            expectedSessions: 0,
          )
        : analytics.ledgers.first;

    return _TrackDetail(
      ledger: ledger,
      rows: sortLedgerRowsByDate(rows),
      courseName: rows.isEmpty ? null : rows.first.courseName,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${widget.studentName} · ${l10n.trackDetailTitle}'.trim(),
        ),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.ios_share_outlined),
            tooltip: l10n.trackExportDetail,
            onPressed: () async {
              final data = await _future;
              if (!mounted) {
                return;
              }
              await _exportDetail(data);
            },
          ),
        ],
      ),
      body: FutureBuilder<_TrackDetail>(
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
      ),
    );
  }

  Widget _buildBody(_TrackDetail data) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final unmarked = unmarkedSessions(data.ledger);
    return ListView(
      padding: const EdgeInsets.only(bottom: AppConstants.spaceXl),
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppConstants.spaceL,
            AppConstants.spaceM,
            AppConstants.spaceL,
            0,
          ),
          child: Text(
            data.courseName == null
                ? l10n.statRangeLabel(widget.fromDate, widget.toDate)
                : l10n.trackRangeCourse(
                    widget.fromDate,
                    widget.toDate,
                    data.courseName!,
                  ),
            style: theme.textTheme.bodySmall,
          ),
        ),
        _buildSummary(data),
        if (data.rows.isEmpty)
          Padding(
            padding: const EdgeInsets.all(AppConstants.spaceL),
            child: AppCard(
              child: Text(l10n.trackDetailEmpty, style: theme.textTheme.bodyMedium),
            ),
          )
        else ...<Widget>[
          _buildTableHeader(),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppConstants.spaceL,
            ),
            child: AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: <Widget>[
                  for (var i = 0; i < data.rows.length; i++) ...<Widget>[
                    if (i > 0)
                      Divider(
                        height: 1,
                        thickness: 1,
                        color: scheme.outlineVariant.withValues(alpha: 0.4),
                      ),
                    _buildRow(data.rows[i]),
                  ],
                ],
              ),
            ),
          ),
        ],
        if (unmarked > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppConstants.spaceL,
              AppConstants.spaceM,
              AppConstants.spaceL,
              0,
            ),
            child: Text(
              l10n.trackUnmarkedNote(unmarked),
              style: theme.textTheme.bodySmall,
            ),
          ),
      ],
    );
  }

  Widget _buildSummary(_TrackDetail data) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final tokens = context.watch<ThemeController>().tokens;
    final ledger = data.ledger;
    final rate = ledger.attendanceRate;
    return Padding(
      padding: const EdgeInsets.all(AppConstants.spaceL),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Text(
                  rate == null ? '—' : '${(rate * 100).toStringAsFixed(1)}%',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: tokens.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: AppConstants.spaceS),
                Expanded(
                  child: Text(
                    l10n.statRate,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                AttendanceFormulaButton(),
              ],
            ),
            const SizedBox(height: AppConstants.spaceM),
            Row(
              children: <Widget>[
                Expanded(
                  child: _metric(
                    l10n.statExpected,
                    '${ledger.expectedSessions}',
                  ),
                ),
                Expanded(
                  child: _metric(
                    l10n.statAbnormalSessions,
                    '${ledger.tally.abnormal}',
                  ),
                ),
                Expanded(
                  child: _metric(l10n.statLeave, '${ledger.tally.leave}'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _metric(String label, String value) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(label, style: theme.textTheme.labelSmall),
      ],
    );
  }

  Widget _buildTableHeader() {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final style = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w700,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.spaceL,
        AppConstants.spaceM,
        AppConstants.spaceL,
        AppConstants.spaceS,
      ),
      child: Row(
        children: <Widget>[
          SizedBox(width: 64, child: Text(l10n.trackColDate, style: style)),
          Expanded(child: Text(l10n.trackColCourse, style: style)),
          Text(l10n.trackColStatus, style: style),
        ],
      ),
    );
  }

  Widget _buildRow(AttendanceLedgerRow row) {
    final theme = Theme.of(context);
    final tokens = context.watch<ThemeController>().tokens;
    final color = statusColorOf(tokens, row.status);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.spaceM,
        vertical: AppConstants.spaceM,
      ),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 64,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(row.shortDate, style: theme.textTheme.bodyMedium),
                Text(
                  row.weekdayLabel.isEmpty ? '' : '周${row.weekdayLabel}',
                  style: theme.textTheme.labelSmall,
                ),
              ],
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  row.courseName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
                if (row.timeRange.isNotEmpty)
                  Text(row.timeRange, style: theme.textTheme.labelSmall),
              ],
            ),
          ),
          const SizedBox(width: AppConstants.spaceS),
          _StatusPill(text: statusLabelOf(context, row.status), color: color),
        ],
      ),
    );
  }

  /// 导出当前这一页：这一名学生在区间内的**全部**记录（含出勤）。
  Future<void> _exportDetail(_TrackDetail data) async {
    final l10n = context.l10n;
    try {
      final path = await ExcelService().exportTrackWorkbook(
        fromDate: widget.fromDate,
        toDate: widget.toDate,
        courseName: data.courseName,
        studentName: widget.studentName,
        detailRows: <Map<String, Object?>>[
          for (final row in data.rows)
            <String, Object?>{
              'date': row.date,
              'weekday': row.weekdayLabel,
              'course_name': row.courseName,
              'time': row.timeRange,
              'status': statusLabelOf(context, row.status),
              'note': row.note ?? '',
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
        subject: l10n.trackDetailTitle,
        text: '${widget.studentName} ${l10n.trackDetailTitle}',
      );
    } catch (error, stack) {
      AppLogger.e('导出个人出勤明细失败', error: error, stack: stack);
      if (!mounted) {
        return;
      }
      showAppSnackBar(context, l10n.operationFailed('$error'));
    }
  }
}

/// 出勤情况的小胶囊（统计口径色板，和考勤页一致）。
class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.spaceS,
        vertical: 3,
      ),
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

class _TrackDetail {
  const _TrackDetail({
    required this.ledger,
    required this.rows,
    required this.courseName,
  });

  final StudentLedger ledger;
  final List<AttendanceLedgerRow> rows;
  final String? courseName;
}
