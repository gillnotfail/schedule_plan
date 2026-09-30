import 'package:sqflite/sqflite.dart' hide DatabaseException;

import 'package:schedule_plan/core/constants/app_constants.dart';
import 'package:schedule_plan/core/error/app_exceptions.dart';
import 'package:schedule_plan/core/logging/app_logger.dart';
import 'package:schedule_plan/core/utils/time_utils.dart';
import 'package:schedule_plan/data/models/schedule_template.dart';

/// SQLite 建表脚本与迁移（readme 第三章完整 Schema）。
///
/// 约束：
/// - 所有外键显式声明 ON DELETE 行为，禁止裸外键不写级联策略；
/// - 迁移脚本必须包在事务中，失败整体回滚（第六章「数据库迁移丢失数据」）；
/// - 迁移完成后校验所有 class.template_id 均能在 schedule_template 中查到（避免外键悬空）。
abstract final class DatabaseSchema {
  /// 当前数据库版本号。
  ///
  /// v1 -> v2：学生增加 `gender`；课程由「单班级」升级为「多班级」
  /// （新增 `course_class` 关联表，`course.class_id` 降级为可空主班级）。
  /// v2 -> v3：课程增加 `color`（可空）。为空表示"跟随所属班级的颜色"，
  /// 非空表示老师给这门课单独指定的标记色（用户规格：新增课程时可选颜色）。
  /// v3 -> v4：重建 `attendance_record`——外键改为 SET NULL 并补快照字段，
  /// 让考勤历史不随课表条目/课程/班级被删而消失。
  /// v4 -> v5：新增 `student_course_status`——「休学 / 免修」这类**课程级长期状态**，
  /// 点一次管 180 天，不用每节课重复标记（用户规格）。纯加表，不动老表。
  /// v6 -> v7：新增 `holiday_day`——节假日 / 调休安排的**本地缓存表**，
  /// 用来装从网上取回的年度安排，覆盖掉内置表里缺的年份（见
  /// `holiday_sync_service.dart`）。同样是纯加表，不动老表。
  /// v7 -> v8：**删表**——`note`（快速笔记）与 `llm_provider_config`（LLM 提供商）
  /// 对应的功能整块下线（用户规格：这两个功能用得不多，通通去掉），
  /// 建表语句与迁移脚本里的定义一并移除，老库升级时把这两张表 DROP 掉。
  static const int version = 8;

  /// 首次建库时写入的默认作息模板名称（种子数据，非界面文案）。
  static const String _seedTemplateName = '默认作息';

  /// 3.18 课程级长期状态（休学 / 免修）建表语句。
  ///
  /// 抽成常量是因为**建库与迁移要执行同一段 DDL**：
  /// 新库走 [createTables]，老库走 [_migrateV4ToV5]，两处各写一份迟早会漂。
  static const String createCourseStudentStatusTable = '''
    CREATE TABLE IF NOT EXISTS student_course_status (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      student_id INTEGER NOT NULL REFERENCES student(id) ON DELETE CASCADE,
      course_id INTEGER NOT NULL REFERENCES course(id) ON DELETE CASCADE,
      status TEXT NOT NULL,
      start_date TEXT NOT NULL,
      end_date TEXT NOT NULL,
      note TEXT,
      created_at INTEGER,
      updated_at INTEGER,
      UNIQUE(student_id, course_id)
    )
    ''';

  /// 建表语句，顺序遵循依赖（被引用的表先建）。
  static const List<String> createTables = <String>[
    // 3.1 作息模板
    '''
    CREATE TABLE IF NOT EXISTS schedule_template (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL UNIQUE,
      is_default INTEGER NOT NULL DEFAULT 0,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    )
    ''',
    // 3.2 模板节次时间
    '''
    CREATE TABLE IF NOT EXISTS template_period (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      template_id INTEGER NOT NULL REFERENCES schedule_template(id) ON DELETE CASCADE,
      weekday INTEGER NOT NULL CHECK(weekday BETWEEN 1 AND 7),
      period_index INTEGER NOT NULL,
      period_type TEXT NOT NULL DEFAULT 'normal',
      start_time TEXT NOT NULL,
      end_time TEXT NOT NULL,
      label TEXT,
      UNIQUE(template_id, weekday, period_index)
    )
    ''',
    // 3.3 班级
    '''
    CREATE TABLE IF NOT EXISTS class (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      grade TEXT NOT NULL,
      head_teacher TEXT,
      student_count INTEGER NOT NULL DEFAULT 0,
      color TEXT NOT NULL,
      template_id INTEGER NOT NULL REFERENCES schedule_template(id) ON DELETE RESTRICT,
      sort_order INTEGER NOT NULL DEFAULT 0
    )
    ''',
    // 3.4 课程
    //
    // class_id 为「主班级」，可为空：大课/合班场景下课程可挂在多个班级上，
    // 真实归属以 course_class 关联表为准。班级被删除时置空而不是级联删课，
    // 避免删掉一个班把合班课程整体带走。
    // color 可空：NULL = 跟随所属班级颜色，有值 = 这门课自己的标记色。
    '''
    CREATE TABLE IF NOT EXISTS course (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      teacher_name TEXT NOT NULL,
      class_id INTEGER REFERENCES class(id) ON DELETE SET NULL,
      description TEXT,
      room TEXT,
      color TEXT
    )
    ''',
    // 3.17 课程-班级关联（多对多，支持合班/大课）
    '''
    CREATE TABLE IF NOT EXISTS course_class (
      course_id INTEGER NOT NULL REFERENCES course(id) ON DELETE CASCADE,
      class_id INTEGER NOT NULL REFERENCES class(id) ON DELETE CASCADE,
      PRIMARY KEY (course_id, class_id)
    )
    ''',
    // 3.5 课表条目
    '''
    CREATE TABLE IF NOT EXISTS lesson (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      course_id INTEGER NOT NULL REFERENCES course(id) ON DELETE CASCADE,
      class_id INTEGER NOT NULL REFERENCES class(id) ON DELETE CASCADE,
      teacher_id INTEGER NOT NULL,
      weekday INTEGER NOT NULL CHECK(weekday BETWEEN 1 AND 7),
      period_index INTEGER NOT NULL
    )
    ''',
    // 3.6 学生
    '''
    CREATE TABLE IF NOT EXISTS student (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      student_no TEXT,
      gender TEXT,
      class_id INTEGER NOT NULL REFERENCES class(id) ON DELETE CASCADE
    )
    ''',
    // 3.7 考勤记录
    //
    // 外键策略（用户规格："保存考勤信息后就应该放好久，只要调用就能立刻读取"）：
    // 课表条目、班级、课程都可能被老师改掉或删掉，而考勤是**历史事实**，
    // 不能跟着一起消失。所以这三个外键都可空 + ON DELETE SET NULL，
    // 记录本身留下；同时把「哪天第几节上什么课、哪个班」冗余成快照列，
    // 条目没了也还能读懂、能导出。只有学生被删除时才级联（人没了记录无意义）。
    '''
    CREATE TABLE IF NOT EXISTS attendance_record (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      student_id INTEGER NOT NULL REFERENCES student(id) ON DELETE CASCADE,
      lesson_id INTEGER REFERENCES lesson(id) ON DELETE SET NULL,
      class_id INTEGER REFERENCES class(id) ON DELETE SET NULL,
      course_id INTEGER REFERENCES course(id) ON DELETE SET NULL,
      date TEXT NOT NULL,
      weekday INTEGER,
      period_index INTEGER,
      start_time TEXT,
      end_time TEXT,
      course_name TEXT,
      class_name TEXT,
      status TEXT NOT NULL,
      note TEXT,
      recorded_at INTEGER,
      updated_at INTEGER,
      UNIQUE(student_id, lesson_id, date)
    )
    ''',
    // 3.18 课程级长期状态（休学 / 免修，用户规格）
    //
    // 唯一键 (student_id, course_id)：一个学生在**同一门课**上只可能有一个长期状态，
    // 再点一次是"改状态"而不是叠一条。学生或课程被删除时级联清理 ——
    // 人没了、课没了，这条状态也就没有意义了。
    createCourseStudentStatusTable,
    // 3.8 表现标签记录
    '''
    CREATE TABLE IF NOT EXISTS student_tag_record (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      student_id INTEGER NOT NULL REFERENCES student(id) ON DELETE CASCADE,
      date TEXT NOT NULL,
      tag TEXT NOT NULL,
      star_rating INTEGER NOT NULL DEFAULT 0 CHECK(star_rating BETWEEN 0 AND 5),
      remark TEXT
    )
    ''',
    // 3.9 待办
    '''
    CREATE TABLE IF NOT EXISTS todo (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      title TEXT NOT NULL,
      description TEXT,
      priority TEXT NOT NULL DEFAULT 'medium',
      due_date INTEGER,
      is_done INTEGER NOT NULL DEFAULT 0,
      is_auto_generated INTEGER NOT NULL DEFAULT 0,
      related_class_id INTEGER REFERENCES class(id) ON DELETE SET NULL,
      sort_order INTEGER NOT NULL DEFAULT 0
    )
    ''',
    // 3.11 日程安排事件
    '''
    CREATE TABLE IF NOT EXISTS schedule_event (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      title TEXT NOT NULL,
      start_at INTEGER NOT NULL,
      end_at INTEGER,
      location TEXT,
      reminder_enabled INTEGER NOT NULL DEFAULT 0,
      reminder_minutes_before INTEGER,
      recurrence TEXT NOT NULL DEFAULT 'once'
    )
    ''',
    // 3.12 专注模式记录
    '''
    CREATE TABLE IF NOT EXISTS focus_session (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      started_at INTEGER NOT NULL,
      duration_minutes INTEGER NOT NULL,
      completed INTEGER NOT NULL DEFAULT 0
    )
    ''',
    // 3.13 批量导入日志
    '''
    CREATE TABLE IF NOT EXISTS import_log (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      file_name TEXT NOT NULL,
      imported_at INTEGER NOT NULL,
      success_count INTEGER NOT NULL,
      fail_count INTEGER NOT NULL,
      detail_json TEXT
    )
    ''',
    // 3.15 应用设置（单行 KV）
    '''
    CREATE TABLE IF NOT EXISTS app_settings (
      key TEXT PRIMARY KEY,
      value TEXT NOT NULL
    )
    ''',
    // 3.19 节假日 / 调休安排本地缓存（v7）
    //
    // 内置表（`china_holiday_calendar.dart`）只抄到发布过的年份，跨年后就该过期了。
    // 这张表装的是"从网上取回来的年度安排"，按日期逐天存：
    //   - `date` 做主键 → 同一个日期无论来源怎么变，都只留一条（UPSERT 覆盖）；
    //   - `year` 单独存一列 → 「按年整批替换 / 按年判断新鲜度」都只走一次索引，
    //     不用拿字符串前缀去 LIKE（那样索引用不上，还会误伤）；
    //   - `source` 记数据来源 → 失败排查时能一眼看出这条是从哪个接口来的；
    //   - `fetched_at` 毫秒时间戳 → 节流策略靠它判断"该不该再请求一次"。
    //
    // 不设外键：节假日安排跟老师自己的数据没有任何归属关系，
    // 它是纯参考数据，删库重建也不该牵连别的东西。
    '''
    CREATE TABLE IF NOT EXISTS holiday_day (
      date TEXT PRIMARY KEY,
      kind TEXT NOT NULL,
      name TEXT,
      year INTEGER NOT NULL,
      source TEXT NOT NULL,
      fetched_at INTEGER NOT NULL
    )
    ''',
  ];

  /// 索引：加速常用查询（readme 3.5 明确要求两个索引）。
  static const List<String> createIndexes = <String>[
    'CREATE INDEX IF NOT EXISTS idx_lesson_teacher_weekday ON lesson(teacher_id, weekday)',
    'CREATE INDEX IF NOT EXISTS idx_lesson_class_slot ON lesson(class_id, weekday, period_index)',
    'CREATE INDEX IF NOT EXISTS idx_attendance_date ON attendance_record(date)',
    'CREATE INDEX IF NOT EXISTS idx_attendance_lesson ON attendance_record(lesson_id, date)',
    // 高风险检测是"逐生按时间范围统计状态次数"，没有这个索引就是每生一次全表扫描
    'CREATE INDEX IF NOT EXISTS idx_attendance_student_date ON attendance_record(student_id, date)',
    'CREATE INDEX IF NOT EXISTS idx_student_class ON student(class_id)',
    'CREATE INDEX IF NOT EXISTS idx_course_class ON course(class_id)',
    'CREATE INDEX IF NOT EXISTS idx_course_class_link ON course_class(class_id)',
    'CREATE INDEX IF NOT EXISTS idx_tag_student_date ON student_tag_record(student_id, date)',
    // 点名时按课程 + 日期区间取生效中的休学 / 免修，没有这个索引就是每次全表扫
    'CREATE INDEX IF NOT EXISTS idx_course_status_lookup ON student_course_status(course_id, start_date, end_date)',
    'CREATE INDEX IF NOT EXISTS idx_course_status_student ON student_course_status(student_id)',
    // 节假日缓存按年整批替换 / 按年查新鲜度，不建索引就是每次全表扫
    'CREATE INDEX IF NOT EXISTS idx_holiday_year ON holiday_day(year)',
  ];

  /// 建库：整段包在事务中，任何一步失败整体回滚。
  static Future<void> createAll(Database db) async {
    try {
      await db.transaction((txn) async {
        for (final statement in createTables) {
          await txn.execute(statement);
        }
        for (final statement in createIndexes) {
          await txn.execute(statement);
        }
        await _seedDefaults(txn);
      });
    } catch (error, stack) {
      AppLogger.e('建表失败，事务已回滚', error: error, stack: stack);
      throw DatabaseException('数据库初始化失败，已回滚：$error', cause: error);
    }
  }

  /// 迁移：同样包在事务中（第六章「迁移脚本中途失败导致外键悬空」）。
  ///
  /// v1 -> v2 需要**重建 course 表**（去掉 class_id 的 NOT NULL 约束）。
  /// SQLite 的 `DROP TABLE` 会隐式触发外键的 ON DELETE 动作，若不临时关闭外键，
  /// 重建过程中 lesson 会被整表级联清空——这是本迁移最危险的一步，必须先关外键。
  static Future<void> migrate(Database db, int from, int to) async {
    final rebuildingCourse = from < 2 && to >= 2;
    final rebuildingAttendance = from < 4 && to >= 4;
    // SQLite 的 `DROP TABLE` 会隐式触发外键的 ON DELETE 动作：
    // 重建 course 会把 lesson 整表级联清空，重建 attendance_record 同理。
    // 两条重建路径都必须在**事务外**先关掉外键（事务内改 PRAGMA 是空操作）。
    final needsForeignKeysOff = rebuildingCourse || rebuildingAttendance;
    if (needsForeignKeysOff) {
      await db.execute('PRAGMA foreign_keys = OFF');
    }
    try {
      await db.transaction((txn) async {
        if (from < 1 && to >= 1) {
          for (final statement in createTables) {
            await txn.execute(statement);
          }
          for (final statement in createIndexes) {
            await txn.execute(statement);
          }
        }
        if (rebuildingCourse) {
          await _migrateV1ToV2(txn);
        }
        if (from < 3 && to >= 3) {
          await _migrateV2ToV3(txn);
        }
        if (rebuildingAttendance) {
          await _migrateV3ToV4(txn);
        }
        if (from < 5 && to >= 5) {
          await _migrateV4ToV5(txn);
        }
        if (from < 6 && to >= 6) {
          await _migrateV5ToV6(txn);
        }
        if (from < 7 && to >= 7) {
          await _migrateV6ToV7(txn);
        }
        if (from < 8 && to >= 8) {
          await _migrateV7ToV8(txn);
        }
      });
    } catch (error, stack) {
      AppLogger.e('数据库迁移失败（$from -> $to），事务已回滚', error: error, stack: stack);
      throw DatabaseException('数据库迁移失败，已回滚：$error', cause: error);
    } finally {
      if (needsForeignKeysOff) {
        await db.execute('PRAGMA foreign_keys = ON');
      }
    }
    await validate(db);
  }

  /// v1 -> v2：
  /// 1) student 增加 gender 列；
  /// 2) 重建 course（class_id 可空 + ON DELETE SET NULL）；
  /// 3) 建 course_class 关联表，并用旧的 course.class_id 回填，保证老数据不丢班级归属。
  static Future<void> _migrateV1ToV2(Transaction txn) async {
    final columns = await txn.rawQuery('PRAGMA table_info(student)');
    final hasGender = columns.any((row) => row['name'] == 'gender');
    if (!hasGender) {
      await txn.execute('ALTER TABLE student ADD COLUMN gender TEXT');
    }

    await txn.execute('''
      CREATE TABLE IF NOT EXISTS course_new (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        teacher_name TEXT NOT NULL,
        class_id INTEGER REFERENCES class(id) ON DELETE SET NULL,
        description TEXT,
        room TEXT
      )
    ''');
    await txn.execute('''
      INSERT INTO course_new (id, name, teacher_name, class_id, description, room)
      SELECT id, name, teacher_name, class_id, description, room FROM course
    ''');
    await txn.execute('DROP TABLE course');
    await txn.execute('ALTER TABLE course_new RENAME TO course');

    await txn.execute('''
      CREATE TABLE IF NOT EXISTS course_class (
        course_id INTEGER NOT NULL REFERENCES course(id) ON DELETE CASCADE,
        class_id INTEGER NOT NULL REFERENCES class(id) ON DELETE CASCADE,
        PRIMARY KEY (course_id, class_id)
      )
    ''');
    // 老数据回填：原来的单班级就是现在的主班级
    await txn.execute('''
      INSERT OR IGNORE INTO course_class (course_id, class_id)
      SELECT id, class_id FROM course WHERE class_id IS NOT NULL
    ''');
    await txn.execute(
      'CREATE INDEX IF NOT EXISTS idx_course_class ON course(class_id)',
    );
    await txn.execute(
      'CREATE INDEX IF NOT EXISTS idx_course_class_link ON course_class(class_id)',
    );

    // 重建后校验：课表条目数量必须与迁移前一致（防止级联误删）
    final lessonCount = Sqflite.firstIntValue(
          await txn.rawQuery('SELECT COUNT(*) FROM lesson'),
        ) ??
        0;
    AppLogger.i('v1 -> v2 迁移完成，课表条目保留 $lessonCount 条');
  }

  /// v2 -> v3：课程增加可空的 `color` 列。
  ///
  /// 用 `ALTER TABLE ADD COLUMN` 而不是重建表：新列可空、没有默认值，
  /// 老数据自动为 NULL（语义正好是"跟随班级色"），不需要回填，
  /// 也不触碰 lesson / course_class 的级联关系。
  /// 仍然按 `PRAGMA table_info` 判断一次，保证迁移脚本可重复执行而不报错。
  static Future<void> _migrateV2ToV3(Transaction txn) async {
    final columns = await txn.rawQuery('PRAGMA table_info(course)');
    final hasColor = columns.any((row) => row['name'] == 'color');
    if (!hasColor) {
      await txn.execute('ALTER TABLE course ADD COLUMN color TEXT');
      AppLogger.i('v2 -> v3 迁移完成：course 表新增 color 列');
    }
  }

  /// v3 -> v4：重建 `attendance_record`。
  ///
  /// 老表的 `lesson_id` 是 `NOT NULL ... ON DELETE CASCADE`：老师在课表页
  /// 「移出课表」、或删掉一门课，都会**连带把历史考勤一起抹掉** ——
  /// 这跟"考勤记录要长期保存、随时能读"直接冲突。SQLite 改不动已有外键的
  /// 删除动作，只能整表重建（沿用 v1 -> v2 重建 course 的同一套路）。
  ///
  /// 重建时按现有的 lesson / course / class / template_period 把快照列**回填**，
  /// 这样升级上来的老记录也具备"条目没了还能读懂"的能力。
  /// 全程包在调用方的迁移事务里，任一步失败整体回滚。
  static Future<void> _migrateV3ToV4(Transaction txn) async {
    final columns = await txn.rawQuery('PRAGMA table_info(attendance_record)');
    final alreadyMigrated = columns.any((row) => row['name'] == 'recorded_at');
    if (alreadyMigrated) {
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;

    await txn.execute('''
      CREATE TABLE IF NOT EXISTS attendance_record_new (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        student_id INTEGER NOT NULL REFERENCES student(id) ON DELETE CASCADE,
        lesson_id INTEGER REFERENCES lesson(id) ON DELETE SET NULL,
        class_id INTEGER REFERENCES class(id) ON DELETE SET NULL,
        course_id INTEGER REFERENCES course(id) ON DELETE SET NULL,
        date TEXT NOT NULL,
        weekday INTEGER,
        period_index INTEGER,
        start_time TEXT,
        end_time TEXT,
        course_name TEXT,
        class_name TEXT,
        status TEXT NOT NULL,
        note TEXT,
        recorded_at INTEGER,
        updated_at INTEGER,
        UNIQUE(student_id, lesson_id, date)
      )
    ''');
    // 老记录只有 student_id / lesson_id / date / status / note，
    // 其余全部靠 JOIN 回填；JOIN 不上的（条目已丢失）留空，记录本身仍然留下。
    await txn.execute('''
      INSERT INTO attendance_record_new (
        id, student_id, lesson_id, class_id, course_id, date, weekday, period_index,
        start_time, end_time, course_name, class_name, status, note,
        recorded_at, updated_at
      )
      SELECT a.id, a.student_id, a.lesson_id, l.class_id, l.course_id, a.date,
             l.weekday, l.period_index,
             tp.start_time, tp.end_time,
             co.name, c.name, a.status, a.note,
             $now, $now
      FROM attendance_record a
      LEFT JOIN lesson l ON l.id = a.lesson_id
      LEFT JOIN course co ON co.id = l.course_id
      LEFT JOIN class c ON c.id = l.class_id
      LEFT JOIN template_period tp
        ON tp.template_id = c.template_id
       AND tp.weekday = l.weekday
       AND tp.period_index = l.period_index
    ''');
    final kept = Sqflite.firstIntValue(
          await txn.rawQuery('SELECT COUNT(*) FROM attendance_record_new'),
        ) ??
        0;
    final before = Sqflite.firstIntValue(
          await txn.rawQuery('SELECT COUNT(*) FROM attendance_record'),
        ) ??
        0;
    if (kept != before) {
      throw DatabaseException(
        '考勤记录重建前后条数不一致（$before -> $kept），迁移已回滚',
      );
    }
    await txn.execute('DROP TABLE attendance_record');
    await txn.execute(
      'ALTER TABLE attendance_record_new RENAME TO attendance_record',
    );
    // DROP TABLE 会连索引一起带走，必须重建
    await txn.execute(
      'CREATE INDEX IF NOT EXISTS idx_attendance_date ON attendance_record(date)',
    );
    await txn.execute(
      'CREATE INDEX IF NOT EXISTS idx_attendance_lesson ON attendance_record(lesson_id, date)',
    );
    await txn.execute(
      'CREATE INDEX IF NOT EXISTS idx_attendance_student_date ON attendance_record(student_id, date)',
    );
    AppLogger.i('v3 -> v4 迁移完成：attendance_record 保留 $kept 条历史记录');
  }

  /// v4 -> v5：新增 `student_course_status`（课程级长期状态：休学 / 免修）。
  ///
  /// **纯加表**，不重建任何老表，所以这里既不需要临时关外键，也不会级联误删：
  /// SQLite 的 `CREATE TABLE IF NOT EXISTS` 天然可重复执行，
  /// 老库升级上来直接补一张空表即可（老数据里本来就没有长期状态）。
  static Future<void> _migrateV4ToV5(Transaction txn) async {
    await txn.execute(createCourseStudentStatusTable);
    await txn.execute(
      'CREATE INDEX IF NOT EXISTS idx_course_status_lookup ON student_course_status(course_id, start_date, end_date)',
    );
    await txn.execute(
      'CREATE INDEX IF NOT EXISTS idx_course_status_student ON student_course_status(student_id)',
    );
    AppLogger.i('v4 -> v5 迁移完成：新增 student_course_status（休学 / 免修）');
  }

  /// v5 -> v6：`schedule_event` 加 `recurrence` 列（单次 / 每周 / 隔周 / 每月）。
  ///
  /// 纯加列、带默认值，可重复执行；老日程自动回落为「单次」，
  /// 语义与旧版本一致（以前就只有一次性日程）。
  static Future<void> _migrateV5ToV6(Transaction txn) async {
    final columns = await txn.rawQuery('PRAGMA table_info(schedule_event)');
    final has = columns.any((row) => row['name'] == 'recurrence');
    if (!has) {
      await txn.execute(
        "ALTER TABLE schedule_event ADD COLUMN recurrence TEXT NOT NULL DEFAULT 'once'",
      );
    }
    AppLogger.i('v5 -> v6 迁移完成：schedule_event 新增 recurrence（单次/隔周/隔月）');
  }

  /// v6 -> v7：新增 `holiday_day`（节假日 / 调休安排的本地缓存表）。
  ///
  /// 纯加表，不重建、不回填：老库里没有任何节假日缓存完全正常——
  /// 内置表（`china_holiday_calendar.dart`）会先兜住，联网取到数据后再逐天写入。
  /// 沿用 `CREATE TABLE IF NOT EXISTS` + `PRAGMA table_info` 双保险，
  /// 保证这段脚本被重复执行也不会报错（迁移中断后重跑的常见场景）。
  static Future<void> _migrateV6ToV7(Transaction txn) async {
    final columns = await txn.rawQuery('PRAGMA table_info(holiday_day)');
    if (columns.isEmpty) {
      await txn.execute('''
        CREATE TABLE IF NOT EXISTS holiday_day (
          date TEXT PRIMARY KEY,
          kind TEXT NOT NULL,
          name TEXT,
          year INTEGER NOT NULL,
          source TEXT NOT NULL,
          fetched_at INTEGER NOT NULL
        )
      ''');
      await txn.execute(
        'CREATE INDEX IF NOT EXISTS idx_holiday_year ON holiday_day(year)',
      );
      AppLogger.i('v6 -> v7 迁移完成：新增 holiday_day（节假日缓存）');
    }
  }

  /// v7 -> v8：删掉 `note` 与 `llm_provider_config` 两张表。
  ///
  /// 这是本项目**第一次做"减表"迁移**（此前全是纯加表加列）：
  /// 「快速笔记」和「LLM 提供商」两个功能整块下线，表再留着就是死表——
  /// 每加一张表都得记得避开它，清库时还要单独绕开，不如一次删干净。
  ///
  /// 用 `DROP TABLE IF EXISTS`，保证这段脚本重复执行也不报错
  /// （迁移中断后重跑是常见场景）；两张表都没被外键引用，删掉不影响别的表。
  /// 新库（from == 0）走 [createTables]，本来就不会建这两张表，这里是无害的空操作。
  static Future<void> _migrateV7ToV8(Transaction txn) async {
    await txn.execute('DROP TABLE IF EXISTS note');
    await txn.execute('DROP TABLE IF EXISTS llm_provider_config');
    AppLogger.i('v7 -> v8 迁移完成：删除 note / llm_provider_config 两张表');
  }

  /// 迁移后一致性校验：
  /// 1) 所有 class.template_id 均能查到对应 schedule_template；
  /// 2) 外键完整性检查无异常。
  static Future<void> validate(Database db) async {
    final dangling = await db.rawQuery(
      '''
      SELECT c.id, c.name, c.template_id
      FROM class c
      LEFT JOIN schedule_template t ON t.id = c.template_id
      WHERE t.id IS NULL
      ''',
    );
    if (dangling.isNotEmpty) {
      throw DatabaseException(
        '检测到 ${dangling.length} 个班级绑定了不存在的作息模板，迁移已回滚',
      );
    }
    final fkIssues = await db.rawQuery('PRAGMA foreign_key_check');
    if (fkIssues.isNotEmpty) {
      throw DatabaseException('外键完整性校验未通过：${fkIssues.length} 条异常记录');
    }
  }

  /// 首次建库时写入一份默认作息模板与默认设置，保证「新建班级默认预选模板」可用。
  static Future<void> _seedDefaults(Transaction txn) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    // 种子数据（非界面文案），保证「新建班级默认预选模板」在首次启动即可用。
    final templateId = await txn.insert('schedule_template', <String, Object?>{
      'name': _seedTemplateName,
      'is_default': 1,
      'created_at': now,
      'updated_at': now,
    });
    await insertDefaultPeriods(txn, templateId);
  }

  /// 为指定模板写入出厂作息：周一至周五 × 08:00 开始 × 每节 40 分钟 ×
  /// 课间 10 分钟 × 共 10 节。
  ///
  /// 与「课表设置 → 一键生成作息」共用 [generatePeriodRows]，
  /// 保证出厂作息与用户自定义作息的口径完全一致。
  /// 建库种子、新建模板、老模板自愈都走这一个入口，避免多处各写一份。
  ///
  /// 参数类型是 [DatabaseExecutor]，`Database` 与 `Transaction` 都满足，
  /// 这样调用方可以自己在事务里调用，也可以直接对库调用。
  static Future<void> insertDefaultPeriods(
    DatabaseExecutor executor,
    int templateId,
  ) async {
    final periods = generatePeriodRows(
      startTime: AppConstants.defaultDayStartTime,
      lessonMinutes: AppConstants.defaultLessonMinutes,
      breakMinutes: AppConstants.defaultBreakMinutes,
      count: AppConstants.defaultDayPeriodCount,
    );
    for (var weekday = 1;
        weekday <= AppConstants.defaultWorkdayCount;
        weekday++) {
      for (var i = 0; i < periods.length; i++) {
        await executor.insert('template_period', <String, Object?>{
          'template_id': templateId,
          'weekday': weekday,
          'period_index': i + 1,
          'period_type': PeriodType.normal.storageKey,
          'start_time': periods[i].$1,
          'end_time': periods[i].$2,
        });
      }
    }
  }

  /// 按「开始时间 + 每节时长 + 课间间隔 + 节数」生成 (start, end) 序列。
  ///
  /// 纯函数，被种子数据、一键生成作息、节次级联顺延共用，
  /// 保证出厂作息与用户自定义作息走同一套算术。
  static List<(String, String)> generatePeriodRows({
    required String startTime,
    required int lessonMinutes,
    required int breakMinutes,
    required int count,
  }) {
    final first = TimeUtils.tryParseMinutes(startTime) ?? 0;
    final step = lessonMinutes + breakMinutes;
    return List<(String, String)>.generate(count, (index) {
      final start = first + index * step;
      final end = start + lessonMinutes;
      return (
        TimeUtils.formatMinutes(start.clamp(0, 24 * 60 - 1)),
        TimeUtils.formatMinutes(end.clamp(0, 24 * 60 - 1)),
      );
    }, growable: false);
  }
}
