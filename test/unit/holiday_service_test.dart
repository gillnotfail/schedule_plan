import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:schedule_plan/core/constants/setting_keys.dart';
import 'package:schedule_plan/data/db/schema.dart';
import 'package:schedule_plan/data/models/china_holiday.dart';
import 'package:schedule_plan/data/repositories/settings_repository.dart';
import 'package:schedule_plan/data/services/holiday_service.dart';

/// 「调休那天上周几的课」的读取口径（`HolidayService.shiftMap` / `dayOf`）。
///
/// 这是"考勤日历、日历圆环、课时结算能不能对齐调休"的地基：上层全部按
/// `map[date] ?? date.weekday` 解析，所以这里必须钉死三件事 ——
/// 只有**调休上班日**能带映射、只有**区间内**的日期才返回、**总开关关掉**后
/// 一律不算（否则关掉开关的老师会看到日历还在偷偷按调休算）。
///
/// 用真库的理由和 `holiday_repository_test.dart` 一样：这一层的风险全在
/// 「写进去再读出来还是不是同一件事」，打桩反而测不到。
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
  late SettingsRepository settings;
  late HolidayService holidays;

  setUp(() async {
    db = await _openMemoryDb();
    settings = SettingsRepository(database: db);
    holidays = HolidayService(settings: settings);
  });

  tearDown(() async {
    await db.close();
  });

  test('调休日确认过映射后，labelWeekday 跟着走', () async {
    final date = DateTime(2026, 10, 10); // 周六，2026 年国庆调休上班日
    expect(HolidayService.kindOf(date), CalendarDayKind.makeupWorkday);

    // 老师还没确认 → 按当天（各校通知不一样，这里绝不替她猜）
    final pending = await holidays.dayOf(date);
    expect(pending.labelWeekday, DateTime.saturday);
    expect(pending.isShifted, isFalse);

    await holidays.setShift(date, DateTime.wednesday);
    final shifted = await holidays.dayOf(date);
    expect(shifted.labelWeekday, DateTime.wednesday);
    expect(shifted.isShifted, isTrue);
    expect(shifted.shiftOverridden, isTrue);
  });

  test('shiftMap：只收「调休上班日 + 老师确认过」的日子', () async {
    await holidays.setShift(DateTime(2026, 10, 10), 3); // 周六 → 上周三的课
    // 2026-09-26 在中秋假期内（9/25~9/27），是法定放假日而不是调休日
    await holidays.setShift(DateTime(2026, 9, 26), 1);

    final map = await holidays.shiftMap(
      from: DateTime(2026, 9, 1),
      to: DateTime(2026, 10, 31),
    );
    expect(map, <String, int>{'2026-10-10': 3}, reason: '法定放假日即使写了映射也不能算调休上班日');
  });

  test('shiftMap：区间外的不返回（考勤页一次只问一个月的 42 天）', () async {
    await holidays.setShift(DateTime(2026, 10, 10), 3);

    final map = await holidays.shiftMap(
      from: DateTime(2026, 11, 1),
      to: DateTime(2026, 11, 30),
    );
    expect(map, isEmpty);
  });

  test('总开关关掉后一律不算调休（shiftMap 与 dayOf 口径必须一致）', () async {
    await holidays.setShift(DateTime(2026, 10, 10), 3);
    await settings.writeBool(SettingKeys.holidayAwareEnabled, false);
    holidays.invalidate(); // 设置页改完开关会重建页面，这里手动失效缓存

    final map = await holidays.shiftMap(
      from: DateTime(2026, 10, 1),
      to: DateTime(2026, 10, 31),
    );
    expect(map, isEmpty, reason: '关掉开关后调休不该再影响任何页面');

    final day = await holidays.dayOf(DateTime(2026, 10, 10));
    expect(day.labelWeekday, DateTime.saturday);
    expect(day.isShifted, isFalse);
  });

  test('脏数据不会污染映射：非调休日的键、越界的值都丢掉', () async {
    // 手工写两条不该生效的：一个是普通工作日（周一），一个是非法星期几
    await settings.write('${SettingKeys.holidayShiftPrefix}2026-10-12', '3');
    await settings.write('${SettingKeys.holidayShiftPrefix}2026-10-10', '9');

    final map = await holidays.shiftMap(
      from: DateTime(2026, 10, 1),
      to: DateTime(2026, 10, 31),
    );
    expect(map, isEmpty);
  });

  test('readByPrefix 只匹配真前缀：LIKE 里的下划线必须被转义', () async {
    // `holiday_shift_` 里的下划线在 SQL LIKE 中是「任意单字符」通配符，
    // 不转义的话这条会被误当成命中
    await settings.write('holidayXshiftY2026-10-10', '3');

    final rows = await settings.readByPrefix(SettingKeys.holidayShiftPrefix);
    expect(rows, isEmpty);
  });
}
