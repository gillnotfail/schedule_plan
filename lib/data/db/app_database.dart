import 'dart:io' show Platform;

import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide DatabaseException;

import 'package:schedule_plan/core/error/app_exceptions.dart';
import 'package:schedule_plan/core/logging/app_logger.dart';
import 'package:schedule_plan/data/db/schema.dart';

/// SQLite 连接单例。
///
/// readme 第七章 7.6：SQLite 本地存储；不使用云端数据库。
abstract final class AppDatabase {
  static const String fileName = 'schedule_plan.db';

  static Database? _database;
  static bool _ffiReady = false;

  /// 获取数据库实例，首次调用时打开并按需建表/迁移。
  static Future<Database> instance() async {
    final existing = _database;
    if (existing != null && existing.isOpen) {
      return existing;
    }
    _ensureDatabaseFactory();
    try {
      final directory = await getDatabasesPath();
      final path = p.join(directory, fileName);
      final db = await openDatabase(
        path,
        version: DatabaseSchema.version,
        onConfigure: (db) async {
          // 外键级联策略依赖此开关
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (db, version) => DatabaseSchema.createAll(db),
        onUpgrade: (db, from, to) => DatabaseSchema.migrate(db, from, to),
      );
      _database = db;
      AppLogger.i('数据库已打开：$path（version ${DatabaseSchema.version}）');
      return db;
    } catch (error, stack) {
      AppLogger.e('打开数据库失败', error: error, stack: stack);
      throw DatabaseException('打开本地数据库失败：$error', cause: error);
    }
  }

  /// 桌面平台必须先初始化 sqflite FFI 工厂，否则直接 `openDatabase` 抛
  /// `bad state: databaseFactory not initialized`（APK / iOS 走系统 SQLite，不需要）。
  static void _ensureDatabaseFactory() {
    if (_ffiReady) {
      return;
    }
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    _ffiReady = true;
  }

  /// 关闭连接（应用退出或单元测试收尾时调用）。
  static Future<void> close() async {
    final db = _database;
    _database = null;
    if (db != null && db.isOpen) {
      await db.close();
    }
  }
}
