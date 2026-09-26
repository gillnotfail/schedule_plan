import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:schedule_plan/core/constants/app_constants.dart';
import 'package:schedule_plan/core/theme/app_colors.dart';
import 'package:schedule_plan/core/theme/app_theme.dart';
import 'package:schedule_plan/data/models/lesson.dart';
import 'package:schedule_plan/data/models/schedule_event.dart';
import 'package:schedule_plan/data/models/schedule_template.dart';
import 'package:schedule_plan/features/schedule/timeline_view.dart';
import 'package:schedule_plan/l10n/generated/app_localizations.dart';

/// 时间轴视图（课表页右上角「网格 ⇄ 曲线」里的曲线那一档）自适应回归测试。
///
/// 用户规格："作息课表需要自适应窗口大小，选择周几上课后，
/// 自适应铺满整个屏幕，不需要滑动。" 也就是这一档要和课表格子一样
/// **一屏放下**：7 天均分宽度、像素密度按可用高度反算，不出现任何滚动。
LessonWithTime _lesson({
  required int weekday,
  required String start,
  required String end,
  required String course,
  String className = '高一(1)班',
}) {
  return LessonWithTime(
    lesson: Lesson(
      courseId: 1,
      classId: 1,
      teacherId: 1,
      weekday: weekday,
      periodIndex: 1,
    ),
    startTime: start,
    endTime: end,
    periodType: 'normal',
    courseName: course,
    className: className,
    classColor: '#2196F3',
    templateId: 1,
  );
}

Widget _host(Widget child) {
  return MaterialApp(
    theme: AppTheme.build(AppColorTokens.of(AppThemeKind.mint)),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('zh'),
    home: Scaffold(body: child),
  );
}

/// 把测试窗口设成给定逻辑尺寸（`devicePixelRatio = 1`，逻辑像素即物理像素）。
void _useWindow(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
}

Widget _view(List<LessonWithTime> lessons) => TimelineView(
      lessons: lessons,
      breakPeriods: const <TemplatePeriod>[],
      weekStart: DateTime(2026, 9, 21), // 周一
      tokens: AppColorTokens.of(AppThemeKind.mint),
    );

void main() {
  testWidgets('满一周的课也不出现任何滚动（横向 / 纵向都没有）', (tester) async {
    _useWindow(tester, const Size(393, 852));
    final lessons = <LessonWithTime>[
      for (var day = 1; day <= 5; day++) ...<LessonWithTime>[
        _lesson(weekday: day, start: '08:00', end: '08:40', course: '语文'),
        _lesson(weekday: day, start: '09:00', end: '09:40', course: '数学'),
        _lesson(weekday: day, start: '10:00', end: '10:40', course: '英语'),
        _lesson(weekday: day, start: '14:00', end: '14:40', course: '物理'),
        _lesson(weekday: day, start: '15:00', end: '15:40', course: '化学'),
        _lesson(weekday: day, start: '16:00', end: '16:40', course: '生物'),
      ],
    ];

    await tester.pumpWidget(_host(_view(lessons)));

    expect(
      find.byType(Scrollable),
      findsNothing,
      reason: '时间轴必须一屏铺满，"不需要滑动"就是字面意思',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('只画一键生成作息勾选的星期，周六周日不再占宽度', (tester) async {
    _useWindow(tester, const Size(393, 852));
    await tester.pumpWidget(
      _host(
        TimelineView(
          lessons: <LessonWithTime>[
            _lesson(weekday: 1, start: '08:00', end: '08:40', course: '语文'),
            _lesson(weekday: 3, start: '10:00', end: '10:40', course: '数学'),
          ],
          breakPeriods: const <TemplatePeriod>[],
          weekStart: DateTime(2026, 9, 21),
          tokens: AppColorTokens.of(AppThemeKind.mint),
          weekdays: const <int>[1, 2, 3, 4, 5],
        ),
      ),
    );

    // 用户规格："周六周日是浪费宽度的……如果用户选择周几，这里就对应选择周几"
    expect(find.textContaining('周六'), findsNothing);
    expect(find.textContaining('周日'), findsNothing);
    expect(find.textContaining('周一'), findsWidgets);
    expect(find.textContaining('周五'), findsWidgets);
    expect(tester.takeException(), isNull);

    // 课块文本必须在**这一列的宽度内**先换行、再交给 FittedBox ——
    // 否则 7 列时"课程名+班级+时间"一整行的固有宽度会把字缩到 4pt（看不清）。
    final constrained = tester.widget<ConstrainedBox>(
      find
          .ancestor(
            of: find.text('语文'),
            matching: find.byType(ConstrainedBox),
          )
          .first,
    );
    // (393 - 54) / 5 列 - 左右 2 - 内边距 8 ≈ 55.8
    expect(
      constrained.constraints.maxWidth,
      greaterThan(50),
      reason: '文本宽度要绑定到列宽，字才不会被等比缩小到不可读',
    );
  });

  testWidgets('一节课都没有时也不滚动，并仍然画出 7 天表头', (tester) async {
    _useWindow(tester, const Size(393, 852));
    await tester.pumpWidget(_host(_view(const <LessonWithTime>[])));

    expect(find.byType(Scrollable), findsNothing);
    expect(tester.takeException(), isNull);
    // 表头是"这一周有哪几天"的锚点，没课也必须画出来
    for (final label in <String>['周一', '周三', '周日']) {
      expect(find.textContaining(label), findsWidgets);
    }
  });

  testWidgets('极窄与极宽窗口都不溢出（列宽按可用宽均分）', (tester) async {
    final lessons = <LessonWithTime>[
      _lesson(weekday: 1, start: '08:00', end: '09:00', course: '语文'),
      _lesson(weekday: 6, start: '19:00', end: '20:30', course: '晚自习'),
    ];

    for (final size in <Size>[
      const Size(320, 480), // 小屏
      const Size(393, 852), // 常见手机
      const Size(900, 600), // 平板 / 横屏
    ]) {
      _useWindow(tester, size);
      await tester.pumpWidget(_host(_view(lessons)));
      await tester.pump();
      expect(
        tester.takeException(),
        isNull,
        reason: '$size 下时间轴不该溢出',
      );
      expect(find.byType(Scrollable), findsNothing);
    }
  });

  testWidgets('错峰：同一列里不同真实时间的课按纵轴错开（不重叠成一坨）', (tester) async {
    // 高一第 4 节 11:20 下课，高二第 4 节 12:00 才下课 —— 聚合到同一列时
    // 必须各按自己的真实时间落位，这正是"作息课表能错峰"看得出来的原因。
    _useWindow(tester, const Size(393, 852));
    await tester.pumpWidget(
      _host(
        _view(<LessonWithTime>[
          _lesson(
            weekday: 1,
            start: '10:40',
            end: '11:20',
            course: '高一数学',
            className: '高一(1)班',
          ),
          _lesson(
            weekday: 1,
            start: '11:20',
            end: '12:00',
            course: '高二数学',
            className: '高二(3)班',
          ),
        ]),
      ),
    );

    expect(tester.takeException(), isNull);
    final first = tester.getTopLeft(find.text('高一数学'));
    final second = tester.getTopLeft(find.text('高二数学'));
    expect(
      second.dy,
      greaterThan(first.dy),
      reason: '11:20 的课必须画在 10:40 那节的下方',
    );
  });

  testWidgets('表头高度是常量的一部分（改版式时不会忘记同步）', (tester) async {
    _useWindow(tester, const Size(393, 852));
    await tester.pumpWidget(_host(_view(const <LessonWithTime>[])));
    expect(AppConstants.timeAxisHeaderHeight, greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  // ---------------------------------------------------------------------------
  // 错峰课表上的日程（第 12 轮）
  //
  // 用户规格："新增的日程在课表上显示，目前可以显示。在错峰课表上……
  // 目前只是有日程，但很小，看不出来大概时间和内容。要么将日程时间段显示、
  // 要么点击日程，在日程的右上角小字显示具体时间和内容。"
  //
  // 采用「图例 + 点开看时间」的组合，所以这里守两件事：
  // 1. 有日程时必须出现图例（玫红块有名字）；
  // 2. 点一下必须给出**起止时间**（不能只有标题）。
  // ---------------------------------------------------------------------------

  /// 2026-09-21 是周一，所以这里给一个「周一 14:30-15:10」的单次活动。
  ScheduleEvent mondayEvent() => ScheduleEvent(
        id: 7,
        title: '教研组会',
        startAt: DateTime(2026, 9, 21, 14, 30).millisecondsSinceEpoch,
        endAt: DateTime(2026, 9, 21, 15, 10).millisecondsSinceEpoch,
      );

  Widget viewWithEvents(List<ScheduleEvent> events) => TimelineView(
        lessons: const <LessonWithTime>[],
        breakPeriods: const <TemplatePeriod>[],
        weekStart: DateTime(2026, 9, 21),
        tokens: AppColorTokens.of(AppThemeKind.mint),
        events: events,
      );

  testWidgets('有日程时顶部出现图例，没有日程时不出现', (tester) async {
    _useWindow(tester, const Size(393, 852));

    await tester.pumpWidget(_host(viewWithEvents(const <ScheduleEvent>[])));
    expect(
      find.textContaining('点一下看时间'),
      findsNothing,
      reason: '没有日程就不要挂一条看不懂的图例占地方',
    );

    await tester.pumpWidget(
      _host(viewWithEvents(<ScheduleEvent>[mondayEvent()])),
    );
    expect(find.textContaining('日程'), findsWidgets);
    expect(find.textContaining('点一下看时间'), findsOneWidget);
    // 图例 + 方块本身，两处都占位但都不许把课表撑成可滚动
    expect(find.byType(Scrollable), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('收起态只显示标题；点一下在右上角给出发起止时间', (tester) async {
    _useWindow(tester, const Size(393, 852));
    await tester.pumpWidget(
      _host(viewWithEvents(<ScheduleEvent>[mondayEvent()])),
    );

    // 收起态：只有标题，没有时间
    expect(find.text('教研组会'), findsOneWidget);
    expect(
      find.text('14:30 - 15:10'),
      findsNothing,
      reason: '常驻显示时间会把课块挤没，所以默认收起',
    );

    await tester.tap(find.text('教研组会'));
    await tester.pumpAndSettle();

    // 展开：时间与内容都出来了（内容在浮层里重复了一次标题）
    expect(find.text('14:30 - 15:10'), findsOneWidget);
    expect(find.text('教研组会'), findsNWidgets(2));
    expect(tester.takeException(), isNull);

    // 再点一下收起
    await tester.tap(find.text('教研组会').first);
    await tester.pumpAndSettle();
    expect(find.text('14:30 - 15:10'), findsNothing);
  });

  testWidgets('没有结束时间时只显示开始时间（不出现 " - " 空尾巴）', (tester) async {
    _useWindow(tester, const Size(393, 852));
    await tester.pumpWidget(
      _host(
        viewWithEvents(<ScheduleEvent>[
          ScheduleEvent(
            id: 9,
            title: '家长会',
            startAt: DateTime(2026, 9, 21, 16, 0).millisecondsSinceEpoch,
          ),
        ]),
      ),
    );

    await tester.tap(find.text('家长会'));
    await tester.pumpAndSettle();

    // 16:00 同时也是左侧刻度栏的一个整点，所以这里**限定在浮层内部**断言，
    // 否则找到 2 个「16:00」（刻度 + 浮层）会误判成失败。
    final panel = find.ancestor(
      of: find.text('家长会').last,
      matching: find.byType(Container),
    );
    expect(
      find.descendant(of: panel.first, matching: find.text('16:00')),
      findsOneWidget,
    );
    expect(find.textContaining('16:00 - '), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
