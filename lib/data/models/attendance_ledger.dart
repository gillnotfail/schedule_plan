import 'package:flutter/foundation.dart';

import 'package:schedule_plan/core/utils/date_utils.dart' as app_dates;

import 'attendance.dart';

/// 出勤台账的一行 = 一条 `attendance_record` + 展示需要的快照字段。
///
/// 放在 data/models 而不是统计功能目录里：它是仓储的返回类型，
/// 档案页、排行页、Excel 导出三处共用（`docs/SPEC.md` 3.8）。
///
/// 所有展示字段都取自 `attendance_record` 自己的**快照列**
/// （`course_name` / `class_name` / `start_time` …），所以课表条目被删掉之后，
/// 历史台账照样能正确显示课程名与上课时间。
@immutable
class AttendanceLedgerRow {
  const AttendanceLedgerRow({
    required this.date,
    required this.studentId,
    required this.studentName,
    required this.className,
    required this.courseName,
    required this.status,
    this.studentNo,
    this.classId,
    this.courseId,
    this.periodIndex,
    this.startTime,
    this.endTime,
    this.note,
  });

  /// `"YYYY-MM-DD"`
  final String date;
  final int studentId;
  final String studentName;
  final String? studentNo;
  final int? classId;
  final String className;
  final int? courseId;
  final String courseName;

  /// 第几节（相对班级作息模板）。早期记录可能为空。
  final int? periodIndex;
  final String? startTime;
  final String? endTime;
  final AttendanceStatus status;
  final String? note;

  /// `10-26` 这种短日期，流水表一行放得下。
  String get shortDate => date.length > 5 ? date.substring(5) : date;

  /// 「周一」这种星期文案。日期解析失败时返回空串 ——
  /// 台账不能因为一行坏日期整页崩掉。
  String get weekdayLabel {
    final parsed = app_dates.DateUtils.tryParseDate(date);
    if (parsed == null) {
      return '';
    }
    return const <String>['一', '二', '三', '四', '五', '六', '日'][parsed.weekday - 1];
  }

  /// `08:00-08:45`；两端都缺时返回空串。
  String get timeRange {
    final start = startTime ?? '';
    final end = endTime ?? '';
    if (start.isEmpty && end.isEmpty) {
      return '';
    }
    if (end.isEmpty) {
      return start;
    }
    return '$start-$end';
  }
}
