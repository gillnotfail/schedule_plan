import 'package:sqflite/sqflite.dart' hide DatabaseException;

import 'package:schedule_plan/core/error/app_exceptions.dart';
import 'package:schedule_plan/core/logging/app_logger.dart';
import 'package:schedule_plan/data/db/app_database.dart';
import 'package:schedule_plan/data/models/class_course.dart';
import 'package:schedule_plan/data/repositories/template_repository.dart';

/// 班级数据访问层（readme 3.3 表）。
class ClassRepository {
  ClassRepository({Database? database}) : _db = database;

  Database? _db;

  Future<Database> get _database async => _db ??= await AppDatabase.instance();

  /// 班级列表，按 sort_order（拖拽排序结果）升序。
  Future<List<ClassInfo>> listClasses() async {
    final db = await _database;
    final rows = await db.query('class', orderBy: 'sort_order ASC, id ASC');
    return rows.map(ClassInfo.fromMap).toList();
  }

  Future<List<String>> listGrades() async {
    final db = await _database;
    final rows = await db.rawQuery(
      'SELECT DISTINCT grade FROM class ORDER BY grade ASC',
    );
    return rows.map((row) => row['grade'] as String).toList();
  }

  Future<List<ClassInfo>> listByGrade(String grade) async {
    final db = await _database;
    final rows = await db.query(
      'class',
      where: 'grade = ?',
      whereArgs: <Object?>[grade],
      orderBy: 'sort_order ASC, id ASC',
    );
    return rows.map(ClassInfo.fromMap).toList();
  }

  Future<ClassInfo?> getClass(int id) async {
    final db = await _database;
    final rows = await db.query(
      'class',
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return ClassInfo.fromMap(rows.first);
  }

  /// 新建班级。sort_order 取当前最大值 +1，保证新班级排在末尾。
  Future<int> createClass(ClassInfo info) async {
    final db = await _database;
    if (info.name.trim().isEmpty) {
      throw const ValidationException('班级名称不能为空');
    }
    if (info.grade.trim().isEmpty) {
      throw const ValidationException('年级不能为空');
    }
    try {
      return await db.transaction((txn) async {
        final maxOrder = Sqflite.firstIntValue(
              await txn.rawQuery('SELECT MAX(sort_order) FROM class'),
            ) ??
            -1;
        return txn.insert('class', info.copyWith(sortOrder: maxOrder + 1).toMap());
      });
    } catch (error, stack) {
      AppLogger.e('新建班级失败', error: error, stack: stack);
      throw DatabaseException('新建班级失败：$error', cause: error);
    }
  }

  Future<void> updateClass(ClassInfo info) async {
    final db = await _database;
    if (info.id == null) {
      throw const ValidationException('班级 id 缺失');
    }
    await db.update(
      'class',
      info.toMap(),
      where: 'id = ?',
      whereArgs: <Object?>[info.id],
    );
  }

  /// 删除班级。级联删除其课程 / 课表 / 学生 / 考勤（外键 ON DELETE CASCADE）。
  Future<void> deleteClass(int id) async {
    final db = await _database;
    try {
      await db.transaction((txn) async {
        await txn.delete('class', where: 'id = ?', whereArgs: <Object?>[id]);
      });
    } catch (error, stack) {
      AppLogger.e('删除班级失败', error: error, stack: stack);
      throw DatabaseException('删除班级失败：$error', cause: error);
    }
  }

  /// 班级列表拖拽排序持久化（模块六 6.4）。
  Future<void> reorderClasses(List<int> orderedIds) async {
    final db = await _database;
    try {
      await db.transaction((txn) async {
        for (var i = 0; i < orderedIds.length; i++) {
          await txn.update(
            'class',
            <String, Object?>{'sort_order': i},
            where: 'id = ?',
            whereArgs: <Object?>[orderedIds[i]],
          );
        }
      });
    } catch (error, stack) {
      AppLogger.e('保存班级排序失败', error: error, stack: stack);
      throw DatabaseException('保存班级排序失败：$error', cause: error);
    }
  }

  /// 批量修改本年级所有班级的作息模板（模块一 1.3）。
  Future<void> updateTemplateForGrade(String grade, int templateId) async {
    final db = await _database;
    try {
      await db.transaction((txn) async {
        await txn.update(
          'class',
          <String, Object?>{'template_id': templateId},
          where: 'grade = ?',
          whereArgs: <Object?>[grade],
        );
      });
    } catch (error, stack) {
      AppLogger.e('批量修改作息模板失败', error: error, stack: stack);
      throw DatabaseException('批量修改作息模板失败：$error', cause: error);
    }
  }

  /// 同步 student_count 冗余字段（增删学生时调用）。
  Future<void> syncStudentCount(int classId) async {
    final db = await _database;
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

  /// 按名称查找班级（Excel 导入时用于匹配已存在班级）。
  Future<ClassInfo?> findByName(String name) async {
    final db = await _database;
    final rows = await db.query(
      'class',
      where: 'name = ?',
      whereArgs: <Object?>[name.trim()],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return ClassInfo.fromMap(rows.first);
  }

  /// Excel 导入时按名单里的班级名「按需建档」：
  /// 已存在则直接返回，不存在则用默认作息模板自动创建。
  ///
  /// 用户规格：**只要 Excel 里出现过的班级都默认显示在班级列表里**，
  /// 因此这里不做任何白名单过滤。
  Future<ClassInfo> ensureClass(String name, {required String color}) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw const ValidationException('班级名称不能为空');
    }
    final existing = await findByName(trimmed);
    if (existing != null) {
      return existing;
    }
    final defaultTemplate =
        await TemplateRepository().getDefaultTemplate();
    if (defaultTemplate?.id == null) {
      throw const ValidationException('缺少默认作息模板，无法自动创建班级');
    }
    final id = await createClass(
      ClassInfo(
        name: trimmed,
        grade: _inferGrade(trimmed),
        color: color,
        templateId: defaultTemplate!.id!,
      ),
    );
    return ClassInfo(
      id: id,
      name: trimmed,
      grade: _inferGrade(trimmed),
      color: color,
      templateId: defaultTemplate.id!,
    );
  }

  /// 从班级名推断年级：`高一(3)班` -> `高一`；识别不到时归入「其他」。
  ///
  /// grade 在库里是 NOT NULL，导入时无法向用户追问，只能做保守推断。
  static String _inferGrade(String className) {
    final match = RegExp(r'^([\u4e00-\u9fa5]{0,4}?[一二三四五六七八九]?年级?)')
        .firstMatch(className);
    final guess = match?.group(1) ?? '';
    if (guess.isEmpty || guess.length > 4) {
      return RegExp(r'^[0-9]{4}').hasMatch(className) ? className.substring(0, 4) : '其他';
    }
    return guess;
  }
}
