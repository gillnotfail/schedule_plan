/// 课表照片识别 · 解析层单测（第 11 轮）。
///
/// 这一层是给手机拍照识别兜底的地方：引擎认字经常"认得出来但位置歪"，
/// 排错格子比认不出字更难被发现，所以规则必须有单测压着。
///
/// 这些用例不依赖任何原生插件，`flutter test` 直接跑。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:schedule_plan/data/services/schedule_ocr_parser.dart';
import 'package:schedule_plan/data/services/schedule_ocr_types.dart';

/// 造一行识别结果。坐标用归一化值（0~1），原点左上。
///
/// 默认框很小（OCR 引擎给的包围盒本来就只有文字那么点大），
/// 这样多行文字放在同一格时 **y 中心仍能分开**，便于验证"按中点分界"的逻辑。
OcrTextLine _line(String text, double x, double y, {double w = 0.04, double h = 0.012}) {
  return OcrTextLine(
    text: text,
    left: x - w / 2,
    top: y - h / 2,
    right: x + w / 2,
    bottom: y + h / 2,
  );
}

/// 一张"周一~周五 × 第 1~4 节"的标准课表照片。
List<OcrTextLine> _standardWeek() {
  return <OcrTextLine>[
    // 表头：周几（x 从 0.25 起，每列 0.12）
    _line('周一', 0.25, 0.10),
    _line('周二', 0.37, 0.10),
    _line('周三', 0.49, 0.10),
    _line('周四', 0.61, 0.10),
    _line('周五', 0.73, 0.10),
    // 表头：节次 + 时间（y 从 0.25 起，每行 0.15）
    _line('第1节 08:00-08:40', 0.10, 0.25, w: 0.14, h: 0.02),
    _line('第2节 08:50-09:30', 0.10, 0.40, w: 0.14, h: 0.02),
    _line('第3节 09:50-10:30', 0.10, 0.55, w: 0.14, h: 0.02),
    _line('第4节 10:40-11:20', 0.10, 0.70, w: 0.14, h: 0.02),
    // 课程
    _line('语文', 0.25, 0.25),
    _line('数学', 0.37, 0.25),
    _line('英语', 0.49, 0.25),
    _line('物理', 0.61, 0.25),
    _line('化学', 0.73, 0.25),
    _line('数学', 0.25, 0.40),
    _line('语文', 0.37, 0.40),
    _line('体育', 0.49, 0.40),
    _line('英语', 0.61, 0.40),
    _line('数学', 0.73, 0.40),
    _line('英语', 0.25, 0.55),
    _line('历史', 0.37, 0.55),
    _line('数学', 0.49, 0.55),
    _line('语文', 0.61, 0.55),
    _line('生物', 0.73, 0.55),
    _line('体育', 0.25, 0.70),
    _line('地理', 0.37, 0.70),
    _line('语文', 0.49, 0.70),
    _line('数学', 0.61, 0.70),
    _line('政治', 0.73, 0.70),
  ];
}

void main() {
  group('周几 / 节次的词法识别', () {
    test('认得出 周一~周日 的各种写法', () {
      final result = ScheduleOcrParser.parse(<OcrTextLine>[
        _line('星期一', 0.2, 0.1),
        _line('周二', 0.4, 0.1),
        _line('礼拜三', 0.6, 0.1),
        _line('星期日', 0.8, 0.1),
        _line('第1节', 0.1, 0.3),
        _line('语文', 0.2, 0.3),
        _line('数学', 0.4, 0.3),
        _line('英语', 0.6, 0.3),
        _line('物理', 0.8, 0.3),
      ]);
      expect(result.weekdayColumns, <int>[1, 2, 3, 7]);
      expect(result.drafts.length, 4);
      expect(
        result.drafts.map((item) => item.weekday).toList(),
        <int>[1, 2, 3, 7],
      );
    });

    test('第N节 / N节 / 中文数字 都能认成同一行', () {
      for (final header in <String>['第2节', '2节', '二']) {
        final result = ScheduleOcrParser.parse(<OcrTextLine>[
          _line('周一', 0.3, 0.1),
          _line(header, 0.1, 0.4),
          _line('数学', 0.3, 0.4),
        ]);
        expect(result.drafts.length, 1, reason: '表头 "$header" 应该认成第 2 节');
        expect(result.drafts.single.periodIndex, 2, reason: '表头 "$header"');
      }
    });

    test('时间段被抽出来并规范化成 HH:mm', () {
      final result = ScheduleOcrParser.parse(<OcrTextLine>[
        _line('周一', 0.3, 0.1),
        _line('第1节', 0.1, 0.4),
        _line('8:00～8:40', 0.1, 0.42),
        _line('数学', 0.3, 0.4),
      ]);
      expect(result.drafts.single.startTime, '08:00');
      expect(result.drafts.single.endTime, '08:40');
    });

    test('连堂课 "1-2" 落到起始节', () {
      final result = ScheduleOcrParser.parse(<OcrTextLine>[
        _line('周一', 0.3, 0.1),
        _line('1-2', 0.1, 0.4),
        _line('作文', 0.3, 0.4),
      ]);
      expect(result.drafts.single.periodIndex, 1);
      expect(result.drafts.single.courseName, '作文');
    });
  });

  group('整表还原', () {
    test('周一~周五 × 4 节全部落到正确的格子里', () {
      final result = ScheduleOcrParser.parse(_standardWeek());

      expect(result.weekdayColumns, <int>[1, 2, 3, 4, 5]);
      expect(result.periodRows, <int>[1, 2, 3, 4]);
      expect(result.drafts.length, 20);
      expect(result.dayCount, 5);
      expect(result.confidence, greaterThan(70));

      OcrLessonDraft? at(int weekday, int period) {
        for (final item in result.drafts) {
          if (item.weekday == weekday && item.periodIndex == period) {
            return item;
          }
        }
        return null;
      }

      expect(at(1, 1)?.courseName, '语文');
      expect(at(5, 1)?.courseName, '化学');
      expect(at(3, 2)?.courseName, '体育');
      expect(at(2, 4)?.courseName, '地理');
      expect(at(5, 4)?.courseName, '政治');
    });

    test('草稿按 周几 → 节次 升序排列（UI 直接展示不用再排）', () {
      final result = ScheduleOcrParser.parse(_standardWeek());
      for (var i = 1; i < result.drafts.length; i++) {
        final prev = result.drafts[i - 1];
        final curr = result.drafts[i];
        final ordered = prev.weekday < curr.weekday ||
            (prev.weekday == curr.weekday &&
                prev.periodIndex < curr.periodIndex);
        expect(ordered, isTrue, reason: '第 $i 条顺序不对：$prev → $curr');
      }
    });

    test('同一格里的多行文字拼成一条课程名', () {
      final result = ScheduleOcrParser.parse(<OcrTextLine>[
        _line('周一', 0.3, 0.1),
        _line('第1节', 0.1, 0.4),
        _line('高等数学', 0.3, 0.39),
        _line('3班', 0.3, 0.42),
      ]);
      expect(result.drafts.single.courseName, '高等数学 3班');
    });

    test('节次行高不均匀时也按"中点分界"落到正确的节', () {
      // 第 1 节被压得很扁（早读），第 2 节很高
      final result = ScheduleOcrParser.parse(<OcrTextLine>[
        _line('周一', 0.3, 0.05),
        _line('第1节', 0.1, 0.12),
        _line('第2节', 0.1, 0.60),
        _line('早读', 0.3, 0.14),
        _line('数学', 0.3, 0.55),
      ]);
      final names = result.drafts.map((item) => item.courseName).toList();
      expect(names, containsAll(<String>['早读', '数学']));
      final early = result.drafts.firstWhere((item) => item.courseName == '早读');
      final math = result.drafts.firstWhere((item) => item.courseName == '数学');
      expect(early.periodIndex, 1);
      expect(math.periodIndex, 2);
    });
  });

  group('噪声与异常', () {
    test('午休 / 备注 / 纯数字 不当成课程', () {
      // 注意 y 必须落进某一节的"分界区"内：这里 第1节@0.30 与 第2节@0.60，
      // 分界在 0.45，午休@0.30 归第 1 节，数学@0.60 归第 2 节。
      final result = ScheduleOcrParser.parse(<OcrTextLine>[
        _line('周一', 0.3, 0.05),
        _line('第1节', 0.1, 0.30),
        _line('第2节', 0.1, 0.60),
        _line('午休', 0.3, 0.30),
        _line('2026', 0.3, 0.32),
        _line('数学', 0.3, 0.60),
      ]);
      expect(result.drafts.map((item) => item.courseName), <String>['数学']);
    });

    test('完全不认识时给出警告而不是崩溃', () {
      final result = ScheduleOcrParser.parse(<OcrTextLine>[
        _line('某某中学', 0.5, 0.05, w: 0.3),
        _line('2026年9月', 0.5, 0.9, w: 0.2),
      ]);
      expect(result.drafts, isEmpty);
      expect(result.isEmpty, isTrue);
      expect(
        result.warnings,
        containsAll(<String>['ocrWarnNoWeekday', 'ocrWarnNoPeriod', 'ocrWarnNoLesson']),
      );
      expect(result.confidence, 0);
    });

    test('只认出一部分周几时给出"部分识别"警告', () {
      final result = ScheduleOcrParser.parse(<OcrTextLine>[
        _line('周一', 0.3, 0.1),
        _line('周二', 0.5, 0.1),
        _line('第1节', 0.1, 0.4),
        _line('数学', 0.3, 0.4),
        _line('语文', 0.5, 0.4),
      ]);
      expect(result.warnings, contains('ocrWarnPartialWeekday'));
      expect(result.confidence, lessThan(70));
    });

    test('空输入不抛异常', () {
      final result = ScheduleOcrParser.parse(const <OcrTextLine>[]);
      expect(result.isEmpty, isTrue);
      expect(result.sourceLineCount, 0);
    });

    test('表格线 / 项目符号等噪声字符会被清掉', () {
      final result = ScheduleOcrParser.parse(<OcrTextLine>[
        _line('周一', 0.3, 0.1),
        _line('第1节', 0.1, 0.4),
        _line('| 数学 ·', 0.3, 0.4),
      ]);
      expect(result.drafts.single.courseName, '数学');
    });

    test('格子里只有噪声词时不产生空课程名', () {
      final result = ScheduleOcrParser.parse(<OcrTextLine>[
        _line('周一', 0.3, 0.05),
        _line('第1节', 0.1, 0.40),
        _line('午休', 0.3, 0.40),
        _line('·', 0.3, 0.42),
      ]);
      expect(result.drafts, isEmpty);
    });

    test('纯时间段行不会被误判成节次（08:50-09:30 不是第 8 节）', () {
      final result = ScheduleOcrParser.parse(<OcrTextLine>[
        _line('周一', 0.3, 0.05),
        _line('08:00-08:40', 0.1, 0.40),
        _line('数学', 0.3, 0.40),
      ]);
      // 没有节次锚点 → 不产出草稿，并给出"没认到节次"的警告
      expect(result.drafts, isEmpty);
      expect(result.warnings, contains('ocrWarnNoPeriod'));
    });
  });

  group('结果统计口径', () {
    test('distinctCourseCount 按课程名去重', () {
      final result = ScheduleOcrParser.parse(_standardWeek());
      // 20 节课里：语文4 数学5 英语3 物理1 化学1 体育2 历史1 生物1 地理1 政治1
      expect(result.distinctCourseCount, 10);
    });

    test('analyze 不打分（confidence = -1），parse 才打分', () {
      final analyzed = ScheduleOcrParser.analyze(_standardWeek());
      expect(analyzed.confidence, -1);
      expect(ScheduleOcrParser.parse(_standardWeek()).confidence, greaterThan(0));
    });
  });
}
