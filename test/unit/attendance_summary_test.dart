import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_plan/data/models/attendance.dart';
import 'package:schedule_plan/features/attendance/attendance_summary.dart';

/// 出勤摘要构建器（第 26 轮用户规格）：
/// ```
/// 头部，异常出勤：迟到：2人，高一1班：张三、李四；请假：1人，高一1班：王五
/// ```
/// 文案由页面走 l10n 拼好传入；这里用中文样例验证**结构**。
AttendanceSummaryBuilder _builder() => AttendanceSummaryBuilder(
  header: '10月26日（周一）08:00-08:45，数学，应到：45人。实到：42人',
  abnormalPrefix: '异常出勤：',
  statusCount: (status, count) => '${_label(status)}：$count人',
  classGroup: (className, names) =>
      className.isEmpty ? names.join('、') : '$className：${names.join('、')}',
);

String _label(AttendanceStatus status) => switch (status) {
  AttendanceStatus.late => '迟到',
  AttendanceStatus.earlyLeave => '早退',
  AttendanceStatus.absent => '缺勤',
  AttendanceStatus.leave => '请假',
  AttendanceStatus.suspended => '休学',
  _ => '出勤',
};

AttendanceSummaryEntry _entry(
  AttendanceStatus status,
  String className,
  String name,
) => AttendanceSummaryEntry(
  status: status,
  className: className,
  studentName: name,
);

void main() {
  group('出勤摘要（复制出去的整段文本）', () {
    test('同班学生聚在班级名后面，班级名只出现一次（修重复班级名的 bug）', () {
      final text = _builder().build(<AttendanceSummaryEntry>[
        _entry(AttendanceStatus.late, '高一1班', '张三'),
        _entry(AttendanceStatus.late, '高一1班', '李四'),
      ]);
      expect(
        text,
        '10月26日（周一）08:00-08:45，数学，应到：45人。实到：42人，'
        '异常出勤：迟到：2人，高一1班：张三、李四',
      );
      // 核心回归断言：旧版这里是「高一1班 张三、高一1班 李四」。
      expect('高一1班'.allMatches(text).length, 1);
    });

    test('用户给的完整样例：多状态 + 多班级，状态间「；」班级间「，」', () {
      final text = _builder().build(<AttendanceSummaryEntry>[
        _entry(AttendanceStatus.late, '高一1班', 'A'),
        _entry(AttendanceStatus.late, '高一1班', 'B'),
        _entry(AttendanceStatus.leave, '高二2班', 'C'),
        _entry(AttendanceStatus.leave, '高二3班', 'E'),
        _entry(AttendanceStatus.leave, '高二3班', 'F'),
        _entry(AttendanceStatus.leave, '高二3班', 'G'),
      ]);
      expect(
        text,
        '10月26日（周一）08:00-08:45，数学，应到：45人。实到：42人，'
        '异常出勤：迟到：2人，高一1班：A、B；'
        '请假：4人，高二2班：C，高二3班：E、F、G',
      );
    });

    test('状态按 choices 顺序输出（迟到在请假前），与传入顺序无关', () {
      final text = _builder().build(<AttendanceSummaryEntry>[
        _entry(AttendanceStatus.leave, '高一1班', '王五'),
        _entry(AttendanceStatus.late, '高一1班', '张三'),
      ]);
      expect(
        text,
        '10月26日（周一）08:00-08:45，数学，应到：45人。实到：42人，'
        '异常出勤：迟到：1人，高一1班：张三；请假：1人，高一1班：王五',
      );
    });

    test('没有异常学生时只返回头部，不带「异常出勤」尾巴', () {
      expect(
        _builder().build(<AttendanceSummaryEntry>[]),
        '10月26日（周一）08:00-08:45，数学，应到：45人。实到：42人',
      );
    });

    test('状态人数是该状态在所有班级的总和，不是班级数', () {
      final text = _builder().build(<AttendanceSummaryEntry>[
        _entry(AttendanceStatus.absent, '高一1班', '张三'),
        _entry(AttendanceStatus.absent, '高二2班', '王五'),
        _entry(AttendanceStatus.absent, '高二2班', '赵六'),
      ]);
      expect(text, contains('缺勤：3人'));
      expect(
        text,
        contains('高一1班：张三，高二2班：王五、赵六'),
      );
    });

    test('班级名缺失时退化为纯名单，不出现「：张三」这种空班级', () {
      final text = _builder().build(<AttendanceSummaryEntry>[
        _entry(AttendanceStatus.late, '', '张三'),
        _entry(AttendanceStatus.late, '', '李四'),
      ]);
      expect(text, contains('迟到：2人，张三、李四'));
      expect(text, isNot(contains('：张三、李四')));
    });
  });
}
