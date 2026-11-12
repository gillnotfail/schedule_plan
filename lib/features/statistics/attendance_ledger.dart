import 'package:flutter/foundation.dart';

import '../../core/utils/date_utils.dart' as app_dates;
import '../../data/models/attendance.dart';
import '../../data/models/attendance_ledger.dart';
import '../../data/models/lesson.dart';
import '../../data/models/student.dart';

/// 区间内的**互斥**状态计数。
///
/// 口径红线（`docs/SPEC.md` 3.11）：评价台账里「迟到+早退」**单独一个数**，
/// 不再往迟到、早退两列各加一次 —— 只有这样才能「五个数加起来 = 异常课次」，
/// 老师一眼能核。干预台账（`riskRanking`）那边仍然是各计一次，两者的差别是刻意的。
@immutable
class LedgerTally {
  const LedgerTally({
    this.present = 0,
    this.absent = 0,
    this.late = 0,
    this.earlyLeave = 0,
    this.lateAndEarly = 0,
    this.leave = 0,
  });

  factory LedgerTally.of(Iterable<AttendanceLedgerRow> rows) {
    var present = 0;
    var absent = 0;
    var late = 0;
    var earlyLeave = 0;
    var lateAndEarly = 0;
    var leave = 0;
    for (final row in rows) {
      switch (row.status) {
        case AttendanceStatus.present:
          present++;
        case AttendanceStatus.absent:
          absent++;
        case AttendanceStatus.late:
          late++;
        case AttendanceStatus.earlyLeave:
          earlyLeave++;
        case AttendanceStatus.lateAndEarly:
          lateAndEarly++;
        case AttendanceStatus.leave:
          leave++;
        // 长期状态不落 `attendance_record`，真出现了也不该进台账
        case AttendanceStatus.suspended:
        case AttendanceStatus.exempt:
        case AttendanceStatus.unmarked:
          break;
      }
    }
    return LedgerTally(
      present: present,
      absent: absent,
      late: late,
      earlyLeave: earlyLeave,
      lateAndEarly: lateAndEarly,
      leave: leave,
    );
  }

  final int present;
  final int absent;
  final int late;
  final int earlyLeave;
  final int lateAndEarly;
  final int leave;

  /// 区间内的异常课次 = 五个互斥数之和。
  int get abnormal => absent + late + earlyLeave + lateAndEarly + leave;

  /// 真实记录过的课次（出勤 + 异常）。
  ///
  /// 「应上 − 真实记录」才是**没点名的**课次 —— 用 [unmarkedSessions] 取，
  /// 别在界面上自己减（课表改过时会出现负数，要统一截断）。
  int get recordedSessions => present + abnormal;

  /// 迟到类课次（含「迟到+早退」），只给文案用，不参与互斥加总。
  int get anyLate => late + lateAndEarly;

  /// 早退类课次（含「迟到+早退」）。
  int get anyEarlyLeave => earlyLeave + lateAndEarly;

  bool get isEmpty => abnormal == 0 && present == 0;
}

/// 一名学生在区间内的评价台账。
@immutable
class StudentLedger {
  const StudentLedger({
    required this.student,
    required this.className,
    required this.tally,
    required this.expectedSessions,
  });

  final Student student;
  final String className;
  final LedgerTally tally;

  /// 应上课次：区间内按课表该上几节（未点名的课次按全勤计，见 `docs/SPEC.md` 3.10）。
  final int expectedSessions;

  /// 出勤率 = 1 − 缺勤课次 ÷ 应上课次。
  ///
  /// **迟到、早退、请假都不进分子**（用户规格）：请假是有依据的，不当作逃课。
  /// 应上课次为 0（区间内没排课，或课表还没配）时返回 null —— 那时候
  /// 显示 100% 是骗人，界面上要显示成「—」。
  double? get attendanceRate {
    if (expectedSessions <= 0) {
      return null;
    }
    final attended = expectedSessions - tally.absent;
    if (attended <= 0) {
      return 0;
    }
    return attended / expectedSessions;
  }

  /// 实到课次（= 应上 − 缺勤，负数截断为 0）。
  int get attendedSessions {
    final attended = expectedSessions - tally.absent;
    return attended < 0 ? 0 : attended;
  }
}

/// 档案页流水表的一组（按状态分组，组标题带次数）。
@immutable
class LedgerGroup {
  const LedgerGroup({required this.status, required this.rows});

  final AttendanceStatus status;
  final List<AttendanceLedgerRow> rows;

  int get count => rows.length;
}

/// 档案页的分组顺序：缺勤 → 迟到 → 早退 → 迟到+早退 → 请假 →（出勤）。
///
/// 顺序即「严重程度」，老师在意的先看到。`includePresent` 打开时
/// （「显示全部课次」）才补最后一组，否则出勤记录不进表。
const List<AttendanceStatus> archiveStatusOrder = <AttendanceStatus>[
  AttendanceStatus.absent,
  AttendanceStatus.late,
  AttendanceStatus.earlyLeave,
  AttendanceStatus.lateAndEarly,
  AttendanceStatus.leave,
  AttendanceStatus.present,
];

/// 把台账行按状态分组；空组不返回（组标题上不要出现「迟到 · 0 次」）。
///
/// 组内按日期倒序（最近的在最上面），同一天再按上课时间正序 —— 一天里连堂两节，
/// 顺序要跟课表一致，否则老师对不上。
List<LedgerGroup> groupLedgerRows(
  Iterable<AttendanceLedgerRow> rows, {
  bool includePresent = false,
}) {
  final buckets = <AttendanceStatus, List<AttendanceLedgerRow>>{};
  for (final row in rows) {
    if (!includePresent && row.status == AttendanceStatus.present) {
      continue;
    }
    if (!archiveStatusOrder.contains(row.status)) {
      continue;
    }
    buckets.putIfAbsent(row.status, () => <AttendanceLedgerRow>[]).add(row);
  }
  for (final bucket in buckets.values) {
    bucket.sort((a, b) {
      final byDate = b.date.compareTo(a.date);
      if (byDate != 0) {
        return byDate;
      }
      return (a.startTime ?? '').compareTo(b.startTime ?? '');
    });
  }
  return <LedgerGroup>[
    for (final status in archiveStatusOrder)
      if ((buckets[status] ?? const <AttendanceLedgerRow>[]).isNotEmpty)
        LedgerGroup(status: status, rows: buckets[status]!),
  ];
}

/// 按班级把学生台账分组（排行页一个班一小节）。
///
/// 班内按出勤率升序 —— 最该谈的排最上面；出勤率相同（含"没有应上课次"的 null）
/// 时按姓名排，保证每次打开顺序一致。
List<MapEntry<String, List<StudentLedger>>> groupLedgersByClass(
  List<StudentLedger> ledgers,
) {
  final buckets = <String, List<StudentLedger>>{};
  for (final ledger in ledgers) {
    buckets.putIfAbsent(ledger.className, () => <StudentLedger>[]).add(ledger);
  }
  final keys = buckets.keys.toList()..sort();
  for (final key in keys) {
    buckets[key]!.sort((a, b) {
      final rateA = a.attendanceRate;
      final rateB = b.attendanceRate;
      if (rateA == null && rateB == null) {
        return a.student.name.compareTo(b.student.name);
      }
      if (rateA == null) {
        return 1;
      }
      if (rateB == null) {
        return -1;
      }
      final byRate = rateA.compareTo(rateB);
      if (byRate != 0) {
        return byRate;
      }
      return a.student.name.compareTo(b.student.name);
    });
  }
  return <MapEntry<String, List<StudentLedger>>>[
    for (final key in keys)
      MapEntry<String, List<StudentLedger>>(key, buckets[key]!),
  ];
}

/// 学生追踪详情页的行序：**日期倒序**（最近的在最上面），同一天按上课时间正序。
///
/// 和 [groupLedgerRows] 的组内排序同一套规则，但这里不分状态组 ——
/// 详情页要的是"一条时间线"，出勤和异常混在同一列里往下读。
List<AttendanceLedgerRow> sortLedgerRowsByDate(
  Iterable<AttendanceLedgerRow> rows,
) {
  final sorted = List<AttendanceLedgerRow>.of(rows);
  sorted.sort((a, b) {
    final byDate = b.date.compareTo(a.date);
    if (byDate != 0) {
      return byDate;
    }
    return (a.startTime ?? '').compareTo(b.startTime ?? '');
  });
  return sorted;
}

/// 学生追踪页（工具箱第 3 页）的排序：**异常次数多的先看到**。
///
/// 这一页是"该找谁谈"的入口，不是给分表 —— 所以异常次数优先于出勤率。
/// 异常次数相同的，出勤率低的排前面；再相同按姓名，保证每次打开顺序稳定。
/// 全勤的学生不会消失，只是沉在最后（老师仍然要能点进去看记录）。
List<StudentLedger> sortLedgersForTrack(List<StudentLedger> ledgers) {
  final sorted = List<StudentLedger>.of(ledgers);
  sorted.sort((a, b) {
    final byAbnormal = b.tally.abnormal.compareTo(a.tally.abnormal);
    if (byAbnormal != 0) {
      return byAbnormal;
    }
    final rateA = a.attendanceRate;
    final rateB = b.attendanceRate;
    if (rateA != null && rateB != null && rateA != rateB) {
      return rateA.compareTo(rateB);
    }
    if (rateA == null && rateB != null) {
      return 1;
    }
    if (rateA != null && rateB == null) {
      return -1;
    }
    return a.student.name.compareTo(b.student.name);
  });
  return sorted;
}

/// 没点名的课次 = 应上 − 真实记录条数（不小于 0）。
///
/// 课表后来改过时「应上」可能比实际记录还少，这时截断到 0，
/// 界面上不要出现「−3 节没点名」这种数字。
int unmarkedSessions(StudentLedger ledger) {
  final rest = ledger.expectedSessions - ledger.tally.recordedSessions;
  return rest < 0 ? 0 : rest;
}

/// 一个班整体的出勤率 = 1 − Σ缺勤 ÷ Σ应上。
///
/// 不是"各人出勤率的平均"：那样一个只上过 2 节课的学生和上了 36 节的学生等权，
/// 会把班级数字带偏。
double? classAttendanceRate(List<StudentLedger> ledgers) {
  var absent = 0;
  var expected = 0;
  for (final ledger in ledgers) {
    absent += ledger.tally.absent;
    expected += ledger.expectedSessions;
  }
  if (expected <= 0) {
    return null;
  }
  final attended = expected - absent;
  if (attended <= 0) {
    return 0;
  }
  return attended / expected;
}

/// 本学期区间（上学期 9/1 ~ 次年 1/31；下学期 2/1 ~ 7/31）。
///
/// 八月算暑假，按"上学期准备期"处理 —— 老师八月打开统计，想看的多半是
/// 即将开始的那个学期，而不是已经结束的那个。
///
/// 统计页与「学生名单 → 出勤」两个入口共用这一份，
/// 不允许各写一遍（否则同一份数据在两处显示不同区间）。
({DateTime start, DateTime end}) schoolTermRange(DateTime now) {
  if (now.month >= 8) {
    return (start: DateTime(now.year, 9, 1), end: DateTime(now.year + 1, 1, 31));
  }
  if (now.month <= 1) {
    return (start: DateTime(now.year - 1, 9, 1), end: DateTime(now.year, 1, 31));
  }
  return (start: DateTime(now.year, 2, 1), end: DateTime(now.year, 7, 31));
}

/// 区间内「该上几节课」的推算（`docs/SPEC.md` 3.10）。
///
/// 三条规则，缺一条数字就错：
/// 1. **放假日不算**：法定假日、寒暑假都不上课 —— 判据是 `isRestDay`，
///    由调用方按 `CalendarDayKind` 给（**不要**自己判 `weekday == 6 || 7`，
///    调休上班的周六是要上课的）；
/// 2. **按 labelWeekday 取课表**：调休那天上周几的课由老师确认过，走
///    `HolidayService.labelWeekdayOf`，裸用 `date.weekday` 会把调休日的课算丢；
/// 3. **休学不计入**：该课当时处于休学状态就跳过这一节，否则休学的孩子
///    出勤率会被算成 0，反而比常缺课的还难看。
///
/// 传 `classId` 时只算这个班该上的课（合班课里也认）；不传则算全部。
int countScheduledSessions({
  required List<WeeklySlot> slots,
  required DateTime from,
  required DateTime to,
  required int Function(DateTime date) labelWeekday,
  required bool Function(DateTime date) isRestDay,
  int? classId,
  int? courseId,
  bool Function(int courseId, String date)? isSuspended,
}) {
  if (slots.isEmpty) {
    return 0;
  }
  // 先按"标签星期"建索引，避免 126 天 × 20 节 = 2500 次全表比对
  final byWeekday = <int, List<WeeklySlot>>{};
  for (final slot in slots) {
    if (classId != null && !slot.classIds.contains(classId)) {
      continue;
    }
    if (courseId != null && slot.courseId != courseId) {
      continue;
    }
    byWeekday.putIfAbsent(slot.weekday, () => <WeeklySlot>[]).add(slot);
  }
  if (byWeekday.isEmpty) {
    return 0;
  }

  var total = 0;
  final start = app_dates.DateUtils.dateOnly(from);
  final end = app_dates.DateUtils.dateOnly(to);
  for (var day = start;
      !day.isAfter(end);
      day = DateTime(day.year, day.month, day.day + 1)) {
    if (isRestDay(day)) {
      continue;
    }
    final slotsToday = byWeekday[labelWeekday(day)];
    if (slotsToday == null) {
      continue;
    }
    final date = app_dates.DateUtils.formatDate(day);
    for (final slot in slotsToday) {
      if (isSuspended != null && isSuspended(slot.courseId, date)) {
        continue;
      }
      total++;
    }
  }
  return total;
}
