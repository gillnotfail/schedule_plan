import 'package:sqflite/sqflite.dart' hide DatabaseException;

import 'package:schedule_plan/core/constants/app_constants.dart';
import 'package:schedule_plan/core/error/app_exceptions.dart';
import 'package:schedule_plan/core/logging/app_logger.dart';
import 'package:schedule_plan/core/utils/time_utils.dart';
import 'package:schedule_plan/data/db/app_database.dart';
import 'package:schedule_plan/data/db/schema.dart';
import 'package:schedule_plan/data/models/schedule_template.dart';
import 'package:schedule_plan/data/validators/template_period_validator.dart';

/// 模板仍被班级绑定时禁止删除（readme 模块一 1.2「删除模板前必须校验」）。
class TemplateInUseException extends AppException {
  const TemplateInUseException(super.message, {required this.classNames});

  /// 受影响的班级名单，UI 需要列出并引导用户先迁移。
  final List<String> classNames;
}

/// 作息模板 / 模板节次的数据访问层。
class TemplateRepository {
  TemplateRepository({Database? database}) : _db = database;

  Database? _db;

  Future<Database> get _database async => _db ??= await AppDatabase.instance();

  /// 列表页：模板卡片需要展示「绑定的班级数量」与「是否为默认模板」。
  Future<List<ScheduleTemplate>> listTemplates() async {
    final db = await _database;
    final rows = await db.rawQuery(
      '''
      SELECT t.*, COUNT(c.id) AS bound_class_count
      FROM schedule_template t
      LEFT JOIN class c ON c.template_id = t.id
      GROUP BY t.id
      ORDER BY t.is_default DESC, t.updated_at DESC
      ''',
    );
    return rows.map(ScheduleTemplate.fromMap).toList();
  }

  Future<ScheduleTemplate?> getTemplate(int id) async {
    final db = await _database;
    final rows = await db.query(
      'schedule_template',
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return ScheduleTemplate.fromMap(rows.first);
  }

  /// 当前默认模板；没有则返回任意一条作为兜底。
  Future<ScheduleTemplate?> getDefaultTemplate() async {
    final templates = await listTemplates();
    if (templates.isEmpty) {
      return null;
    }
    return templates.firstWhere(
      (item) => item.isDefault,
      orElse: () => templates.first,
    );
  }

  /// 按 (template_id, weekday) 单独取节次列表。
  ///
  /// readme 第六章明确要求：不假设一周内节次数固定，
  /// 所有涉及节次数量的逻辑必须按 (template_id, weekday) 单独取列表。
  Future<List<TemplatePeriod>> periodsForWeekday(int templateId, int weekday) async {
    final db = await _database;
    final rows = await db.query(
      'template_period',
      where: 'template_id = ? AND weekday = ?',
      whereArgs: <Object?>[templateId, weekday],
      orderBy: 'period_index ASC',
    );
    return rows.map(TemplatePeriod.fromMap).toList();
  }

  Future<List<TemplatePeriod>> allPeriods(int templateId) async {
    final db = await _database;
    final rows = await db.query(
      'template_period',
      where: 'template_id = ?',
      whereArgs: <Object?>[templateId],
      orderBy: 'weekday ASC, period_index ASC',
    );
    return rows.map(TemplatePeriod.fromMap).toList();
  }

  /// 绑定该模板的班级数量。
  Future<int> countBoundClasses(int templateId) async {
    final db = await _database;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS cnt FROM class WHERE template_id = ?',
      <Object?>[templateId],
    );
    return (rows.first['cnt'] as int?) ?? 0;
  }

  /// 绑定该模板的班级名单（删除前校验用）。
  Future<List<String>> boundClassNames(int templateId) async {
    final db = await _database;
    final rows = await db.query(
      'class',
      columns: <String>['name'],
      where: 'template_id = ?',
      whereArgs: <Object?>[templateId],
      orderBy: 'name ASC',
    );
    return rows.map((row) => row['name'] as String).toList();
  }

  /// 新建模板。全库第一条模板自动设为默认。
  ///
  /// 新模板**自带一份出厂作息**（周一~周五 × 一天 10 节 × 8:00 开始 ×
  /// 每节 40 分钟 × 课间 10 分钟），与 [DatabaseSchema.generatePeriodRows]
  /// 共用同一套算术，保证"新建出来就是一张能直接用的表"。
  ///
  /// 之所以在创建时写入而不是进页面时回填：用户在课表设置里点
  /// 「一键清空课表」之后，表就该是空的，不能在下次进页面时又被塞回来。
  Future<int> createTemplate(String name) async {
    final db = await _database;
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw const ValidationException('模板名称不能为空');
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    try {
      return await db.transaction((txn) async {
        final count = Sqflite.firstIntValue(
              await txn.rawQuery('SELECT COUNT(*) FROM schedule_template'),
            ) ??
            0;
        final templateId = await txn.insert(
          'schedule_template',
          <String, Object?>{
            'name': trimmed,
            'is_default': count == 0 ? 1 : 0,
            'created_at': now,
            'updated_at': now,
          },
        );
        await DatabaseSchema.insertDefaultPeriods(txn, templateId);
        return templateId;
      });
    } catch (error, stack) {
      AppLogger.e('新建作息模板失败', error: error, stack: stack);
      throw DatabaseException('新建作息模板失败：$error', cause: error);
    }
  }

  Future<void> renameTemplate(int id, String name) async {
    final db = await _database;
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw const ValidationException('模板名称不能为空');
    }
    await db.update(
      'schedule_template',
      <String, Object?>{'name': trimmed, 'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  /// 设为默认：必须在事务内先清除其他记录的 is_default（readme 3.1 表约束）。
  Future<void> setDefaultTemplate(int id) async {
    final db = await _database;
    try {
      await db.transaction((txn) async {
        await txn.update('schedule_template', <String, Object?>{'is_default': 0});
        await txn.update(
          'schedule_template',
          <String, Object?>{'is_default': 1},
          where: 'id = ?',
          whereArgs: <Object?>[id],
        );
      });
    } catch (error, stack) {
      AppLogger.e('设置默认模板失败', error: error, stack: stack);
      throw DatabaseException('设置默认模板失败：$error', cause: error);
    }
  }

  /// 删除模板：仍有班级绑定则禁止删除，并列出受影响班级名单。
  Future<void> deleteTemplate(int id) async {
    final db = await _database;
    final classNames = await boundClassNames(id);
    if (classNames.isNotEmpty) {
      throw TemplateInUseException(
        '模板仍被 ${classNames.length} 个班级绑定，禁止删除',
        classNames: classNames,
      );
    }
    try {
      await db.transaction((txn) async {
        await txn.delete(
          'template_period',
          where: 'template_id = ?',
          whereArgs: <Object?>[id],
        );
        await txn.delete(
          'schedule_template',
          where: 'id = ?',
          whereArgs: <Object?>[id],
        );
      });
    } catch (error, stack) {
      AppLogger.e('删除作息模板失败', error: error, stack: stack);
      throw DatabaseException('删除作息模板失败：$error', cause: error);
    }
  }

  /// 保存某一工作日的全部节次。
  ///
  /// 保存前执行 [TemplatePeriodValidator]，校验失败直接抛出 [ValidationException]，
  /// 由 UI 内联提示具体原因，绝不静默失败。
  Future<void> saveWeekdayPeriods(
    int templateId,
    int weekday,
    List<TemplatePeriod> periods,
  ) async {
    // 节次序号由系统按录入顺序自动编号（readme 1.2：不可手动改，增删行后自动重排）。
    // 必须先重排再校验，否则调用方传入的旧序号（删行后的空洞/乱序）
    // 会让校验器按旧序号排序，与界面呈现的顺序不一致。
    var sequence = 1;
    final normalized = periods
        .map((period) => period.copyWith(periodIndex: sequence++))
        .toList(growable: false);
    final issues = TemplatePeriodValidator.validate(normalized);
    if (issues.isNotEmpty) {
      throw ValidationException('作息节次校验未通过（${issues.length} 处问题）');
    }
    final db = await _database;
    try {
      await db.transaction((txn) async {
        await txn.delete(
          'template_period',
          where: 'template_id = ? AND weekday = ?',
          whereArgs: <Object?>[templateId, weekday],
        );
        for (final period in normalized) {
          await txn.insert('template_period', <String, Object?>{
            'template_id': templateId,
            'weekday': weekday,
            'period_index': period.periodIndex,
            'period_type': period.periodType.storageKey,
            'start_time': period.startTime,
            'end_time': period.endTime,
            'label': period.label,
          });
        }
        await txn.update(
          'schedule_template',
          <String, Object?>{'updated_at': DateTime.now().millisecondsSinceEpoch},
          where: 'id = ?',
          whereArgs: <Object?>[templateId],
        );
      });
    } catch (error, stack) {
      AppLogger.e('保存作息节次失败', error: error, stack: stack);
      if (error is ValidationException) {
        rethrow;
      }
      throw DatabaseException('保存作息节次失败：$error', cause: error);
    }
  }

  /// 「从其他工作日复制」：把某一天的完整配置一键复制到多个目标日期。
  Future<void> copyWeekdayTo(
    int templateId, {
    required int fromWeekday,
    required List<int> targetWeekdays,
  }) async {
    final source = await periodsForWeekday(templateId, fromWeekday);
    if (source.isEmpty) {
      throw const ValidationException('源工作日没有可复制的节次');
    }
    final db = await _database;
    try {
      await db.transaction((txn) async {
        for (final target in targetWeekdays) {
          if (target == fromWeekday) {
            continue;
          }
          await txn.delete(
            'template_period',
            where: 'template_id = ? AND weekday = ?',
            whereArgs: <Object?>[templateId, target],
          );
          for (final period in source) {
            await txn.insert('template_period', <String, Object?>{
              'template_id': templateId,
              'weekday': target,
              'period_index': period.periodIndex,
              'period_type': period.periodType.storageKey,
              'start_time': period.startTime,
              'end_time': period.endTime,
              'label': period.label,
            });
          }
        }
      });
    } catch (error, stack) {
      AppLogger.e('复制作息节次失败', error: error, stack: stack);
      throw DatabaseException('复制作息节次失败：$error', cause: error);
    }
  }

  /// 时间列级联更新（模块一 1.7）。
  ///
  /// 「同步修改后续所有节次」：按原有节次间隔顺延调整后续节次。
  /// 级联开关由调用方从 app_settings 读取后决定是否调用本方法。
  ///
  /// 写入后立刻**回读校验**：读回来的必须与写进去的逐节一致，否则抛
  /// [DatabaseException]。这道闸的由来是"改了时间、重启又变回默认"的反馈
  /// ——必须先能区分"没写进去"和"读的不是同一套作息"，再谈修哪个。
  /// 宁可报错，也不要把失败当成功提示给用户。
  Future<void> cascadeUpdatePeriods({
    required int templateId,
    required int weekday,
    required int fromPeriodIndex,
    required String newStartTime,
    required String newEndTime,
    required bool cascade,
  }) async {
    final periods = await periodsForWeekday(templateId, weekday);
    if (periods.isEmpty) {
      return;
    }
    final target = periods.firstWhere(
      (item) => item.periodIndex == fromPeriodIndex,
      orElse: () => periods.first,
    );
    final oldStart = TimeUtils.parseMinutes(target.startTime);
    final oldEnd = TimeUtils.parseMinutes(target.endTime);
    final nextStart = TimeUtils.parseMinutes(newStartTime);
    final nextEnd = TimeUtils.parseMinutes(newEndTime);
    final startDelta = nextStart - oldStart;
    final durationDelta = (nextEnd - nextStart) - (oldEnd - oldStart);

    final updated = periods.map((period) {
      if (period.periodIndex == fromPeriodIndex) {
        return period.copyWith(startTime: newStartTime, endTime: newEndTime);
      }
      if (!cascade || period.periodIndex <= fromPeriodIndex) {
        return period;
      }
      final start = TimeUtils.parseMinutes(period.startTime) + startDelta + durationDelta;
      final end = TimeUtils.parseMinutes(period.endTime) + startDelta + durationDelta;
      return period.copyWith(
        startTime: TimeUtils.formatMinutes(start),
        endTime: TimeUtils.formatMinutes(end),
      );
    }).toList();

    await saveWeekdayPeriods(templateId, weekday, updated);

    final persisted = await periodsForWeekday(templateId, weekday);
    final expected = <int, (String, String)>{
      for (final period in updated)
        period.periodIndex: (period.startTime, period.endTime),
    };
    if (persisted.length != expected.length) {
      throw DatabaseException(
        '作息保存后回读校验未通过：期望 ${expected.length} 节，实际 ${persisted.length} 节',
      );
    }
    for (final period in persisted) {
      final want = expected[period.periodIndex];
      if (want == null) {
        throw DatabaseException(
          '作息保存后回读校验未通过：多出第 ${period.periodIndex} 节',
        );
      }
      if (want.$1 != period.startTime || want.$2 != period.endTime) {
        throw DatabaseException(
          '作息保存后回读校验未通过（第 ${period.periodIndex} 节：'
          '期望 ${want.$1}-${want.$2}，实际 ${period.startTime}-${period.endTime}）',
        );
      }
    }
  }

  /// 「一键生成作息」：按开始时间 / 每节时长 / 课间间隔 / 节数，
  /// 批量覆盖写入所选工作日的节次。
  ///
  /// 与出厂种子数据共用 [DatabaseSchema.generatePeriodRows] 的同一套算术，
  /// 因此"一键生成"出来的表与默认表完全一致。
  ///
  /// [clearUnselected] 为真时，**未选中的星期会被一并清空**——这是"一键生成作息
  /// 权限最大"的落地：老师第二次选周一~周五，课表就该只剩 5 列。
  /// 早期版本只删选中的那天、不碰其余天，于是"先选 7 天再选 5 天"永远停在 7 天，
  /// 用户看到的就是"选了也没用"。
  ///
  /// 只清作息（template_period），**不动 lesson**：作息是骨架，
  /// 排课内容是另一回事，误删代价太高。
  Future<void> generatePeriods({
    required int templateId,
    required List<int> weekdays,
    required String startTime,
    required int lessonMinutes,
    required int breakMinutes,
    required int periodCount,
    bool clearUnselected = false,
  }) async {
    if (weekdays.isEmpty) {
      throw const ValidationException('请至少选择一个星期');
    }
    if (lessonMinutes <= 0 || periodCount <= 0) {
      throw const ValidationException('时长与节数必须为正数');
    }
    final rows = DatabaseSchema.generatePeriodRows(
      startTime: startTime,
      lessonMinutes: lessonMinutes,
      breakMinutes: breakMinutes,
      count: periodCount,
    );
    if (TimeUtils.parseMinutes(rows.last.$2) >= 24 * 60) {
      throw const ValidationException('时间超出一天范围');
    }
    final selected = weekdays.toSet();
    final db = await _database;
    try {
      await db.transaction((txn) async {
        for (var weekday = 1;
            weekday <= AppConstants.weekdayCount;
            weekday++) {
          if (clearUnselected && !selected.contains(weekday)) {
            await txn.delete(
              'template_period',
              where: 'template_id = ? AND weekday = ?',
              whereArgs: <Object?>[templateId, weekday],
            );
          }
        }
        for (final weekday in selected) {
          await txn.delete(
            'template_period',
            where: 'template_id = ? AND weekday = ?',
            whereArgs: <Object?>[templateId, weekday],
          );
          for (var i = 0; i < rows.length; i++) {
            await txn.insert('template_period', <String, Object?>{
              'template_id': templateId,
              'weekday': weekday,
              'period_index': i + 1,
              'period_type': PeriodType.normal.storageKey,
              'start_time': rows[i].$1,
              'end_time': rows[i].$2,
            });
          }
        }
        await txn.update(
          'schedule_template',
          <String, Object?>{
            'updated_at': DateTime.now().millisecondsSinceEpoch,
          },
          where: 'id = ?',
          whereArgs: <Object?>[templateId],
        );
      });
    } catch (error, stack) {
      AppLogger.e('一键生成作息失败', error: error, stack: stack);
      if (error is ValidationException) {
        rethrow;
      }
      throw DatabaseException('一键生成作息失败：$error', cause: error);
    }
  }

  /// 若该工作日还没有任何节次，则用出厂默认口径补齐一份，
  /// 保证课表网格「默认一天 10 节课、8:00 开始」永远成立。
  Future<bool> ensureDefaultWeekday(
    int templateId,
    int weekday, {
    String startTime = AppConstants.defaultDayStartTime,
    int lessonMinutes = AppConstants.defaultLessonMinutes,
    int breakMinutes = AppConstants.defaultBreakMinutes,
    int periodCount = AppConstants.defaultDayPeriodCount,
  }) async {
    final existing = await periodsForWeekday(templateId, weekday);
    if (existing.isNotEmpty) {
      return false;
    }
    await generatePeriods(
      templateId: templateId,
      weekdays: <int>[weekday],
      startTime: startTime,
      lessonMinutes: lessonMinutes,
      breakMinutes: breakMinutes,
      periodCount: periodCount,
    );
    return true;
  }

  /// 「一键清空课表」：删掉该模板下所有班级的课表条目。
  ///
  /// **只清课表内容（lesson），不动作息（template_period）**。
  /// 作息决定课表第一列的"第 N 节 + 起止时间"，是课表这张表的骨架；
  /// 把它一起删掉会得到一张连节次都没有的空表，用户看到的就是"课表页没有表格"。
  /// 作息行的增删归「默认作息修改」（作息模板编辑页）管，这里不越界。
  Future<void> clearTemplateSchedule(int templateId) async {
    final db = await _database;
    try {
      await db.transaction((txn) async {
        final classRows = await txn.query(
          'class',
          columns: <String>['id'],
          where: 'template_id = ?',
          whereArgs: <Object?>[templateId],
        );
        for (final row in classRows) {
          await txn.delete(
            'lesson',
            where: 'class_id = ?',
            whereArgs: <Object?>[row['id']],
          );
        }
        await txn.update(
          'schedule_template',
          <String, Object?>{
            'updated_at': DateTime.now().millisecondsSinceEpoch,
          },
          where: 'id = ?',
          whereArgs: <Object?>[templateId],
        );
      });
    } catch (error, stack) {
      AppLogger.e('清空课表失败', error: error, stack: stack);
      throw DatabaseException('清空课表失败：$error', cause: error);
    }
  }

  /// 保证模板有一份可用的作息表；整份作息为空时补一份出厂作息。
  ///
  /// 为什么需要：课表页的第一列是"第 N 节 + 起止时间"，完全由作息决定。
  /// 老版本建库时种子数据没有写出厂作息，旧版「一键清空课表」也会把作息整段
  /// 删掉——这类模板打开课表页时第一列是空的、格子里全是占位符，
  /// 表现就是"课表页没有默认表格"。这里做一次自愈，把骨架补回来。
  ///
  /// 只在**整份作息为空**时补，不覆盖用户已经调过的任何一天；
  /// 走 [DatabaseSchema.insertDefaultPeriods]，与种子数据、一键生成共用同一算法。
  ///
  /// 返回 `true` 表示这次确实补写了一份。
  Future<bool> ensureFactorySchedule(int templateId) async {
    final db = await _database;
    try {
      return await db.transaction((txn) async {
        final count = Sqflite.firstIntValue(
              await txn.rawQuery(
                'SELECT COUNT(*) FROM template_period WHERE template_id = ?',
                <Object?>[templateId],
              ),
            ) ??
            0;
        if (count > 0) {
          return false;
        }
        await DatabaseSchema.insertDefaultPeriods(txn, templateId);
        AppLogger.i('模板 $templateId 作息为空，已补写出厂作息');
        return true;
      });
    } catch (error, stack) {
      AppLogger.e('补写出厂作息失败', error: error, stack: stack);
      throw DatabaseException('补写出厂作息失败：$error', cause: error);
    }
  }
}
