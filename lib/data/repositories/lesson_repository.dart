import 'package:sqflite/sqflite.dart' hide DatabaseException;

import 'package:schedule_plan/core/constants/app_constants.dart';
import 'package:schedule_plan/core/error/app_exceptions.dart';
import 'package:schedule_plan/core/logging/app_logger.dart';
import 'package:schedule_plan/data/db/app_database.dart';
import 'package:schedule_plan/data/models/lesson.dart';

/// 课表条目数据访问层（readme 3.5 表）。
///
/// 真实时间一律通过 `lesson -> class.template_id -> template_period` 联查解析，
/// 课表条目本身不存绝对时间。
class LessonRepository {
  LessonRepository({Database? database}) : _db = database;

  Database? _db;

  Future<Database> get _database async => _db ??= await AppDatabase.instance();

  /// readme 3.5 给出的真实时间解析标准查询模式。
  static const String _selectWithTime = '''
    SELECT l.id AS id, l.course_id AS course_id, l.class_id AS class_id,
           l.teacher_id AS teacher_id, l.weekday AS weekday,
           l.period_index AS period_index,
           tp.start_time AS start_time, tp.end_time AS end_time,
           tp.period_type AS period_type,
           co.name AS course_name,
           c.name AS class_name, c.color AS class_color,
           c.template_id AS template_id
    FROM lesson l
    JOIN class c ON l.class_id = c.id
    JOIN course co ON co.id = l.course_id
    JOIN template_period tp
      ON tp.template_id = c.template_id
     AND tp.weekday = l.weekday
     AND tp.period_index = l.period_index
  ''';

  LessonWithTime _fromRow(Map<String, Object?> row) => LessonWithTime(
        lesson: Lesson(
          id: row['id'] as int,
          courseId: row['course_id'] as int,
          classId: row['class_id'] as int,
          teacherId: row['teacher_id'] as int,
          weekday: row['weekday'] as int,
          periodIndex: row['period_index'] as int,
        ),
        startTime: row['start_time'] as String,
        endTime: row['end_time'] as String,
        periodType: row['period_type'] as String,
        courseName: row['course_name'] as String,
        className: row['class_name'] as String,
        classColor: row['class_color'] as String,
        templateId: row['template_id'] as int,
      );

  /// 查询带真实时间的课表条目。
  Future<List<LessonWithTime>> queryWithTime({
    required int teacherId,
    int? weekday,
    int? classId,
  }) async {
    final db = await _database;
    final clauses = <String>['l.teacher_id = ?'];
    final args = <Object?>[teacherId];
    if (weekday != null) {
      clauses.add('l.weekday = ?');
      args.add(weekday);
    }
    if (classId != null) {
      clauses.add('l.class_id = ?');
      args.add(classId);
    }
    final rows = await db.rawQuery(
      '$_selectWithTime WHERE ${clauses.join(' AND ')} '
      'ORDER BY l.weekday ASC, tp.start_time ASC',
      args,
    );
    return rows.map(_fromRow).toList();
  }

  /// 单班级网格视图：按 class 过滤，节次行由该班级模板决定。
  Future<List<LessonWithTime>> forClass(int classId) async {
    final db = await _database;
    final rows = await db.rawQuery(
      '$_selectWithTime WHERE l.class_id = ? '
      'ORDER BY l.weekday ASC, l.period_index ASC',
      <Object?>[classId],
    );
    return rows.map(_fromRow).toList();
  }

  Future<List<Lesson>> rawLessons({required int teacherId, int? weekday}) async {
    final db = await _database;
    final rows = await db.query(
      'lesson',
      where: weekday == null ? 'teacher_id = ?' : 'teacher_id = ? AND weekday = ?',
      whereArgs: weekday == null ? <Object?>[teacherId] : <Object?>[teacherId, weekday],
    );
    return rows.map(Lesson.fromMap).toList();
  }

  /// 哪些工作日有课（模块二 2.1：有课的日期在日历格子上显示小圆点标记）。
  Future<Set<int>> weekdaysWithLessons(int teacherId) async {
    final db = await _database;
    final rows = await db.rawQuery(
      'SELECT DISTINCT weekday FROM lesson WHERE teacher_id = ?',
      <Object?>[teacherId],
    );
    return rows.map((row) => row['weekday'] as int).toSet();
  }

  Future<Lesson?> getLesson(int id) async {
    final db = await _database;
    final rows = await db.query(
      'lesson',
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return Lesson.fromMap(rows.first);
  }

  /// 新增课表条目：保存前执行冲突检测（模块一 1.5 / readme 3.4 节冲突检测逻辑）。
  ///
  /// 冲突判定基于**真实时间区间重叠**，禁止直接比较 period_index。
  Future<int> addLesson(Lesson lesson) async {
    final db = await _database;
    try {
      return await db.transaction((txn) async {
        final rows = await txn.rawQuery(
          '$_selectWithTime WHERE l.teacher_id = ? AND l.weekday = ?',
          <Object?>[lesson.teacherId, lesson.weekday],
        );
        final existing = rows.map(_fromRow).toList();
        final candidateRows = await txn.rawQuery(
          '''
          SELECT tp.start_time AS start_time, tp.end_time AS end_time,
                 tp.period_type AS period_type, c.template_id AS template_id,
                 c.name AS class_name, c.color AS class_color, co.name AS course_name
          FROM class c
          JOIN course co ON co.id = ?
          JOIN template_period tp
            ON tp.template_id = c.template_id
           AND tp.weekday = ?
           AND tp.period_index = ?
          WHERE c.id = ?
          ''',
          <Object?>[lesson.courseId, lesson.weekday, lesson.periodIndex, lesson.classId],
        );
        if (candidateRows.isEmpty) {
          throw const ValidationException(
            '该班级绑定的作息模板中没有对应的节次，无法排课',
          );
        }
        final candidateRow = candidateRows.first;
        final candidate = LessonWithTime(
          lesson: lesson,
          startTime: candidateRow['start_time'] as String,
          endTime: candidateRow['end_time'] as String,
          periodType: candidateRow['period_type'] as String,
          courseName: candidateRow['course_name'] as String,
          className: candidateRow['class_name'] as String,
          classColor: candidateRow['class_color'] as String,
          templateId: candidateRow['template_id'] as int,
        );
        final conflicts = LessonConflictDetector.findConflicts(
          candidate: candidate,
          existing: existing,
        );
        if (conflicts.isNotEmpty) {
          throw const ConflictException('该时间段已存在其他课程，存在时间冲突');
        }
        if (LessonConflictDetector.hasSameSlot(
          candidate: lesson,
          existing: existing.map((item) => item.lesson).toList(),
        )) {
          throw const ConflictException('该班级本节的课表格子已被占用');
        }
        return txn.insert('lesson', lesson.toMap());
      });
    } on AppException {
      rethrow;
    } catch (error, stack) {
      AppLogger.e('新增课表条目失败', error: error, stack: stack);
      throw DatabaseException('新增课表条目失败：$error', cause: error);
    }
  }

  Future<void> updateLesson(Lesson lesson) async {
    final db = await _database;
    if (lesson.id == null) {
      throw const ValidationException('课表条目 id 缺失');
    }
    await db.update(
      'lesson',
      lesson.toMap(),
      where: 'id = ?',
      whereArgs: <Object?>[lesson.id],
    );
  }

  Future<void> deleteLesson(int id) async {
    final db = await _database;
    await db.delete('lesson', where: 'id = ?', whereArgs: <Object?>[id]);
  }

  /// 「把课程落到这一格」：课表页点空格子 → 滑动选课 → 直接排进 (班级, 周几, 第几节)。
  ///
  /// 走的是与 [addLesson] 完全相同的冲突检测路径（真实时间区间重叠 +
  /// 同班同节占用），因此不另写一套判定，避免两处口径漂移。
  Future<int> placeLesson({
    required int courseId,
    required int classId,
    required int weekday,
    required int periodIndex,
    int teacherId = AppConstants.currentTeacherId,
  }) {
    return addLesson(
      Lesson(
        courseId: courseId,
        classId: classId,
        teacherId: teacherId,
        weekday: weekday,
        periodIndex: periodIndex,
      ),
    );
  }

  /// 把某一格上的课移出课表（课程本身不受影响，仍留在课程管理里）。
  Future<void> clearSlot({
    required int classId,
    required int weekday,
    required int periodIndex,
  }) async {
    final db = await _database;
    await db.delete(
      'lesson',
      where: 'class_id = ? AND weekday = ? AND period_index = ?',
      whereArgs: <Object?>[classId, weekday, periodIndex],
    );
  }

  /// 查某一格上现有的课表条目 id（换课 / 移出时用）。
  Future<int?> lessonIdAt({
    required int classId,
    required int weekday,
    required int periodIndex,
  }) async {
    final db = await _database;
    final rows = await db.query(
      'lesson',
      columns: <String>['id'],
      where: 'class_id = ? AND weekday = ? AND period_index = ?',
      whereArgs: <Object?>[classId, weekday, periodIndex],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return rows.first['id'] as int?;
  }

  /// 课程格子交换（模块一 1.8）。
  ///
  /// 仅允许同一班级同一模板内交换；跨班级/跨模板由调用方先用
  /// [LessonConflictDetector.canSwap] 判定，不合法时 UI 显示禁止图标并震动反馈。
  Future<void> swapLessons({
    required LessonWithTime source,
    required LessonWithTime target,
  }) async {
    if (!LessonConflictDetector.canSwap(source: source, target: target)) {
      throw const ValidationException('跨班级或跨模板的格子不支持直接交换');
    }
    final db = await _database;
    try {
      await db.transaction((txn) async {
        await txn.update(
          'lesson',
          <String, Object?>{'period_index': target.lesson.periodIndex},
          where: 'id = ?',
          whereArgs: <Object?>[source.lesson.id],
        );
        await txn.update(
          'lesson',
          <String, Object?>{'period_index': source.lesson.periodIndex},
          where: 'id = ?',
          whereArgs: <Object?>[target.lesson.id],
        );
      });
    } catch (error, stack) {
      AppLogger.e('交换课表格子失败', error: error, stack: stack);
      throw DatabaseException('交换课表格子失败：$error', cause: error);
    }
  }

  /// 统计某班级某天是否有课（待办自动生成等场景复用）。
  Future<int> countLessonsForClass(int classId) async {
    final db = await _database;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS cnt FROM lesson WHERE class_id = ?',
      <Object?>[classId],
    );
    return (rows.first['cnt'] as int?) ?? 0;
  }
}
