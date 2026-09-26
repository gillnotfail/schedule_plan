import 'package:sqflite/sqflite.dart';

import 'package:schedule_plan/core/constants/setting_keys.dart';
import 'package:schedule_plan/core/logging/app_logger.dart';
import 'package:schedule_plan/data/db/app_database.dart';

/// app_settings 读写（readme 3.15 表）。
///
/// 所有「可在设置中调整」的阈值都从这里读写，避免魔法数字散落。
class SettingsRepository {
  SettingsRepository({Database? database}) : _db = database;

  Database? _db;

  Future<Database> get _database async => _db ??= await AppDatabase.instance();

  /// 读取字符串设置，缺失时返回 [SettingKeys.defaults] 中的默认值。
  Future<String> read(String key, {String? fallback}) async {
    try {
      final db = await _database;
      final rows = await db.query(
        'app_settings',
        columns: <String>['value'],
        where: 'key = ?',
        whereArgs: <Object?>[key],
        limit: 1,
      );
      if (rows.isEmpty) {
        return fallback ?? SettingKeys.defaults[key] ?? '';
      }
      return rows.first['value'] as String;
    } catch (error, stack) {
      AppLogger.e('读取设置失败：$key', error: error, stack: stack);
      return fallback ?? SettingKeys.defaults[key] ?? '';
    }
  }

  Future<int> readInt(String key) async =>
      int.tryParse(await read(key)) ?? int.tryParse(SettingKeys.defaults[key] ?? '') ?? 0;

  Future<double> readDouble(String key) async =>
      double.tryParse(await read(key)) ??
      double.tryParse(SettingKeys.defaults[key] ?? '') ??
      0;

  Future<bool> readBool(String key) async => (await read(key)) == '1';

  /// 写入设置（UPSERT）。
  Future<void> write(String key, String value) async {
    final db = await _database;
    try {
      await db.insert(
        'app_settings',
        <String, Object?>{'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (error, stack) {
      AppLogger.e('写入设置失败：$key', error: error, stack: stack);
      rethrow;
    }
  }

  Future<void> writeInt(String key, int value) => write(key, value.toString());

  Future<void> writeDouble(String key, double value) => write(key, value.toString());

  Future<void> writeBool(String key, bool value) => write(key, value ? '1' : '0');
}
