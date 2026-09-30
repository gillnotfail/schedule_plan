import 'package:sqflite/sqflite.dart' hide DatabaseException;

import 'package:schedule_plan/core/error/app_exceptions.dart';
import 'package:schedule_plan/core/logging/app_logger.dart';
import 'package:schedule_plan/data/db/app_database.dart';
import 'package:schedule_plan/data/db/schema.dart';

/// 维护类操作：清空业务数据、数据库自检。
class MaintenanceRepository {
  MaintenanceRepository({Database? database}) : _db = database;

  Database? _db;

  Future<Database> get _database async => _db ??= await AppDatabase.instance();

  /// 清空全部业务数据（设置保留，避免用户丢失语言/主题偏好）。
  ///
  /// 整段包在事务中，任一步失败整体回滚。
  Future<void> clearAllData() async {
    final db = await _database;
    const tables = <String>[
      'attendance_record',
      'student_tag_record',
      'lesson',
      'student',
      'course',
      'class',
      'todo',
      'schedule_event',
      'focus_session',
      'import_log',
    ];
    try {
      await db.transaction((txn) async {
        for (final table in tables) {
          await txn.delete(table);
        }
      });
      AppLogger.i('已清空全部业务数据');
    } catch (error, stack) {
      AppLogger.e('清空数据失败，事务已回滚', error: error, stack: stack);
      throw DatabaseException('清空数据失败，已回滚：$error', cause: error);
    }
  }

  /// 迁移后一致性校验入口（设置页「自检」按钮）。
  Future<bool> validateIntegrity() async {
    final db = await _database;
    try {
      await DatabaseSchema.validate(db);
      return true;
    } catch (error, stack) {
      AppLogger.e('数据库一致性校验未通过', error: error, stack: stack);
      return false;
    }
  }
}
