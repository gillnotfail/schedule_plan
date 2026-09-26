import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:schedule_plan/core/constants/app_constants.dart';
import 'package:schedule_plan/data/db/schema.dart';
import 'package:schedule_plan/data/models/class_course.dart';
import 'package:schedule_plan/data/models/course_detail.dart';
import 'package:schedule_plan/data/models/student.dart';
import 'package:schedule_plan/data/repositories/class_repository.dart';
import 'package:schedule_plan/data/repositories/course_repository.dart';
import 'package:schedule_plan/data/repositories/lesson_repository.dart';
import 'package:schedule_plan/data/repositories/student_repository.dart';
import 'package:schedule_plan/data/repositories/template_repository.dart';

/// 本轮反馈对应的回归测试：
///
/// 1. **一键生成作息权限最大**——选了周一~周五，课表就该只剩 5 列。
///    早期版本只删选中的那天、不碰其余天，于是"先选 7 天再改回 5 天"永远停在 7 天。
/// 2. **课程标记色**——可以给课程单独挑颜色，挑了就优先于班级色。
/// 3. **v2 -> v3 迁移**——老库的 course 表补上 color 列，原有课程不能丢。
/// 4. **提醒时长 2 秒**。
/// 5. **课表页课程不按班级过滤**——只要课程管理里有课，点格子就该能滑动选课。
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

  setUp(() async {
    db = await _openMemoryDb();
    templates = TemplateRepository(database: db);
    classes = ClassRepository(database: db);
    courses = CourseRepository(database: db);
  });

  tearDown(() async {
    await db.close();
  });

  group('一键生成作息跟随最近一次选择', () {
    /// 生成后返回「模板里有节次的星期」。
    Future<List<int>> daysWithPeriods(int templateId) async {
      final all = await templates.allPeriods(templateId);
      return all.map((item) => item.weekday).toSet().toList()..sort();
    }

    test('先选周1~周日，再改回周1~周五，只剩 5 天', () async {
      final templateId = (await templates.listTemplates()).first.id!;

      await templates.generatePeriods(
        templateId: templateId,
        weekdays: <int>[1, 2, 3, 4, 5, 6, 7],
        startTime: '08:00',
        lessonMinutes: 40,
        breakMinutes: 10,
        periodCount: 8,
        clearUnselected: true,
      );
      expect(await daysWithPeriods(templateId), <int>[1, 2, 3, 4, 5, 6, 7]);

      await templates.generatePeriods(
        templateId: templateId,
        weekdays: <int>[1, 2, 3, 4, 5],
        startTime: '08:00',
        lessonMinutes: 40,
        breakMinutes: 10,
        periodCount: 8,
        clearUnselected: true,
      );

      // 用户报的 bug：这里以前还是 7 天
      expect(await daysWithPeriods(templateId), <int>[1, 2, 3, 4, 5]);
      expect(await templates.periodsForWeekday(templateId, 6), isEmpty);
      expect(await templates.periodsForWeekday(templateId, 7), isEmpty);
      expect(
        (await templates.periodsForWeekday(templateId, 1)).length,
        8,
      );
    });

    test('不带 clearUnselected 时不动其他星期（既有调用方行为不变）', () async {
      final templateId = (await templates.listTemplates()).first.id!;

      // 出厂种子只有周一到周五；单独给周六补一份只影响周六
      await templates.ensureDefaultWeekday(templateId, 6);
      expect(await daysWithPeriods(templateId), <int>[1, 2, 3, 4, 5, 6]);

      await templates.generatePeriods(
        templateId: templateId,
        weekdays: <int>[3],
        startTime: '09:00',
        lessonMinutes: 45,
        breakMinutes: 5,
        periodCount: 4,
      );

      final wednesday = await templates.periodsForWeekday(templateId, 3);
      expect(wednesday.length, 4);
      expect(wednesday.first.startTime, '09:00');
      // 周六那份还在
      expect(await templates.periodsForWeekday(templateId, 6), isNotEmpty);
    });

    test('清空未选中的星期不会动课表内容（lesson 只归「一键清空课表」管）', () async {
      final templateId = (await templates.listTemplates()).first.id!;
      final classId = await classes.createClass(
        ClassInfo(
          name: '高一(1)班',
          grade: '高一',
          color: 'FF26A69A',
          templateId: templateId,
        ),
      );
      final courseId = await courses.createCourse(
        Course(name: '语文', teacherName: '王老师', classIds: <int>[classId]),
      );
      await db.insert('lesson', <String, Object?>{
        'course_id': courseId,
        'class_id': classId,
        'teacher_id': AppConstants.currentTeacherId,
        'weekday': 6,
        'period_index': 1,
      });

      await templates.generatePeriods(
        templateId: templateId,
        weekdays: <int>[1, 2, 3, 4, 5],
        startTime: '08:00',
        lessonMinutes: 40,
        breakMinutes: 10,
        periodCount: 8,
        clearUnselected: true,
      );

      final lessons = await db.query('lesson');
      expect(lessons.length, 1, reason: '作息生成不应该删掉排课内容');
    });
  });

  group('课程标记色', () {
    late int classId;

    setUp(() async {
      final templateId = (await templates.listTemplates()).first.id!;
      classId = await classes.createClass(
        ClassInfo(
          name: '高一(1)班',
          grade: '高一',
          color: 'FF26A69A',
          templateId: templateId,
        ),
      );
    });

    test('课程挑过颜色就用课程色，没挑过回落班级色', () async {
      final ownId = await courses.createCourse(
        Course(
          name: '数学',
          teacherName: '李老师',
          classIds: <int>[classId],
          color: 'FFE53935',
        ),
      );
      final plainId = await courses.createCourse(
        Course(name: '语文', teacherName: '王老师', classIds: <int>[classId]),
      );

      final all = await courses.listCourses();
      final classList = await classes.listClasses();
      final own = CourseDetail.from(
        all.firstWhere((item) => item.id == ownId),
        classList,
      );
      final plain = CourseDetail.from(
        all.firstWhere((item) => item.id == plainId),
        classList,
      );

      expect(own.color, 'FFE53935');
      expect(own.hasOwnColor, isTrue);
      expect(plain.color, 'FF26A69A', reason: '没挑过颜色时应回落成班级色');
      expect(plain.hasOwnColor, isFalse);
    });

    test('颜色随课程一起落库（重开连接后仍在）', () async {
      final id = await courses.createCourse(
        Course(
          name: '英语',
          teacherName: '张老师',
          classIds: <int>[classId],
          color: 'FF5C6BC0',
        ),
      );

      // 换一个仓储实例读同一个库，等价于"退出重开"
      final reopened = CourseRepository(database: db);
      final course = await reopened.getCourse(id);
      expect(course?.color, 'FF5C6BC0');
    });

    test('改动颜色后能保存并清回跟随班级色', () async {
      final id = await courses.createCourse(
        Course(
          name: '物理',
          teacherName: '赵老师',
          classIds: <int>[classId],
          color: 'FF0288D1',
        ),
      );
      var course = (await courses.getCourse(id))!;
      await courses.updateCourse(
        Course(
          id: id,
          name: course.name,
          teacherName: course.teacherName,
          classIds: course.classIds,
          color: 'FF43A047',
        ),
      );
      expect((await courses.getCourse(id))?.color, 'FF43A047');

      await courses.updateCourse(
        Course(
          id: id,
          name: course.name,
          teacherName: course.teacherName,
          classIds: course.classIds,
        ),
      );
      expect((await courses.getCourse(id))?.color, isNull);
    });
  });

  group('课表页课程不再按班级过滤', () {
    // 回归用户反馈："回到课表页，点击对应的单元格，还是提示去添加课程"。
    // 根因就是候选课程按"当前选中班级"过滤：老师在课程管理里给别的班建的课，
    // 课表页查不到 → 又被当成"一门课都没有"。
    late int classA;
    late int classB;

    setUp(() async {
      final templateId = (await templates.listTemplates()).first.id!;
      classA = await classes.createClass(
        ClassInfo(
          name: '高一(1)班',
          grade: '高一',
          color: 'FF26A69A',
          templateId: templateId,
        ),
      );
      classB = await classes.createClass(
        ClassInfo(
          name: '高一(2)班',
          grade: '高一',
          color: 'FF5C6BC0',
          templateId: templateId,
        ),
      );
      await courses.createCourse(
        Course(name: '数学', teacherName: '李老师', classIds: <int>[classB]),
      );
    });

    test('listCourses() 不带 classId 时返回全库课程（含别的班的课）', () async {
      final all = await courses.listCourses();
      expect(
        all.map((item) => item.name),
        contains('数学'),
        reason: '课表页要能选到课程管理里"任何一个班"的课',
      );
      // 对照：按班级过滤确实拿不到（这正是旧版课表页踩的坑）
      expect(await courses.listCourses(classId: classA), isEmpty);
    });

    test('排课落到课程自己挂载的班级，而不是课表兜底班级', () async {
      final collected = await courses.listCourses();
      final detail = CourseDetail.from(
        collected.firstWhere((item) => item.name == '数学'),
        await classes.listClasses(),
      );
      expect(detail.primaryClassIdOrNull, classB);

      final lessons = LessonRepository(database: db);
      await lessons.placeLesson(
        courseId: detail.id!,
        classId: detail.primaryClassIdOrNull!,
        weekday: 1,
        periodIndex: 1,
      );
      final placed = await lessons.forClass(classB);
      expect(placed, hasLength(1));
      expect(placed.first.courseName, '数学');
      expect(await lessons.forClass(classA), isEmpty);
    });
  });

  group('导入去重的判定口径', () {
    test('同一班级的同名学生视为重复；不同班级不算', () {
      expect(
        StudentRepository.rosterKey(3, '张三'),
        StudentRepository.rosterKey(3, ' 张三 '),
        reason: '首尾空格不应造成"同一个人两条记录"',
      );
      expect(
        StudentRepository.rosterKey(3, '张三'),
        isNot(StudentRepository.rosterKey(4, '张三')),
      );
    });

    test('existingRosterKeys 覆盖全库已有学生（导入前拿它拦重复行）', () async {
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
      final students = StudentRepository(database: db);
      await students.insertMany(<Student>[
        Student(name: '张三', classId: classA),
        Student(name: '李四', classId: classA),
        Student(name: '张三', classId: classB),
      ]);

      final keys = await students.existingRosterKeys();
      expect(keys.length, 3);
      expect(keys.contains(StudentRepository.rosterKey(classA, '张三')), isTrue);
      expect(keys.contains(StudentRepository.rosterKey(classB, '张三')), isTrue);
      expect(keys.contains(StudentRepository.rosterKey(classB, '李四')), isFalse);
    });
  });

  group('v2 -> v3 迁移', () {
    /// v2 的 course 表：没有 color 列。
    const String v2CourseTable = '''
    CREATE TABLE IF NOT EXISTS course (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      teacher_name TEXT NOT NULL,
      class_id INTEGER REFERENCES class(id) ON DELETE SET NULL,
      description TEXT,
      room TEXT
    )
    ''';

    test('老库补上 color 列，原有课程不丢', () async {
      final dir = await Directory.systemTemp.createTemp('schedule_plan_migrate');
      final path = p.join(dir.path, 'legacy.db');
      try {
        // 1) 造一个 v2 的库：其余表用当前建表语句，course 用 v2 结构
        final legacy = await databaseFactory.openDatabase(
          path,
          options: OpenDatabaseOptions(
            version: 2,
            singleInstance: false,
            onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
            onCreate: (db, _) async {
              for (final statement in DatabaseSchema.createTables) {
                if (statement.contains('CREATE TABLE IF NOT EXISTS course (')) {
                  continue;
                }
                await db.execute(statement);
              }
              await db.execute(v2CourseTable);
            },
          ),
        );
        // 手写 onCreate 不走 _seedDefaults，这里补一条模板满足 class 的外键
        final templateId = await legacy.insert('schedule_template', <String, Object?>{
          'name': '默认作息',
          'is_default': 1,
          'created_at': 0,
          'updated_at': 0,
        });
        final classId = await legacy.insert('class', <String, Object?>{
          'name': '高一(1)班',
          'grade': '高一',
          'student_count': 0,
          'color': 'FF26A69A',
          'template_id': templateId,
          'sort_order': 0,
        });
        await legacy.insert('course', <String, Object?>{
          'name': '语文',
          'teacher_name': '王老师',
          'class_id': classId,
          'room': '101',
        });
        final before = await legacy.query('course');
        expect(before.first.containsKey('color'), isFalse);
        await legacy.close();

        // 2) 按当前版本重新打开 → 触发 onUpgrade(v2 -> v3)
        final upgraded = await databaseFactory.openDatabase(
          path,
          options: OpenDatabaseOptions(
            version: DatabaseSchema.version,
            singleInstance: false,
            onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
            onUpgrade: (db, from, to) => DatabaseSchema.migrate(db, from, to),
          ),
        );
        try {
          final columns = await upgraded.rawQuery('PRAGMA table_info(course)');
          expect(
            columns.any((row) => row['name'] == 'color'),
            isTrue,
            reason: 'v2 -> v3 必须给 course 补上 color 列',
          );
          final after = await upgraded.query('course');
          expect(after.length, 1, reason: '迁移不能丢课程数据');
          expect(after.first['name'], '语文');
          expect(after.first['room'], '101');
          expect(after.first['color'], isNull, reason: '老课程默认跟随班级色');
        } finally {
          await upgraded.close();
        }
      } finally {
        // 临时目录清理失败不影响用例结论
        // （Windows 上文件句柄偶尔还没释放，删不掉就算了，系统会自己清临时目录）
        try {
          await dir.delete(recursive: true);
        } on FileSystemException {
          // ignore: 目录清理不是本用例的验证目标
        }
      }
    });
  });

  group('v3 -> v4 迁移（考勤记录长期保存）', () {
    /// v3 的 attendance_record：lesson_id 是 `NOT NULL ... ON DELETE CASCADE`，
    /// 也没有任何快照列 —— 就是这个外键让"删一门课 = 抹掉一学期考勤"。
    const String v3AttendanceTable = '''
    CREATE TABLE IF NOT EXISTS attendance_record (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      student_id INTEGER NOT NULL REFERENCES student(id) ON DELETE CASCADE,
      lesson_id INTEGER NOT NULL REFERENCES lesson(id) ON DELETE CASCADE,
      date TEXT NOT NULL,
      status TEXT NOT NULL,
      note TEXT,
      UNIQUE(student_id, lesson_id, date)
    )
    ''';

    Future<Database> upgradeFromV3(File file, {required bool seed}) async {
      final legacy = await databaseFactory.openDatabase(
        file.path,
        options: OpenDatabaseOptions(
          version: 3,
          singleInstance: false,
          onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
          onCreate: (db, _) async {
            for (final statement in DatabaseSchema.createTables) {
              if (statement.contains('attendance_record (')) {
                continue;
              }
              await db.execute(statement);
            }
            await db.execute(v3AttendanceTable);
            for (final statement in DatabaseSchema.createIndexes) {
              // 索引里有两处引用 attendance_record 的新列，v3 的老表没有
              if (statement.contains('attendance_record')) {
                continue;
              }
              await db.execute(statement);
            }
          },
        ),
      );
      if (!seed) {
        return legacy;
      }
      final templateId =
          await legacy.insert('schedule_template', <String, Object?>{
        'name': '默认作息',
        'is_default': 1,
        'created_at': 0,
        'updated_at': 0,
      });
      await legacy.insert('template_period', <String, Object?>{
        'template_id': templateId,
        'weekday': 1,
        'period_index': 1,
        'period_type': 'normal',
        'start_time': '08:00',
        'end_time': '08:40',
      });
      final classId = await legacy.insert('class', <String, Object?>{
        'name': '高一(1)班',
        'grade': '高一',
        'student_count': 1,
        'color': 'FF26A69A',
        'template_id': templateId,
        'sort_order': 0,
      });
      final courseId = await legacy.insert('course', <String, Object?>{
        'name': '语文',
        'teacher_name': '王老师',
        'class_id': classId,
        'room': '101',
        'color': null,
      });
      final lessonId = await legacy.insert('lesson', <String, Object?>{
        'course_id': courseId,
        'class_id': classId,
        'teacher_id': AppConstants.currentTeacherId,
        'weekday': 1,
        'period_index': 1,
      });
      final studentId = await legacy.insert('student', <String, Object?>{
        'name': '张三',
        'student_no': '01',
        'gender': 'male',
        'class_id': classId,
      });
      await legacy.insert('attendance_record', <String, Object?>{
        'student_id': studentId,
        'lesson_id': lessonId,
        'date': '2026-09-14',
        'status': 'absent',
        'note': null,
      });
      return legacy;
    }

    test('老库重建表：记录一条不丢，快照列按现有课表回填', () async {
      final dir = await Directory.systemTemp.createTemp('schedule_plan_v4');
      final file = File(p.join(dir.path, 'legacy_v3.db'));
      try {
        final legacy = await upgradeFromV3(file, seed: true);
        final beforeColumns =
            await legacy.rawQuery('PRAGMA table_info(attendance_record)');
        expect(
          beforeColumns.any((row) => row['name'] == 'recorded_at'),
          isFalse,
          reason: 'v3 的老表不该有快照列，否则这个用例没意义',
        );
        await legacy.close();

        final upgraded = await databaseFactory.openDatabase(
          file.path,
          options: OpenDatabaseOptions(
            version: DatabaseSchema.version,
            singleInstance: false,
            onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
            onUpgrade: (db, from, to) => DatabaseSchema.migrate(db, from, to),
          ),
        );
        try {
          final columns = await upgraded.rawQuery(
            'PRAGMA table_info(attendance_record)',
          );
          for (final name in <String>[
            'class_id',
            'course_id',
            'weekday',
            'period_index',
            'start_time',
            'end_time',
            'course_name',
            'class_name',
            'recorded_at',
            'updated_at',
          ]) {
            expect(
              columns.any((row) => row['name'] == name),
              isTrue,
              reason: 'v3 -> v4 必须补上 $name',
            );
          }

          final rows = await upgraded.query('attendance_record');
          expect(rows.length, 1, reason: '迁移不能丢历史考勤');
          final row = rows.single;
          expect(row['status'], 'absent');
          expect(row['date'], '2026-09-14');
          expect(row['course_name'], '语文', reason: '课程名要按现有课表回填');
          expect(row['class_name'], '高一(1)班');
          expect(row['weekday'], 1);
          expect(row['period_index'], 1);
          expect(row['start_time'], '08:00', reason: '起止时间要按作息回填');
          expect(row['end_time'], '08:40');
          expect(row['recorded_at'], isNotNull);
          expect(row['updated_at'], isNotNull);

          // 关键回归：删掉课表条目之后，历史考勤必须还在
          await upgraded.delete('lesson');
          final kept = await upgraded.query('attendance_record');
          expect(
            kept.length,
            1,
            reason: '用户规格：考勤信息要"放好久"，不能随课表条目被删而消失',
          );
          expect(kept.single['lesson_id'], isNull);
          expect(kept.single['course_name'], '语文', reason: '快照要能独立读懂这条记录');

          final fkIssues = await upgraded.rawQuery('PRAGMA foreign_key_check');
          expect(fkIssues, isEmpty);
        } finally {
          await upgraded.close();
        }
      } finally {
        try {
          await dir.delete(recursive: true);
        } on FileSystemException {
          // ignore: 目录清理不是本用例的验证目标
        }
      }
    });
  });

  group('v4 -> v5 迁移（课程级长期状态：休学 / 免修）', () {
    /// 模拟一个 v4 库：v4 还没有 `student_course_status` 这张表。
    Future<Database> upgradeFromV4(File file) async {
      return databaseFactory.openDatabase(
        file.path,
        options: OpenDatabaseOptions(
          version: 4,
          singleInstance: false,
          onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
          onCreate: (db, _) async {
            for (final statement in DatabaseSchema.createTables) {
              if (statement.contains('student_course_status')) {
                continue;
              }
              await db.execute(statement);
            }
            for (final statement in DatabaseSchema.createIndexes) {
              if (statement.contains('student_course_status')) {
                continue;
              }
              await db.execute(statement);
            }
          },
        ),
      );
    }

    test('纯加表：老库补上长期状态表与索引，其余数据一条不动', () async {
      final dir = await Directory.systemTemp.createTemp('schedule_plan_v5');
      final file = File(p.join(dir.path, 'legacy_v4.db'));
      try {
        final legacy = await upgradeFromV4(file);
        final templateId =
            await legacy.insert('schedule_template', <String, Object?>{
          'name': '默认作息',
          'is_default': 1,
          'created_at': 0,
          'updated_at': 0,
        });
        final classId = await legacy.insert('class', <String, Object?>{
          'name': '高一(1)班',
          'grade': '高一',
          'student_count': 1,
          'color': 'FF26A69A',
          'template_id': templateId,
          'sort_order': 0,
        });
        await legacy.insert('student', <String, Object?>{
          'name': '张三',
          'student_no': '01',
          'gender': 'male',
          'class_id': classId,
        });
        await legacy.close();

        final upgraded = await databaseFactory.openDatabase(
          file.path,
          options: OpenDatabaseOptions(
            version: DatabaseSchema.version,
            singleInstance: false,
            onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
            onUpgrade: (db, from, to) => DatabaseSchema.migrate(db, from, to),
          ),
        );
        try {
          final tables = (await upgraded.rawQuery(
            "SELECT name FROM sqlite_master WHERE type = 'table'",
          ))
              .map((row) => row['name'])
              .toList();
          expect(
            tables,
            contains('student_course_status'),
            reason: 'v4 -> v5 必须补上长期状态表',
          );

          final indexes = (await upgraded.rawQuery(
            "SELECT name FROM sqlite_master WHERE type = 'index'",
          ))
              .map((row) => row['name'])
              .toList();
          expect(indexes, contains('idx_course_status_lookup'));

          // 加表不能把老数据带走
          expect((await upgraded.query('student')).length, 1);
          expect((await upgraded.query('class')).length, 1);
          expect(await upgraded.rawQuery('PRAGMA foreign_key_check'), isEmpty);

          // 迁移脚本必须可重复执行（IF NOT EXISTS）
          await DatabaseSchema.migrate(upgraded, 4, 5);
          expect(
            (await upgraded.query('student')).length,
            1,
            reason: '重复执行迁移不该影响数据',
          );
        } finally {
          await upgraded.close();
        }
      } finally {
        try {
          await dir.delete(recursive: true);
        } on FileSystemException {
          // ignore: 目录清理不是本用例的验证目标
        }
      }
    });
  });

  group('提醒时长', () {
    test('所有 SnackBar 提醒统一 2 秒', () {
      expect(AppConstants.snackBarDuration.inSeconds, 2);
      expect(
        AppConstants.snackBarLongDuration.inSeconds,
        2,
        reason: '用户规格：不要出现过长的黑框提醒',
      );
    });
  });
}
