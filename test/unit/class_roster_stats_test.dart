import 'package:flutter_test/flutter_test.dart';

import 'package:schedule_plan/data/models/student.dart';
import 'package:schedule_plan/features/management/class_detail_page.dart';

/// 班级人数与男女构成（班级详情页抬头那几个数字）。
void main() {
  Student student(String name, StudentGender? gender) =>
      Student(name: name, gender: gender, classId: 1);

  test('统计总人数与男女构成', () {
    final stats = ClassRosterStats.of(<Student>[
      student('张三', StudentGender.male),
      student('李四', StudentGender.male),
      student('王五', StudentGender.female),
    ]);
    expect(stats.total, 3);
    expect(stats.male, 2);
    expect(stats.female, 1);
    expect(stats.unset, 0);
  });

  test('导入表格里性别留空的行算「未填」，不计进男女任何一边', () {
    final stats = ClassRosterStats.of(<Student>[
      student('张三', StudentGender.male),
      student('李四', null),
      student('王五', null),
    ]);
    expect(stats.total, 3);
    expect(stats.male, 1);
    expect(stats.female, 0);
    expect(stats.unset, 2);
    // 三项相加必须等于总数，否则抬头卡会出现「3 人但男女加起来只有 1」
    expect(stats.male + stats.female + stats.unset, stats.total);
  });

  test('空名单不出现负数', () {
    final stats = ClassRosterStats.of(const <Student>[]);
    expect(stats.total, 0);
    expect(stats.male, 0);
    expect(stats.female, 0);
    expect(stats.unset, 0);
  });
}
