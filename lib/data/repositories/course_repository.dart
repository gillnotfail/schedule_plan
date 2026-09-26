import 'package:sqflite/sqflite.dart' hide DatabaseException;

import 'package:schedule_plan/core/error/app_exceptions.dart';
import 'package:schedule_plan/core/logging/app_logger.dart';
import 'package:schedule_plan/data/db/app_database.dart';
import 'package:schedule_plan/data/models/class_course.dart';

/// 课程数据访问层（readme 3.4 表，模块六 6.1）。
///
/// 用户规格：课程可挂载到**多个班级**（合班 / 大课），
/// 归属关系存放在 `course_class` 关联表；`course.class_id` 只保留主班级冗余列。
class CourseRepository {
  CourseRepository({Database? database}) : _db = database;

  Database? _db;

  Future<Database> get _database async => _db ??= await AppDatabase.instance();

  /// 课程列表。[classId] 非空时只返回挂载了该班级的课程（含合班课）。
  Future<List<Course>> listCourses({int? classId}) async {
    final db = await _database;
    final rows = await db.rawQuery(
      classId == null
          ? '''
            SELECT c.*, GROUP_CONCAT(cc.class_id) AS class_ids
            FROM course c
            LEFT JOIN course_class cc ON cc.course_id = c.id
            GROUP BY c.id
            ORDER BY c.id ASC
            '''
          : '''
            SELECT c.*, GROUP_CONCAT(cc.class_id) AS class_ids
            FROM course c
            JOIN course_class cc ON cc.course_id = c.id
            WHERE c.id IN (SELECT course_id FROM course_class WHERE class_id = ?)
            GROUP BY c.id
            ORDER BY c.id ASC
            ''',
      classId == null ? null : <Object?>[classId],
    );
    return rows.map(_fromJoinedRow).toList();
  }

  Future<Course?> getCourse(int id) async {
    final db = await _database;
    final rows = await db.query(
      'course',
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    final links = await db.query(
      'course_class',
      columns: <String>['class_id'],
      where: 'course_id = ?',
      whereArgs: <Object?>[id],
      orderBy: 'class_id ASC',
    );
    return Course.fromMap(
      rows.first,
      classIds: links.map((row) => row['class_id'] as int).toList(),
    );
  }

  /// 一门课挂载的班级 id（课表页「去点名」据此拉全部班级的名单）。
  ///
  /// 用户规格：课程管理里一门课可以勾选多个班级，这节课的学生就是这些班级
  /// 名单的并集，所以点名不能只取 `lesson.class_id` 那一个班。
  Future<List<int>> classIdsOfCourse(int courseId) async {
    final db = await _database;
    final rows = await db.query(
      'course_class',
      columns: <String>['class_id'],
      where: 'course_id = ?',
      whereArgs: <Object?>[courseId],
      orderBy: 'class_id ASC',
    );
    return rows.map((row) => row['class_id'] as int).toList(growable: false);
  }

  /// 各课程的学生人数：合班课为所选班级人数之和。
  Future<Map<int, int>> studentCountByCourse() async {
    final db = await _database;
    final rows = await db.rawQuery('''
      SELECT cc.course_id AS course_id,
             COALESCE(SUM(c.student_count), 0) AS total
      FROM course_class cc
      JOIN class c ON c.id = cc.class_id
      GROUP BY cc.course_id
    ''');
    return <int, int>{
      for (final row in rows) row['course_id'] as int: (row['total'] as int?) ?? 0,
    };
  }

  Future<int> createCourse(Course course) async {
    final db = await _database;
    if (course.name.trim().isEmpty) {
      throw const ValidationException('课程名称不能为空');
    }
    if (course.classIds.isEmpty) {
      throw const ValidationException('课程至少要挂载一个班级');
    }
    try {
      return await db.transaction((txn) async {
        final id = await txn.insert('course', course.toMap());
        for (final classId in course.classIds.toSet()) {
          await txn.insert(
            'course_class',
            <String, Object?>{'course_id': id, 'class_id': classId},
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        }
        return id;
      });
    } catch (error, stack) {
      AppLogger.e('新建课程失败', error: error, stack: stack);
      throw DatabaseException('新建课程失败：$error', cause: error);
    }
  }

  Future<void> updateCourse(Course course) async {
    final db = await _database;
    if (course.id == null) {
      throw const ValidationException('课程 id 缺失');
    }
    if (course.classIds.isEmpty) {
      throw const ValidationException('课程至少要挂载一个班级');
    }
    try {
      await db.transaction((txn) async {
        await txn.update(
          'course',
          course.toMap(),
          where: 'id = ?',
          whereArgs: <Object?>[course.id],
        );
        // 关联关系整体替换，避免残留已移除的班级
        await txn.delete(
          'course_class',
          where: 'course_id = ?',
          whereArgs: <Object?>[course.id],
        );
        for (final classId in course.classIds.toSet()) {
          await txn.insert(
            'course_class',
            <String, Object?>{'course_id': course.id, 'class_id': classId},
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        }
      });
    } catch (error, stack) {
      AppLogger.e('更新课程失败', error: error, stack: stack);
      throw DatabaseException('更新课程失败：$error', cause: error);
    }
  }

  /// 删除课程会级联删除其 lesson（外键 ON DELETE CASCADE）。
  Future<void> deleteCourse(int id) async {
    final db = await _database;
    try {
      await db.transaction((txn) async {
        await txn.delete('course', where: 'id = ?', whereArgs: <Object?>[id]);
      });
    } catch (error, stack) {
      AppLogger.e('删除课程失败', error: error, stack: stack);
      throw DatabaseException('删除课程失败：$error', cause: error);
    }
  }

  /// 清空全部课程（设置页「清空全部课程」，级联清掉对应课表条目）。
  Future<int> clearAllCourses() async {
    final db = await _database;
    final before = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM course'),
        ) ??
        0;
    try {
      await db.transaction((txn) async {
        await txn.delete('course');
      });
      return before;
    } catch (error, stack) {
      AppLogger.e('清空课程失败', error: error, stack: stack);
      throw DatabaseException('清空课程失败：$error', cause: error);
    }
  }

  Course _fromJoinedRow(Map<String, Object?> row) {
    final raw = row['class_ids'] as String?;
    final ids = <int>[
      if (raw != null)
        for (final part in raw.split(','))
          if (int.tryParse(part) != null) int.parse(part),
    ];
    return Course.fromMap(row, classIds: ids);
  }
}
