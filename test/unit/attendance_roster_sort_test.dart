import 'package:flutter_test/flutter_test.dart';

import 'package:schedule_plan/core/widgets/sort_arrow.dart';
import 'package:schedule_plan/data/models/attendance.dart';
import 'package:schedule_plan/data/models/student.dart';
import 'package:schedule_plan/features/attendance/attendance_page.dart';

/// 考勤名单「班内排序」的纯函数回归测试。
///
/// 用户规格：**按班级分类学生，同时每个班支持姓名、学号、考勤排序**，
/// 并且**休学 / 免修的学生在这门课里排到后面**。
///
/// 这里守两件事：
/// 1. 三种排序维度都真的生效（且升 / 降序方向相反）；
/// 2. 休学 / 免修**永远沉底**，连降序也不能把它们翻到最前面 ——
///    否则"按姓名降序"会把不上课的学生顶到名单第一屏。
Student _student(int id, String name, {String? no}) =>
    Student(id: id, name: name, studentNo: no, classId: 1);

List<String> _names(
  List<Student> input, {
  required StudentSortMode mode,
  required SortDirection direction,
  Set<int> longTerm = const <int>{},
  Map<int, AttendanceStatus> statuses = const <int, AttendanceStatus>{},
}) {
  final sorted = <Student>[...input]
    ..sort(
      (a, b) => compareRosterStudents(
        a,
        b,
        mode: mode,
        direction: direction,
        isLongTerm: (student) => longTerm.contains(student.id),
        statusIndexOf: (student) =>
            (statuses[student.id] ?? AttendanceStatus.unmarked).index,
      ),
    );
  return sorted.map((item) => item.name).toList();
}

void main() {
  final roster = <Student>[
    _student(1, '陈一', no: '03'),
    _student(2, '李二', no: '01'),
    _student(3, '王三', no: '02'),
  ];

  group('compareRosterStudents', () {
    test('按姓名拼音升序 / 降序', () {
      // 拼音：陈(c) < 李(l) < 王(w)
      expect(
        _names(
          roster,
          mode: StudentSortMode.namePinyin,
          direction: SortDirection.ascending,
        ),
        <String>['陈一', '李二', '王三'],
      );
      expect(
        _names(
          roster,
          mode: StudentSortMode.namePinyin,
          direction: SortDirection.descending,
        ),
        <String>['王三', '李二', '陈一'],
      );
    });

    test('按学号升序 / 降序', () {
      expect(
        _names(
          roster,
          mode: StudentSortMode.studentNo,
          direction: SortDirection.ascending,
        ),
        <String>['李二', '王三', '陈一'],
      );
      expect(
        _names(
          roster,
          mode: StudentSortMode.studentNo,
          direction: SortDirection.descending,
        ),
        <String>['陈一', '王三', '李二'],
      );
    });

    test('按考勤状态排（比较的是枚举下标）', () {
      final names = _names(
        roster,
        mode: StudentSortMode.attendanceStatus,
        direction: SortDirection.ascending,
        statuses: <int, AttendanceStatus>{
          1: AttendanceStatus.absent, // 下标 3
          2: AttendanceStatus.present, // 下标 0
          3: AttendanceStatus.leave, // 下标 4
        },
      );
      // 出勤(0) → 缺勤(3) → 请假(4)
      expect(names, <String>['李二', '陈一', '王三']);
    });

    test('休学 / 免修沉底，升序降序都一样', () {
      for (final direction in SortDirection.values) {
        final names = _names(
          roster,
          mode: StudentSortMode.namePinyin,
          direction: direction,
          longTerm: <int>{2}, // 李二休学
        );
        expect(
          names.last,
          '李二',
          reason: '休学 / 免修必须排在本班最后（$direction）',
        );
        expect(names.length, 3, reason: '沉底不是删人');
      }
    });

    test('多个长期状态学生之间仍按当前排序维度排', () {
      final names = _names(
        roster,
        mode: StudentSortMode.namePinyin,
        direction: SortDirection.ascending,
        longTerm: <int>{1, 3}, // 陈一、王三都休学
      );
      expect(names, <String>['李二', '陈一', '王三']);
    });

    test('学号缺失的学生不会因为比较 null 而崩溃', () {
      final withNull = <Student>[
        _student(1, '陈一'),
        _student(2, '李二', no: '01'),
      ];
      expect(
        _names(
          withNull,
          mode: StudentSortMode.studentNo,
          direction: SortDirection.ascending,
        ),
        <String>['陈一', '李二'],
      );
    });
  });

  group('长期状态本身就是长期状态', () {
    test('休学 / 免修被识别为长期状态，日常六态（含组合态）不是', () {
      expect(AttendanceStatus.suspended.isLongTerm, isTrue);
      expect(AttendanceStatus.exempt.isLongTerm, isTrue);
      for (final status in AttendanceStatus.dailyChoices) {
        expect(status.isLongTerm, isFalse, reason: '${status.name} 是日常状态');
      }
      expect(AttendanceStatus.lateAndEarly.isLongTerm, isFalse);
    });

    test('长期状态不算"异常出勤"（不污染异常明细）', () {
      expect(AttendanceStatus.suspended.isAbnormal, isFalse);
      expect(AttendanceStatus.exempt.isAbnormal, isFalse);
      expect(AttendanceStatus.absent.isAbnormal, isTrue);
    });

    test('组合态：迟到 / 早退两个口径都认，但只算一次异常', () {
      const both = AttendanceStatus.lateAndEarly;
      expect(both.isLate, isTrue, reason: '迟到次数里要含它');
      expect(both.isEarlyLeave, isTrue, reason: '早退次数里要含它');
      expect(both.isAbnormal, isTrue);
      expect(
        AttendanceStatus.late.isEarlyLeave,
        isFalse,
        reason: '只迟到的人不能被算成早退',
      );
      expect(AttendanceStatus.earlyLeave.isLate, isFalse);
      // 组合态不是缺勤：它不会把整行标红
      expect(both.countsAsAbsence, isFalse);
    });

    test('两枚胶囊的开关合成一个落库状态（and 语义）', () {
      expect(
        AttendanceStatus.fromLateEarly(late: true, earlyLeave: true),
        AttendanceStatus.lateAndEarly,
      );
      expect(
        AttendanceStatus.fromLateEarly(late: true, earlyLeave: false),
        AttendanceStatus.late,
      );
      expect(
        AttendanceStatus.fromLateEarly(late: false, earlyLeave: true),
        AttendanceStatus.earlyLeave,
      );
      expect(
        AttendanceStatus.fromLateEarly(late: false, earlyLeave: false),
        AttendanceStatus.present,
      );
    });

    test('一键胶囊平铺七个状态：日常五个 + 长期两个（组合态不占格子）', () {
      expect(AttendanceStatus.choices.length, 7);
      expect(AttendanceStatus.choices.take(5), AttendanceStatus.dailyChoices);
      expect(
        AttendanceStatus.choices.skip(5),
        AttendanceStatus.longTermChoices,
      );
      expect(
        AttendanceStatus.choices.contains(AttendanceStatus.lateAndEarly),
        isFalse,
        reason: '组合态由「迟」「早」两枚同亮表示，不再单独占一格',
      );
    });

    test('组合态的库内键名是 late_early，能被读回来', () {
      expect(AttendanceStatus.lateAndEarly.storageKey, 'late_early');
      expect(
        AttendanceStatus.fromStorage('late_early'),
        AttendanceStatus.lateAndEarly,
      );
    });
  });
}
