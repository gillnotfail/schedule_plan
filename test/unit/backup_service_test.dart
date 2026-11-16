import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:schedule_plan/core/constants/setting_keys.dart';
import 'package:schedule_plan/data/db/schema.dart';
import 'package:schedule_plan/data/services/backup_service.dart';

/// 数据备份 / 恢复（用户规格第 36 轮）。
///
/// 这组用例守的是**能不能真的把数据带回来**，不是界面：
/// - 勾「考勤记录」必须自动带上班级 / 学生 / 课程 / 课表，否则恢复时外键过不去；
/// - 备份文件必须能被自己读回来（往返一致），且运行时状态不许混进去；
/// - 恢复失败必须整份回滚——半套数据比没有更难查。

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

/// 造一套最小但完整的数据：1 个班、1 个学生、1 门课、1 节课、1 条考勤。
Future<void> _seed(Database db) async {
  await db.insert('class', <String, Object?>{
    'name': '高一(1)班',
    'grade': '高一',
    'color': '#4FA8F5',
    'template_id': 1,
  });
  await db.insert('student', <String, Object?>{
    'name': '张三',
    'student_no': '2026001',
    'gender': 'male',
    'class_id': 1,
  });
  await db.insert('course', <String, Object?>{
    'name': '数学',
    'teacher_name': '李老师',
    'class_id': 1,
  });
  await db.insert('course_class', <String, Object?>{
    'course_id': 1,
    'class_id': 1,
  });
  await db.insert('lesson', <String, Object?>{
    'course_id': 1,
    'class_id': 1,
    'teacher_id': 1,
    'weekday': 1,
    'period_index': 1,
  });
  await db.insert('attendance_record', <String, Object?>{
    'student_id': 1,
    'lesson_id': 1,
    'class_id': 1,
    'course_id': 1,
    'date': '2026-03-02',
    'weekday': 1,
    'period_index': 1,
    'start_time': '08:00',
    'end_time': '08:40',
    'course_name': '数学',
    'class_name': '高一(1)班',
    'status': 'absent',
  });
  await db.insert('student_course_status', <String, Object?>{
    'student_id': 1,
    'course_id': 1,
    'status': 'exempt',
    'start_date': '2026-03-01',
    'end_date': '2026-08-01',
  });
  await db.insert('app_settings', <String, Object?>{
    'key': SettingKeys.riskAbsenceThreshold,
    'value': '5',
  });
  // 运行时状态：备份里不该出现
  await db.insert('app_settings', <String, Object?>{
    'key': SettingKeys.updateLastCheckAt,
    'value': '1731234567890',
  });
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late BackupService service;

  setUp(() async {
    db = await _openMemoryDb();
    service = BackupService(database: db);
  });

  tearDown(() async {
    await db.close();
  });

  group('条目与依赖', () {
    test('只勾考勤：自动带上班级、学生、课程、课表', () {
      expect(
        service.resolve(<BackupSlice>[BackupSlice.attendance]),
        <BackupSlice>[
          BackupSlice.classes,
          BackupSlice.students,
          BackupSlice.courses,
          BackupSlice.timetable,
          BackupSlice.attendance,
        ],
        reason: '少任何一条，恢复时 attendance_record 的外键都会把它整段挡回去',
      );
    });

    test('只勾偏好设置：不带任何业务数据', () {
      expect(
        service.resolve(<BackupSlice>[BackupSlice.settings]),
        <BackupSlice>[BackupSlice.settings],
      );
    });

    test('全选就是全部条目，顺序稳定', () {
      expect(
        service.resolve(BackupSlice.values),
        BackupSlice.values,
      );
    });

    test('impliedBy 只返回被自动带上的，不含自己勾的', () {
      final implied = service.impliedBy(<BackupSlice>[BackupSlice.attendance]);
      expect(implied, isNot(contains(BackupSlice.attendance)));
      expect(implied, contains(BackupSlice.students));
      expect(implied, contains(BackupSlice.classes));
      expect(implied, isNot(contains(BackupSlice.settings)));
    });
  });

  group('备份内容', () {
    test('collect 把选中条目的表整份读出来', () async {
      await _seed(db);
      final bundle = await service.collect(
        <BackupSlice>[BackupSlice.attendance],
        appVersion: '1.0.17+18',
      );

      expect(bundle.countOf('student'), 1);
      expect(bundle.countOf('class'), 1);
      expect(bundle.countOf('course'), 1);
      expect(bundle.countOf('lesson'), 1);
      expect(bundle.countOf('attendance_record'), 1);
      // 班级带了作息模板，否则课表第一列没有时间
      expect(bundle.countOf('schedule_template'), 1);
      expect(bundle.countOf('template_period'), greaterThan(0));
      // 没勾的条目不该出现
      expect(bundle.tables.containsKey('student_tag_record'), isFalse);
      expect(bundle.tables.containsKey('app_settings'), isFalse);
      expect(bundle.appVersion, '1.0.17+18');
    });

    test('运行时状态不进备份，老师设的阈值要进', () async {
      await _seed(db);
      final bundle = await service.collect(<BackupSlice>[BackupSlice.settings]);
      final keys = bundle.tables['app_settings']!
          .map((row) => row['key'])
          .toSet();
      expect(keys, contains(SettingKeys.riskAbsenceThreshold));
      expect(keys, isNot(contains(SettingKeys.updateLastCheckAt)));
    });

    test('countRows 按主表算，不把作息模板的行数算进去', () async {
      await _seed(db);
      final counts = await service.countRows();
      expect(counts[BackupSlice.classes], 1);
      expect(counts[BackupSlice.students], 1);
      expect(counts[BackupSlice.attendance], 1);
      // 偏好设置只数"非运行时"的那条
      expect(counts[BackupSlice.settings], 1);
    });
  });

  group('序列化', () {
    test('encode → decode 往返一致', () async {
      await _seed(db);
      final bundle = await service.collect(BackupSlice.values);
      final restored = service.decode(service.encode(bundle));

      expect(restored.schemaVersion, DatabaseSchema.version);
      expect(restored.slices, bundle.slices);
      expect(restored.totalRows, bundle.totalRows);
      expect(restored.countOf('attendance_record'), 1);
      expect(
        restored.tables['student']!.first['name'],
        '张三',
        reason: '中文与内容都要原样回来',
      );
    });

    test('不是本应用的文件报 notBackup', () {
      expect(
        () => service.decode('{"hello": 1}'),
        throwsA(
          isA<BackupFormatException>().having(
            (e) => e.problem,
            'problem',
            BackupProblem.notBackup,
          ),
        ),
      );
      expect(
        () => service.decode('这不是 JSON'),
        throwsA(
          isA<BackupFormatException>().having(
            (e) => e.problem,
            'problem',
            BackupProblem.notBackup,
          ),
        ),
      );
    });

    test('来自更新版本的文件报 newerFormat', () {
      const raw = '{"app":"schedule_plan","format":99,"tables":{}}';
      expect(
        () => service.decode(raw),
        throwsA(
          isA<BackupFormatException>().having(
            (e) => e.problem,
            'problem',
            BackupProblem.newerFormat,
          ),
        ),
      );
    });

    test('表内容不是数组时报 broken', () {
      const raw = '{"app":"schedule_plan","format":1,"tables":{"student":3}}';
      expect(
        () => service.decode(raw),
        throwsA(
          isA<BackupFormatException>().having(
            (e) => e.problem,
            'problem',
            BackupProblem.broken,
          ),
        ),
      );
    });

    test('不认识的表跳过，不整份拒收', () {
      const raw = '{"app":"schedule_plan","format":1,'
          '"tables":{"future_table":[{"id":1}],"class":[]}}';
      final bundle = service.decode(raw);
      expect(bundle.tables.containsKey('future_table'), isFalse);
      expect(bundle.tables.containsKey('class'), isTrue);
    });

    test('老文件没写 slices 时从表名反推', () {
      const raw = '{"app":"schedule_plan","format":1,'
          '"tables":{"student":[{"id":1,"name":"张三","class_id":1}]}}';
      final bundle = service.decode(raw);
      expect(bundle.slices, contains(BackupSlice.students));
    });
  });

  group('恢复', () {
    test('空库恢复后数据一条不少', () async {
      await _seed(db);
      final bundle = await service.collect(BackupSlice.values);

      final fresh = await _openMemoryDb();
      addTearDown(fresh.close);
      final report = await BackupService(database: fresh).restore(bundle);

      expect(report.countOf('student'), 1);
      expect(report.countOf('attendance_record'), 1);
      final students = await fresh.query('student');
      expect(students.single['name'], '张三');
      final attendance = await fresh.query('attendance_record');
      expect(attendance.single['status'], 'absent');
      // 恢复 app_settings 时运行时键要被挡掉
      final settings = await fresh.query('app_settings');
      final keys = settings.map((row) => row['key']).toSet();
      expect(keys, contains(SettingKeys.riskAbsenceThreshold));
      expect(keys, isNot(contains(SettingKeys.updateLastCheckAt)));
    });

    test('重复恢复不会翻倍（按主键覆盖）', () async {
      await _seed(db);
      final bundle = await service.collect(BackupSlice.values);
      await service.restore(bundle);
      await service.restore(bundle);
      expect((await db.query('student')).length, 1);
      expect((await db.query('attendance_record')).length, 1);
    });

    test('只恢复班级名单，不会顺带删掉已排的课', () async {
      await _seed(db);
      final classesOnly = await service.collect(<BackupSlice>[
        BackupSlice.classes,
      ]);
      expect((await db.query('lesson')).length, 1);

      await service.restore(classesOnly);

      // 这条守的是一次真事故：写回如果用 INSERT OR REPLACE，
      // 覆盖 class 会先 DELETE 旧行，把 lesson / student（ON DELETE CASCADE）
      // 一起带走 —— 老师只想恢复个班级名单，课表却空了。
      expect((await db.query('lesson')).length, 1);
      expect((await db.query('student')).length, 1);
      expect(
        (await db.query('attendance_record')).length,
        1,
        reason: '考勤的 lesson_id 是 SET NULL，覆盖课表也不该把它清空',
      );
    });

    test('外键对不上时整体回滚，不留半套', () async {
      final broken = BackupBundle(
        createdAt: DateTime(2026, 3, 2),
        schemaVersion: DatabaseSchema.version,
        appVersion: '1.0.17+18',
        slices: const <BackupSlice>[
          BackupSlice.classes,
          BackupSlice.students,
          BackupSlice.attendance,
        ],
        tables: <String, List<Map<String, Object?>>>{
          'class': <Map<String, Object?>>[
            <String, Object?>{
              'id': 1,
              'name': '高一(1)班',
              'grade': '高一',
              'color': '#4FA8F5',
              'template_id': 1,
            },
          ],
          'student': <Map<String, Object?>>[
            <String, Object?>{'id': 1, 'name': '张三', 'class_id': 1},
          ],
          'attendance_record': <Map<String, Object?>>[
            // student_id = 999 不存在：这一行必然被外键挡住
            <String, Object?>{
              'id': 1,
              'student_id': 999,
              'date': '2026-03-02',
              'status': 'absent',
            },
          ],
        },
      );

      await expectLater(
        service.restore(broken),
        throwsA(isA<BackupRestoreException>()),
      );
      expect(
        await db.query('class'),
        isEmpty,
        reason: '前面的班级已经写进去了，但事务必须把它一起回滚',
      );
      expect(await db.query('student'), isEmpty);
      expect(await db.query('attendance_record'), isEmpty);
    });
  });
}
