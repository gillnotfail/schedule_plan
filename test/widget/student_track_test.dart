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
import 'package:schedule_plan/features/statistics/student_track_panel.dart';
import 'package:schedule_plan/l10n/generated/app_localizations.dart';

/// 工具箱第 3 页「学生追踪」的界面护栏（用户规格第 33 轮）。
///
/// 守三件事：
/// 1. 名单按异常次数从多到少排，二级行把缺/迟/早拆开给出来；
/// 2. 点姓名进详情页，表头是「日期 / 课程 / 出勤情况」；
/// 3. **正常出勤也列出来**（和档案页"默认只列异常"刻意不同）。
void main() {
  sqfliteFfiInit();
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
  late int zhangSanId;
  late int liSiId;
  late int mondayLessonId;
  late int templateId;

  const monday = '2026-09-07';

  /// 2026-09-07 是周一，这一周没有节假日；本学期区间（9/1~1/31）覆盖它。
  DateTime clock() => DateTime(2026, 9, 9);

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
    zhangSanId = await students.createStudent(
      Student(name: '张三', studentNo: '07', classId: classId),
    );
    liSiId = await students.createStudent(
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
    // 周一这节：张三缺勤、李四出勤；周三那节谁都没点（按全勤计）
    await attendance.mark(
      lesson: lessonWithTime(mondayLessonId, weekday: 1, periodIndex: 1),
      studentId: zhangSanId,
      date: monday,
      status: AttendanceStatus.absent,
    );
    await attendance.mark(
      lesson: lessonWithTime(mondayLessonId, weekday: 1, periodIndex: 1),
      studentId: liSiId,
      date: monday,
      status: AttendanceStatus.present,
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
    // 面板里有常驻动画，不能用 pumpAndSettle
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

  Widget panel() {
    return Scaffold(
      body: StudentTrackPanel(
        holidayService: HolidayService(settings: settings),
        clock: clock,
      ),
    );
  }

  testWidgets('名单：异常多的排前面，二级行拆开缺/迟/早/请假', (tester) async {
    useTallWindow(tester);
    await tester.pumpWidget(host(panel()));
    await settleWithIo(tester);

    expect(find.text('按异常次数从多到少'), findsOneWidget);
    expect(find.text('1 次异常'), findsOneWidget);
    expect(find.text('全勤'), findsOneWidget);
    expect(find.text('缺 1 · 迟 0 · 早 0 · 迟早 0 · 假 0'), findsOneWidget);
    // 这一页也能导出当前显示状态
    expect(find.byTooltip('导出学生列表'), findsOneWidget);

    // 张三（1 次异常）在李四（全勤）上面
    final zhang = tester.getTopLeft(find.text('张三')).dy;
    final li = tester.getTopLeft(find.text('李四')).dy;
    expect(zhang, lessThan(li));
  });

  testWidgets('详情：日期-课程-出勤情况，正常出勤也列出来', (tester) async {
    useTallWindow(tester);
    await tester.pumpWidget(host(panel()));
    await settleWithIo(tester);

    await tester.tap(find.text('李四'));
    await settleWithIo(tester);

    expect(find.text('李四 · 出勤记录'), findsOneWidget);
    expect(find.text('日期'), findsOneWidget);
    expect(find.text('课程'), findsOneWidget);
    expect(find.text('出勤情况'), findsOneWidget);
    // 正常出勤也要显示（这一页和档案页的差别就在这里）
    expect(find.text('出勤'), findsOneWidget);
    expect(find.text('数学'), findsWidgets);
    // 周三那节没点名 → 表下小字交代，不伪造行
    // 9/1~9/9 之间排得上的是 9/2(三)、9/7(一)、9/9(三) 三节，只点了一次名
    expect(find.text('另有 2 节课没点名，按全勤计入出勤率，不逐条列出'), findsOneWidget);
    expect(find.byTooltip('导出出勤明细'), findsOneWidget);
  });

  testWidgets('详情：缺勤也在这张表里，出勤率按 1 − 缺勤 ÷ 应上', (tester) async {
    useTallWindow(tester);
    await tester.pumpWidget(host(panel()));
    await settleWithIo(tester);

    await tester.tap(find.text('张三'));
    await settleWithIo(tester);

    expect(find.text('张三 · 出勤记录'), findsOneWidget);
    expect(find.text('缺勤'), findsOneWidget);
    // 应上 3 节（9/2、9/7、9/9）、缺 1 节 → 66.7%
    // 名单页还在路由栈下面，同一个数字会出现两次，所以只断言"至少一处"
    expect(find.text('66.7%'), findsWidgets);
    expect(find.text('应上'), findsOneWidget);
    expect(find.text('异常课次'), findsOneWidget);
  });

  testWidgets('课程筛选：只留这门课的学生', (tester) async {
    useTallWindow(tester);
    await tester.pumpWidget(host(panel()));
    await settleWithIo(tester);

    // 只有一门课，选中后名单不空（学生属于排了这门课的班）
    await tester.tap(find.text('全部'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('数学').last);
    await settleWithIo(tester);

    expect(find.text('张三'), findsOneWidget);
    expect(find.text('李四'), findsOneWidget);
  });
}
