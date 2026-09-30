import 'package:sqflite/sqflite.dart' hide DatabaseException;

import 'package:schedule_plan/core/error/app_exceptions.dart';
import 'package:schedule_plan/core/logging/app_logger.dart';
import 'package:schedule_plan/data/db/app_database.dart';
import 'package:schedule_plan/data/models/import_log.dart';

// 第 19 轮从 llm_repository.dart 拆出来的：那个文件里同时装着 LlmProviderRepository
// 与 ImportLogRepository，LLM 提供商整块下线后只能拆开，否则批量导入日志会跟着一起
// 消失。

/// 批量导入日志数据访问层（readme 3.13 表）。
class ImportLogRepository {
  ImportLogRepository({Database? database}) : _db = database;

  Database? _db;

  Future<Database> get _database async => _db ??= await AppDatabase.instance();

  Future<int> saveLog(ImportLog log) async {
    final db = await _database;
    try {
      return db.insert('import_log', log.toMap());
    } catch (error, stack) {
      AppLogger.e('写入导入日志失败', error: error, stack: stack);
      throw DatabaseException('写入导入日志失败：$error', cause: error);
    }
  }

  Future<List<ImportLog>> listLogs({int limit = 50}) async {
    final db = await _database;
    final rows = await db.query(
      'import_log',
      orderBy: 'imported_at DESC',
      limit: limit,
    );
    return rows.map(ImportLog.fromMap).toList();
  }

  /// 超期导入日志清理（保留天数来自设置，readme 7.6）。
  Future<int> deleteBefore(int cutoffMillis) async {
    final db = await _database;
    try {
      return await db.transaction((txn) async {
        return txn.delete(
          'import_log',
          where: 'imported_at < ?',
          whereArgs: <Object?>[cutoffMillis],
        );
      });
    } catch (error, stack) {
      AppLogger.e('清理导入日志失败', error: error, stack: stack);
      throw DatabaseException('清理导入日志失败：$error', cause: error);
    }
  }
}
