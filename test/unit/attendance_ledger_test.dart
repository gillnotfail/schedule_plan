import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:schedule_plan/core/constants/app_constants.dart';
import 'package:schedule_plan/data/db/schema.dart';
import 'package:schedule_plan/data/models/attendance.dart';
import 'package:schedule_plan/data/models/attendance_ledger.dart';
import 'package:schedule_plan/data/models/class_course.dart';
import 'package:schedule_plan/data/models/lesson.dart';
import 'package:schedule_plan/data/models/student.dart';
import 'package:schedule_plan/data/repositories/attendance_repository.dart';
import 'package:schedule_plan/data/repositories/class_repository.dart';
import 'package:schedule_plan/data/repositories/course_repository.dart';
import 'package:schedule_plan/data/repositories/lesson_repository.dart';
import 'package:schedule_plan/data/repositories/student_repository.dart';
import 'package:schedule_plan/data/repositories/template_repository.dart';
import 'package:schedule_plan/features/statistics/attendance_ledger.dart';

/// 评价台账（SPEC 3.8 ~ 3.10）的口径测试。
///
/// 这组用例守的是**数字对不对**，不是界面好不好看：
/// - 出勤率必须是 `1 − 缺勤 ÷ 应上`，请假/迟到/早退都不许进分子；
/// - 应上课次必须按"放假日不算 / 调休按 labelWeekday / 休学跳过"三条规则算；
/// - 流水表分组必须互斥（组合态单独一组，不能重复计两次）。

AttendanceLedgerRow _row({
  String date = '2026-03-02',
  int studentId = 1,
  String name = '张三',
  String className = '高一(1)班',
  int? classId = 1,
  int? courseId = 1,
  String course = '数学',
  AttendanceStatus status = AttendanceStatus.absent,
  String? startTime = '08:00',
  String? endTime = '08:40',
  String? note,
}) {
  return AttendanceLedgerRow(
    date: date,
    studentId: studentId,
    studentName: name,
    classId: classId,
    className: className,
    courseId: courseId,
    courseName: course,
    startTime: startTime,
    endTime: endTime,
    status: status,
    note: note,
  );
}

void main() {
  group('互斥计数', () {
    test('五个数加起来正好等于异常课次', () {
      final tally = LedgerTally.of(<AttendanceLedgerRow>[
        _row(status: AttendanceStatus.absent),
        _row(status: AttendanceStatus.absent),
        _row(status: AttendanceStatus.late),
        _row(status: AttendanceStatus.earlyLeave),
        _row(status: AttendanceStatus.lateAndEarly),
        _row(status: AttendanceStatus.leave),
        _row(status: AttendanceStatus.present),
      ]);
      expect(tally.absent, 2);
      expect(tally.late, 1);
      expect(tally.earlyLeave, 1);
      expect(tally.lateAndEarly, 1);
      expect(tally.leave, 1);
      expect(tally.abnormal, 6, reason: '异常 = 5 个互斥数之和，出勤不算');
      expect(tally.present, 1);
    });

    test('迟到+早退只算一次异常，但迟到/早退两栏都要认它（文案用）', () {
      final tally = LedgerTally.of(<AttendanceLedgerRow>[
        _row(status: AttendanceStatus.lateAndEarly),
      ]);
      expect(tally.abnormal, 1, reason: '一条记录只算一次异常');
      expect(tally.anyLate, 1);
      expect(tally.anyEarlyLeave, 1);
    });
  });

  group('出勤率 = 1 − 缺勤 ÷ 应上', () {
    test('18 周 × 每周 2 节 = 36 节，缺 5 节 → 86.1%', () {
      const ledger = StudentLedger(
        student: Student(id: 1, name: '张三', classId: 1),
        className: '高一(1)班',
        tally: LedgerTally(absent: 5),
        expectedSessions: 36,
      );
      expect(ledger.attendanceRate, closeTo(31 / 36, 1e-9));
      expect((ledger.attendanceRate! * 100).toStringAsFixed(1), '86.1');
      expect(ledger.attendedSessions, 31);
    });

    test('请假、迟到、早退都不扣出勤率', () {
      const ledger = StudentLedger(
        student: Student(id: 1, name: '张三', classId: 1),
        className: '高一(1)班',
        tally: LedgerTally(leave: 6, late: 4, earlyLeave: 3, lateAndEarly: 2),
        expectedSessions: 36,
      );
      expect(ledger.attendanceRate, 1.0);
      expect(ledger.tally.abnormal, 15, reason: '异常课次照样算，只是不影响出勤率');
    });

    test('没有应上课次时返回 null（界面显示「—」，不显示 100%）', () {
      const ledger = StudentLedger(
        student: Student(id: 1, name: '张三', classId: 1),
        className: '高一(1)班',
        tally: LedgerTally(),
        expectedSessions: 0,
      );
      expect(ledger.attendanceRate, isNull);
    });

    test('缺勤超过应上时截断到 0，不出现负数', () {
      const ledger = StudentLedger(
        student: Student(id: 1, name: '张三', classId: 1),
        className: '高一(1)班',
        tally: LedgerTally(absent: 40),
        expectedSessions: 36,
      );
      expect(ledger.attendanceRate, 0);
      expect(ledger.attendedSessions, 0);
    });
  });

  group('流水表分组', () {
    test('默认只列异常，按 缺勤→迟到→早退→迟早→请假 排列', () {
      final groups = groupLedgerRows(<AttendanceLedgerRow>[
        _row(status: AttendanceStatus.present),
        _row(status: AttendanceStatus.leave, date: '2026-03-03'),
        _row(status: AttendanceStatus.absent, date: '2026-03-02'),
        _row(status: AttendanceStatus.late, date: '2026-03-04'),
      ]);
      expect(
        groups.map((group) => group.status),
        <AttendanceStatus>[
          AttendanceStatus.absent,
          AttendanceStatus.late,
          AttendanceStatus.leave,
        ],
      );
    });

    test('打开「显示全部课次」才补出勤组', () {
      final groups = groupLedgerRows(
        <AttendanceLedgerRow>[_row(status: AttendanceStatus.present)],
        includePresent: true,
      );
      expect(groups.single.status, AttendanceStatus.present);
    });

    test('组内按日期倒序，同一天按上课时间正序', () {
      final groups = groupLedgerRows(<AttendanceLedgerRow>[
        _row(date: '2026-03-02', startTime: '09:00'),
        _row(date: '2026-03-02', startTime: '08:00'),
        _row(date: '2026-03-05', startTime: '10:00'),
      ]);
      expect(
        groups.single.rows.map((row) => '${row.date} ${row.startTime}'),
        <String>['2026-03-05 10:00', '2026-03-02 08:00', '2026-03-02 09:00'],
      );
    });
  });

  group('排行排序', () {
    test('班内按出勤率升序，缺得多的排前面', () {
      final ledgers = <StudentLedger>[
        const StudentLedger(
          student: Student(id: 1, name: '甲', classId: 1),
          className: '高一(1)班',
          tally: LedgerTally(),
          expectedSessions: 36,
        ),
        const StudentLedger(
          student: Student(id: 2, name: '乙', classId: 1),
          className: '高一(1)班',
          tally: LedgerTally(absent: 9),
          expectedSessions: 36,
        ),
      ];
      final groups = groupLedgersByClass(ledgers);
      expect(groups.single.value.first.student.name, '乙');
    });

    test('班级整体出勤率按人次加权，不是各人出勤率的平均', () {
      final ledgers = <StudentLedger>[
        const StudentLedger(
          student: Student(id: 1, name: '甲', classId: 1),
          className: '高一(1)班',
          tally: LedgerTally(),
          expectedSessions: 36,
        ),
        const StudentLedger(
          student: Student(id: 2, name: '乙', classId: 1),
          className: '高一(1)班',
          tally: LedgerTally(absent: 2),
          expectedSessions: 4,
        ),
      ];
      // (36+4-2)/(36+4) = 38/40，而不是 (100% + 50%)/2 = 75%
      expect(classAttendanceRate(ledgers), closeTo(0.95, 1e-9));
    });
  });

  group('应上课次推算', () {
    // 2026-02-02 是周一；到 2026-06-07 正好 126 天 = 18 周
    final from = DateTime(2026, 2, 2);
    final to = DateTime(2026, 6, 7);
    const slots = <WeeklySlot>[
      WeeklySlot(weekday: 1, periodIndex: 1, courseId: 1, classIds: <int>{1}),
      WeeklySlot(weekday: 3, periodIndex: 2, courseId: 1, classIds: <int>{1}),
    ];

    test('18 周 × 每周 2 节 = 36 节', () {
      final count = countScheduledSessions(
        slots: slots,
        from: from,
        to: to,
        labelWeekday: (date) => date.weekday,
        isRestDay: (_) => false,
      );
      expect(count, 36);
    });

    test('放假日不算（寒假那一周少两节）', () {
      final count = countScheduledSessions(
        slots: slots,
        from: from,
        to: to,
        labelWeekday: (date) => date.weekday,
        // 只管 2 月 9 日那一周，缩成"这一周放寒假"
        isRestDay: (date) =>
            !date.isBefore(DateTime(2026, 2, 9)) &&
            date.isBefore(DateTime(2026, 2, 16)),
      );
      expect(count, 34);
    });

    test('调休上班的周六按 labelWeekday 上周一的课', () {
      // 2026-02-07 是周六，被定为"上周一的课"
      final saturday = DateTime(2026, 2, 7);
      final count = countScheduledSessions(
        slots: slots,
        from: saturday,
        to: DateTime(2026, 2, 8),
        labelWeekday: (date) => date == saturday ? DateTime.monday : date.weekday,
        isRestDay: (_) => false,
      );
      expect(count, 1, reason: '不按 labelWeekday 算就会漏掉这一节');
    });

    test('休学期间不计入应上', () {
      final count = countScheduledSessions(
        slots: slots,
        from: from,
        to: to,
        labelWeekday: (date) => date.weekday,
        isRestDay: (_) => false,
        isSuspended: (courseId, date) =>
            courseId == 1 && date.compareTo('2026-03-01') >= 0 &&
            date.compareTo('2026-03-31') <= 0,
      );
      // 三月有 5 个周一 + 4 个周三 = 9 节休学，36 - 9 = 27
      expect(count, 27);
    });

    test('只看某个班时，别的班的课不算进来', () {
      const twoClasses = <WeeklySlot>[
        WeeklySlot(weekday: 1, periodIndex: 1, courseId: 1, classIds: <int>{1}),
        WeeklySlot(weekday: 1, periodIndex: 2, courseId: 2, classIds: <int>{2}),
      ];
      final count = countScheduledSessions(
        slots: twoClasses,
        from: from,
        to: to,
        labelWeekday: (date) => date.weekday,
        isRestDay: (_) => false,
        classId: 2,
      );
      expect(count, 18);
    });
  });

  group('仓储查询', () {
    late Database db;
    late TemplateRepository templates;
    late ClassRepository classes;
    late CourseRepository courses;
    late LessonRepository lessons;
    late StudentRepository students;
    late AttendanceRepository attendance;

    setUp(() async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      db = await databaseFactory.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: DatabaseSchema.version,
          singleInstance: false,
          onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
          onCreate: (db, _) => DatabaseSchema.createAll(db),
        ),
      );
      templates = TemplateRepository(database: db);
      classes = ClassRepository(database: db);
      courses = CourseRepository(database: db);
      lessons = LessonRepository(database: db);
      students = StudentRepository(database: db);
      attendance = AttendanceRepository(database: db);
    });

    tearDown(() async => db.close());

    test('ledger 把课程名/班级名/上课时间都按快照取出来', () async {
      final templateId = await templates.createTemplate('台账作息');
      final classId = await classes.createClass(
        ClassInfo(
          name: '高一(1)班',
          grade: '高一',
          color: '#4FA8F5',
          templateId: templateId,
        ),
      );
      final courseId = await courses.createCourse(
        Course(name: '数学', teacherName: '王老师', classIds: <int>[classId]),
      );
      final studentId = await students.createStudent(
        Student(name: '张三', studentNo: '07', classId: classId),
      );
      final lessonId = await lessons.placeLesson(
        courseId: courseId,
        classId: classId,
        weekday: 1,
        periodIndex: 1,
      );
      await attendance.mark(
        lesson: LessonWithTime(
          lesson: Lesson(
            id: lessonId,
            courseId: courseId,
            classId: classId,
            teacherId: AppConstants.currentTeacherId,
            weekday: 1,
            periodIndex: 1,
          ),
          startTime: '08:00',
          endTime: '08:40',
          periodType: 'normal',
          courseName: '数学',
          className: '高一(1)班',
          classColor: '#4FA8F5',
          templateId: templateId,
        ),
        studentId: studentId,
        date: '2026-03-02',
        status: AttendanceStatus.absent,
        note: '病假条没交',
      );

      final rows = await attendance.ledger(
        fromDate: '2026-03-01',
        toDate: '2026-03-31',
      );
      expect(rows.length, 1);
      final row = rows.single;
      expect(row.studentName, '张三');
      expect(row.courseName, '数学');
      expect(row.className, '高一(1)班');
      expect(row.timeRange, '08:00-08:40');
      expect(row.status, AttendanceStatus.absent);
      expect(row.note, '病假条没交');
      expect(row.weekdayLabel, '一');

      final mine = await attendance.ledger(
        fromDate: '2026-03-01',
        toDate: '2026-03-31',
        studentId: studentId,
      );
      expect(mine.length, 1);
      final others = await attendance.ledger(
        fromDate: '2026-03-01',
        toDate: '2026-03-31',
        studentId: studentId + 999,
      );
      expect(others, isEmpty);
    });

    test('weeklySlots 带上课程挂载的班级，缺 course_class 时回落到 lesson', () async {
      final templateId = await templates.createTemplate('slot 作息');
      final classA = await classes.createClass(
        ClassInfo(
          name: '高一(1)班',
          grade: '高一',
          color: '#4FA8F5',
          templateId: templateId,
        ),
      );
      final classB = await classes.createClass(
        ClassInfo(
          name: '高一(2)班',
          grade: '高一',
          color: '#4FA8F5',
          templateId: templateId,
        ),
      );
      final courseId = await courses.createCourse(
        Course(
          name: '合班物理',
          teacherName: '李老师',
          classIds: <int>[classA, classB],
        ),
      );
      await lessons.placeLesson(
        courseId: courseId,
        classId: classA,
        weekday: 2,
        periodIndex: 3,
      );

      final slots = await lessons.weeklySlots();
      expect(slots.length, 1);
      expect(slots.single.weekday, 2);
      expect(slots.single.periodIndex, 3);
      expect(slots.single.classIds, <int>{classA, classB});
    });
  });
}
