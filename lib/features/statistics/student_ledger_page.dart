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
import 'package:schedule_plan/data/models/attendance.dart';
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
import 'package:schedule_plan/l10n/generated/app_localizations.dart';

/// 学生出勤档案（`docs/SPEC.md` 3.8，评价台账 · 个人）。
///
/// 用户规格：*"拉出来的流水表，先显示异常情况、多少次，然后具体什么时间缺、
/// 列几行，早退列几行，迟到列几行"*。所以这一页是**汇总条 + 按状态分组**，
/// 不是一张从头到尾的大表。
///
/// 两个入口（学生名单行尾的「出勤」、班级排行点姓名）都推这一页。
class StudentLedgerPage extends StatefulWidget {
  const StudentLedgerPage({
    super.key,
    required this.studentId,
    required this.fromDate,
    required this.toDate,
    this.courseId,
    this.studentName,
    this.holidayService,
  });

  final int studentId;
  final String fromDate;
  final String toDate;
  final int? courseId;

  /// 只是骨架屏期间用来显示标题，真实姓名以库里为准。
  final String? studentName;

  /// 测试可注入（生产留空，自己 new 一个）。
  final HolidayService? holidayService;

  @override
  State<StudentLedgerPage> createState() => _StudentLedgerPageState();
}

class _StudentLedgerPageState extends State<StudentLedgerPage> {
  late final HolidayService _holidays = widget.holidayService ?? HolidayService();
  late Future<_StudentArchive> _future;
  bool _showAllLessons = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_StudentArchive> _load() async {
    final attendance = context.read<AttendanceRepository>();
    final lessonRepo = context.read<LessonRepository>();
    final studentRepo = context.read<StudentRepository>();
    final classRepo = context.read<ClassRepository>();

    final from = app_dates.DateUtils.tryParseDate(widget.fromDate) ??
        DateTime.now();
    final to = app_dates.DateUtils.tryParseDate(widget.toDate) ?? from;

    final students = await studentRepo.listAll();
    final student = students.firstWhere(
      (item) => item.id == widget.studentId,
      orElse: () => Student(
        id: widget.studentId,
        name: widget.studentName ?? '',
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

    return _StudentArchive(
      student: student,
      ledger: analytics.ledgers.isEmpty
          ? StudentLedger(
              student: student,
              className: '',
              tally: const LedgerTally(),
              expectedSessions: 0,
            )
          : analytics.ledgers.first,
      rows: rows,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${widget.studentName ?? ''} ${l10n.statLedgerTitle}'.trim(),
        ),
        actions: <Widget>[
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
      body: FutureBuilder<_StudentArchive>(
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

  Widget _buildBody(_StudentArchive data) {
    final l10n = context.l10n;
    final tokens = context.watch<ThemeController>().tokens;
    final groups = groupLedgerRows(
      data.rows,
      includePresent: _showAllLessons,
    );
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
            l10n.statRangeLabel(widget.fromDate, widget.toDate),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        _buildSummary(data, tokens),
        _buildShowAllSwitch(l10n),
        if (groups.isEmpty)
          Padding(
            padding: const EdgeInsets.all(AppConstants.spaceL),
            child: Text(l10n.statLedgerEmpty),
          )
        else
          for (final group in groups) ...<Widget>[
            _buildGroupHeader(group, tokens),
            for (final row in group.rows) _buildRow(row),
          ],
      ],
    );
  }

  Widget _buildSummary(_StudentArchive data, AppColorTokens tokens) {
    final l10n = context.l10n;
    final ledger = data.ledger;
    final rate = ledger.attendanceRate;
    final rateText = rate == null
        ? '—'
        : '${(rate * 100).toStringAsFixed(1)}%';
    return Padding(
      padding: const EdgeInsets.all(AppConstants.spaceL),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Text(
                  rateText,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: tokens.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: AppConstants.spaceS),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(l10n.statRate),
                ),
                const Spacer(),
                AttendanceFormulaButton(),
              ],
            ),
            const SizedBox(height: AppConstants.spaceM),
            Wrap(
              spacing: AppConstants.spaceL,
              runSpacing: AppConstants.spaceS,
              children: <Widget>[
                _metric(l10n.statExpected, ledger.expectedSessions),
                _metric(l10n.statAbsent, ledger.tally.absent),
                _metric(l10n.statLate, ledger.tally.late),
                _metric(l10n.statEarlyLeave, ledger.tally.earlyLeave),
                _metric(l10n.statLateAndEarly, ledger.tally.lateAndEarly),
                _metric(l10n.statLeave, ledger.tally.leave),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _metric(String label, int value) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('$value', style: theme.textTheme.titleMedium),
        Text(label, style: theme.textTheme.bodySmall),
      ],
    );
  }

  Widget _buildShowAllSwitch(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppConstants.spaceL),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: Text(l10n.statShowAllLessons)),
              Switch.adaptive(
                value: _showAllLessons,
                onChanged: (value) => setState(() => _showAllLessons = value),
              ),
            ],
          ),
          // 只有真实标记过的出勤记录才列得出来。没点名的课次是按全勤**推算**的，
          // 拿它当"那天他确实来了"的证据会被家长质疑，所以宁可少列。
          if (_showAllLessons)
            Padding(
              padding: const EdgeInsets.only(bottom: AppConstants.spaceS),
              child: Text(
                l10n.statUnmarkedCounted,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildGroupHeader(LedgerGroup group, AppColorTokens tokens) {
    final color = statusColorOf(tokens, group.status);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.spaceL,
        AppConstants.spaceL,
        AppConstants.spaceL,
        AppConstants.spaceS,
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: AppConstants.spaceS),
          Text(
            statusLabelOf(context, group.status),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(width: AppConstants.spaceS),
          Text(
            context.l10n.statSessionCount(group.count),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _buildRow(AttendanceLedgerRow row) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.spaceL,
        vertical: 3,
      ),
      child: AppCard(
        padding: const EdgeInsets.all(AppConstants.spaceM),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 50,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(row.shortDate, style: theme.textTheme.bodyMedium),
                  Text(
                    '周${row.weekdayLabel}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppConstants.spaceM),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(row.courseName, style: theme.textTheme.bodyMedium),
                  if (row.timeRange.isNotEmpty)
                    Text(row.timeRange, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            if ((row.note ?? '').isNotEmpty)
              Flexible(
                child: Text(
                  row.note!,
                  textAlign: TextAlign.right,
                  style: theme.textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _export(_StudentArchive data) async {
    final l10n = context.l10n;
    try {
      final path = await ExcelService().exportAttendanceWorkbook(
        summaryRows: const <Map<String, Object?>>[],
        abnormalRows: const <Map<String, Object?>>[],
        ranking: const <RiskStudent>[],
        fromDate: widget.fromDate,
        toDate: widget.toDate,
        studentRows: <Map<String, Object?>>[
          for (final row in data.rows)
            <String, Object?>{
              'date': row.date,
              'weekday': row.weekdayLabel,
              'time': row.timeRange,
              'course_name': row.courseName,
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
        subject: l10n.statLedgerTitle,
        text: l10n.statLedgerTitle,
      );
    } catch (error, stack) {
      AppLogger.e('导出个人出勤台账失败', error: error, stack: stack);
      if (!mounted) {
        return;
      }
      showAppSnackBar(context, l10n.operationFailed('$error'));
    }
  }
}

class _StudentArchive {
  const _StudentArchive({
    required this.student,
    required this.ledger,
    required this.rows,
  });

  final Student student;
  final StudentLedger ledger;
  final List<AttendanceLedgerRow> rows;
}
