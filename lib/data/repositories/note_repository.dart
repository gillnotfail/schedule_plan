import 'package:sqflite/sqflite.dart' hide DatabaseException;

import 'package:schedule_plan/core/error/app_exceptions.dart';
import 'package:schedule_plan/core/logging/app_logger.dart';
import 'package:schedule_plan/data/db/app_database.dart';
import 'package:schedule_plan/data/models/note.dart';
import 'package:schedule_plan/data/models/schedule_event.dart';

/// 快速笔记数据访问层（readme 3.10 表）。
class NoteRepository {
  NoteRepository({Database? database}) : _db = database;

  Database? _db;

  Future<Database> get _database async => _db ??= await AppDatabase.instance();

  Future<List<Note>> listNotes() async {
    final db = await _database;
    final rows = await db.query('note', orderBy: 'updated_at DESC');
    return rows.map(Note.fromMap).toList();
  }

  Future<int> createNote(String content) async {
    final db = await _database;
    final now = DateTime.now().millisecondsSinceEpoch;
    try {
      return db.insert(
        'note',
        Note(content: content, createdAt: now, updatedAt: now).toMap(),
      );
    } catch (error, stack) {
      AppLogger.e('新建笔记失败', error: error, stack: stack);
      throw DatabaseException('新建笔记失败：$error', cause: error);
    }
  }

  Future<void> updateNote(Note note) async {
    final db = await _database;
    if (note.id == null) {
      throw const ValidationException('笔记 id 缺失');
    }
    await db.update(
      'note',
      note.copyWith(updatedAt: DateTime.now().millisecondsSinceEpoch).toMap(),
      where: 'id = ?',
      whereArgs: <Object?>[note.id],
    );
  }

  Future<void> deleteNote(int id) async {
    final db = await _database;
    await db.delete('note', where: 'id = ?', whereArgs: <Object?>[id]);
  }
}

/// 日程事件 + 专注记录数据访问层（readme 3.11 / 3.12 表）。
class ScheduleEventRepository {
  ScheduleEventRepository({Database? database}) : _db = database;

  Database? _db;

  Future<Database> get _database async => _db ??= await AppDatabase.instance();

  Future<List<ScheduleEvent>> listEvents() async {
    final db = await _database;
    final rows = await db.query('schedule_event', orderBy: 'start_at ASC');
    return rows.map(ScheduleEvent.fromMap).toList();
  }

  Future<List<ScheduleEvent>> eventsOnDay(DateTime day) async {
    final start = DateTime(day.year, day.month, day.day).millisecondsSinceEpoch;
    final end = start + const Duration(days: 1).inMilliseconds;
    final db = await _database;
    final rows = await db.query(
      'schedule_event',
      where: 'start_at >= ? AND start_at < ?',
      whereArgs: <Object?>[start, end],
      orderBy: 'start_at ASC',
    );
    return rows.map(ScheduleEvent.fromMap).toList();
  }

  Future<int> createEvent(ScheduleEvent event) async {
    final db = await _database;
    if (event.title.trim().isEmpty) {
      throw const ValidationException('日程标题不能为空');
    }
    try {
      return db.insert('schedule_event', event.toMap());
    } catch (error, stack) {
      AppLogger.e('新建日程失败', error: error, stack: stack);
      throw DatabaseException('新建日程失败：$error', cause: error);
    }
  }

  Future<void> updateEvent(ScheduleEvent event) async {
    final db = await _database;
    if (event.id == null) {
      throw const ValidationException('日程 id 缺失');
    }
    await db.update(
      'schedule_event',
      event.toMap(),
      where: 'id = ?',
      whereArgs: <Object?>[event.id],
    );
  }

  Future<void> deleteEvent(int id) async {
    final db = await _database;
    await db.delete('schedule_event', where: 'id = ?', whereArgs: <Object?>[id]);
  }

  /// 记录一次专注会话（模块五 5.1）。
  Future<int> saveFocusSession(FocusSession session) async {
    final db = await _database;
    try {
      return db.insert('focus_session', session.toMap());
    } catch (error, stack) {
      AppLogger.e('保存专注记录失败', error: error, stack: stack);
      throw DatabaseException('保存专注记录失败：$error', cause: error);
    }
  }

  Future<List<FocusSession>> listFocusSessions({int limit = 50}) async {
    final db = await _database;
    final rows = await db.query(
      'focus_session',
      orderBy: 'started_at DESC',
      limit: limit,
    );
    return rows.map(FocusSession.fromMap).toList();
  }

  /// 某个时间范围内的专注记录（教学成果页"本周专注次数 / 累计分钟"）。
  ///
  /// `started_at` 是毫秒时间戳，所以直接比大小即可，不需要字符串日期。
  Future<List<FocusSession>> focusSessionsBetween({
    required int fromMs,
    required int toMs,
  }) async {
    final db = await _database;
    final rows = await db.query(
      'focus_session',
      where: 'started_at >= ? AND started_at <= ?',
      whereArgs: <Object?>[fromMs, toMs],
      orderBy: 'started_at DESC',
    );
    return rows.map(FocusSession.fromMap).toList();
  }
}
