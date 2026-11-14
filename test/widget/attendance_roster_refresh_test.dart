import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:schedule_plan/app/app_navigation.dart';
import 'package:schedule_plan/core/theme/app_colors.dart';
import 'package:schedule_plan/core/theme/app_theme.dart';
import 'package:schedule_plan/core/theme/theme_controller.dart';
import 'package:schedule_plan/core/widgets/pulse_loading.dart';
import 'package:schedule_plan/data/db/schema.dart';
import 'package:schedule_plan/data/models/class_course.dart';
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
import 'package:schedule_plan/features/attendance/attendance_page.dart';
import 'package:schedule_plan/l10n/generated/app_localizations.dart';

/// 考勤页名单必须跟着「学生名单」的修改实时走（用户规格第 36 轮）。
///
/// 老师的真实用法：导入名单 → 发现几个名字/学号/班级不对 → 改掉 →
/// 课表页点格子「去点名」→ 考勤页必须显示**改过之后**的名单。
/// 名单是老师面对面的那一屏，这里显示旧姓名等于让她照着错的名字点名。
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
  late AppNavigationState navigation;

  late int templateId;
  late int classAId;
  late int classBId;
  late int courseId;
  late int lessonId;
  late int zhangId;
  late int liId;

  /// 2026-11-16 是周一，离测试里的「今天」最近的那个周一。
  const monday = '2026-11-16';

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
    navigation = AppNavigationState();

    templateId = await templates.createTemplate('测试作息');
    classAId = await classes.createClass(
      ClassInfo(
        name: '高一(1)班',
        grade: '高一',
        color: '#4FA8F5',
        templateId: templateId,
      ),
    );
    classBId = await classes.createClass(
      ClassInfo(
        name: '高一(2)班',
        grade: '高一',
        color: '#F5A34F',
        templateId: templateId,
      ),
    );
    // 这门课带了两个班（合班课），名单是并集
    courseId = await courses.createCourse(
      Course(name: '数学', teacherName: '王老师', classIds: <int>[classAId, classBId]),
    );
    lessonId = await lessons.placeLesson(
      courseId: courseId,
      classId: classAId,
      weekday: 1,
      periodIndex: 1,
    );
    zhangId = await students.createStudent(
      Student(name: '张三', studentNo: '07', classId: classAId),
    );
    liId = await students.createStudent(
      Student(name: '李四', studentNo: '08', classId: classAId),
    );
  });

  tearDown(() async {
    navigation.dispose();
    await db.close();
  });

  Future<void> settleWithIo(WidgetTester tester) async {
    for (var i = 0; i < 40; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
      if (find.byType(PulseLoading).evaluate().isEmpty) {
        break;
      }
    }
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// 等某段文字出现：页面里是真实 sqlite 查询，`pump` 推的是假时钟，
  /// 光靠 settle 会跑在查询返回之前（断言就变成"名单是空的"）。
  Future<void> waitForText(WidgetTester tester, String text) async {
    for (var i = 0; i < 40; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump();
      if (find.text(text).evaluate().isNotEmpty) {
        return;
      }
    }
  }

  Widget host(Widget child) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AppNavigationState>.value(value: navigation),
        Provider<ClassRepository>.value(value: classes),
        Provider<CourseRepository>.value(value: courses),
        Provider<LessonRepository>.value(value: lessons),
        Provider<StudentRepository>.value(value: students),
        Provider<AttendanceRepository>.value(value: attendance),
        Provider<SettingsRepository>.value(value: settings),
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

  void useTallWindow(WidgetTester tester) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(420, 2200);
    addTearDown(tester.view.reset);
  }

  /// 课表页「去点名」的等价动作：投递定位意图并切到考勤 Tab。
  Future<void> goRollCall(WidgetTester tester) async {
    navigation.openAttendance(
      AttendanceRequest(
        lessonId: lessonId,
        classId: classAId,
        weekday: 1,
        date: monday,
      ),
    );
    await settleWithIo(tester);
    // 名单是真实查库，等它落到界面上再往下断言
    await waitForText(tester, '张三');
    await waitForText(tester, '张三丰');
    await waitForText(tester, '王五');
  }

  testWidgets('首屏还没加载完就点「去点名」，名单也不能被旧加载盖掉', (tester) async {
    useTallWindow(tester);
    await tester.pumpWidget(
      host(AttendancePage(holidayService: HolidayService(settings: settings))),
    );
    // 不等首屏加载完，立刻投递定位请求：两次加载撞在一起，
    // 先发起的那次如果后返回，会把已定位好的名单盖回"今天这节课"的（常常是空的）
    navigation.openAttendance(
      AttendanceRequest(
        lessonId: lessonId,
        classId: classAId,
        weekday: 1,
        date: monday,
      ),
    );
    await settleWithIo(tester);
    await waitForText(tester, '张三');

    expect(find.text('张三'), findsOneWidget);
    expect(find.text('李四'), findsOneWidget);
  });

  testWidgets('去点名：改过姓名/学号/班级后，考勤页名单跟着变', (tester) async {
    useTallWindow(tester);
    await tester.pumpWidget(
      host(AttendancePage(holidayService: HolidayService(settings: settings))),
    );
    await settleWithIo(tester);
    await goRollCall(tester);

    expect(find.text('张三'), findsOneWidget);
    expect(find.text('李四'), findsOneWidget);

    // 老师去学生名单里改名 + 改学号，再把李四转到 2 班
    await students.updateStudent(
      Student(id: zhangId, name: '张三丰', studentNo: '21', classId: classAId),
    );
    await students.updateStudent(
      Student(id: liId, name: '李四光', studentNo: '22', classId: classBId),
    );

    navigation.switchTab(AppNavigationState.scheduleTabIndex);
    await tester.pump();
    await goRollCall(tester);

    expect(find.text('张三丰'), findsOneWidget, reason: '改名后名单要跟着变');
    expect(find.text('张三'), findsNothing, reason: '旧姓名不能还留在名单上');
    // 李四转到 2 班后仍在名单里（合班课两个班都要），但要在 2 班的分组下
    expect(find.text('李四光'), findsOneWidget);
    expect(find.text('高一(2)班'), findsWidgets);
  });

  testWidgets('切 Tab 回考勤页：名单也要跟着最新的学生信息', (tester) async {
    useTallWindow(tester);
    await tester.pumpWidget(
      host(AttendancePage(holidayService: HolidayService(settings: settings))),
    );
    await settleWithIo(tester);
    await goRollCall(tester);
    expect(find.text('张三'), findsOneWidget);

    // 老师改完名单后，没有走「去点名」，而是从设置页直接点回「考勤」Tab
    await students.updateStudent(
      Student(id: zhangId, name: '张三丰', studentNo: '21', classId: classAId),
    );
    navigation.switchTab(AppNavigationState.toolboxTabIndex);
    await tester.pump();
    navigation.switchTab(AppNavigationState.attendanceTabIndex);
    await settleWithIo(tester);

    expect(find.text('张三丰'), findsOneWidget, reason: '切回 Tab 要重读名单');
    expect(find.text('张三'), findsNothing);
  });

  testWidgets('班级改名后，考勤页的分组标题也要跟着变', (tester) async {
    useTallWindow(tester);
    await tester.pumpWidget(
      host(AttendancePage(holidayService: HolidayService(settings: settings))),
    );
    await settleWithIo(tester);
    await goRollCall(tester);
    expect(find.text('高一(1)班'), findsWidgets);

    // 在班级管理里改名：分组横带上的班名是「学生信息」的一部分
    await classes.updateClass(
      ClassInfo(
        id: classAId,
        name: '高一(1)班（实验）',
        grade: '高一',
        color: '#4FA8F5',
        templateId: templateId,
      ),
    );
    navigation.switchTab(AppNavigationState.toolboxTabIndex);
    await tester.pump();
    navigation.switchTab(AppNavigationState.attendanceTabIndex);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await waitForText(tester, '高一(1)班（实验）');

    expect(find.text('高一(1)班（实验）'), findsWidgets);
  });

  testWidgets('去点名：新增/删除学生后名单条数跟着变', (tester) async {
    useTallWindow(tester);
    await tester.pumpWidget(
      host(AttendancePage(holidayService: HolidayService(settings: settings))),
    );
    await settleWithIo(tester);
    await goRollCall(tester);

    expect(find.text('张三'), findsOneWidget);
    expect(find.text('李四'), findsOneWidget);

    await students.createStudent(
      Student(name: '王五', studentNo: '09', classId: classAId),
    );
    await students.deleteStudent(liId);

    navigation.switchTab(AppNavigationState.scheduleTabIndex);
    await tester.pump();
    await goRollCall(tester);

    expect(find.text('王五'), findsOneWidget, reason: '新增的学生要出现在名单里');
    expect(find.text('李四'), findsNothing, reason: '删掉的学生不能还留在名单里');
  });
}
