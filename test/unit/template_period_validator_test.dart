import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_plan/data/models/schedule_template.dart';
import 'package:schedule_plan/data/validators/template_period_validator.dart';

TemplatePeriod _period(
  int index, {
  String start = '08:00',
  String end = '08:45',
  PeriodType type = PeriodType.normal,
}) =>
    TemplatePeriod(
      templateId: 1,
      weekday: 1,
      periodIndex: index,
      periodType: type,
      startTime: start,
      endTime: end,
    );

bool _has(List<PeriodIssue> issues, int index, PeriodIssueType type) =>
    issues.any((issue) => issue.periodIndex == index && issue.type == type);

void main() {
  group('TemplatePeriodValidator', () {
    test('空列表直接通过', () {
      expect(TemplatePeriodValidator.validate(<TemplatePeriod>[]), isEmpty);
    });

    test('合法的一天（含午休）无问题', () {
      final issues = TemplatePeriodValidator.validate(<TemplatePeriod>[
        _period(1, start: '08:00', end: '08:45'),
        _period(2, start: '08:55', end: '09:40'),
        _period(3, start: '12:00', end: '13:00', type: PeriodType.lunchBreak),
        _period(4, start: '14:00', end: '14:45'),
      ]);
      expect(issues, isEmpty);
    });

    test('结束时间早于起始时间 → endBeforeStart', () {
      final issues = TemplatePeriodValidator.validate(<TemplatePeriod>[
        _period(1, start: '08:45', end: '08:00'),
      ]);
      expect(_has(issues, 1, PeriodIssueType.endBeforeStart), isTrue);
    });

    test('结束时间等于起始时间（跨天时段）→ endBeforeStart', () {
      final issues = TemplatePeriodValidator.validate(<TemplatePeriod>[
        _period(1, start: '08:00', end: '08:00'),
      ]);
      expect(_has(issues, 1, PeriodIssueType.endBeforeStart), isTrue);
    });

    test('时间格式非法 → invalidFormat', () {
      final issues = TemplatePeriodValidator.validate(<TemplatePeriod>[
        _period(1, start: '25:00', end: '08:45'),
      ]);
      expect(_has(issues, 1, PeriodIssueType.invalidFormat), isTrue);
    });

    test('两节次时间重叠 → overlap（标记靠后的一节）', () {
      final issues = TemplatePeriodValidator.validate(<TemplatePeriod>[
        _period(1, start: '08:00', end: '08:45'),
        _period(2, start: '08:30', end: '09:15'),
      ]);
      expect(_has(issues, 2, PeriodIssueType.overlap), isTrue);
      expect(_has(issues, 1, PeriodIssueType.overlap), isFalse);
    });

    test('非 normal 类型（午休/自习）同样参与重叠校验', () {
      final issues = TemplatePeriodValidator.validate(<TemplatePeriod>[
        _period(1, start: '08:00', end: '09:00'),
        _period(2, start: '08:30', end: '09:30', type: PeriodType.selfStudy),
      ]);
      expect(_has(issues, 2, PeriodIssueType.overlap), isTrue);
    });

    test('节次序号升序但起始时间未严格递增 → notAscending', () {
      final issues = TemplatePeriodValidator.validate(<TemplatePeriod>[
        _period(1, start: '10:00', end: '10:45'),
        _period(2, start: '09:00', end: '09:45'),
      ]);
      expect(_has(issues, 2, PeriodIssueType.notAscending), isTrue);
    });

    test('起始时间相同（非严格递增）→ notAscending', () {
      final issues = TemplatePeriodValidator.validate(<TemplatePeriod>[
        _period(1, start: '10:00', end: '10:45'),
        _period(2, start: '10:00', end: '11:45'),
      ]);
      expect(_has(issues, 2, PeriodIssueType.notAscending), isTrue);
    });

    test('输入乱序时先按 period_index 排序再校验', () {
      final issues = TemplatePeriodValidator.validate(<TemplatePeriod>[
        _period(3, start: '09:50', end: '10:35'),
        _period(1, start: '08:00', end: '08:45'),
        _period(2, start: '08:55', end: '09:40'),
      ]);
      expect(issues, isEmpty);
    });

    test('同一节次的多类问题去重后按序号升序输出', () {
      final issues = TemplatePeriodValidator.validate(<TemplatePeriod>[
        _period(2, start: '07:00', end: '09:00'),
        _period(1, start: '08:00', end: '08:45'),
      ]);
      // 排序后 period 1 = 08:00-08:45，period 2 = 07:00-09:00，
      // 两类问题都归属第 2 节：overlap + notAscending
      expect(issues.length, 2);
      expect(issues.map((issue) => issue.periodIndex).toSet(), <int>{2});
      expect(
        issues.map((issue) => issue.type).toSet(),
        <PeriodIssueType>{PeriodIssueType.overlap, PeriodIssueType.notAscending},
      );
    });

    test('问题类型映射到稳定的 i18n key（禁止硬编码文案）', () {
      expect(PeriodIssueType.invalidFormat.l10nKey, 'periodErrorInvalidFormat');
      expect(PeriodIssueType.endBeforeStart.l10nKey, 'periodErrorEndBeforeStart');
      expect(PeriodIssueType.overlap.l10nKey, 'periodErrorOverlap');
      expect(PeriodIssueType.notAscending.l10nKey, 'periodErrorNotAscending');
    });
  });
}
