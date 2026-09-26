import 'package:flutter_test/flutter_test.dart';

import 'package:schedule_plan/data/models/schedule_event.dart';

/// 日程重复周期（单次 / 每周 / 隔周 / 每月）的判定回归测试。
///
/// 用户规格（第 9 轮）："如果是单次，联动到课表里，下一周就没有了；
/// 隔周的话，就不用单独打开日程安排，直接在课表上就可以看到。"
void main() {
  // 2026-09-21 是周一
  final anchorWeek = DateTime(2026, 9, 21);
  DateTime eventOn(int weekday) =>
      anchorWeek.add(Duration(days: weekday - 1, hours: 9));

  ScheduleEvent event(EventRecurrence recurrence, [DateTime? at]) =>
      ScheduleEvent(
        title: '教研会',
        startAt: (at ?? eventOn(3)).millisecondsSinceEpoch,
        recurrence: recurrence,
      );

  group('单次（once）', () {
    test('只在自己那一周发生，下周就没了', () {
      final e = event(EventRecurrence.once);
      expect(e.occursOnWeek(anchorWeek), isTrue);
      expect(e.occursOnWeek(anchorWeek.add(const Duration(days: 7))), isFalse);
      expect(e.occursOnWeek(anchorWeek.subtract(const Duration(days: 7))), isFalse);
    });
  });

  group('每周（weekly）', () {
    test('每一周都发生', () {
      final e = event(EventRecurrence.weekly);
      expect(e.occursOnWeek(anchorWeek), isTrue);
      expect(e.occursOnWeek(anchorWeek.add(const Duration(days: 7))), isTrue);
      expect(e.occursOnWeek(anchorWeek.subtract(const Duration(days: 21))), isTrue);
    });
  });

  group('隔周（biweekly）', () {
    test('从自己那周起，隔着周发生', () {
      final e = event(EventRecurrence.biweekly);
      expect(e.occursOnWeek(anchorWeek), isTrue, reason: '起始周');
      expect(e.occursOnWeek(anchorWeek.add(const Duration(days: 14))), isTrue,
          reason: '第 2 周');
      expect(e.occursOnWeek(anchorWeek.add(const Duration(days: 7))), isFalse,
          reason: '中间隔掉的那周');
    });
  });

  group('每月（monthly）', () {
    test('在「和开始日同一天号」的那周发生', () {
      // 开始日是 9 月 23 日（周三）
      final start = DateTime(2026, 9, 23, 9);
      final e = event(EventRecurrence.monthly, start);
      // 10 月里，23 号所在的那一周（10-19 周一）
      final octWeek = DateTime(2026, 10, 19);
      expect(e.occursOnWeek(octWeek), isTrue, reason: '10 月 23 号落在这一周');
      expect(e.occursOnWeek(DateTime(2026, 10, 26)), isFalse,
          reason: '下一周没有 23 号');
    });
  });

  test('默认就是单次（老数据/未指定回落）', () {
    final e = ScheduleEvent(title: 'x', startAt: eventOn(1).millisecondsSinceEpoch);
    expect(e.recurrence, EventRecurrence.once);
  });
}
