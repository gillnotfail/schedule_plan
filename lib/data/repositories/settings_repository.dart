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

  /// 按 key 前缀批量读取，返回「完整键 → 值」。
  ///
  /// 服务的是「一天一条」的设置项 —— 目前只有调休映射
  /// （`holiday_shift_YYYY-MM-DD`，见 [SettingKeys.holidayShiftPrefix]）。
  /// 这类键逐条 [read] 会变成几十次 query（考勤页的圆环一次要算 42 天），
  /// 一次 `LIKE` 扫回来在内存里挑更快，也让调用方只付一次 IO。
  ///
  /// 注意 `_` 在 SQL LIKE 里是「任意单字符」通配符，而本项目的键名恰好
  /// 全是下划线分词（`holiday_shift_`），所以必须显式 `ESCAPE`，
  /// 否则 `holiday_shift_` 会顺带匹配到 `holidayXshiftY` 之类。
  Future<Map<String, String>> readByPrefix(String prefix) async {
    try {
      final db = await _database;
      final rows = await db.query(
        'app_settings',
        columns: <String>['key', 'value'],
        where: "key LIKE ? ESCAPE '\\'",
        whereArgs: <Object?>['${_escapeLike(prefix)}%'],
      );
      return <String, String>{
        for (final row in rows)
          (row['key'] as String? ?? ''): (row['value'] as String? ?? ''),
      };
    } catch (error, stack) {
      AppLogger.e('批量读取设置失败：$prefix', error: error, stack: stack);
      return const <String, String>{};
    }
  }

  /// 把 LIKE 的通配符（`%` `_`）与转义符本身都转义掉。
  static String _escapeLike(String value) => value
      .replaceAll('\\', '\\\\')
      .replaceAll('%', '\\%')
      .replaceAll('_', '\\_');

  Future<int> readInt(String key) async =>
      int.tryParse(await read(key)) ??
      int.tryParse(SettingKeys.defaults[key] ?? '') ??
      0;

  Future<double> readDouble(String key) async =>
      double.tryParse(await read(key)) ??
      double.tryParse(SettingKeys.defaults[key] ?? '') ??
      0;

  Future<bool> readBool(String key) async => (await read(key)) == '1';

  /// 写入设置（UPSERT）。
  Future<void> write(String key, String value) async {
    final db = await _database;
    try {
      await db.insert('app_settings', <String, Object?>{
        'key': key,
        'value': value,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    } catch (error, stack) {
      AppLogger.e('写入设置失败：$key', error: error, stack: stack);
      rethrow;
    }
  }

  Future<void> writeInt(String key, int value) => write(key, value.toString());

  Future<void> writeDouble(String key, double value) =>
      write(key, value.toString());

  Future<void> writeBool(String key, bool value) =>
      write(key, value ? '1' : '0');
}
