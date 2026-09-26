import 'package:sqflite/sqflite.dart';

import 'package:schedule_plan/core/logging/app_logger.dart';
import 'package:schedule_plan/data/db/app_database.dart';
import 'package:schedule_plan/data/models/china_holiday.dart';

/// 节假日 / 调休安排的本地缓存读写（`holiday_day` 表，DB v7）。
///
/// 这张表只装**从网上取回来的**年度安排，内置表不进库：
/// 内置表编译在代码里本来就一直在，再复制一份到库里只会多出
/// "代码更新了、库里还是老数据"这种两套真相的问题。
class HolidayRepository {
  HolidayRepository({Database? database}) : _db = database;

  Database? _db;

  Future<Database> get _database async => _db ??= await AppDatabase.instance();

  /// 读出全部缓存。
  ///
  /// 不做按年过滤：一年也就几十条，全读出来一次注入内存，
  /// 之后日历翻月、课表结算都是纯内存查表，不再碰数据库。
  Future<Map<String, ChinaHoliday>> loadAll() async {
    try {
      final db = await _database;
      final rows = await db.query('holiday_day');
      final result = <String, ChinaHoliday>{};
      for (final row in rows) {
        final date = row['date'];
        if (date is! String || date.isEmpty) {
          continue;
        }
        result[date] = ChinaHoliday(
          date: date,
          kind: CalendarDayKind.fromStorage(row['kind'] as String?),
          name: _holidayNameOf(row['name'] as String?),
        );
      }
      return result;
    } catch (error, stack) {
      // 缓存读不出来不是致命问题：内置表还在，顶多少了新一年的安排
      AppLogger.e('读取节假日缓存失败，本次按内置数据兜底', error: error, stack: stack);
      return const <String, ChinaHoliday>{};
    }
  }

  /// 已经缓存了哪几年（判断"还缺哪年"用）。
  Future<Set<int>> cachedYears() async {
    try {
      final db = await _database;
      final rows = await db.rawQuery('SELECT DISTINCT year FROM holiday_day');
      return rows.map((row) => row['year']).whereType<int>().toSet();
    } catch (error, stack) {
      AppLogger.e('读取节假日缓存年份失败', error: error, stack: stack);
      return const <int>{};
    }
  }

  /// 用一整年的新数据整体替换掉该年的旧缓存。
  ///
  /// 先删后插放在**同一个事务**里：中途失败会整体回滚，
  /// 不会留下"旧数据删掉了、新数据还没写进去"的空档。
  Future<void> replaceYear(
    int year,
    Map<String, ChinaHoliday> days, {
    required String source,
    required int fetchedAt,
  }) async {
    if (days.isEmpty) {
      return;
    }
    final db = await _database;
    await db.transaction((txn) async {
      await txn.delete(
        'holiday_day',
        where: 'year = ?',
        whereArgs: <Object?>[year],
      );
      for (final item in days.values) {
        await txn.insert(
          'holiday_day',
          <String, Object?>{
            'date': item.date,
            'kind': item.kind.name,
            'name': item.name?.name,
            'year': year,
            'source': source,
            'fetched_at': fetchedAt,
          },
          // date 是主键：同一天再写一次就覆盖，不会堆出重复行
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  /// 清空全部缓存（设置页「恢复内置数据」）。
  Future<void> clear() async {
    final db = await _database;
    await db.delete('holiday_day');
  }
}

/// 库里存的是枚举名（`HolidayName.name`）。
///
/// 刻意不用 [HolidayName.fromStorage]——那个认不出来会回落成"国庆节"，
/// 在这里就是**给日子安错节日名**；解析不出来时返回 null 才是诚实的。
HolidayName? _holidayNameOf(String? value) {
  if (value == null || value.isEmpty) {
    return null;
  }
  for (final item in HolidayName.values) {
    if (item.name == value) {
      return item;
    }
  }
  return null;
}
