import '../../data/models/attendance.dart';
import '../../data/models/attendance_ledger.dart';
import '../../data/models/lesson.dart';
import '../../data/models/student.dart';
import 'attendance_ledger.dart';

/// 统计页的一次性计算：把「台账行 + 课表 + 日历 + 长期状态」算成
/// 应上课次、缺勤次数和出勤率。
///
/// 为什么集中在 Dart 里算，而不是写成几条聚合 SQL：出勤率的分子来自
/// `attendance_record`，分母却来自**课表推算**（未点名的课次按全勤计），
/// 两者不在同一张表里，SQL 里凑不出来。放在纯函数里还有个好处 ——
/// 不用开数据库就能单测（`test/unit/attendance_analytics_test.dart`）。
///
/// 口径一律以 `docs/SPEC.md` 3.10 为准：
/// 出勤率 = 1 − 缺勤课次 ÷ 应上课次；迟到、早退、请假都不进分子。
class AttendanceAnalytics {
  AttendanceAnalytics._({
    required this.ledgers,
    required this.expectedByDateCourse,
    required this.expectedByCourse,
    required this.absentByDateCourse,
    required this.absentByCourse,
    required this.expectedTotal,
    required this.absentTotal,
  });

  /// 每名学生一条（**包括一次假都没请过的**）：排行表要列出全班，
  /// 只拿台账反推会漏掉出勤率 100% 的那些人。
  final List<StudentLedger> ledgers;

  /// `"2026-10-26|3"` → 当天该课应上的学生人次。折线图的分母。
  final Map<String, int> expectedByDateCourse;

  /// 课程 id → 应上人次。柱状图的分母。
  final Map<int, int> expectedByCourse;

  /// `"2026-10-26|3"` → 当天该课的缺勤人次。折线图的分子。
  final Map<String, int> absentByDateCourse;

  /// 课程 id → 缺勤人次。
  final Map<int, int> absentByCourse;

  final int expectedTotal;
  final int absentTotal;

  /// 整体出勤率；没有应上课次时返回 null（界面显示「—」，不显示 100%）。
  double? get overallRate => rateOf(absentTotal, expectedTotal);

  /// 某门课的出勤率。
  double? courseRate(int courseId) =>
      rateOf(absentByCourse[courseId] ?? 0, expectedByCourse[courseId] ?? 0);

  /// 某天某门课的出勤率。
  double? dateCourseRate(String date, int courseId) {
    final key = '$date|$courseId';
    return rateOf(absentByDateCourse[key] ?? 0, expectedByDateCourse[key] ?? 0);
  }

  /// 某天所有课程合起来的出勤率（折线图按日聚合时用）。
  double? dateRate(String date) {
    var absent = 0;
    var expected = 0;
    for (final entry in expectedByDateCourse.entries) {
      final separator = entry.key.indexOf('|');
      if (separator < 0 || entry.key.substring(0, separator) != date) {
        continue;
      }
      expected += entry.value;
      absent += absentByDateCourse[entry.key] ?? 0;
    }
    return rateOf(absent, expected);
  }

  /// 某门课在区间内的应上人次。
  int expectedOfCourse(int courseId) => expectedByCourse[courseId] ?? 0;

  /// 按班级分组的排行数据（一页一个班一小节）。
  List<MapEntry<String, List<StudentLedger>>> get ledgersByClass =>
      groupLedgersByClass(ledgers);

  /// 统一在这里截断，避免负数和除零散落在各处。
  static double? rateOf(int absent, int expected) {
    if (expected <= 0) {
      return null;
    }
    final attended = expected - absent;
    if (attended <= 0) {
      return 0;
    }
    return attended / expected;
  }

  /// 构造：先把"该上几节"按天摊开，再用台账填分子。
  factory AttendanceAnalytics.build({
    required List<WeeklySlot> slots,
    required List<Student> students,
    required List<AttendanceLedgerRow> rows,
    required List<CourseStudentStatus> longTermStatuses,
    required DateTime from,
    required DateTime to,
    required int Function(DateTime date) labelWeekday,
    required bool Function(DateTime date) isRestDay,
    Map<int, String> classNames = const <int, String>{},
    int? courseId,
    int? studentId,
  }) {
    final studentsById = <int, Student>{
      for (final student in students)
        if (student.id != null) student.id!: student,
    };
    final studentsByClass = <int, List<Student>>{};
    for (final student in studentsById.values) {
      studentsByClass.putIfAbsent(student.classId, () => <Student>[]).add(student);
    }

    // 休学按「课程 + 日期」生效：一门课休学不代表别的课也不用上
    final suspensionByStudent = <int, List<CourseStudentStatus>>{};
    for (final status in longTermStatuses) {
      if (status.status != AttendanceStatus.suspended) {
        continue;
      }
      suspensionByStudent
          .putIfAbsent(status.studentId, () => <CourseStudentStatus>[])
          .add(status);
    }

    bool isSuspended(int studentId, int courseId, String date) {
      final list = suspensionByStudent[studentId];
      if (list == null) {
        return false;
      }
      for (final status in list) {
        if (status.courseId == courseId && status.coversDate(date)) {
          return true;
        }
      }
      return false;
    }

    final slotsByWeekday = <int, List<WeeklySlot>>{};
    for (final slot in slots) {
      if (courseId != null && slot.courseId != courseId) {
        continue;
      }
      slotsByWeekday.putIfAbsent(slot.weekday, () => <WeeklySlot>[]).add(slot);
    }

    final expectedByDateCourse = <String, int>{};
    final expectedByCourse = <int, int>{};
    final expectedByStudent = <int, int>{};
    var expectedTotal = 0;

    final start = DateTime(from.year, from.month, from.day);
    final end = DateTime(to.year, to.month, to.day);
    for (var day = start;
        !day.isAfter(end);
        day = DateTime(day.year, day.month, day.day + 1)) {
      if (isRestDay(day)) {
        continue;
      }
      final todaySlots = slotsByWeekday[labelWeekday(day)];
      if (todaySlots == null || todaySlots.isEmpty) {
        continue;
      }
      final date = _formatDate(day);
      for (final slot in todaySlots) {
        for (final classId in slot.classIds) {
          final roster = studentsByClass[classId];
          if (roster == null) {
            continue;
          }
          for (final student in roster) {
            final id = student.id;
            if (id == null || (studentId != null && id != studentId)) {
              continue;
            }
            if (isSuspended(id, slot.courseId, date)) {
              continue;
            }
            final key = '$date|${slot.courseId}';
            expectedByDateCourse[key] = (expectedByDateCourse[key] ?? 0) + 1;
            expectedByCourse[slot.courseId] =
                (expectedByCourse[slot.courseId] ?? 0) + 1;
            expectedByStudent[id] = (expectedByStudent[id] ?? 0) + 1;
            expectedTotal++;
          }
        }
      }
    }

    final absentByDateCourse = <String, int>{};
    final absentByCourse = <int, int>{};
    final rowsByStudent = <int, List<AttendanceLedgerRow>>{};
    var absentTotal = 0;

    for (final row in rows) {
      rowsByStudent
          .putIfAbsent(row.studentId, () => <AttendanceLedgerRow>[])
          .add(row);
      if (row.status != AttendanceStatus.absent) {
        continue;
      }
      final course = row.courseId;
      if (course != null) {
        final key = '${row.date}|$course';
        absentByDateCourse[key] = (absentByDateCourse[key] ?? 0) + 1;
        absentByCourse[course] = (absentByCourse[course] ?? 0) + 1;
      }
      absentTotal++;
    }

    final ledgers = <StudentLedger>[];
    for (final student in studentsById.values) {
      final id = student.id!;
      final studentRows = rowsByStudent[id] ?? const <AttendanceLedgerRow>[];
      ledgers.add(
        StudentLedger(
          student: student,
          className: classNames[student.classId] ??
              _classNameFromRows(studentRows),
          tally: LedgerTally.of(studentRows),
          expectedSessions: expectedByStudent[id] ?? 0,
        ),
      );
    }
    ledgers.sort((a, b) => a.student.name.compareTo(b.student.name));

    return AttendanceAnalytics._(
      ledgers: ledgers,
      expectedByDateCourse: expectedByDateCourse,
      expectedByCourse: expectedByCourse,
      absentByDateCourse: absentByDateCourse,
      absentByCourse: absentByCourse,
      expectedTotal: expectedTotal,
      absentTotal: absentTotal,
    );
  }

  /// 台账里保存的是**当时的**班级名快照：学生后来转班了，这里仍然能看到他
  /// 当时在哪个班。查不到就留空，界面按"未分班"处理，不硬编一个班号。
  static String _classNameFromRows(List<AttendanceLedgerRow> rows) {
    for (final row in rows) {
      if (row.className.isNotEmpty) {
        return row.className;
      }
    }
    return '';
  }

  static String _formatDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }
}
