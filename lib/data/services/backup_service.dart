/// 数据备份与恢复（用户规格第 36 轮）。
///
/// 背景：老师一旦卸载重装，库里的名单、课表、一学期记下来的考勤全部消失。
/// 更新检查坏掉那一版就是活例子——让人重装前先能把自己的东西存出来。
///
/// 四条设计原则：
///
/// 1. **按条目选，但依赖自动补齐**。条目之间存在真实外键（考勤要能找到人和课），
///    只勾「考勤记录」就必然恢复失败，所以 [resolve] 会把被依赖的条目一起带上，
///    界面上标成"已包含"。宁可多备份两张表，也不要做出一个导不回来的文件。
///
/// 2. **存 JSON，不打包 .db 文件**。数据库文件跟设备、跟版本强耦合，
///    跨版本直接塞回去轻则 `database disk image is malformed`，重则把好数据也弄坏；
///    JSON 逐表逐行对齐，缺列用默认值、多出来的表直接忽略，才有跨版本的余地。
///
/// 3. **恢复是"放回来"，不是"还原成那天"**。写回策略是"先 UPDATE、更新不到再
///    INSERT"（见 [_writeRow]），**既不删除**备份里没有的数据，也不触发外键级联。
///    用户在这期间新记的考勤不该因为一次恢复被抹掉；真要清空，设置页里有明确的
///    「清空数据」。
///
/// 4. **整段包在事务里**。恢复中途外键失败（备份来自另一套数据、缺了学生）
///    必须整体回滚，不能留下半套数据——半套比没有更难查。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' hide DatabaseException;

import 'package:schedule_plan/core/constants/setting_keys.dart';
import 'package:schedule_plan/core/logging/app_logger.dart';
import 'package:schedule_plan/core/utils/file_naming.dart';
import 'package:schedule_plan/data/db/app_database.dart';
import 'package:schedule_plan/data/db/schema.dart';

/// 备份条目：界面上让用户勾的"要备份什么"。
///
/// 声明顺序 = 备份文件里的表顺序 = 恢复时的写入顺序，
/// 靠被引用的表排在前面来满足外键（[restoreOrder] 由这份顺序生成）。
enum BackupSlice {
  /// 班级名单（连带所用作息模板：班级的 `template_id` 是 NOT NULL，
  /// 课表第一列的时间也完全由它决定，少了它课表就是一堆没有时间的格子）。
  classes,

  /// 学生名单。`student.class_id` 是 NOT NULL，所以依赖 [classes]。
  students,

  /// 课程（含「合班」关联与休学 / 免修这类课程级长期状态）。
  courses,

  /// 课表：每个格子排了哪门课。
  timetable,

  /// 考勤记录：一天天点出来的历史。
  attendance,

  /// 表现标签（星级评价）。
  tags,

  /// 偏好设置：默认考勤状态、风险阈值、调休那天上周几的课……
  ///
  /// 这些是老师一条条手工设过的，重装后全部回到出厂值同样让人难受。
  /// 运行时的临时键不进备份（见 [_volatileSettings]）。
  settings,
}

/// 一个条目装哪些表、依赖哪些条目。
class _SliceSpec {
  const _SliceSpec(this.tables, [this.requires = const <BackupSlice>{}]);

  /// 该条目负责的表，顺序即写入顺序。
  final List<String> tables;

  /// 必须先有这些条目，本条目才恢复得进去。
  final Set<BackupSlice> requires;
}

/// 条目 → 表 的映射。
///
/// 注意 [BackupSlice.courses] 里装着 `student_course_status`：它语义上是
/// "某生在某门课上的长期状态"，结构上两头都是硬外键，只能等学生和课程都在
/// 之后才写——所以它跟着课程走，`courses` 也就顺带依赖 `students`。
const Map<BackupSlice, _SliceSpec> _sliceSpecs = <BackupSlice, _SliceSpec>{
  BackupSlice.classes: _SliceSpec(<String>[
    'schedule_template',
    'template_period',
    'class',
  ]),
  BackupSlice.students: _SliceSpec(
    <String>['student'],
    <BackupSlice>{BackupSlice.classes},
  ),
  BackupSlice.courses: _SliceSpec(
    <String>['course', 'course_class', 'student_course_status'],
    <BackupSlice>{BackupSlice.classes, BackupSlice.students},
  ),
  BackupSlice.timetable: _SliceSpec(
    <String>['lesson'],
    <BackupSlice>{BackupSlice.classes, BackupSlice.courses},
  ),
  BackupSlice.attendance: _SliceSpec(
    <String>['attendance_record'],
    <BackupSlice>{BackupSlice.students, BackupSlice.timetable},
  ),
  BackupSlice.tags: _SliceSpec(
    <String>['student_tag_record'],
    <BackupSlice>{BackupSlice.students},
  ),
  BackupSlice.settings: _SliceSpec(<String>['app_settings']),
};

/// 界面上每个条目显示"当前有多少条"时看的那张表。
///
/// 不能拿条目里所有表的行数相加：一个班就带 50 行作息，
/// 显示"当前 153 条"只会让人以为备份了什么了不得的东西。
const Map<BackupSlice, String> _countTableOf = <BackupSlice, String>{
  BackupSlice.classes: 'class',
  BackupSlice.students: 'student',
  BackupSlice.courses: 'course',
  BackupSlice.timetable: 'lesson',
  BackupSlice.attendance: 'attendance_record',
  BackupSlice.tags: 'student_tag_record',
  BackupSlice.settings: 'app_settings',
};

/// 恢复时的写表顺序：严格由条目声明顺序展开，被引用的表先写。
final List<String> restoreOrder = <String>[
  for (final slice in BackupSlice.values) ..._sliceSpecs[slice]!.tables,
];

/// 备份文件里认识的所有表（其余表名一律忽略，给未来版本留余地）。
final Set<String> _knownTables = <String>{...restoreOrder};

/// 不进备份的 `app_settings` 键：都是**运行时状态**，不是老师的配置。
///
/// - `focus_session_snapshot`：进行中的专注会话快照，恢复到另一台设备毫无意义；
/// - `holiday_last_sync_at` / `holiday_last_sync_ok`：上次联网取节假日的节流记录，
///   恢复成旧值只会让"该不该再取一次"判断错；
/// - `update_last_check_at` / `update_skipped_version_code`：更新检查的节流与
///   "跳过这一版"，跟着设备走，不该跟着数据走。
///
/// 备份与恢复**两处都过滤**：备份时排除，恢复时再挡一次——
/// 用户手工改过的备份文件也不该把这类键塞回来。
const Set<String> _volatileSettings = <String>{
  SettingKeys.focusSessionSnapshot,
  SettingKeys.holidayLastSyncAt,
  SettingKeys.holidayLastSyncOk,
  SettingKeys.updateLastCheckAt,
  SettingKeys.updateSkippedVersionCode,
};

/// 备份文件的格式标记与版本。
///
/// [backupAppTag] 用来一眼认出"这是本应用的文件"，防止把别的 JSON 当备份导进来；
/// [backupFormatVersion] 只在**结构不兼容**时才 +1（加表加字段不算），
/// 这样老备份永远能读。
const String backupAppTag = 'schedule_plan';
const int backupFormatVersion = 1;

/// 解析备份文件时的三类失败。
enum BackupProblem {
  /// 根本不是备份文件（JSON 都不是，或者是别人的 JSON）
  notBackup,

  /// 备份来自更新版本的应用，当前版本读不懂
  newerFormat,

  /// 结构损坏（缺字段、某一行不是对象……）
  broken,
}

/// 备份文件读不出来。
class BackupFormatException implements Exception {
  const BackupFormatException(this.problem);

  final BackupProblem problem;

  @override
  String toString() => 'BackupFormatException($problem)';
}

/// 恢复到库里失败（多半是外键对不上：备份缺了它依赖的人/课）。
class BackupRestoreException implements Exception {
  const BackupRestoreException(this.cause);

  final Object cause;

  @override
  String toString() => 'BackupRestoreException($cause)';
}

/// 一份备份：元信息 + 逐表的行。
class BackupBundle {
  const BackupBundle({
    required this.createdAt,
    required this.schemaVersion,
    required this.appVersion,
    required this.slices,
    required this.tables,
  });

  /// 备份生成时间（本地时间）。
  final DateTime createdAt;

  /// 生成备份那台设备的数据库版本，恢复前拿来提示"版本不一致"。
  final int schemaVersion;

  /// 生成备份时的应用版本号，只用于展示（如 `1.0.17+18`）。
  final String appVersion;

  /// 这份备份实际包含的条目（已展开依赖）。
  final List<BackupSlice> slices;

  /// 表名 → 行。行是 sqflite 原样查出来的 `列名 → 值`。
  final Map<String, List<Map<String, Object?>>> tables;

  int get totalRows =>
      tables.values.fold<int>(0, (sum, rows) => sum + rows.length);

  int countOf(String table) => tables[table]?.length ?? 0;

  bool contains(BackupSlice slice) => slices.contains(slice);
}

/// 恢复结果：每张表实际写回多少行。
class RestoreReport {
  const RestoreReport(this.counts);

  final Map<String, int> counts;

  int get totalRows => counts.values.fold<int>(0, (sum, n) => sum + n);

  int countOf(String table) => counts[table] ?? 0;
}

/// 数据备份与恢复。
///
/// 无状态：所有方法要么纯函数，要么直接对库操作，可以随手 new。
class BackupService {
  BackupService({Database? database}) : _db = database;

  Database? _db;

  Future<Database> get _database async => _db ??= await AppDatabase.instance();

  /// 当前应用的数据库版本，界面上用来提示"这份备份来自另一个版本"。
  int get currentSchemaVersion => DatabaseSchema.version;

  // ---------------------------------------------------------------------------
  // 条目与依赖
  // ---------------------------------------------------------------------------

  /// 把用户勾的条目展开成**能真正恢复回去**的最小集合（含依赖，顺序稳定）。
  ///
  /// 例如只勾「考勤记录」会得到 班级 → 学生 → 课程 → 课表 → 考勤 五条：
  /// 少任何一条，恢复时 `attendance_record` 的外键就会把它整段挡回去。
  List<BackupSlice> resolve(Iterable<BackupSlice> selected) {
    final result = <BackupSlice>{};
    final queue = <BackupSlice>[...selected];
    while (queue.isNotEmpty) {
      final slice = queue.removeLast();
      if (!result.add(slice)) {
        continue;
      }
      queue.addAll(_sliceSpecs[slice]!.requires);
    }
    // 按声明顺序输出：既是备份文件的表顺序，也是恢复顺序
    return <BackupSlice>[
      for (final slice in BackupSlice.values)
        if (result.contains(slice)) slice,
    ];
  }

  /// [resolve] 之后**被自动带上**的条目（界面上标"已包含"）。
  List<BackupSlice> impliedBy(Iterable<BackupSlice> selected) {
    final picked = selected.toSet();
    return resolve(picked).where((slice) => !picked.contains(slice)).toList();
  }

  /// 每个条目当前有多少条数据（界面上的"当前 N 条"）。
  Future<Map<BackupSlice, int>> countRows({Database? database}) async {
    final db = database ?? await _database;
    final result = <BackupSlice, int>{};
    for (final slice in BackupSlice.values) {
      final table = _countTableOf[slice]!;
      result[slice] = await _count(db, table);
    }
    return result;
  }

  Future<int> _count(Database db, String table) async {
    if (table == 'app_settings') {
      final rows = await db.query('app_settings', columns: <String>['key']);
      return rows
          .where((row) => !_volatileSettings.contains(row['key']))
          .length;
    }
    return Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM $table'),
        ) ??
        0;
  }

  // ---------------------------------------------------------------------------
  // 备份
  // ---------------------------------------------------------------------------

  /// 把选中条目（含依赖）的数据整份读出来。
  ///
  /// [appVersion] 只用于展示，读不到版本号时留空即可。
  Future<BackupBundle> collect(
    Iterable<BackupSlice> selected, {
    Database? database,
    String appVersion = '',
  }) async {
    final db = database ?? await _database;
    final slices = resolve(selected);
    final tables = <String, List<Map<String, Object?>>>{};
    for (final slice in slices) {
      for (final table in _sliceSpecs[slice]!.tables) {
        var rows = await db.query(table);
        if (table == 'app_settings') {
          rows = rows
              .where((row) => !_volatileSettings.contains(row['key']))
              .toList();
        }
        tables[table] = <Map<String, Object?>>[
          for (final row in rows) _asRow(row),
        ];
      }
    }
    return BackupBundle(
      createdAt: DateTime.now(),
      schemaVersion: DatabaseSchema.version,
      appVersion: appVersion,
      slices: slices,
      tables: tables,
    );
  }

  /// 序列化成写入文件的字符串（UTF-8 明文 JSON，用户用记事本也能看）。
  String encode(BackupBundle bundle) {
    final payload = <String, Object?>{
      'app': backupAppTag,
      'format': backupFormatVersion,
      'created_at': bundle.createdAt.millisecondsSinceEpoch,
      'schema_version': bundle.schemaVersion,
      'app_version': bundle.appVersion,
      'slices': <String>[for (final slice in bundle.slices) slice.name],
      // counts 是给人看的索引：不解开 tables 也能知道"里面有几个学生"
      'counts': <String, int>{
        for (final entry in bundle.tables.entries) entry.key: entry.value.length,
      },
      'tables': bundle.tables,
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  /// 把备份写进应用内的 `backups/` 目录，返回落盘路径。
  ///
  /// 这一步**先做**再让用户选保存位置：系统保存对话框可能被取消、可能在某些
  /// 机型上直接不可用，应用内这一份是保底（卸载会清掉，但至少当场没白干）。
  Future<String> saveLocal(String content, {required String subject}) async {
    final directory = await getApplicationDocumentsDirectory();
    final backupDir = Directory(p.join(directory.path, 'backups'));
    if (!backupDir.existsSync()) {
      backupDir.createSync(recursive: true);
    }
    final file = File(
      p.join(
        backupDir.path,
        buildExportFileName(
          kind: '数据备份',
          subject: subject,
          extension: 'json',
        ),
      ),
    );
    await file.writeAsString(content, flush: true);
    AppLogger.i('数据备份已写入：${file.path}');
    return file.path;
  }

  /// 弹系统保存对话框，把备份存到用户自己选的位置（下载 / 文档 / 网盘）。
  ///
  /// 返回 `null` 表示用户取消。方法不是 static，测试里可以覆写掉。
  Future<Uri?> saveToDevice({
    required String fileName,
    required Uint8List bytes,
    required String dialogTitle,
  }) async {
    return FilePickerPlatform.instance.saveFile(
      dialogTitle: dialogTitle,
      fileName: fileName,
      bytes: bytes,
      mimeType: 'application/json',
    );
  }

  // ---------------------------------------------------------------------------
  // 恢复
  // ---------------------------------------------------------------------------

  /// 解析备份文件内容；读不懂时抛 [BackupFormatException]。
  ///
  /// 容错口径：**认识的表**逐行校验，不认识的表名直接跳过（未来的版本多导出了
  /// 一张表，不该让今天的应用整份拒收）；行必须是对象，否则整份文件按损坏处理。
  BackupBundle decode(String raw) {
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (error) {
      AppLogger.w('备份文件不是合法 JSON：$error');
      throw const BackupFormatException(BackupProblem.notBackup);
    }
    if (decoded is! Map) {
      throw const BackupFormatException(BackupProblem.notBackup);
    }
    final map = _asRow(decoded);
    if (map['app'] != backupAppTag) {
      throw const BackupFormatException(BackupProblem.notBackup);
    }
    final format = map['format'];
    if (format is! int) {
      throw const BackupFormatException(BackupProblem.broken);
    }
    if (format > backupFormatVersion) {
      throw const BackupFormatException(BackupProblem.newerFormat);
    }

    final rawTables = map['tables'];
    if (rawTables is! Map) {
      throw const BackupFormatException(BackupProblem.broken);
    }
    final tables = <String, List<Map<String, Object?>>>{};
    for (final entry in rawTables.entries) {
      final table = '${entry.key}';
      if (!_knownTables.contains(table)) {
        AppLogger.d('备份里有当前版本不认识的表，已跳过：$table');
        continue;
      }
      final rows = entry.value;
      if (rows is! List) {
        throw const BackupFormatException(BackupProblem.broken);
      }
      tables[table] = <Map<String, Object?>>[
        for (final row in rows) _asRow(row),
      ];
    }

    final rawSlices = map['slices'];
    final slices = <BackupSlice>[];
    if (rawSlices is List) {
      for (final name in rawSlices) {
        for (final slice in BackupSlice.values) {
          if (slice.name == name && !slices.contains(slice)) {
            slices.add(slice);
          }
        }
      }
    }
    if (slices.isEmpty) {
      // 老文件没写 slices（或写坏了）时从表名反推，别让文件白读
      for (final slice in BackupSlice.values) {
        if (_sliceSpecs[slice]!.tables.any(tables.containsKey)) {
          slices.add(slice);
        }
      }
    }

    final createdAt = map['created_at'];
    final schemaVersion = map['schema_version'];
    return BackupBundle(
      createdAt: createdAt is int
          ? DateTime.fromMillisecondsSinceEpoch(createdAt)
          : DateTime.now(),
      schemaVersion: schemaVersion is int ? schemaVersion : 0,
      appVersion: '${map['app_version'] ?? ''}',
      slices: slices,
      tables: tables,
    );
  }

  /// 把备份写回库（按主键覆盖，不删除备份以外的数据）。
  ///
  /// 整段包在事务里：任何一张表失败就整体回滚，
  /// 保证库要么是恢复前的样子，要么是恢复后的样子，不会停在半路。
  Future<RestoreReport> restore(BackupBundle bundle, {Database? database}) async {
    final db = database ?? await _database;
    final counts = <String, int>{};
    try {
      await db.transaction((txn) async {
        for (final table in restoreOrder) {
          final rows = bundle.tables[table];
          if (rows == null || rows.isEmpty) {
            continue;
          }
          var written = 0;
          for (final row in rows) {
            if (table == 'app_settings' &&
                _volatileSettings.contains(row['key'])) {
              continue;
            }
            await _writeRow(txn, table, row);
            written++;
          }
          counts[table] = written;
        }
      });
    } catch (error, stack) {
      AppLogger.e('恢复备份失败，事务已回滚', error: error, stack: stack);
      throw BackupRestoreException(error);
    }
    AppLogger.i(
      '备份恢复完成：${counts.length} 张表，共 '
      '${counts.values.fold<int>(0, (sum, n) => sum + n)} 行',
    );
    return RestoreReport(counts);
  }

  /// 当前应用的版本号（`1.0.17+18` 这种），只写进备份文件的展示字段。
  ///
  /// 放在 service 里而不是页面上，是为了 widget 测试能整体换掉：
  /// 平台通道在测试环境里没有实现，直接调用会一直挂着不返回。
  Future<String> appVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return info.buildNumber.isEmpty
          ? info.version
          : '${info.version}+${info.buildNumber}';
    } catch (error) {
      AppLogger.d('读不到版本号，备份里留空：$error');
      return '';
    }
  }

  /// 按主键写一行（有则更新、无则插入）。
  ///
  /// **刻意不用 `INSERT OR REPLACE`**：SQLite 的 REPLACE 是"先 DELETE 再 INSERT"，
  /// 会连带触发外键动作 —— 覆盖一个班级会把该班已排的课（`ON DELETE CASCADE`）
  /// 一起删掉，覆盖作息模板又会被 `class.template_id` 的 `RESTRICT` 直接挡回来
  /// （实测：同一个库上连恢复两次就报 FOREIGN KEY constraint failed）。
  /// 老师到这一步是来**找回**数据的，绝不能顺手删掉他没备份的东西。
  /// 先 UPDATE、更新不到才 INSERT：既覆盖同编号记录，又不触发任何删除动作。
  ///
  /// 三张表的主键不是自增 id，得单独说：`app_settings` 用 `key`，
  /// `course_class` 是 `(course_id, class_id)` 复合主键，其余都走 `id`。
  Future<void> _writeRow(
    DatabaseExecutor txn,
    String table,
    Map<String, Object?> row,
  ) async {
    if (table == 'app_settings') {
      final key = row['key'];
      if (key == null) {
        return;
      }
      final updated = await txn.update(
        table,
        row,
        where: 'key = ?',
        whereArgs: <Object?>[key],
      );
      if (updated == 0) {
        await txn.insert(table, row);
      }
      return;
    }
    if (table == 'course_class') {
      final updated = await txn.update(
        table,
        row,
        where: 'course_id = ? AND class_id = ?',
        whereArgs: <Object?>[row['course_id'], row['class_id']],
      );
      if (updated == 0) {
        await txn.insert(table, row);
      }
      return;
    }
    final id = row['id'];
    if (id == null) {
      await txn.insert(table, row);
      return;
    }
    final updated = await txn.update(
      table,
      row,
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
    if (updated == 0) {
      await txn.insert(table, row);
    }
  }

  /// 选一个备份文件并读出内容；用户取消或读取失败返回 null。
  ///
  /// 刻意用 `FileType.any` 而不是限定 json：安卓的扩展名过滤经常把从微信、
  /// 网盘里取出来的文件判成"不支持的格式"，反而挡住用户。内容对不对由
  /// [decode] 判断，错了会给明确的提示。
  Future<String?> pickBackupFile() async {
    try {
      final file = await FilePickerPlatform.instance.pickFile(
        type: FileType.any,
      );
      if (file == null) {
        return null;
      }
      final bytes = await file.readAsBytes();
      return utf8.decode(
        Uint8List.fromList(bytes),
        allowMalformed: true,
      );
    } catch (error, stack) {
      AppLogger.e('读取备份文件失败', error: error, stack: stack);
      return null;
    }
  }

  Map<String, Object?> _asRow(Object? raw) {
    if (raw is! Map) {
      throw const BackupFormatException(BackupProblem.broken);
    }
    return <String, Object?>{
      for (final entry in raw.entries) '${entry.key}': entry.value,
    };
  }
}
