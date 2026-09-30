import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:schedule_plan/data/models/china_holiday.dart';
import 'package:schedule_plan/features/attendance/calendar_marks.dart';

/// 考勤日历「标记口径 + 底部图例」测试（用户规格，第 18 轮定稿）。
///
/// 日历上有四样东西：**放假红点、调休紫点、有课未点名的淡圈、出勤红弧**。
/// 这里把颜色口径钉死，免得以后有人"顺手"把两个点改成同一个色，
/// 又回到老师"分不清哪个是哪个"的老问题。
void main() {
  const scheme = ColorScheme.light();

  group('CalendarMark.colorOf', () {
    test('放假 = 红点，调休上班 = 紫点', () {
      expect(
        CalendarMark.colorOf(CalendarDayKind.holiday, scheme),
        scheme.error,
      );
      expect(
        CalendarMark.colorOf(CalendarDayKind.makeupWorkday, scheme),
        scheme.tertiary,
      );
    });

    test('两种点必须是两个不同的色号 —— 同色就分不清了', () {
      expect(
        CalendarMark.holidayColor(scheme),
        isNot(CalendarMark.makeupColor(scheme)),
      );
    });

    test('普通工作日 / 周末 / 查不到的日子都不标', () {
      expect(CalendarMark.colorOf(CalendarDayKind.workday, scheme), isNull);
      expect(CalendarMark.colorOf(CalendarDayKind.weekend, scheme), isNull);
      // 节假日与调休总开关关掉时，调用方直接传 null 进来
      expect(CalendarMark.colorOf(null, scheme), isNull);
    });

    test('格子上的点与图例上的点是同一个色号', () {
      expect(
        CalendarMark.colorOf(CalendarDayKind.holiday, scheme),
        CalendarMark.holidayColor(scheme),
      );
      expect(
        CalendarMark.colorOf(CalendarDayKind.makeupWorkday, scheme),
        CalendarMark.makeupColor(scheme),
      );
    });
  });

  testWidgets('图例把四样标记都写出来', (tester) async {
    const arcColor = Color(0xFFE23B3B);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AttendanceCalendarLegend(
            items: <CalendarLegendItem>[
              CalendarLegendItem(
                glyph: CalendarLegendGlyph.dot,
                color: scheme.error,
                label: '放假',
              ),
              CalendarLegendItem(
                glyph: CalendarLegendGlyph.dot,
                color: scheme.tertiary,
                label: '调休上班',
              ),
              CalendarLegendItem(
                glyph: CalendarLegendGlyph.ring,
                color: scheme.outlineVariant,
                label: '有课未点名',
              ),
              CalendarLegendItem(
                glyph: CalendarLegendGlyph.arc,
                color: arcColor,
                label: '出勤率',
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('放假'), findsOneWidget);
    expect(find.text('调休上班'), findsOneWidget);
    expect(find.text('有课未点名'), findsOneWidget);
    expect(find.text('出勤率'), findsOneWidget);

    // 图例里恰好三个 Container：放假点、调休点、未点名淡圈
    // （出勤率那一项是 CustomPaint 画的弧，不是 Container）
    final glyphs = tester
        .widgetList<Container>(
          find.descendant(
            of: find.byType(AttendanceCalendarLegend),
            matching: find.byType(Container),
          ),
        )
        .toList();
    expect(glyphs, hasLength(3));

    // 放假：实心红点
    final holiday = glyphs[0].decoration! as BoxDecoration;
    expect(holiday.color, scheme.error);
    expect(holiday.shape, BoxShape.circle);

    // 调休上班：实心紫点 —— 必须和放假的点不同色
    final makeup = glyphs[1].decoration! as BoxDecoration;
    expect(makeup.color, scheme.tertiary);
    expect(makeup.shape, BoxShape.circle);
    expect(makeup.color, isNot(holiday.color));

    // 未点名：空心淡圈（有描边、不填充）
    final ring = glyphs[2].decoration! as BoxDecoration;
    expect(ring.color, isNull);
    expect((ring.border! as Border).top.color, scheme.outlineVariant);

    // 出勤率：一段红弧
    expect(
      find.descendant(
        of: find.byType(AttendanceCalendarLegend),
        matching: find.byType(CustomPaint),
      ),
      findsOneWidget,
    );
  });
}
