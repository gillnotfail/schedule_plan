import 'package:sqflite/sqflite.dart' hide DatabaseException;

import 'package:schedule_plan/core/error/app_exceptions.dart';
import 'package:schedule_plan/core/logging/app_logger.dart';
import 'package:schedule_plan/data/db/app_database.dart';
import 'package:schedule_plan/data/models/import_log.dart';
import 'package:schedule_plan/data/models/llm_provider_config.dart';

/// LLM 提供商配置数据访问层（readme 3.14 表）。
class LlmProviderRepository {
  LlmProviderRepository({Database? database}) : _db = database;

  Database? _db;

  Future<Database> get _database async => _db ??= await AppDatabase.instance();

  Future<List<LlmProviderConfig>> listProviders() async {
    final db = await _database;
    final rows = await db.query(
      'llm_provider_config',
      orderBy: 'is_default DESC, id ASC',
    );
    return rows.map(LlmProviderConfig.fromMap).toList();
  }

  Future<LlmProviderConfig?> getDefaultProvider() async {
    final providers = await listProviders();
    if (providers.isEmpty) {
      return null;
    }
    return providers.firstWhere(
      (item) => item.isDefault,
      orElse: () => providers.first,
    );
  }

  Future<int> createProvider(LlmProviderConfig config) async {
    final db = await _database;
    if (config.name.trim().isEmpty || config.baseUrl.trim().isEmpty) {
      throw const ValidationException('提供商名称与接口地址不能为空');
    }
    try {
      return db.transaction((txn) async {
        final count = Sqflite.firstIntValue(
              await txn.rawQuery('SELECT COUNT(*) FROM llm_provider_config'),
            ) ??
            0;
        return txn.insert(
          'llm_provider_config',
          config.copyWith(isDefault: count == 0 ? true : config.isDefault).toMap(),
        );
      });
    } catch (error, stack) {
      AppLogger.e('新增 LLM 提供商失败', error: error, stack: stack);
      throw DatabaseException('新增 LLM 提供商失败：$error', cause: error);
    }
  }

  Future<void> updateProvider(LlmProviderConfig config) async {
    final db = await _database;
    if (config.id == null) {
      throw const ValidationException('提供商 id 缺失');
    }
    await db.update(
      'llm_provider_config',
      config.toMap(),
      where: 'id = ?',
      whereArgs: <Object?>[config.id],
    );
  }

  /// 切换默认提供商：事务内先清除其他记录的 is_default。
  Future<void> setDefaultProvider(int id) async {
    final db = await _database;
    try {
      await db.transaction((txn) async {
        await txn.update('llm_provider_config', <String, Object?>{'is_default': 0});
        await txn.update(
          'llm_provider_config',
          <String, Object?>{'is_default': 1},
          where: 'id = ?',
          whereArgs: <Object?>[id],
        );
      });
    } catch (error, stack) {
      AppLogger.e('切换默认 LLM 提供商失败', error: error, stack: stack);
      throw DatabaseException('切换默认 LLM 提供商失败：$error', cause: error);
    }
  }

  Future<void> deleteProvider(int id) async {
    final db = await _database;
    await db.delete('llm_provider_config', where: 'id = ?', whereArgs: <Object?>[id]);
  }
}

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
