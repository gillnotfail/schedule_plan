import 'package:schedule_plan/core/utils/time_utils.dart';
import 'package:schedule_plan/data/models/schedule_template.dart';

/// 作息模板节次校验（readme 模块一 1.2 第 4 条）。
///
/// 校验规则：
/// 1. 同一天内所有时间段（**含非 normal 类型**）不得互相重叠；
/// 2. 按节次序号升序排列时，起始时间必须严格递增；
/// 3. 结束时间必须晚于起始时间，且同属一个自然日
///    （本期不支持跨天时段，end_time <= start_time 直接拒绝保存）。
///
/// 设计为纯函数，不依赖 Flutter / 数据库，便于单元测试覆盖。
abstract final class TemplatePeriodValidator {
  /// 校验某一工作日下的全部节次。
  ///
  /// 返回按节次序号升序排列的问题列表；空列表表示校验通过。
  /// 校验失败时由 UI 在**对应行内联提示**具体原因，不允许静默失败或直接崩溃。
  static List<PeriodIssue> validate(List<TemplatePeriod> periods) {
    final issues = <PeriodIssue>[];
    if (periods.isEmpty) {
      return issues;
    }
    final sorted = [...periods]..sort((a, b) => a.periodIndex.compareTo(b.periodIndex));

    // 规则 3：格式与起止顺序
    for (final period in sorted) {
      final start = TimeUtils.tryParseMinutes(period.startTime);
      final end = TimeUtils.tryParseMinutes(period.endTime);
      if (start == null || end == null) {
        issues.add(PeriodIssue(period.periodIndex, PeriodIssueType.invalidFormat));
        continue;
      }
      if (end <= start) {
        issues.add(PeriodIssue(period.periodIndex, PeriodIssueType.endBeforeStart));
      }
    }

    // 规则 1：任意两段时间不得重叠（含非 normal 类型）
    for (var i = 0; i < sorted.length; i++) {
      for (var j = i + 1; j < sorted.length; j++) {
        final a = sorted[i];
        final b = sorted[j];
        final aStart = TimeUtils.tryParseMinutes(a.startTime);
        final aEnd = TimeUtils.tryParseMinutes(a.endTime);
        final bStart = TimeUtils.tryParseMinutes(b.startTime);
        final bEnd = TimeUtils.tryParseMinutes(b.endTime);
        if (aStart == null || aEnd == null || bStart == null || bEnd == null) {
          continue;
        }
        if (TimeUtils.overlaps(aStart, aEnd, bStart, bEnd)) {
          // 时间靠后的那一行标记为「与上一节重叠」
          issues.add(PeriodIssue(b.periodIndex, PeriodIssueType.overlap));
        }
      }
    }

    // 规则 2：按节次序号升序排列时，起始时间严格递增
    for (var i = 1; i < sorted.length; i++) {
      final prevStart = TimeUtils.tryParseMinutes(sorted[i - 1].startTime);
      final currentStart = TimeUtils.tryParseMinutes(sorted[i].startTime);
      if (prevStart == null || currentStart == null) {
        continue;
      }
      if (currentStart <= prevStart) {
        issues.add(PeriodIssue(sorted[i].periodIndex, PeriodIssueType.notAscending));
      }
    }

    // 同一节次序号去重后按序号排序输出，保证 UI 内联提示顺序稳定
    final seen = <String>{};
    final unique = <PeriodIssue>[];
    for (final issue in issues) {
      final key = '${issue.periodIndex}:${issue.type.name}';
      if (seen.add(key)) {
        unique.add(issue);
      }
    }
    unique.sort((a, b) => a.periodIndex.compareTo(b.periodIndex));
    return unique;
  }
}

/// 校验问题类型。
enum PeriodIssueType {
  invalidFormat,
  endBeforeStart,
  overlap,
  notAscending;

  /// 对应的 i18n key，界面禁止硬编码文案。
  String get l10nKey => switch (this) {
        PeriodIssueType.invalidFormat => 'periodErrorInvalidFormat',
        PeriodIssueType.endBeforeStart => 'periodErrorEndBeforeStart',
        PeriodIssueType.overlap => 'periodErrorOverlap',
        PeriodIssueType.notAscending => 'periodErrorNotAscending',
      };
}

/// 单条校验问题：绑定到具体节次行，供 UI 内联展示。
class PeriodIssue {
  const PeriodIssue(this.periodIndex, this.type);

  final int periodIndex;
  final PeriodIssueType type;
}
