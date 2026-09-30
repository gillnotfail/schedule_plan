import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:schedule_plan/core/constants/app_constants.dart';
import 'package:schedule_plan/core/error/app_exceptions.dart';
import 'package:schedule_plan/data/db/schema.dart';
import 'package:schedule_plan/data/models/attendance.dart';
import 'package:schedule_plan/data/models/class_course.dart';
import 'package:schedule_plan/data/models/lesson.dart';
import 'package:schedule_plan/data/models/schedule_template.dart';
import 'package:schedule_plan/data/models/student.dart';
import 'package:schedule_plan/data/repositories/attendance_repository.dart';
import 'package:schedule_plan/data/repositories/class_repository.dart';
import 'package:schedule_plan/data/repositories/course_repository.dart';
import 'package:schedule_plan/data/repositories/lesson_repository.dart';
import 'package:schedule_plan/data/repositories/settings_repository.dart';
import 'package:schedule_plan/data/repositories/student_repository.dart';
import 'package:schedule_plan/data/repositories/template_repository.dart';

/// 数据库层集成测试（readme 第五章：Repository/DAO 需编写单元测试）。
///
/// 使用 sqflite_common_ffi 在内存中建库，与真机一致的完整 Schema + 外键约束。
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
  // 单元测试环境不是 Android/iOS，必须显式切换到 ffi 实现
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late TemplateRepository templates;
  late ClassRepository classes;
  late CourseRepository courses;
  late LessonRepository lessons;
  late StudentRepository students;
  late AttendanceRepository attendance;
  late SettingsRepository settings;

  setUp(() async {
    db = await _openMemoryDb();
    templates = TemplateRepository(database: db);
    classes = ClassRepository(database: db);
    courses = CourseRepository(database: db);
    lessons = LessonRepository(database: db);
    students = StudentRepository(database: db);
    attendance = AttendanceRepository(database: db);
    settings = SettingsRepository(database: db);
  });

  tearDown(() async {
    await db.close();
  });

  group('建库与种子数据', () {
    test('首次建库写入默认作息模板与周一至周五走读作息', () async {
      final list = await templates.listTemplates();
      expect(list.length, 1);
      expect(list.first.isDefault, isTrue);

      final monday = await templates.periodsForWeekday(list.first.id!, 1);
      expect(monday.length, 10);
      // 出厂作息：08:00 开始、每节 40 分钟、课间 10 分钟
      expect(monday.first.startTime, '08:00');
      expect(monday.first.endTime, '08:40');
      expect(monday[1].startTime, '08:50');
      expect(monday[1].endTime, '09:30');
      // 出厂作息是均匀网格，全部为普通课节；
      // 午休 / 大课间由用户在模板编辑器里自行标注（下方单独用例覆盖）
      expect(
        monday.every((item) => item.periodType == PeriodType.normal),
        isTrue,
      );
      // 与「课表设置 → 一键生成作息」共用同一套算术，两处口径必须完全一致
      final generated = DatabaseSchema.generatePeriodRows(
        startTime: AppConstants.defaultDayStartTime,
        lessonMinutes: AppConstants.defaultLessonMinutes,
        breakMinutes: AppConstants.defaultBreakMinutes,
        count: AppConstants.defaultDayPeriodCount,
      );
      for (var i = 0; i < generated.length; i++) {
        expect(monday[i].startTime, generated[i].$1);
        expect(monday[i].endTime, generated[i].$2);
      }
    });

    test('新建模板自带同一份出厂作息', () async {
      final id = await templates.createTemplate('错峰作息');
      final monday = await templates.periodsForWeekday(id, 1);
      expect(monday.length, AppConstants.defaultDayPeriodCount);
      expect(monday.first.startTime, AppConstants.defaultDayStartTime);
    });

    test('一键清空课表只清课表内容，作息（第一列的时间）必须保留', () async {
      final id = await templates.createTemplate('待清空作息');
      final classId = await classes.createClass(
        ClassInfo(
          name: '高一(9)班',
          grade: '高一',
          color: '#4FA8F5',
          templateId: id,
        ),
      );
      await courses.createCourse(
        Course(name: '语文', teacherName: '王老师', classIds: <int>[classId]),
      );
      final courseRows = await courses.listCourses(classId: classId);
      await lessons.addLesson(
        Lesson(
          courseId: courseRows.first.id!,
          classId: classId,
          teacherId: AppConstants.currentTeacherId,
          weekday: 1,
          periodIndex: 1,
        ),
      );
      expect(await lessons.forClass(classId), isNotEmpty);

      await templates.clearTemplateSchedule(id);

      // 课表内容清空了
      expect(await lessons.forClass(classId), isEmpty);
      // 但作息还在 —— 否则课表页第一列会变成空的，整张表就没了
      expect(await templates.periodsForWeekday(id, 1), isNotEmpty);
    });

    test('作息为空的模板会被自愈补齐（老库升级后课表页不再空白）', () async {
      final id = await templates.createTemplate('被清空的作息');
      for (final day in <int>[1, 2, 3, 4, 5]) {
        await templates.saveWeekdayPeriods(id, day, const <TemplatePeriod>[]);
      }
      expect(await templates.allPeriods(id), isEmpty);

      expect(await templates.ensureFactorySchedule(id), isTrue);
      final monday = await templates.periodsForWeekday(id, 1);
      expect(monday.length, AppConstants.defaultDayPeriodCount);
      expect(monday.first.startTime, AppConstants.defaultDayStartTime);

      // 已经有作息时不再重复补写，用户调过的时间不会被覆盖
      expect(await templates.ensureFactorySchedule(id), isFalse);
      expect(
        await templates.periodsForWeekday(id, 1),
        hasLength(AppConstants.defaultDayPeriodCount),
      );
    });

    test('午休 / 大课间等非普通节次类型能落库并回读', () async {
      final template = (await templates.listTemplates()).first;
      final templateId = template.id!;
      await templates.saveWeekdayPeriods(templateId, 6, <TemplatePeriod>[
        TemplatePeriod(
          templateId: templateId,
          weekday: 6,
          periodIndex: 1,
          periodType: PeriodType.normal,
          startTime: '08:00',
          endTime: '08:40',
        ),
        TemplatePeriod(
          templateId: templateId,
          weekday: 6,
          periodIndex: 2,
          periodType: PeriodType.recess,
          startTime: '08:40',
          endTime: '09:00',
        ),
        TemplatePeriod(
          templateId: templateId,
          weekday: 6,
          periodIndex: 3,
          periodType: PeriodType.lunchBreak,
          startTime: '09:00',
          endTime: '09:50',
        ),
      ]);
      final saved = await templates.periodsForWeekday(template.id!, 6);
      expect(saved.length, 3);
      expect(saved[1].periodType, PeriodType.recess);
      expect(saved[2].periodType, PeriodType.lunchBreak);
    });

    test('周六周日不预置节次（不假设一周内节次数固定）', () async {
      final template = (await templates.listTemplates()).first;
      expect(await templates.periodsForWeekday(template.id!, 6), isEmpty);
      expect(await templates.periodsForWeekday(template.id!, 7), isEmpty);
    });

    test('种子节次本身能通过校验器', () async {
      final template = (await templates.listTemplates()).first;
      final issues = await templates.periodsForWeekday(template.id!, 1);
      expect(issues, isNotEmpty);
    });
  });

  group('作息模板 CRUD', () {
    test('空名称被拒绝', () async {
      expect(
        () => templates.createTemplate('   '),
        throwsA(isA<ValidationException>()),
      );
    });

    test('新建第二条模板不会抢走默认标记', () async {
      final second = await templates.createTemplate('错峰作息');
      final list = await templates.listTemplates();
      final defaultOnes = list.where((item) => item.isDefault);
      expect(defaultOnes.length, 1);
      expect(defaultOnes.first.id, isNot(second));
    });

    test('设为默认时清除其他记录的默认标记', () async {
      final second = await templates.createTemplate('错峰作息');
      await templates.setDefaultTemplate(second);
      final list = await templates.listTemplates();
      expect(list.where((item) => item.isDefault).length, 1);
      expect(list.firstWhere((item) => item.id == second).isDefault, isTrue);
    });

    test('保存节次前执行校验，重叠直接拒绝且不落库', () async {
      final template = (await templates.listTemplates()).first;
      final before = await templates.periodsForWeekday(template.id!, 1);
      expect(
        () => templates.saveWeekdayPeriods(template.id!, 1, <TemplatePeriod>[
          TemplatePeriod(
            templateId: template.id!,
            weekday: 1,
            periodIndex: 1,
            startTime: '08:00',
            endTime: '08:45',
          ),
          TemplatePeriod(
            templateId: template.id!,
            weekday: 1,
            periodIndex: 2,
            startTime: '08:30',
            endTime: '09:15',
          ),
        ]),
        throwsA(isA<ValidationException>()),
      );
      final after = await templates.periodsForWeekday(template.id!, 1);
      expect(after.length, before.length);
    });

    test('保存节次后自动重排序号（不留空洞）', () async {
      final template = (await templates.listTemplates()).first;
      await templates.saveWeekdayPeriods(template.id!, 1, <TemplatePeriod>[
        TemplatePeriod(
          templateId: template.id!,
          weekday: 1,
          periodIndex: 99,
          startTime: '08:00',
          endTime: '08:45',
        ),
        TemplatePeriod(
          templateId: template.id!,
          weekday: 1,
          periodIndex: 77,
          startTime: '08:55',
          endTime: '09:40',
        ),
      ]);
      final saved = await templates.periodsForWeekday(template.id!, 1);
      expect(saved.map((item) => item.periodIndex).toList(), <int>[1, 2]);
    });

    test('从其他工作日复制', () async {
      final template = (await templates.listTemplates()).first;
      await templates.copyWeekdayTo(
        template.id!,
        fromWeekday: 1,
        targetWeekdays: <int>[2, 3, 4, 5],
      );
      for (var day = 2; day <= 5; day++) {
        final periods = await templates.periodsForWeekday(template.id!, day);
        expect(periods.length, 10);
      }
    });

    test('复制空的工作日被拒绝', () async {
      final template = (await templates.listTemplates()).first;
      expect(
        () => templates.copyWeekdayTo(
          template.id!,
          fromWeekday: 6,
          targetWeekdays: <int>[7],
        ),
        throwsA(isA<ValidationException>()),
      );
    });

    test('级联更新：后续节次按间隔顺延', () async {
      final template = (await templates.listTemplates()).first;
      await templates.cascadeUpdatePeriods(
        templateId: template.id!,
        weekday: 1,
        fromPeriodIndex: 1,
        newStartTime: '08:10',
        newEndTime: '08:55',
        cascade: true,
      );
      final periods = await templates.periodsForWeekday(template.id!, 1);
      expect(periods.first.startTime, '08:10');
      // 第 2 节顺延 15 分钟：开始时间推迟 10 分钟 + 时长增加 5 分钟
      expect(periods[1].startTime, '09:05');
      expect(periods[1].endTime, '09:45');
    });

    test('非级联更新：只改目标节次', () async {
      final template = (await templates.listTemplates()).first;
      await templates.cascadeUpdatePeriods(
        templateId: template.id!,
        weekday: 1,
        fromPeriodIndex: 1,
        // 08:10~08:45 结束早于第 2 节的 08:50，不会产生重叠
        newStartTime: '08:10',
        newEndTime: '08:45',
        cascade: false,
      );
      final periods = await templates.periodsForWeekday(template.id!, 1);
      expect(periods.first.startTime, '08:10');
      expect(periods.first.endTime, '08:45');
      // 第 2 节保持不动
      expect(periods[1].startTime, '08:50');
    });

    test('非级联更新若造成重叠必须被拒绝（禁止写出非法时间列）', () async {
      final template = (await templates.listTemplates()).first;
      await expectLater(
        () => templates.cascadeUpdatePeriods(
          templateId: template.id!,
          weekday: 1,
          fromPeriodIndex: 1,
          // 结束时间 08:55 晚于第 2 节的 08:50，属于重叠
          newStartTime: '08:10',
          newEndTime: '08:55',
          cascade: false,
        ),
        throwsA(isA<ValidationException>()),
      );
      // 校验失败一律不得落库
      final periods = await templates.periodsForWeekday(template.id!, 1);
      expect(periods.first.startTime, '08:00');
    });

    test('模板被班级绑定时禁止删除，并列出受影响班级', () async {
      final template = (await templates.listTemplates()).first;
      await classes.createClass(
        ClassInfo(
          name: '高一(3)班',
          grade: '高一',
          color: '#2196F3',
          templateId: template.id!,
        ),
      );
      try {
        await templates.deleteTemplate(template.id!);
        fail('应当抛出 TemplateInUseException');
      } on TemplateInUseException catch (error) {
        expect(error.classNames, contains('高一(3)班'));
      }
    });

    test('未绑定的模板可以删除，且节次级联清理', () async {
      final id = await templates.createTemplate('临时模板');
      await templates.saveWeekdayPeriods(id, 1, <TemplatePeriod>[
        TemplatePeriod(
          templateId: id,
          weekday: 1,
          periodIndex: 1,
          startTime: '08:00',
          endTime: '08:45',
        ),
      ]);
      expect(await templates.periodsForWeekday(id, 1), isNotEmpty);
      await templates.deleteTemplate(id);
      expect(await templates.getTemplate(id), isNull);
      expect(await templates.periodsForWeekday(id, 1), isEmpty);
    });

    test('列表页展示绑定班级数量', () async {
      final template = (await templates.listTemplates()).first;
      await classes.createClass(
        ClassInfo(
          name: '高一(1)班',
          grade: '高一',
          color: '#4CAF50',
          templateId: template.id!,
        ),
      );
      await classes.createClass(
        ClassInfo(
          name: '高一(2)班',
          grade: '高一',
          color: '#FF9800',
          templateId: template.id!,
        ),
      );
      final list = await templates.listTemplates();
      expect(list.first.boundClassCount, 2);
    });
  });

  group('班级 / 课程 / 学生', () {
    test('新增学生后 student_count 冗余字段同步', () async {
      final template = (await templates.listTemplates()).first;
      final classId = await classes.createClass(
        ClassInfo(
          name: '高二(1)班',
          grade: '高二',
          color: '#9C27B0',
          templateId: template.id!,
        ),
      );
      await students.createStudent(
        Student(name: '张三', studentNo: '001', classId: classId),
      );
      await students.createStudent(
        Student(name: '李四', studentNo: '002', classId: classId),
      );
      final info = await classes.getClass(classId);
      expect(info!.studentCount, 2);
    });

    test('删除班级时课程与学生级联清理', () async {
      final template = (await templates.listTemplates()).first;
      final classId = await classes.createClass(
        ClassInfo(
          name: '高二(2)班',
          grade: '高二',
          color: '#009688',
          templateId: template.id!,
        ),
      );
      await courses.createCourse(
        Course(name: '语文', teacherName: '王老师', classIds: <int>[classId]),
      );
      await students.createStudent(Student(name: '王五', classId: classId));
      await classes.deleteClass(classId);

      final remainingStudents = await db.query(
        'student',
        where: 'class_id = ?',
        whereArgs: <Object?>[classId],
      );
      final remainingCourses = await db.query(
        'course',
        where: 'class_id = ?',
        whereArgs: <Object?>[classId],
      );
      expect(remainingStudents, isEmpty);
      expect(remainingCourses, isEmpty);
    });

    test('批量修改年级模板只影响该年级', () async {
      final template = (await templates.listTemplates()).first;
      final other = await templates.createTemplate('高三作息');
      await classes.createClass(
        ClassInfo(
          name: '高一(1)班',
          grade: '高一',
          color: '#4CAF50',
          templateId: template.id!,
        ),
      );
      await classes.createClass(
        ClassInfo(
          name: '高三(1)班',
          grade: '高三',
          color: '#FF5722',
          templateId: template.id!,
        ),
      );

      await classes.updateTemplateForGrade('高三', other);

      final all = await classes.listClasses();
      final g1 = all.firstWhere((item) => item.grade == '高一');
      final g3 = all.firstWhere((item) => item.grade == '高三');
      expect(g1.templateId, template.id);
      expect(g3.templateId, other);
    });

    test('拖拽排序持久化', () async {
      final template = (await templates.listTemplates()).first;
      final a = await classes.createClass(
        ClassInfo(
          name: 'A班',
          grade: '高一',
          color: '#000001',
          templateId: template.id!,
        ),
      );
      final b = await classes.createClass(
        ClassInfo(
          name: 'B班',
          grade: '高一',
          color: '#000002',
          templateId: template.id!,
        ),
      );
      await classes.reorderClasses(<int>[b, a]);
      final all = await classes.listClasses();
      expect(all.first.id, b);
      expect(all.last.id, a);
    });
  });

  group('课表与冲突检测', () {
    /// 造一个「班级 + 课程 + 模板节次」的可用场景。
    Future<int> prepareClass({
      required int templateId,
      required String className,
      required String grade,
    }) async {
      final classId = await classes.createClass(
        ClassInfo(
          name: className,
          grade: grade,
          color: '#2196F3',
          templateId: templateId,
        ),
      );
      await courses.createCourse(
        Course(name: '数学', teacherName: '李老师', classIds: <int>[classId]),
      );
      return classId;
    }

    test('新增课表成功', () async {
      final template = (await templates.listTemplates()).first;
      final classId = await prepareClass(
        templateId: template.id!,
        className: '高一(3)班',
        grade: '高一',
      );
      final course = (await courses.listCourses(classId: classId)).first;
      final id = await lessons.addLesson(
        Lesson(
          courseId: course.id!,
          classId: classId,
          teacherId: 1,
          weekday: 1,
          periodIndex: 1,
        ),
      );
      expect(id, greaterThan(0));
      final withTime = await lessons.queryWithTime(teacherId: 1, weekday: 1);
      expect(withTime.length, 1);
      // 真实时间由模板解析，色块内展示「真实起止时间」而非裸节次编号
      expect(withTime.first.timeRangeText, '08:00-08:40');
    });

    test('同班级同节次重复排课被拒绝', () async {
      final template = (await templates.listTemplates()).first;
      final classId = await prepareClass(
        templateId: template.id!,
        className: '高一(3)班',
        grade: '高一',
      );
      final course = (await courses.listCourses(classId: classId)).first;
      await lessons.addLesson(
        Lesson(
          courseId: course.id!,
          classId: classId,
          teacherId: 1,
          weekday: 1,
          periodIndex: 1,
        ),
      );
      expect(
        () => lessons.addLesson(
          Lesson(
            courseId: course.id!,
            classId: classId,
            teacherId: 1,
            weekday: 1,
            periodIndex: 1,
          ),
        ),
        throwsA(isA<ConflictException>()),
      );
    });

    test('跨模板的真实时间冲突也能被检出（不比较 period_index）', () async {
      final base = (await templates.listTemplates()).first;
      // 另建一个「错峰模板」：第 1 节实际是 08:15-09:00，与基础模板第 1 节重叠
      final offset = await templates.createTemplate('错峰作息');
      await templates.saveWeekdayPeriods(offset, 1, <TemplatePeriod>[
        TemplatePeriod(
          templateId: offset,
          weekday: 1,
          periodIndex: 1,
          startTime: '08:15',
          endTime: '09:00',
        ),
      ]);

      final classA = await prepareClass(
        templateId: base.id!,
        className: '高一(3)班',
        grade: '高一',
      );
      final classB = await prepareClass(
        templateId: offset,
        className: '高二(1)班',
        grade: '高二',
      );
      final courseA = (await courses.listCourses(classId: classA)).first;
      final courseB = (await courses.listCourses(classId: classB)).first;

      await lessons.addLesson(
        Lesson(
          courseId: courseA.id!,
          classId: classA,
          teacherId: 1,
          weekday: 1,
          periodIndex: 1,
        ),
      );
      // 不同班级、同为「第 1 节」，但真实时间 08:15-09:00 与 08:00-08:45 重叠
      expect(
        () => lessons.addLesson(
          Lesson(
            courseId: courseB.id!,
            classId: classB,
            teacherId: 1,
            weekday: 1,
            periodIndex: 1,
          ),
        ),
        throwsA(isA<ConflictException>()),
      );
    });

    test('班级绑定模板中不存在该节次时拒绝排课', () async {
      final template = (await templates.listTemplates()).first;
      final classId = await prepareClass(
        templateId: template.id!,
        className: '高一(3)班',
        grade: '高一',
      );
      final course = (await courses.listCourses(classId: classId)).first;
      expect(
        () => lessons.addLesson(
          Lesson(
            courseId: course.id!,
            classId: classId,
            teacherId: 1,
            weekday: 6,
            periodIndex: 1,
          ),
        ),
        throwsA(isA<ValidationException>()),
      );
    });

    test('交换两节课（同班级同模板）', () async {
      final template = (await templates.listTemplates()).first;
      final classId = await prepareClass(
        templateId: template.id!,
        className: '高一(3)班',
        grade: '高一',
      );
      final course = (await courses.listCourses(classId: classId)).first;
      final firstId = await lessons.addLesson(
        Lesson(
          courseId: course.id!,
          classId: classId,
          teacherId: 1,
          weekday: 1,
          periodIndex: 1,
        ),
      );
      final secondId = await lessons.addLesson(
        Lesson(
          courseId: course.id!,
          classId: classId,
          teacherId: 1,
          weekday: 1,
          periodIndex: 2,
        ),
      );
      final before = await lessons.queryWithTime(
        teacherId: 1,
        weekday: 1,
        classId: classId,
      );
      final source = before.firstWhere((item) => item.lesson.id == firstId);
      final target = before.firstWhere((item) => item.lesson.id == secondId);
      await lessons.swapLessons(source: source, target: target);
      final a = await lessons.getLesson(firstId);
      final b = await lessons.getLesson(secondId);
      expect(a!.periodIndex, 2);
      expect(b!.periodIndex, 1);
    });
  });

  group('考勤记录', () {
    test('同天同课程不同节次考勤互不覆盖（唯一键含 lesson_id）', () async {
      final template = (await templates.listTemplates()).first;
      final classId = await classes.createClass(
        ClassInfo(
          name: '高一(3)班',
          grade: '高一',
          color: '#2196F3',
          templateId: template.id!,
        ),
      );
      await courses.createCourse(
        Course(name: '语文', teacherName: '王老师', classIds: <int>[classId]),
      );
      final course = (await courses.listCourses(classId: classId)).first;
      final lesson1 = await lessons.addLesson(
        Lesson(
          courseId: course.id!,
          classId: classId,
          teacherId: 1,
          weekday: 1,
          periodIndex: 1,
        ),
      );
      final lesson2 = await lessons.addLesson(
        Lesson(
          courseId: course.id!,
          classId: classId,
          teacherId: 1,
          weekday: 1,
          periodIndex: 2,
        ),
      );
      final studentId = await students.createStudent(
        Student(name: '赵六', classId: classId),
      );

      await attendance.upsert(
        AttendanceRecord(
          studentId: studentId,
          lessonId: lesson1,
          date: '2026-09-14',
          status: AttendanceStatus.absent,
        ),
      );
      await attendance.upsert(
        AttendanceRecord(
          studentId: studentId,
          lessonId: lesson2,
          date: '2026-09-14',
          status: AttendanceStatus.present,
        ),
      );

      final first = await attendance.forLessonDate(lesson1, '2026-09-14');
      final second = await attendance.forLessonDate(lesson2, '2026-09-14');
      expect(first.single.status, AttendanceStatus.absent);
      expect(second.single.status, AttendanceStatus.present);
    });

    test('同一条记录重复写入按唯一键覆盖（UPSERT）', () async {
      final template = (await templates.listTemplates()).first;
      final classId = await classes.createClass(
        ClassInfo(
          name: '高一(3)班',
          grade: '高一',
          color: '#2196F3',
          templateId: template.id!,
        ),
      );
      await courses.createCourse(
        Course(name: '语文', teacherName: '王老师', classIds: <int>[classId]),
      );
      final course = (await courses.listCourses(classId: classId)).first;
      final lessonId = await lessons.addLesson(
        Lesson(
          courseId: course.id!,
          classId: classId,
          teacherId: 1,
          weekday: 1,
          periodIndex: 1,
        ),
      );
      final studentId = await students.createStudent(
        Student(name: '赵六', classId: classId),
      );

      await attendance.upsert(
        AttendanceRecord(
          studentId: studentId,
          lessonId: lessonId,
          date: '2026-09-14',
          status: AttendanceStatus.present,
        ),
      );
      await attendance.upsert(
        AttendanceRecord(
          studentId: studentId,
          lessonId: lessonId,
          date: '2026-09-14',
          status: AttendanceStatus.late,
        ),
      );

      final rows = await attendance.forLessonDate(lessonId, '2026-09-14');
      expect(rows.length, 1);
      expect(rows.single.status, AttendanceStatus.late);
    });

    test('按时间范围统计各状态次数（高风险检测口径）', () async {
      final template = (await templates.listTemplates()).first;
      final classId = await classes.createClass(
        ClassInfo(
          name: '高一(3)班',
          grade: '高一',
          color: '#2196F3',
          templateId: template.id!,
        ),
      );
      await courses.createCourse(
        Course(name: '语文', teacherName: '王老师', classIds: <int>[classId]),
      );
      final course = (await courses.listCourses(classId: classId)).first;
      final studentId = await students.createStudent(
        Student(name: '孙七', classId: classId),
      );

      for (var i = 1; i <= 4; i++) {
        final lessonId = await lessons.addLesson(
          Lesson(
            courseId: course.id!,
            classId: classId,
            teacherId: 1,
            weekday: i,
            periodIndex: i,
          ),
        );
        await attendance.upsert(
          AttendanceRecord(
            studentId: studentId,
            lessonId: lessonId,
            date: '2026-09-0$i',
            status: i <= 3 ? AttendanceStatus.absent : AttendanceStatus.late,
          ),
        );
      }

      final counts = await attendance.statusCountsForStudent(
        studentId,
        fromDate: '2026-09-01',
        toDate: '2026-09-30',
      );
      expect(counts['absent'], 3);
      expect(counts['late'], 1);
      // 达到默认阈值即为高风险
      expect(
        (counts['absent'] ?? 0) >= AppConstants.riskAbsenceThreshold,
        isTrue,
      );
    });

    test('超期考勤记录可清理', () async {
      final template = (await templates.listTemplates()).first;
      final classId = await classes.createClass(
        ClassInfo(
          name: '高一(3)班',
          grade: '高一',
          color: '#2196F3',
          templateId: template.id!,
        ),
      );
      await courses.createCourse(
        Course(name: '语文', teacherName: '王老师', classIds: <int>[classId]),
      );
      final course = (await courses.listCourses(classId: classId)).first;
      final lessonId = await lessons.addLesson(
        Lesson(
          courseId: course.id!,
          classId: classId,
          teacherId: 1,
          weekday: 1,
          periodIndex: 1,
        ),
      );
      final studentId = await students.createStudent(
        Student(name: '周八', classId: classId),
      );
      await attendance.upsert(
        AttendanceRecord(
          studentId: studentId,
          lessonId: lessonId,
          date: '2025-01-01',
          status: AttendanceStatus.present,
        ),
      );
      await attendance.upsert(
        AttendanceRecord(
          studentId: studentId,
          lessonId: lessonId,
          date: '2026-09-14',
          status: AttendanceStatus.present,
        ),
      );
      final removed = await attendance.deleteBefore('2026-01-01');
      expect(removed, 1);
    });

    test('标记考勤时把课程 / 班级 / 节次快照一起落库', () async {
      final template = (await templates.listTemplates()).first;
      final classId = await classes.createClass(
        ClassInfo(
          name: '高一(3)班',
          grade: '高一',
          color: '#2196F3',
          templateId: template.id!,
        ),
      );
      await courses.createCourse(
        Course(name: '语文', teacherName: '王老师', classIds: <int>[classId]),
      );
      final course = (await courses.listCourses(classId: classId)).first;
      final lessonId = await lessons.addLesson(
        Lesson(
          courseId: course.id!,
          classId: classId,
          teacherId: 1,
          weekday: 1,
          periodIndex: 1,
        ),
      );
      final studentId = await students.createStudent(
        Student(name: '赵六', classId: classId),
      );
      final withTime = (await lessons.queryWithTime(
        teacherId: 1,
        weekday: 1,
      )).single;

      await attendance.mark(
        lesson: withTime,
        studentId: studentId,
        date: '2026-09-14',
        status: AttendanceStatus.absent,
      );

      final record = (await attendance.forLessonDate(
        lessonId,
        '2026-09-14',
      )).single;
      expect(record.courseName, '语文');
      expect(record.className, '高一(3)班');
      expect(record.weekday, 1);
      expect(record.periodIndex, 1);
      expect(record.startTime, isNotNull);
      expect(record.endTime, isNotNull);
      expect(record.recordedAt, isNotNull);
    });

    test('课表条目被删除后，历史考勤仍然保留（lesson_id 置空 + 快照可读）', () async {
      final template = (await templates.listTemplates()).first;
      final classId = await classes.createClass(
        ClassInfo(
          name: '高一(3)班',
          grade: '高一',
          color: '#2196F3',
          templateId: template.id!,
        ),
      );
      await courses.createCourse(
        Course(name: '语文', teacherName: '王老师', classIds: <int>[classId]),
      );
      final course = (await courses.listCourses(classId: classId)).first;
      final lessonId = await lessons.addLesson(
        Lesson(
          courseId: course.id!,
          classId: classId,
          teacherId: 1,
          weekday: 1,
          periodIndex: 1,
        ),
      );
      final studentId = await students.createStudent(
        Student(name: '赵六', classId: classId),
      );
      final withTime = (await lessons.queryWithTime(
        teacherId: 1,
        weekday: 1,
      )).single;
      await attendance.mark(
        lesson: withTime,
        studentId: studentId,
        date: '2026-09-14',
        status: AttendanceStatus.absent,
      );

      // 老师把这一格移出课表 / 删掉了这门课
      await db.delete(
        'lesson',
        where: 'id = ?',
        whereArgs: <Object?>[lessonId],
      );

      final kept = await db.query('attendance_record');
      expect(kept.length, 1, reason: '用户规格：考勤信息要长期保存，不能随课表条目一起消失');
      expect(kept.single['lesson_id'], isNull);
      expect(kept.single['course_name'], '语文');

      // 异常明细（模块三 3.3）也要能读到这条孤儿记录
      final abnormal = await attendance.abnormalDetails(
        fromDate: '2026-09-01',
        toDate: '2026-09-30',
      );
      expect(abnormal.length, 1);
      expect(abnormal.single['student_name'], '赵六');
      expect(abnormal.single['course_name'], '语文');
      expect(abnormal.single['class_name'], '高一(3)班');
    });

    test('重复点名只刷新更新时间，首次标记时间不被覆盖', () async {
      final template = (await templates.listTemplates()).first;
      final classId = await classes.createClass(
        ClassInfo(
          name: '高一(3)班',
          grade: '高一',
          color: '#2196F3',
          templateId: template.id!,
        ),
      );
      await courses.createCourse(
        Course(name: '语文', teacherName: '王老师', classIds: <int>[classId]),
      );
      final course = (await courses.listCourses(classId: classId)).first;
      final lessonId = await lessons.addLesson(
        Lesson(
          courseId: course.id!,
          classId: classId,
          teacherId: 1,
          weekday: 1,
          periodIndex: 1,
        ),
      );
      final studentId = await students.createStudent(
        Student(name: '赵六', classId: classId),
      );

      await attendance.upsert(
        AttendanceRecord(
          studentId: studentId,
          lessonId: lessonId,
          date: '2026-09-14',
          status: AttendanceStatus.present,
          recordedAt: 1000,
          updatedAt: 1000,
        ),
      );
      await attendance.upsert(
        AttendanceRecord(
          studentId: studentId,
          lessonId: lessonId,
          date: '2026-09-14',
          status: AttendanceStatus.late,
          recordedAt: 2000,
          updatedAt: 2000,
        ),
      );

      final rows = await attendance.forLessonDate(lessonId, '2026-09-14');
      expect(rows.length, 1, reason: '唯一键仍然是 (student, lesson, date)');
      expect(rows.single.status, AttendanceStatus.late);
      expect(rows.single.recordedAt, 1000, reason: '首次标记时间不能被后来的点名冲掉');
      expect(rows.single.updatedAt, 2000);
    });
  });

  group('合班课名单与每日考勤概览（日历圆环）', () {
    /// 造一门挂在两个班上的合班课：班 A 两人、班 B 一人。
    Future<(int, List<Student>)> seedSharedCourse() async {
      final template = (await templates.listTemplates()).first;
      final classA = await classes.createClass(
        ClassInfo(
          name: '高一(1)班',
          grade: '高一',
          color: '#26A69A',
          templateId: template.id!,
        ),
      );
      final classB = await classes.createClass(
        ClassInfo(
          name: '高一(2)班',
          grade: '高一',
          color: '#2196F3',
          templateId: template.id!,
        ),
      );
      final courseId = await courses.createCourse(
        Course(name: '音乐', teacherName: '李老师', classIds: <int>[classA, classB]),
      );
      await lessons.addLesson(
        Lesson(
          courseId: courseId,
          classId: classA,
          teacherId: 1,
          weekday: 1,
          periodIndex: 1,
        ),
      );
      await students.insertMany(<Student>[
        Student(name: '陈一', classId: classA),
        Student(name: '陈二', classId: classA),
        Student(name: '陈三', classId: classB),
      ]);
      // insertMany 只回条数，名单按落库结果再读一次（也顺便验证了排序口径）
      final roster = await students.listByClasses(<int>[classA, classB]);
      return (courseId, roster);
    }

    test('去点名的名单是这门课**全部班级**的并集', () async {
      final (courseId, roster) = await seedSharedCourse();

      final classIds = await courses.classIdsOfCourse(courseId);
      expect(classIds.length, 2, reason: '课程管理里挂了两条班级');

      expect(roster.map((item) => item.name).toList(), <String>[
        '陈一',
        '陈二',
        '陈三',
      ], reason: '两个班的学生都要出现，按班级再按 id 排');

      // 只取 lesson.class_id（旧实现）会漏掉另一个班 —— 这正是本轮的 bug
      final onlyFirst = await students.listByClass(classIds.first);
      expect(onlyFirst.length, lessThan(roster.length));
    });

    test('应点名人次按课程全部班级累加，出勤率按人次算', () async {
      final (courseId, roster) = await seedSharedCourse();
      // 2026-09-21 是周一，正好对上这门课的 weekday
      const date = '2026-09-21';
      final withTime = (await lessons.queryWithTime(
        teacherId: 1,
        weekday: 1,
      )).single;

      var stats = await attendance.dayStats(
        fromDate: date,
        toDate: date,
        teacherId: 1,
      );
      expect(stats[date], isNotNull);
      expect(stats[date]!.hasLesson, isTrue);
      expect(stats[date]!.expected, 3, reason: '合班课要算两个班的人');
      expect(stats[date]!.marked, 0);
      expect(stats[date]!.hasRecord, isFalse);

      await attendance.mark(
        lesson: withTime,
        studentId: roster[0].id!,
        date: date,
        status: AttendanceStatus.present,
      );
      await attendance.mark(
        lesson: withTime,
        studentId: roster[1].id!,
        date: date,
        status: AttendanceStatus.present,
      );
      await attendance.mark(
        lesson: withTime,
        studentId: roster[2].id!,
        date: date,
        status: AttendanceStatus.absent,
      );

      stats = await attendance.dayStats(
        fromDate: date,
        toDate: date,
        teacherId: 1,
      );
      expect(stats[date]!.marked, 3);
      expect(stats[date]!.present, 2);
      expect(stats[date]!.rate, closeTo(2 / 3, 1e-9));

      // 同一天的另一门课没有排课，就不该出现在统计里
      expect(stats['2026-09-22'], isNull, reason: '没课没记录的日子不进 map');
      expect(courseId, greaterThan(0));
    });

    test('区间的每一天都按各自的星期几取应点名人次', () async {
      await seedSharedCourse();
      final stats = await attendance.dayStats(
        fromDate: '2026-09-21',
        toDate: '2026-09-27',
        teacherId: 1,
      );
      expect(stats.keys, contains('2026-09-21'));
      expect(
        stats.keys.any((key) => key.startsWith('2026-09-26')),
        isFalse,
        reason: '周六没有排课，不该有标记',
      );
    });

    test('调休日按覆盖后的星期几取应点名人次：周六上星期一的课', () async {
      await seedSharedCourse();
      // 2026-10-10 是周六，也是国务院排的调休上班日
      const makeup = '2026-10-10';

      // 不传映射：那天算「周六的课」，而周六本来就没排课 → 日历上一个标记都没有
      final plain = await attendance.dayStats(
        fromDate: makeup,
        toDate: makeup,
        teacherId: 1,
      );
      expect(plain[makeup], isNull, reason: '周六本来就没排课');

      // 传了映射（上周一的课）：必须按周一那门课的人数算 ——
      // 否则调休日明明要上课，圆环反而是个空圈，和当天真实要点的名对不上
      final shifted = await attendance.dayStats(
        fromDate: makeup,
        toDate: makeup,
        teacherId: 1,
        weekdayOverrides: const <String, int>{makeup: 1},
      );
      expect(shifted[makeup], isNotNull);
      expect(shifted[makeup]!.hasLesson, isTrue);
      expect(shifted[makeup]!.expected, 3, reason: '合班课，两个班共 3 人');
    });
  });

  group('课程级长期状态：休学 / 免修（点一次管 180 天）', () {
    /// 造一门课 + 一名学生。
    Future<(int courseId, int studentId)> seedCourseAndStudent() async {
      final template = (await templates.listTemplates()).first;
      final classId = await classes.createClass(
        ClassInfo(
          name: '高一(6)班',
          grade: '高一',
          color: '#26A69A',
          templateId: template.id!,
        ),
      );
      final courseId = await courses.createCourse(
        Course(name: '体育', teacherName: '王老师', classIds: <int>[classId]),
      );
      final studentId = await students.createStudent(
        Student(name: '张三', classId: classId),
      );
      return (courseId, studentId);
    }

    test('点一次就生效：截止日 = 起始日 + 180 天', () async {
      final (courseId, studentId) = await seedCourseAndStudent();

      final saved = await attendance.setCourseStatus(
        studentId: studentId,
        courseId: courseId,
        status: AttendanceStatus.exempt,
        startDate: '2026-09-21',
      );
      expect(saved.status, AttendanceStatus.exempt);
      expect(saved.startDate, '2026-09-21');
      // 180 天后：9/21 + 180 = 次年 3/20
      expect(saved.endDate, '2027-03-20');

      final active = await attendance.activeCourseStatuses(
        courseId: courseId,
        date: '2026-09-21',
      );
      expect(active[studentId]?.status, AttendanceStatus.exempt);
    });

    test('区间内每天都生效，区间外自动失效（不用每节课标记）', () async {
      final (courseId, studentId) = await seedCourseAndStudent();
      await attendance.setCourseStatus(
        studentId: studentId,
        courseId: courseId,
        status: AttendanceStatus.suspended,
        startDate: '2026-09-21',
      );

      // 落在区间中间的一天照样生效 —— 这就是"不用每节重复标记"的含义
      final middle = await attendance.activeCourseStatuses(
        courseId: courseId,
        date: '2026-12-01',
      );
      expect(middle[studentId]?.status, AttendanceStatus.suspended);

      // 首尾是闭区间
      final onLastDay = await attendance.activeCourseStatuses(
        courseId: courseId,
        date: '2027-03-20',
      );
      expect(onLastDay, contains(studentId));

      // 超出区间（第 181 天）就不再算长期状态了
      final expired = await attendance.activeCourseStatuses(
        courseId: courseId,
        date: '2027-03-21',
      );
      expect(expired, isEmpty);
    });

    test('同一学生同一门课只有一条：再点一次是改状态而不是叠一条', () async {
      final (courseId, studentId) = await seedCourseAndStudent();
      await attendance.setCourseStatus(
        studentId: studentId,
        courseId: courseId,
        status: AttendanceStatus.exempt,
        startDate: '2026-09-21',
      );
      await attendance.setCourseStatus(
        studentId: studentId,
        courseId: courseId,
        status: AttendanceStatus.suspended,
        startDate: '2026-10-01',
      );

      final rows = await db.query('student_course_status');
      expect(rows.length, 1, reason: '唯一键 (student_id, course_id) 不该留下两条');

      final active = await attendance.activeCourseStatuses(
        courseId: courseId,
        date: '2026-10-02',
      );
      expect(active[studentId]?.status, AttendanceStatus.suspended);
      // 起始日也跟着改成新的那次点击，而不是保留旧区间
      expect(active[studentId]?.startDate, '2026-10-01');

      // 旧区间里已经不再生效了（因为记录只有一条）
      final inOldWindow = await attendance.activeCourseStatuses(
        courseId: courseId,
        date: '2026-09-22',
      );
      expect(inOldWindow, isEmpty);
    });

    test('长期状态与别的课程互不影响', () async {
      final (courseId, studentId) = await seedCourseAndStudent();
      final template = (await templates.listTemplates()).first;
      final otherClass = await classes.createClass(
        ClassInfo(
          name: '高一(7)班',
          grade: '高一',
          color: '#2196F3',
          templateId: template.id!,
        ),
      );
      final otherCourse = await courses.createCourse(
        Course(name: '音乐', teacherName: '李老师', classIds: <int>[otherClass]),
      );

      await attendance.setCourseStatus(
        studentId: studentId,
        courseId: courseId,
        status: AttendanceStatus.suspended,
        startDate: '2026-09-21',
      );

      final other = await attendance.activeCourseStatuses(
        courseId: otherCourse,
        date: '2026-09-21',
      );
      expect(other, isEmpty, reason: '长期状态只针对被点的那门课');
    });

    test('取消后恢复：查不到、也没有残留行', () async {
      final (courseId, studentId) = await seedCourseAndStudent();
      await attendance.setCourseStatus(
        studentId: studentId,
        courseId: courseId,
        status: AttendanceStatus.exempt,
        startDate: '2026-09-21',
      );
      await attendance.clearCourseStatus(
        studentId: studentId,
        courseId: courseId,
      );

      final active = await attendance.activeCourseStatuses(
        courseId: courseId,
        date: '2026-09-21',
      );
      expect(active, isEmpty);
      expect(await attendance.courseStatusesForStudent(studentId), isEmpty);
    });

    test('日常状态不能当长期状态写（守住类型边界）', () async {
      final (courseId, studentId) = await seedCourseAndStudent();
      await expectLater(
        attendance.setCourseStatus(
          studentId: studentId,
          courseId: courseId,
          status: AttendanceStatus.absent,
          startDate: '2026-09-21',
        ),
        throwsA(isA<ValidationException>()),
      );
    });

    test('删除学生或课程时级联清理长期状态', () async {
      final (courseId, studentId) = await seedCourseAndStudent();
      await attendance.setCourseStatus(
        studentId: studentId,
        courseId: courseId,
        status: AttendanceStatus.exempt,
        startDate: '2026-09-21',
      );
      await students.deleteStudent(studentId);
      expect((await db.query('student_course_status')), isEmpty);

      // 换成删课程：同样要清干净（外键 ON DELETE CASCADE）
      final (courseId2, studentId2) = await seedCourseAndStudent();
      await attendance.setCourseStatus(
        studentId: studentId2,
        courseId: courseId2,
        status: AttendanceStatus.suspended,
        startDate: '2026-09-21',
      );
      await courses.deleteCourse(courseId2);
      expect((await db.query('student_course_status')), isEmpty);
    });
  });

  group('设置 KV', () {
    test('读写与默认值', () async {
      expect(
        await settings.read('missing_key', fallback: 'fallback'),
        'fallback',
      );
      await settings.write('theme', 'nightCare');
      expect(await settings.read('theme'), 'nightCare');
    });

    test('整型/浮点/布尔读写', () async {
      await settings.writeInt('risk_absence_threshold', 5);
      expect(await settings.readInt('risk_absence_threshold'), 5);
      await settings.writeDouble('attendance_warn_rate', 92.5);
      expect(await settings.readDouble('attendance_warn_rate'), 92.5);
      await settings.writeBool('cascade_enabled', true);
      expect(await settings.readBool('cascade_enabled'), isTrue);
    });
  });
}
