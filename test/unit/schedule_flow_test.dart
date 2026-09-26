import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:schedule_plan/core/constants/setting_keys.dart';
import 'package:schedule_plan/core/error/app_exceptions.dart';
import 'package:schedule_plan/data/db/schema.dart';
import 'package:schedule_plan/data/models/class_course.dart';
import 'package:schedule_plan/data/models/course_detail.dart';
import 'package:schedule_plan/data/models/student.dart';
import 'package:schedule_plan/data/repositories/class_repository.dart';
import 'package:schedule_plan/data/repositories/course_repository.dart';
import 'package:schedule_plan/data/repositories/lesson_repository.dart';
import 'package:schedule_plan/data/repositories/settings_repository.dart';
import 'package:schedule_plan/data/repositories/student_repository.dart';
import 'package:schedule_plan/data/repositories/template_repository.dart';

/// 课表页「点格子」全链路的冷存储回归测试。
///
/// 覆盖用户报过的问题与本次新增的交互：
/// 1. **改过的时间不能丢**——展示用的作息模板 id 必须落库，
///    否则重启后按 `is_default` 临时挑一套模板，第一列就变回默认时间；
/// 2. 空格子排课 / 同格冲突拦截 / 移出一格；
/// 3. 格子里显示的「人数」= 课程所选班级人数之和（合班课相加）。
Future<Database> _openMemoryDb() {
  return databaseFactory.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: DatabaseSchema.version,
      singleInstance: false,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, _) => DatabaseSchema.createAll(db),
    ),
  );
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late TemplateRepository templates;
  late ClassRepository classes;
  late CourseRepository courses;
  late LessonRepository lessons;
  late StudentRepository students;
  late SettingsRepository settings;

  setUp(() async {
    db = await _openMemoryDb();
    templates = TemplateRepository(database: db);
    classes = ClassRepository(database: db);
    courses = CourseRepository(database: db);
    lessons = LessonRepository(database: db);
    students = StudentRepository(database: db);
    settings = SettingsRepository(database: db);
  });

  tearDown(() async {
    await db.close();
  });

  group('课表展示状态的冷存储', () {
    test('改过时间的作息，重开后第一列仍是改后的时间', () async {
      final templateId = (await templates.listTemplates()).first.id!;

      // 用户场景：点第一列改第一节时间，并顺延后续（cascade）
      await templates.cascadeUpdatePeriods(
        templateId: templateId,
        weekday: 1,
        fromPeriodIndex: 1,
        newStartTime: '09:00',
        newEndTime: '09:45',
        cascade: true,
      );

      // 模拟「退出重开」：换一批仓储实例，读同一个库
      final reopenedTemplates = TemplateRepository(database: db);
      final periods = await reopenedTemplates.periodsForWeekday(templateId, 1);
      expect(periods, isNotEmpty);
      expect(periods.first.startTime, '09:00');
      expect(periods.first.endTime, '09:45');
      // 后续节次顺延，不再与第一节重叠
      expect(periods[1].startTime, '09:55');
    });

    test('展示作息 id 与选中班级 id 落库，重开后原样取回', () async {
      // 造第二套作息：老版本靠 `is_default` 临时挑模板，
      // 只要多出一套就会静默换表，所以必须把「正在看哪套」持久化
      final secondTemplateId = await templates.createTemplate('错峰作息');
      await settings.writeInt(
        SettingKeys.scheduleDisplayTemplateId,
        secondTemplateId,
      );
      await settings.writeInt(SettingKeys.scheduleSelectedClassId, 0);

      // 模拟「退出重开」
      final reopenedSettings = SettingsRepository(database: db);
      expect(
        await reopenedSettings.readInt(SettingKeys.scheduleDisplayTemplateId),
        secondTemplateId,
        reason: '重启后必须还是用户上次在看的这套作息',
      );
      expect(
        await reopenedSettings.readInt(SettingKeys.scheduleSelectedClassId),
        0,
        reason: '没有班级时 0 就是「无班级」，不能被写成别的班级',
      );
    });

    test('默认值：从未写过展示状态时读出来是 0（而不是报错）', () async {
      final fresh = SettingsRepository(database: db);
      expect(
        await fresh.readInt(SettingKeys.scheduleDisplayTemplateId),
        0,
      );
      expect(await fresh.readInt(SettingKeys.scheduleSelectedClassId), 0);
    });
  });

  group('空格子排课 / 换课 / 移出', () {
    late int templateId;
    late int classId;
    late int courseId;

    setUp(() async {
      templateId = (await templates.listTemplates()).first.id!;
      classId = await classes.createClass(
        ClassInfo(
          name: '高一(1)班',
          grade: '高一',
          color: 'FF26A69A',
          templateId: templateId,
        ),
      );
      courseId = await courses.createCourse(
        Course(
          name: '数学',
          teacherName: '王老师',
          classIds: <int>[classId],
          room: '教学楼 101',
        ),
      );
    });

    test('placeLesson 把课排进空格子，并能按格子反查条目 id', () async {
      final lessonId = await lessons.placeLesson(
        courseId: courseId,
        classId: classId,
        weekday: 1,
        periodIndex: 2,
      );
      expect(lessonId, greaterThan(0));
      expect(
        await lessons.lessonIdAt(
          classId: classId,
          weekday: 1,
          periodIndex: 2,
        ),
        lessonId,
      );
      // 排课走的是与 addLesson 相同的联查路径，时间必须能解析出来
      final withTime = await lessons.forClass(classId);
      expect(withTime, hasLength(1));
      expect(withTime.first.courseName, '数学');
      expect(withTime.first.startTime, isNotEmpty);
    });

    test('同一格重复排课会被冲突检测拦住', () async {
      await lessons.placeLesson(
        courseId: courseId,
        classId: classId,
        weekday: 1,
        periodIndex: 2,
      );
      await expectLater(
        lessons.placeLesson(
          courseId: courseId,
          classId: classId,
          weekday: 1,
          periodIndex: 2,
        ),
        throwsA(isA<ConflictException>()),
      );
    });

    test('移出一格只删课表条目，课程本身仍留在课程管理里', () async {
      await lessons.placeLesson(
        courseId: courseId,
        classId: classId,
        weekday: 3,
        periodIndex: 1,
      );
      await lessons.clearSlot(classId: classId, weekday: 3, periodIndex: 1);

      expect(
        await lessons.lessonIdAt(
          classId: classId,
          weekday: 3,
          periodIndex: 1,
        ),
        isNull,
      );
      final remaining = await courses.listCourses(classId: classId);
      expect(remaining, hasLength(1), reason: '课程本身不能被连带删掉');
      expect(remaining.first.name, '数学');
    });
  });

  group('格子里显示的「人数」', () {
    test('合班课人数 = 所选班级人数之和', () async {
      final templateId = (await templates.listTemplates()).first.id!;
      final classA = await classes.createClass(
        ClassInfo(
          name: '高一(1)班',
          grade: '高一',
          color: 'FF26A69A',
          templateId: templateId,
        ),
      );
      final classB = await classes.createClass(
        ClassInfo(
          name: '高一(2)班',
          grade: '高一',
          color: 'FF5C6BC0',
          templateId: templateId,
        ),
      );
      for (var i = 0; i < 3; i++) {
        await students.createStudent(Student(name: '甲$i', classId: classA));
      }
      for (var i = 0; i < 2; i++) {
        await students.createStudent(Student(name: '乙$i', classId: classB));
      }
      final courseId = await courses.createCourse(
        Course(
          name: '大课间讲堂',
          teacherName: '',
          classIds: <int>[classA, classB],
        ),
      );

      final counts = await courses.studentCountByCourse();
      expect(counts[courseId], 5);

      // 格子（CourseDetail）与课程列表用的是同一口径
      final detail = CourseDetail.from(
        (await courses.listCourses(classId: classA)).first,
        await classes.listClasses(),
      );
      expect(detail.studentCount, 5);
      expect(
        detail.classNames.toSet(),
        <String>{'高一(1)班', '高一(2)班'},
      );
      // 颜色取其中一个所选班级的班级色（用户规格：不新建颜色字段）
      expect(detail.color, isIn(<String>['FF26A69A', 'FF5C6BC0']));
    });
  });
}
