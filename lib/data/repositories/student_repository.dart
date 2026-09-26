import 'package:sqflite/sqflite.dart' hide DatabaseException;

import 'package:schedule_plan/core/error/app_exceptions.dart';
import 'package:schedule_plan/core/logging/app_logger.dart';
import 'package:schedule_plan/data/db/app_database.dart';
import 'package:schedule_plan/data/models/student.dart';

/// 学生数据访问层（readme 3.6 表）。
class StudentRepository {
  StudentRepository({Database? database}) : _db = database;

  Database? _db;

  Future<Database> get _database async => _db ??= await AppDatabase.instance();

  Future<List<Student>> listByClass(int classId) async {
    final db = await _database;
    final rows = await db.query(
      'student',
      where: 'class_id = ?',
      whereArgs: <Object?>[classId],
      orderBy: 'id ASC',
    );
    return rows.map(Student.fromMap).toList();
  }

  /// 多个班级的学生（合班/大课去点名时用）。
  ///
  /// 用户规格：课程管理里可以给一门课勾选**多个班级**，那么这节课的学生就是
  /// 这些班级名单的并集——点「去点名」时必须全都在，不能只出现其中一个班。
  /// 因此这里按班级聚合，同一个学生只出现一次（`IN` 天然去重），
  /// 返回顺序先按班级、再按班级内 id，方便按班核对名单。
  Future<List<Student>> listByClasses(Iterable<int> classIds) async {
    final ids = classIds.toSet().toList(growable: false);
    if (ids.isEmpty) {
      return const <Student>[];
    }
    final db = await _database;
    final placeholders = List<String>.filled(ids.length, '?').join(',');
    final rows = await db.query(
      'student',
      where: 'class_id IN ($placeholders)',
      whereArgs: ids.cast<Object?>(),
      orderBy: 'class_id ASC, id ASC',
    );
    return rows.map(Student.fromMap).toList();
  }

  /// 全部学生（设置页「学生名单」总览）。
  Future<List<Student>> listAll() async {
    final db = await _database;
    final rows = await db.query(
      'student',
      orderBy: 'class_id ASC, id ASC',
    );
    return rows.map(Student.fromMap).toList();
  }

  /// 各班级人数（导入后用于刷新班级列表的冗余人数列）。
  Future<Map<int, int>> countByClass() async {
    final db = await _database;
    final rows = await db.rawQuery(
      'SELECT class_id, COUNT(*) AS cnt FROM student GROUP BY class_id',
    );
    return <int, int>{
      for (final row in rows) row['class_id'] as int: (row['cnt'] as int?) ?? 0,
    };
  }

  /// 导入去重用的键：**同一个班里的同名同学视为同一个人**。
  ///
  /// 抽成静态纯函数是为了让"重复判定"只有一处口径，并且可以直接单测。
  static String rosterKey(int classId, String name) =>
      '$classId|${name.trim()}';

  /// 全库已有学生的去重键集合。
  ///
  /// Excel 导入现在**没有二次确认**（选完文件就入库），所以必须在写库前
  /// 拿它拦一道：否则误选同一个文件两次，整份名单会翻倍。
  Future<Set<String>> existingRosterKeys() async {
    final all = await listAll();
    return <String>{
      for (final student in all) rosterKey(student.classId, student.name),
    };
  }

  Future<Student?> getStudent(int id) async {
    final db = await _database;
    final rows = await db.query(
      'student',
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return Student.fromMap(rows.first);
  }

  /// 新增学生，并同步 class.student_count 冗余字段。
  Future<int> createStudent(Student student) async {
    final db = await _database;
    if (student.name.trim().isEmpty) {
      throw const ValidationException('学生姓名不能为空');
    }
    try {
      final id = await db.insert('student', student.toMap());
      await _syncCount(db, student.classId);
      return id;
    } catch (error, stack) {
      AppLogger.e('新增学生失败', error: error, stack: stack);
      throw DatabaseException('新增学生失败：$error', cause: error);
    }
  }

  Future<void> updateStudent(Student student) async {
    final db = await _database;
    if (student.id == null) {
      throw const ValidationException('学生 id 缺失');
    }
    final previous = await getStudent(student.id!);
    await db.update(
      'student',
      student.toMap(),
      where: 'id = ?',
      whereArgs: <Object?>[student.id],
    );
    await _syncCount(db, student.classId);
    // 学生被转到别的班级时，原班级的人数也要同步
    if (previous != null && previous.classId != student.classId) {
      await _syncCount(db, previous.classId);
    }
  }

  Future<void> deleteStudent(int id) async {
    final db = await _database;
    final student = await getStudent(id);
    try {
      await db.delete('student', where: 'id = ?', whereArgs: <Object?>[id]);
      if (student != null) {
        await _syncCount(db, student.classId);
      }
    } catch (error, stack) {
      AppLogger.e('删除学生失败', error: error, stack: stack);
      throw DatabaseException('删除学生失败：$error', cause: error);
    }
  }

  /// Excel 批量导入：整批包在事务中，任一行失败整体回滚。
  ///
  /// 一份名单可能同时覆盖多个班级（合班导入），因此逐行按各自的 class_id
  /// 落库，最后统一同步受影响的班级人数。
  Future<int> insertMany(List<Student> students) async {
    final db = await _database;
    if (students.isEmpty) {
      return 0;
    }
    try {
      var inserted = 0;
      await db.transaction((txn) async {
        for (final student in students) {
          await txn.insert('student', student.toMap());
          inserted++;
        }
      });
      for (final classId in students.map((item) => item.classId).toSet()) {
        await _syncCount(db, classId);
      }
      return inserted;
    } catch (error, stack) {
      AppLogger.e('批量导入学生失败', error: error, stack: stack);
      throw DatabaseException('批量导入学生失败：$error', cause: error);
    }
  }

  Future<void> _syncCount(Database db, int classId) async {
    final count = Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM student WHERE class_id = ?',
            <Object?>[classId],
          ),
        ) ??
        0;
    await db.update(
      'class',
      <String, Object?>{'student_count': count},
      where: 'id = ?',
      whereArgs: <Object?>[classId],
    );
  }
}
