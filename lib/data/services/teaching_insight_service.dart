import 'package:flutter/foundation.dart';

import 'package:schedule_plan/core/constants/app_constants.dart';
import 'package:schedule_plan/core/utils/date_utils.dart' as app_dates;
import 'package:schedule_plan/core/utils/time_utils.dart';
import 'package:schedule_plan/data/models/attendance.dart';
import 'package:schedule_plan/data/models/china_holiday.dart';
import 'package:schedule_plan/data/models/lesson.dart';
import 'package:schedule_plan/data/models/schedule_event.dart';
import 'package:schedule_plan/data/repositories/attendance_repository.dart';
import 'package:schedule_plan/data/repositories/lesson_repository.dart';
import 'package:schedule_plan/data/repositories/schedule_event_repository.dart';
import 'package:schedule_plan/data/services/holiday_service.dart';

/// 某个班级在某段时间里的出勤率。
///
/// 用户规格（第 13 轮）："除了上了多少节课、本周专注多少次、出勤率、
/// 出勤率最低、最高的班级、额外事务……这样内容更充实。"
@immutable
class ClassAttendanceRate {
  const ClassAttendanceRate({
    required this.className,
    required this.ratePercent,
    required this.total,
  });

  final String className;

  /// 0~100
  final int ratePercent;

  /// 应点名人次（= 记录条数），为 0 表示这个班本周根本没点过名。
  final int total;

  bool get hasData => total > 0;
}

/// 工具箱页「教学成果」的数据快照。
///
/// 只做聚合计算，不含任何 UI 逻辑。**课时结算走节假日/调休**
/// （[HolidayWeek]）：放假那天不算课时，调休上班日按学校通知的星期几算。
class TeachingInsight {
  const TeachingInsight({
    required this.doneLessons,
    required this.totalLessons,
    required this.attendanceRatePercent,
    required this.benefitedStudents,
    required this.attention,
    required this.weekStart,
    required this.weekEnd,
    required this.todayLessons,
    required this.todayEvents,
    required this.courseCount,
    required this.focusSessions,
    required this.focusMinutes,
    required this.weekEvents,
    required this.classList,
    required this.lessonsByCourse,
    required this.lessonsByWeekday,
    required this.holidayWeek,
  });

  /// 本周已上（按当前时刻判定）
  final int doneLessons;

  /// 本周总课时（**已按调休/放假结算**：放假的那天不算，调休上班日照算）
  final int totalLessons;

  /// 本周出勤率（0~100，无数据时为 -1）
  final int attendanceRatePercent;

  /// 受益学生数：本周被点过名的去重总人数（一个学生在几节课都只算 1 个）。
  final int benefitedStudents;

  /// 需要关注的学生（本周有缺勤/迟到/早退，按风险分降序）
  final List<RiskStudent> attention;

  final DateTime weekStart;
  final DateTime weekEnd;

  /// 今天要上的课节数（放假 / 周末为 0）
  final int todayLessons;

  /// 今天的额外事务（日程）
  final List<ScheduleEvent> todayEvents;

  /// 本周涉及几门课（去重）
  final int courseCount;

  /// 本周完成的专注次数
  final int focusSessions;

  /// 本周累计专注分钟
  final int focusMinutes;

  /// 本周的额外事务（日程 + 教研活动等，按开始时间升序）
  final List<ScheduleEvent> weekEvents;

  /// 各班本周出勤率（按班级名升序）
  final List<ClassAttendanceRate> classList;

  /// 本周课时按课程分布（课程名 → 节数，按节数降序）
  final List<MapEntry<String, int>> lessonsByCourse;

  /// 本周课时的"每天分布"：key = 星期几(1~7)，value = 那天的节数。
  /// 已经按调休映射过——调休上班日会落在它实际执行的 labelWeekday 上。
  final Map<int, int> lessonsByWeekday;

  /// 这一周的节假日执行方案（含放假与调休上班日）。
  final HolidayWeek holidayWeek;

  int get remainingLessons =>
      totalLessons - doneLessons < 0 ? 0 : totalLessons - doneLessons;

  bool get hasCourseData => totalLessons > 0;

  bool get hasAttendanceData => attendanceRatePercent >= 0;

  /// 有足够多的班级才能比"最高/最低"（只有一个班时最高就是最低，没意义）。
  bool get hasClassComparison =>
      classList.where((item) => item.hasData).length >= 2;

  ClassAttendanceRate? get bestClass => _extreme(highest: true);

  ClassAttendanceRate? get worstClass => _extreme(highest: false);

  /// 本周被放假冲掉的日子（用来在 UI 上说明"为什么这周少了 4 节"）。
  List<HolidayDay> get holidayDays => holidayWeek.days
      .where((day) => day.kind == CalendarDayKind.holiday)
      .toList(growable: false);

  HolidayDay? get makeupDay => holidayWeek.makeupDay;

  ClassAttendanceRate? _extreme({required bool highest}) {
    ClassAttendanceRate? result;
    for (final item in classList) {
      if (!item.hasData) {
        continue;
      }
      if (result == null) {
        result = item;
        continue;
      }
      // 平局保留先出现的那个（classList 已按班级名升序），
      // 保证同一份数据每次渲染给出同一个班，不会闪。
      final better = highest
          ? item.ratePercent > result.ratePercent
          : item.ratePercent < result.ratePercent;
      if (better) {
        result = item;
      }
    }
    return result;
  }
}

/// 教师教学成果聚合服务。
class TeachingInsightService {
  TeachingInsightService({
    LessonRepository? lessons,
    AttendanceRepository? attendance,
    ScheduleEventRepository? events,
    HolidayService? holidays,
  })  : _lessons = lessons ?? LessonRepository(),
        _attendance = attendance ?? AttendanceRepository(),
        _events = events ?? ScheduleEventRepository(),
        _holidays = holidays ?? HolidayService();

  final LessonRepository _lessons;
  final AttendanceRepository _attendance;
  final ScheduleEventRepository _events;
  final HolidayService _holidays;

  /// 统计口径（第 13 轮起**一律按日历结算**，不再按 weekday 数）：
  ///
  /// 1. 先由 [HolidayService] 拿到这一周七天的"执行方案"；
  /// 2. 放假日（法定假日 + 普通周末）不计课时；
  /// 3. 调休上班日按老师确认的 `labelWeekday` 取那一天的课表 ——
  ///    所以"周日上周三的课"会把周三的课算进这一周；
  /// 4. 「已上」= 日期在今天之前的那天全算，今天的课按下课时间算。
  Future<TeachingInsight> load({DateTime? now}) async {
    final current = now ?? DateTime.now();
    final weekStart = app_dates.DateUtils.startOfWeek(current);
    final weekEnd = weekStart.add(const Duration(days: 6));
    final fromDate = app_dates.DateUtils.formatDate(weekStart);
    final toDate = app_dates.DateUtils.formatDate(weekEnd);

    final lessons = await _lessons.queryWithTime(
      teacherId: AppConstants.currentTeacherId,
    );
    final holidayWeek = await _holidays.weekOf(weekStart);

    final byWeekday = <int, List<LessonWithTime>>{};
    for (final item in lessons) {
      byWeekday.putIfAbsent(item.lesson.weekday, () => <LessonWithTime>[]).add(item);
    }

    final today = app_dates.DateUtils.dateOnly(current);
    final nowMinutes = current.hour * 60 + current.minute;
    var total = 0;
    var done = 0;
    var todayLessons = 0;
    final lessonsByWeekday = <int, int>{};
    for (final day in holidayWeek.days) {
      if (!day.hasClasses) {
        continue;
      }
      final list = byWeekday[day.labelWeekday] ?? const <LessonWithTime>[];
      total += list.length;
      lessonsByWeekday[day.labelWeekday] =
          (lessonsByWeekday[day.labelWeekday] ?? 0) + list.length;
      for (final item in list) {
        if (day.date.isBefore(today)) {
          done++;
        } else if (app_dates.DateUtils.isSameDay(day.date, today) &&
            TimeUtils.parseMinutes(item.endTime) <= nowMinutes) {
          done++;
        }
      }
      if (app_dates.DateUtils.isSameDay(day.date, today)) {
        todayLessons = list.length;
      }
    }

    final risk = await _attendance.riskRanking(
      fromDate: fromDate,
      toDate: toDate,
      weightAbsent: AppConstants.riskWeightAbsent,
      weightLate: AppConstants.riskWeightLate,
      weightEarlyLeave: AppConstants.riskWeightEarlyLeave,
    );

    final series = await _attendance.attendanceRateSeries(
      fromDate: fromDate,
      toDate: toDate,
    );
    var present = 0;
    var marked = 0;
    for (final row in series) {
      present += (row['present_count'] as int?) ?? 0;
      marked += (row['total_count'] as int?) ?? 0;
    }

    final benefited = await _attendance.distinctStudentCount(
      fromDate: fromDate,
      toDate: toDate,
    );

    final classRows = await _attendance.attendanceRateByClass(
      fromDate: fromDate,
      toDate: toDate,
    );
    final classList = <ClassAttendanceRate>[];
    for (final row in classRows) {
      final rowTotal = (row['total_count'] as int?) ?? 0;
      final rowPresent = (row['present_count'] as int?) ?? 0;
      final name = (row['class_name'] as String?) ?? '';
      if (name.isEmpty) {
        continue;
      }
      classList.add(
        ClassAttendanceRate(
          className: name,
          total: rowTotal,
          ratePercent: rowTotal == 0 ? 0 : ((rowPresent * 100) / rowTotal).round(),
        ),
      );
    }

    // 本周额外事务：只看"这一周会发生"的日程（occursOnWeek 是唯一的重复周期判定）
    final allEvents = await _events.listEvents();
    final weekEvents = allEvents
        .where((event) => event.occursOnWeek(weekStart))
        .toList(growable: false)
      ..sort((a, b) => a.startAt.compareTo(b.startAt));
    final todayEvents = weekEvents
        .where((event) => app_dates.DateUtils.isSameDay(
              DateTime.fromMillisecondsSinceEpoch(event.startAt),
              today,
            ))
        .toList(growable: false);

    final focus = await _events.focusSessionsBetween(
      fromMs: weekStart.millisecondsSinceEpoch,
      toMs: weekEnd.add(const Duration(days: 1)).millisecondsSinceEpoch - 1,
    );
    // 只算"跑完的"番茄钟：中途放弃的不计入专注次数与分钟数，
    // 否则"累计专注 2 分钟"这种数字会显得莫名其妙。
    final completedFocus =
        focus.where((item) => item.completed).toList(growable: false);

    final courseCount =
        lessons.map((item) => item.lesson.courseId).toSet().length;

    final courseCounter = <String, int>{};
    for (final item in lessons) {
      courseCounter[item.courseName] = (courseCounter[item.courseName] ?? 0) + 1;
    }
    final lessonsByCourse = courseCounter.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        return byCount != 0 ? byCount : a.key.compareTo(b.key);
      });

    return TeachingInsight(
      doneLessons: done,
      totalLessons: total,
      attendanceRatePercent: marked == 0 ? -1 : ((present * 100) / marked).round(),
      benefitedStudents: benefited,
      attention: risk.take(AppConstants.insightAttentionLimit).toList(),
      weekStart: weekStart,
      weekEnd: weekEnd,
      todayLessons: todayLessons,
      todayEvents: todayEvents,
      courseCount: courseCount,
      focusSessions: completedFocus.length,
      focusMinutes:
          completedFocus.fold<int>(0, (sum, item) => sum + item.durationMinutes),
      weekEvents: weekEvents,
      classList: classList,
      lessonsByCourse: lessonsByCourse,
      lessonsByWeekday: lessonsByWeekday,
      holidayWeek: holidayWeek,
    );
  }
}
