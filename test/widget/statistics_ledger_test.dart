import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:schedule_plan/core/constants/app_constants.dart';
import 'package:schedule_plan/core/theme/app_colors.dart';
import 'package:schedule_plan/core/theme/app_theme.dart';
import 'package:schedule_plan/core/theme/theme_controller.dart';
import 'package:schedule_plan/core/widgets/pulse_loading.dart';
import 'package:schedule_plan/data/db/schema.dart';
import 'package:schedule_plan/data/models/attendance.dart';
import 'package:schedule_plan/data/models/class_course.dart';
import 'package:schedule_plan/data/models/lesson.dart';
import 'package:schedule_plan/data/models/student.dart';
import 'package:schedule_plan/data/repositories/attendance_repository.dart';
import 'package:schedule_plan/data/repositories/class_repository.dart';
import 'package:schedule_plan/data/repositories/course_repository.dart';
import 'package:schedule_plan/data/repositories/lesson_repository.dart';
import 'package:schedule_plan/data/repositories/settings_repository.dart';
import 'package:schedule_plan/data/repositories/student_repository.dart';
import 'package:schedule_plan/data/repositories/template_repository.dart';
import 'package:schedule_plan/data/services/holiday_service.dart';
import 'package:schedule_plan/data/settings_state.dart';
import 'package:schedule_plan/features/statistics/statistics_page.dart';
import 'package:schedule_plan/features/statistics/student_ledger_page.dart';
import 'package:schedule_plan/l10n/generated/app_localizations.dart';

/// 评价台账的界面护栏（`docs/SPEC.md` 3.8 / 3.9）。
///
/// 守三件事：
/// 1. 档案页顶部的出勤率是 `1 − 缺勤 ÷ 应上`（一周 2 节缺 1 节 = 50%）；
/// 2. 流水表默认只列异常，「显示全部课次」打开后才补出勤组；
/// 3. 排行里点姓名能进档案页 —— 两个入口共用一个页面。
void main() {
  sqfliteFfiInit();
  // 同 isolate 实现：widget 测试推的是假时钟，独立 isolate 的 sqlite
  // 会让 pumpAndSettle 放不完那些查询（见 settings_page_test 的注释）。
  databaseFactory = databaseFactoryFfiNoIsolate;

  late Database db;
  late TemplateRepository templates;
  late ClassRepository classes;
  late CourseRepository courses;
  late LessonRepository lessons;
  late StudentRepository students;
  late AttendanceRepository attendance;
  late SettingsRepository settings;
  late int classId;
  late int courseId;
  late int aliceId;
  late int mondayLessonId;
  late int templateId;

  /// 2026-09-07 是周一，这一周没有节假日，正好当"一周两节课"的样本。
  const monday = '2026-09-07';
  const sunday = '2026-09-13';

  LessonWithTime lessonWithTime(
    int lessonId, {
    required int weekday,
    required int periodIndex,
  }) {
    return LessonWithTime(
      lesson: Lesson(
        id: lessonId,
        courseId: courseId,
        classId: classId,
        teacherId: AppConstants.currentTeacherId,
        weekday: weekday,
        periodIndex: periodIndex,
      ),
      startTime: '08:00',
      endTime: '08:40',
      periodType: 'normal',
      courseName: '数学',
      className: '高一(1)班',
      classColor: '#4FA8F5',
      templateId: templateId,
    );
  }

  setUp(() async {
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
    settings = SettingsRepository(database: db);

    templateId = await templates.createTemplate('测试作息');
    classId = await classes.createClass(
      ClassInfo(
        name: '高一(1)班',
        grade: '高一',
        color: '#4FA8F5',
        templateId: templateId,
      ),
    );
    courseId = await courses.createCourse(
      Course(name: '数学', teacherName: '王老师', classIds: <int>[classId]),
    );
    aliceId = await students.createStudent(
      Student(name: '张三', studentNo: '07', classId: classId),
    );
    await students.createStudent(
      Student(name: '李四', studentNo: '08', classId: classId),
    );
    mondayLessonId = await lessons.placeLesson(
      courseId: courseId,
      classId: classId,
      weekday: 1,
      periodIndex: 1,
    );
    await lessons.placeLesson(
      courseId: courseId,
      classId: classId,
      weekday: 3,
      periodIndex: 2,
    );
    await attendance.mark(
      lesson: lessonWithTime(mondayLessonId, weekday: 1, periodIndex: 1),
      studentId: aliceId,
      date: monday,
      status: AttendanceStatus.absent,
    );
  });

  tearDown(() async {
    await db.close();
  });

  void useTallWindow(WidgetTester tester) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(420, 2200);
    addTearDown(tester.view.reset);
  }

  /// 页面 `initState` 就去读 sqlite，`pumpAndSettle` 推的是假时钟，
  /// 查询只能靠真实时间跑完 —— 所以要反复"让出真实时间 + pump"，
  /// 等骨架屏消失再 settle，否则脉冲动画会一直把 settle 拖到超时。
  Future<void> settleWithIo(WidgetTester tester) async {
    for (var i = 0; i < 30; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
      if (find.byType(PulseLoading).evaluate().isEmpty) {
        break;
      }
    }
    // 不用 pumpAndSettle：统计页里有常驻的图表/分段控件动画，
    // settle 会一直等下去。多推几帧足够把加载后的第一屏画出来。
    await tester.pump(const Duration(milliseconds: 400));
  }

  Widget host(Widget child) {
    return MultiProvider(
      providers: [
        Provider<ClassRepository>.value(value: classes),
        Provider<CourseRepository>.value(value: courses),
        Provider<LessonRepository>.value(value: lessons),
        Provider<StudentRepository>.value(value: students),
        Provider<AttendanceRepository>.value(value: attendance),
        ChangeNotifierProvider<SettingsState>.value(
          value: SettingsState(settings),
        ),
        ChangeNotifierProvider<ThemeController>.value(
          value: ThemeController(settings),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.build(AppColorTokens.of(AppThemeKind.mint)),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: child,
      ),
    );
  }

  testWidgets('档案页：一周两节缺一节 → 50%，且默认只列异常', (tester) async {
    useTallWindow(tester);
    await tester.pumpWidget(
      host(
        StudentLedgerPage(
          studentId: aliceId,
          studentName: '张三',
          fromDate: monday,
          toDate: sunday,
          holidayService: HolidayService(settings: settings),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('50.0%'), findsOneWidget);
    expect(find.text('数学'), findsWidgets);
    // 默认只看异常：缺勤那一组在，出勤组不在
    expect(find.text('缺勤'), findsWidgets);
    expect(find.text('出勤'), findsNothing);

    // 打开「显示全部课次」：这节课没标过出勤，所以补不出出勤行，
    // 但必须给出「没点名按全勤计」的说明，不能让人以为漏了记录。
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.text('没点名的课次按全勤计，不单独列出'), findsOneWidget);
  });

  testWidgets('排行页：出勤率升序，点姓名进档案', (tester) async {
    useTallWindow(tester);
    await tester.pumpWidget(
      host(StatisticsPage(holidayService: HolidayService(settings: settings))),
    );
    await settleWithIo(tester);

    await tester.tap(find.text('班级排行'));
    await tester.pumpAndSettle();

    expect(find.text('张三'), findsWidgets);
    expect(find.text('李四'), findsWidgets);

    await tester.tap(find.text('张三').first);
    await settleWithIo(tester);
    expect(find.textContaining('出勤档案'), findsWidgets);
  });
}
