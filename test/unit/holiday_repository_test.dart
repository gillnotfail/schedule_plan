import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:schedule_plan/data/db/schema.dart';
import 'package:schedule_plan/data/models/china_holiday.dart';
import 'package:schedule_plan/data/repositories/holiday_repository.dart';

/// 节假日缓存表（`holiday_day`，v7）的读写往返测试。
///
/// 特意用真库（内存 SQLite + 完整 Schema）而不是打桩：这张表的全部风险都在
/// "写进去再读出来还是不是同一个东西"——枚举序列化成字符串这一步最容易写错，
/// 而错了以后表现是"假期莫名其妙没了"，很难从界面上定位。
Future<Database> _openMemoryDb() => databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: DatabaseSchema.version,
        singleInstance: false,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, _) => DatabaseSchema.createAll(db),
      ),
    );

void main() {
  // 单元测试环境不是 Android/iOS，必须显式切到 ffi 实现
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late HolidayRepository repository;

  setUp(() async {
    db = await _openMemoryDb();
    repository = HolidayRepository(database: db);
  });

  tearDown(() async {
    await db.close();
  });

  test('写进去再读回来，日期 / 属性 / 节日名一个不差', () async {
    await repository.replaceYear(
      2027,
      const <String, ChinaHoliday>{
        '2027-01-01': ChinaHoliday(
          date: '2027-01-01',
          kind: CalendarDayKind.holiday,
          name: HolidayName.newYear,
        ),
        '2027-01-04': ChinaHoliday(
          date: '2027-01-04',
          kind: CalendarDayKind.makeupWorkday,
          name: HolidayName.newYear,
        ),
        '2027-02-06': ChinaHoliday(
          date: '2027-02-06',
          kind: CalendarDayKind.holiday,
        ),
      },
      source: 'test',
      fetchedAt: 1000,
    );

    final loaded = await repository.loadAll();

    expect(loaded.length, 3);
    expect(loaded['2027-01-01']?.kind, CalendarDayKind.holiday);
    expect(loaded['2027-01-01']?.name, HolidayName.newYear);
    expect(loaded['2027-01-04']?.kind, CalendarDayKind.makeupWorkday);
    expect(
      loaded['2027-02-06']?.name,
      isNull,
      reason: '名字缺失要读成 null，不能瞎猜一个节日塞进去',
    );
  });

  test('replaceYear 是整年替换：该年的旧数据清掉，别的年份不动', () async {
    await repository.replaceYear(
      2026,
      const <String, ChinaHoliday>{
        '2026-10-01': ChinaHoliday(
          date: '2026-10-01',
          kind: CalendarDayKind.holiday,
          name: HolidayName.nationalDay,
        ),
      },
      source: 'a',
      fetchedAt: 1,
    );
    await repository.replaceYear(
      2027,
      const <String, ChinaHoliday>{
        '2027-01-01': ChinaHoliday(
          date: '2027-01-01',
          kind: CalendarDayKind.holiday,
          name: HolidayName.newYear,
        ),
        '2027-01-04': ChinaHoliday(
          date: '2027-01-04',
          kind: CalendarDayKind.makeupWorkday,
          name: HolidayName.newYear,
        ),
      },
      source: 'b',
      fetchedAt: 2,
    );

    // 2027 第二次拉取时结构变了（多了补班日、少了国庆）
    await repository.replaceYear(
      2027,
      const <String, ChinaHoliday>{
        '2027-01-01': ChinaHoliday(
          date: '2027-01-01',
          kind: CalendarDayKind.holiday,
          name: HolidayName.newYear,
        ),
      },
      source: 'c',
      fetchedAt: 3,
    );

    final loaded = await repository.loadAll();
    expect(loaded.length, 2, reason: '2027 应该只剩 1 条，加上 2026 那条');
    expect(loaded.containsKey('2027-01-04'), isFalse, reason: '该年旧数据要被清掉');
    expect(loaded.containsKey('2026-10-01'), isTrue, reason: '别的年份不能被牵连');
  });

  test('同一天重复写入只留最新一条（date 是主键，属性改了要覆盖）', () async {
    await repository.replaceYear(
      2027,
      const <String, ChinaHoliday>{
        '2027-05-01': ChinaHoliday(
          date: '2027-05-01',
          kind: CalendarDayKind.holiday,
        ),
      },
      source: 'a',
      fetchedAt: 1,
    );
    await repository.replaceYear(
      2027,
      const <String, ChinaHoliday>{
        '2027-05-01': ChinaHoliday(
          date: '2027-05-01',
          kind: CalendarDayKind.workday,
        ),
      },
      source: 'b',
      fetchedAt: 2,
    );

    final loaded = await repository.loadAll();
    expect(loaded.length, 1);
    expect(loaded['2027-05-01']?.kind, CalendarDayKind.workday);
  });

  test('cachedYears 拿到去重后的年份，空表时是空集合', () async {
    expect(await repository.cachedYears(), isEmpty);

    await repository.replaceYear(
      2026,
      const <String, ChinaHoliday>{
        '2026-10-01': ChinaHoliday(
          date: '2026-10-01',
          kind: CalendarDayKind.holiday,
        ),
        '2026-10-02': ChinaHoliday(
          date: '2026-10-02',
          kind: CalendarDayKind.holiday,
        ),
      },
      source: 'a',
      fetchedAt: 1,
    );
    await repository.replaceYear(
      2027,
      const <String, ChinaHoliday>{
        '2027-01-01': ChinaHoliday(
          date: '2027-01-01',
          kind: CalendarDayKind.holiday,
        ),
      },
      source: 'a',
      fetchedAt: 1,
    );

    expect(await repository.cachedYears(), <int>{2026, 2027});
  });

  test('空数据不写库（避免"拉到了空表"把已有缓存误清掉）', () async {
    await repository.replaceYear(
      2027,
      const <String, ChinaHoliday>{
        '2027-01-01': ChinaHoliday(
          date: '2027-01-01',
          kind: CalendarDayKind.holiday,
        ),
      },
      source: 'a',
      fetchedAt: 1,
    );

    await repository.replaceYear(
      2027,
      const <String, ChinaHoliday>{},
      source: 'b',
      fetchedAt: 2,
    );

    expect((await repository.loadAll()).length, 1, reason: '空写入应当被忽略');
  });

  test('clear 清空全部缓存', () async {
    await repository.replaceYear(
      2027,
      const <String, ChinaHoliday>{
        '2027-01-01': ChinaHoliday(
          date: '2027-01-01',
          kind: CalendarDayKind.holiday,
        ),
      },
      source: 'a',
      fetchedAt: 1,
    );

    await repository.clear();

    expect(await repository.loadAll(), isEmpty);
    expect(await repository.cachedYears(), isEmpty);
  });
}
