import '../../data/models/attendance.dart';

/// 出勤摘要「复制出勤摘要」复制出去的整段文本（纯组装，可单测）。
///
/// 格式（用户规格，第 26 轮）：
/// ```
/// 10月26日（周一）08:00-08:45，数学，应到：45人。实到：42人，异常出勤：
/// 迟到：2人，高一1班：张三、李四；请假：1人，高一1班：王五
/// ```
/// - 头部（时间 / 课程 / 应到 / 实到）由页面拼好传入；
/// - 异常段按「状态 → 班级」两级分组：**班级名只出现一次**，学生聚在班级名后面
///   （修掉旧版「高一1班 张三、高一1班 李四」里班级名跟着每个学生重复的问题）；
/// - 状态之间的分隔是「；」，班级之间是「，」；
/// - 状态按 [AttendanceStatus.choices] 的顺序输出；
/// - 没有异常学生时不带「异常出勤」尾巴，只复制头部。
class AttendanceSummaryBuilder {
  AttendanceSummaryBuilder({
    required this.header,
    required this.abnormalPrefix,
    required String Function(AttendanceStatus status, int count) statusCount,
    required String Function(String className, List<String> names)
    classGroup,
  }) : _statusCount = statusCount,
       _classGroup = classGroup;

  /// 拼好的头部：`10月26日（周一）08:00-08:45，数学，应到：45人。实到：42人`。
  final String header;

  /// 「异常出勤：」——异常段的总标签（含结尾冒号）。
  final String abnormalPrefix;

  /// `(状态, 人数) → 迟到：2人`。
  final String Function(AttendanceStatus status, int count) _statusCount;

  /// `(班级名, 名单) → 高一1班：张三、李四`；班级名为空时退化为纯名单。
  final String Function(String className, List<String> names) _classGroup;

  /// 组装整段摘要。调用方只应传**异常**学生（出勤 / 未标记的不进摘要，
  /// 否则头部里的应到 / 实到就对不上了）。
  String build(List<AttendanceSummaryEntry> entries) {
    if (entries.isEmpty) {
      return header;
    }
    // 状态 → (班级 → 名单)。Dart 的 Map 按插入顺序遍历，
    // 所以班级顺序 = 名单里第一次出现的顺序（名单本身按班级排过序）。
    final byStatus = <AttendanceStatus, Map<String, List<String>>>{};
    for (final entry in entries) {
      byStatus
          .putIfAbsent(entry.status, () => <String, List<String>>{})
          .putIfAbsent(entry.className, () => <String>[])
          .add(entry.studentName);
    }
    final sections = <String>[];
    for (final status in AttendanceStatus.choices) {
      final byClass = byStatus[status];
      if (byClass == null) {
        continue;
      }
      var total = 0;
      final classTexts = <String>[];
      for (final group in byClass.entries) {
        total += group.value.length;
        classTexts.add(_classGroup(group.key, group.value));
      }
      // 人数是**这个状态在所有班级的总和**，跟头部的应到/实到能对上账。
      sections.add('${_statusCount(status, total)}，${classTexts.join('，')}');
    }
    return '$header，$abnormalPrefix${sections.join('；')}';
  }
}

/// 一条异常记录：状态 + 班级名（查不到时为空）+ 学生名。
class AttendanceSummaryEntry {
  const AttendanceSummaryEntry({
    required this.status,
    required this.className,
    required this.studentName,
  });

  final AttendanceStatus status;
  final String className;
  final String studentName;
}
