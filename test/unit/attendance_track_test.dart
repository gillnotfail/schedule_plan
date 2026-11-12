import 'package:flutter_test/flutter_test.dart';

import 'package:schedule_plan/data/models/attendance.dart';
import 'package:schedule_plan/data/models/attendance_ledger.dart';
import 'package:schedule_plan/data/models/student.dart';
import 'package:schedule_plan/features/statistics/attendance_ledger.dart';

/// 工具箱「学生追踪」页的口径（用户规格第 33 轮）。
void main() {
  Student student(int id, String name) =>
      Student(id: id, name: name, classId: 1);

  StudentLedger ledger(
    String name, {
    int expected = 10,
    int absent = 0,
    int late = 0,
    int earlyLeave = 0,
    int lateAndEarly = 0,
    int leave = 0,
    int present = 0,
    int id = 1,
  }) {
    return StudentLedger(
      student: student(id, name),
      className: '高一(1)班',
      tally: LedgerTally(
        present: present,
        absent: absent,
        late: late,
        earlyLeave: earlyLeave,
        lateAndEarly: lateAndEarly,
        leave: leave,
      ),
      expectedSessions: expected,
    );
  }

  group('sortLedgersForTrack', () {
    test('异常次数多的排在最上面（这是"该找谁谈"的入口）', () {
      final sorted = sortLedgersForTrack(<StudentLedger>[
        ledger('全勤的'),
        ledger('缺三次的', absent: 3, id: 2),
        ledger('缺一次的', absent: 1, id: 3),
      ]);
      expect(
        sorted.map((item) => item.student.name).toList(),
        <String>['缺三次的', '缺一次的', '全勤的'],
      );
    });

    test('异常次数相同 → 出勤率低的在前', () {
      final sorted = sortLedgersForTrack(<StudentLedger>[
        ledger('应上多', expected: 20, absent: 2, id: 1),
        ledger('应上少', expected: 4, absent: 2, id: 2),
      ]);
      // 2/4 缺一半比 2/20 缺一成严重
      expect(sorted.first.student.name, '应上少');
    });

    test('没有应上课次（出勤率为 null）的沉到同组后面，再按姓名', () {
      final sorted = sortLedgersForTrack(<StudentLedger>[
        ledger('乙', expected: 0, absent: 1, id: 1),
        ledger('甲', expected: 0, absent: 1, id: 2),
        ledger('有课表的', expected: 10, absent: 1, id: 3),
      ]);
      expect(sorted.first.student.name, '有课表的');
      expect(
        sorted.skip(1).map((item) => item.student.name).toList(),
        <String>['乙', '甲'],
      );
    });

    test('不改原列表（返回新列表）', () {
      final original = <StudentLedger>[ledger('甲', id: 1), ledger('乙', absent: 1, id: 2)];
      final sorted = sortLedgersForTrack(original);
      expect(identical(original, sorted), isFalse);
      expect(original.first.student.name, '甲');
    });
  });

  group('没点名的课次', () {
    test('应上 − 真实记录', () {
      final item = ledger('张三', expected: 10, present: 6, absent: 2);
      expect(item.tally.recordedSessions, 8);
      expect(unmarkedSessions(item), 2);
    });

    test('记录比应上还多（课表后来改小）时截断到 0，不出现负数', () {
      final item = ledger('张三', expected: 1, present: 3);
      expect(unmarkedSessions(item), 0);
    });

    test('请假也算真实记录，不该被当成没点名', () {
      final item = ledger('张三', expected: 5, present: 4, leave: 1);
      expect(unmarkedSessions(item), 0);
    });

    test('补考：组合态是一条记录，只算一次', () {
      final item = ledger('张三', expected: 3, lateAndEarly: 1, present: 2);
      expect(item.tally.recordedSessions, 3);
      expect(item.tally.abnormal, 1);
    });
  });

  group('sortLedgerRowsByDate', () {
    AttendanceLedgerRow row(String date, String? startTime, {int id = 1}) {
      return AttendanceLedgerRow(
        date: date,
        studentId: id,
        studentName: '张三',
        className: '高一(1)班',
        courseName: '数学',
        status: AttendanceStatus.present,
        startTime: startTime,
      );
    }

    test('日期倒序，同一天按上课时间正序', () {
      final sorted = sortLedgerRowsByDate(<AttendanceLedgerRow>[
        row('2026-09-07', '10:00'),
        row('2026-09-09', '08:00'),
        row('2026-09-07', '08:00'),
      ]);
      expect(
        sorted.map((item) => '${item.date} ${item.startTime}').toList(),
        <String>['2026-09-09 08:00', '2026-09-07 08:00', '2026-09-07 10:00'],
      );
    });

    test('缺上课时间的行不崩，排在当天最前面', () {
      final sorted = sortLedgerRowsByDate(<AttendanceLedgerRow>[
        row('2026-09-07', '08:00'),
        row('2026-09-07', null),
      ]);
      expect(sorted.first.startTime, isNull);
    });
  });
}
