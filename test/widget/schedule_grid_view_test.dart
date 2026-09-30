import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:schedule_plan/core/constants/app_constants.dart';
import 'package:schedule_plan/core/theme/app_colors.dart';
import 'package:schedule_plan/core/theme/app_theme.dart';
import 'package:schedule_plan/data/db/schema.dart';
import 'package:schedule_plan/data/models/lesson.dart';
import 'package:schedule_plan/data/models/schedule_template.dart';
import 'package:schedule_plan/data/repositories/template_repository.dart';
import 'package:schedule_plan/features/schedule/class_grid_view.dart';
import 'package:schedule_plan/l10n/generated/app_localizations.dart';

/// 课表页「默认表格」回归测试。
///
/// 用户规格：**第一列是节次与对应时间，第一行是周几**，
/// 打开课表页就应该看到这张表，而不是空白页。
///
/// 注意：`testWidgets` 的测试体跑在 FakeAsync 里，**不能直接 await 真实 I/O**
/// （sqflite 会永远等不到回调，表现为 `pumpAndSettle` 十分钟超时）。
/// 所以数据库相关的准备全部放在 `setUp` 里，测试体只做 pump。
Future<Database> _openMemoryDb() {
  return databaseFactory.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: DatabaseSchema.version,
      singleInstance: false,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, _) => DatabaseSchema.createAll(db),
    ),
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

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late TemplateRepository templates;
  late int seededTemplateId;
  late Map<int, List<TemplatePeriod>> seededPeriods;

  setUp(() async {
    db = await _openMemoryDb();
    templates = TemplateRepository(database: db);
    final template = (await templates.listTemplates()).first;
    seededTemplateId = template.id!;
    seededPeriods = <int, List<TemplatePeriod>>{
      for (var day = 1; day <= AppConstants.defaultWorkdayCount; day++)
        day: await templates.periodsForWeekday(seededTemplateId, day),
    };
  });

  tearDown(() async {
    await db.close();
  });

  testWidgets('出厂状态下第一列显示节次与时间、第一行显示周一到周五', (tester) async {
    expect(seededPeriods[1], isNotEmpty, reason: '出厂模板必须自带默认作息');

    await tester.pumpWidget(
      _host(
        ClassGridView(
          templateId: seededTemplateId,
          periodsByWeekday: seededPeriods,
          lessons: const <LessonWithTime>[],
          onEmptyCellTap: _noopAdd,
          onLessonTap: _noopTapLesson,
          onPeriodTap: _noopTapPeriod,
        ),
      ),
    );
    await tester.pump();

    // 第一行：周一到周五
    expect(find.text('周一'), findsOneWidget);
    expect(find.text('周五'), findsOneWidget);

    // 第一列：节次 + 起止时间
    expect(find.text(periodIndexLabelText(1)), findsWidgets);
    expect(find.text(AppConstants.defaultDayStartTime), findsWidgets);
    expect(find.text('08:40'), findsWidgets);
    expect(find.text('08:50'), findsWidgets);
  });

  testWidgets('节次为空时也要渲染出出厂节次骨架（不能是空白表）', (tester) async {
    await tester.pumpWidget(
      _host(
        const ClassGridView(
          templateId: 1,
          periodsByWeekday: <int, List<TemplatePeriod>>{},
          lessons: <LessonWithTime>[],
          onEmptyCellTap: _noopAdd,
          onLessonTap: _noopTapLesson,
          onPeriodTap: _noopTapPeriod,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('周一'), findsOneWidget);
    expect(find.text(periodIndexLabelText(1)), findsWidgets);
    expect(find.text(AppConstants.defaultDayStartTime), findsWidgets);
  });

  testWidgets('调休日：角标标在「实际上课的那一列」，长按可见说明', (tester) async {
    await tester.pumpWidget(
      _host(
        ClassGridView(
          templateId: seededTemplateId,
          periodsByWeekday: seededPeriods,
          lessons: const <LessonWithTime>[],
          // 周六补周三的课 → 角标该落在「周三」列，而不是周六
          makeupHints: const <int, String>{3: '10-10 调休上班，上周三的课'},
          onEmptyCellTap: _noopAdd,
          onLessonTap: _noopTapLesson,
          onPeriodTap: _noopTapPeriod,
        ),
      ),
    );
    await tester.pump();

    final marked = tester.widget<Tooltip>(
      find.ancestor(of: find.text('周三'), matching: find.byType(Tooltip)),
    );
    expect(marked.message, '10-10 调休上班，上周三的课');

    // 没有调休安排的列不长角标
    expect(
      find.ancestor(of: find.text('周一'), matching: find.byType(Tooltip)),
      findsNothing,
    );
  });

  testWidgets('「今天」跟着调休走：按实际执行的星期几落列', (tester) async {
    final scheme = AppTheme.build(
      AppColorTokens.of(AppThemeKind.mint),
    ).colorScheme;

    await tester.pumpWidget(
      _host(
        ClassGridView(
          templateId: seededTemplateId,
          periodsByWeekday: seededPeriods,
          lessons: const <LessonWithTime>[],
          // 周六压根不在「周一到周五」这几列里，所以一列都不该是「今天」。
          // 若实现还偷偷用 DateTime.now().weekday，今天是工作日时就会有一列亮起来。
          todayWeekday: DateTime.saturday,
          onEmptyCellTap: _noopAdd,
          onLessonTap: _noopTapLesson,
          onPeriodTap: _noopTapPeriod,
        ),
      ),
    );
    await tester.pump();

    Color? headerColor(String label) =>
        (tester
                    .widget<AnimatedContainer>(
                      find.ancestor(
                        of: find.text(label),
                        matching: find.byType(AnimatedContainer),
                      ),
                    )
                    .decoration
                as BoxDecoration)
            .color;

    final todayColor = scheme.primaryContainer.withValues(alpha: 0.85);
    for (final label in <String>['周一', '周二', '周三', '周四', '周五']) {
      expect(headerColor(label), isNot(todayColor), reason: '$label 不该被判成今天');
    }
  });

  testWidgets('格子默认只显示课程名；点开后先淡入详情，再交给课表页弹详情并收回等宽', (tester) async {
    final lesson = _lessonFor(seededPeriods[1]!.first, seededTemplateId);
    final detailTaps = <LessonWithTime>[];

    await tester.pumpWidget(
      _host(
        ClassGridView(
          templateId: seededTemplateId,
          periodsByWeekday: seededPeriods,
          lessons: <LessonWithTime>[lesson],
          courseStudentCounts: const <int, int>{7: 42},
          onEmptyCellTap: _noopAdd,
          onLessonTap: (item) async => detailTaps.add(item),
          onPeriodTap: _noopTapPeriod,
        ),
      ),
    );
    await tester.pump();

    // 用户规格："不点击的话默认显示课程名称，不显示其他"
    expect(find.text('数学'), findsOneWidget);
    expect(find.text('42 人 · 高一(1)班'), findsNothing);

    // 点一下：列先变宽、详情接着淡入 —— 但详情弹窗要等列宽动画走完才弹
    await tester.tap(find.text('数学'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 160));
    expect(find.text('42 人 · 高一(1)班'), findsOneWidget);
    expect(detailTaps, isEmpty, reason: '变宽的过程要先看得见，弹窗不能抢在前面');

    // 动画走完后交给课表页（那边弹课程详情对话框）
    await tester.pumpAndSettle();
    expect(detailTaps, <LessonWithTime>[lesson]);
    // 用户规格：对话框退出后课表要回到默认大小
    expect(find.text('42 人 · 高一(1)班'), findsNothing);
  });

  testWidgets('手风琴：点开的列变宽、其余列同步收窄，弹窗关闭后恢复默认等宽', (tester) async {
    final lesson = _lessonFor(seededPeriods[1]!.first, seededTemplateId);

    await tester.pumpWidget(
      _host(
        ClassGridView(
          templateId: seededTemplateId,
          periodsByWeekday: seededPeriods,
          lessons: <LessonWithTime>[lesson],
          courseStudentCounts: const <int, int>{7: 42},
          onEmptyCellTap: _noopAdd,
          onLessonTap: _noopTapLesson,
          onPeriodTap: _noopTapPeriod,
        ),
      ),
    );
    await tester.pump();

    final monBefore = _columnWidth(tester, '周一');
    final tueBefore = _columnWidth(tester, '周二');
    expect(monBefore, closeTo(tueBefore, 0.01), reason: '默认应该是等宽窄条');

    await tester.tap(find.text('数学'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 160));

    final monAfter = _columnWidth(tester, '周一');
    final tueAfter = _columnWidth(tester, '周二');
    expect(monAfter, greaterThan(monBefore), reason: '被点开的课所在列要变宽');
    expect(tueAfter, lessThan(tueBefore), reason: '其余列要同步收窄');
    expect(
      monAfter + tueAfter * 4,
      closeTo(monBefore + tueBefore * 4, 0.5),
      reason: '总宽度守恒，整表不会横向溢出',
    );

    // 跑完整个流程（详情回调返回 → 收回）后必须回到默认等宽
    await tester.pumpAndSettle();
    expect(
      _columnWidth(tester, '周一'),
      closeTo(monBefore, 0.01),
      reason: '用户规格：退出弹窗要"显示默认大小课表"',
    );
    expect(_columnWidth(tester, '周二'), closeTo(tueBefore, 0.01));
  });

  testWidgets('手风琴：展开期间点其它格子也会恢复默认等宽', (tester) async {
    final lesson = _lessonFor(seededPeriods[1]!.first, seededTemplateId);
    // 用 Completer 把"对话框还开着"的状态挂住，模拟老师停在弹窗里
    final hold = Completer<void>();
    final emptyTaps = <(int, int)>[];

    await tester.pumpWidget(
      _host(
        ClassGridView(
          templateId: seededTemplateId,
          periodsByWeekday: seededPeriods,
          lessons: <LessonWithTime>[lesson],
          courseStudentCounts: const <int, int>{7: 42},
          onEmptyCellTap: (weekday, periodIndex) =>
              emptyTaps.add((weekday, periodIndex)),
          onLessonTap: (item) => hold.future,
          onPeriodTap: _noopTapPeriod,
        ),
      ),
    );
    await tester.pump();

    final monBefore = _columnWidth(tester, '周一');
    await tester.tap(find.text('数学'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      _columnWidth(tester, '周一'),
      greaterThan(monBefore),
      reason: '详情弹窗还开着时，被点的列应该是变宽状态',
    );

    // 点周二第一格（空格子）：先把手风琴收回默认，再走建课/选课那条路。
    // 周一一整列第 1 格被"数学"占了，所以 add 图标的第一个就是周二第 1 节。
    await tester.tap(find.byIcon(Icons.add).first);
    await tester.pumpAndSettle();

    expect(
      _columnWidth(tester, '周一'),
      closeTo(monBefore, 0.01),
      reason: '用户规格：点其它区域要恢复默认大小',
    );
    expect(emptyTaps, <(int, int)>[(2, 1)], reason: '空格子的原有交互不能被吃掉');

    hold.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('7 天也自适应一屏：不出现横向滚动，最后一列不越界', (tester) async {
    // 用一台真机尺寸跑（393 × 852 逻辑像素），比默认测试画布更接近用户观感
    tester.view.physicalSize = const Size(393 * 3, 852 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    // 用周一的节次复制一份周一到周日的骨架（纯内存构造，不碰数据库）
    final seven = <int, List<TemplatePeriod>>{
      for (var day = 1; day <= AppConstants.weekdayCount; day++)
        day: <TemplatePeriod>[
          for (final item in seededPeriods[1]!)
            TemplatePeriod(
              templateId: seededTemplateId,
              weekday: day,
              periodIndex: item.periodIndex,
              startTime: item.startTime,
              endTime: item.endTime,
            ),
        ],
    };

    await tester.pumpWidget(
      _host(
        ClassGridView(
          templateId: seededTemplateId,
          periodsByWeekday: seven,
          lessons: const <LessonWithTime>[],
          onEmptyCellTap: _noopAdd,
          onLessonTap: _noopTapLesson,
          onPeriodTap: _noopTapPeriod,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('周日'), findsOneWidget);
    final grid = tester.getRect(find.byType(ClassGridView));
    for (final label in <String>['周一', '周三', '周五', '周日']) {
      expect(
        tester.getRect(find.text(label)).right,
        lessThanOrEqualTo(grid.right + 0.5),
        reason: '$label 不该被挤出视图（旧版靠横向滚动，用户要的是自适应一屏）',
      );
    }

    // 一屏放得下 ⇒ 纵向也不用滚（内容比视口高时才有 maxScrollExtent）。
    // 允许亚像素级的浮点残差，但绝不能真的多出一行的高度。
    final position = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;
    expect(
      position.maxScrollExtent,
      lessThan(0.5),
      reason: '用户规格："自动缩放表格，使得课表在同一个页面上显示，不需要缩放"',
    );
  });

  testWidgets('课程挑过颜色时格子用课程色，而不是班级色', (tester) async {
    final lesson = _lessonFor(seededPeriods[1]!.first, seededTemplateId);

    await tester.pumpWidget(
      _host(
        ClassGridView(
          templateId: seededTemplateId,
          periodsByWeekday: seededPeriods,
          lessons: <LessonWithTime>[lesson],
          courseStudentCounts: const <int, int>{7: 42},
          courseColors: const <int, String>{7: 'FFE53935'},
          onEmptyCellTap: _noopAdd,
          onLessonTap: _noopTapLesson,
          onPeriodTap: _noopTapPeriod,
        ),
      ),
    );
    await tester.pump();

    final accent = _cellAccent(tester, '数学');
    expect(accent, const Color(0xFFE53935));
    expect(accent, isNot(const Color(0xFF26A69A)));
  });

  testWidgets('课程没挑颜色时仍然沿用班级色', (tester) async {
    final lesson = _lessonFor(seededPeriods[1]!.first, seededTemplateId);

    await tester.pumpWidget(
      _host(
        ClassGridView(
          templateId: seededTemplateId,
          periodsByWeekday: seededPeriods,
          lessons: <LessonWithTime>[lesson],
          courseColors: const <int, String>{},
          onEmptyCellTap: _noopAdd,
          onLessonTap: _noopTapLesson,
          onPeriodTap: _noopTapPeriod,
        ),
      ),
    );
    await tester.pump();

    expect(_cellAccent(tester, '数学'), const Color(0xFF26A69A));
  });
}

LessonWithTime _lessonFor(TemplatePeriod period, int templateId) {
  return LessonWithTime(
    lesson: Lesson(
      id: 1,
      courseId: 7,
      classId: 3,
      teacherId: AppConstants.currentTeacherId,
      weekday: 1,
      periodIndex: period.periodIndex,
    ),
    startTime: period.startTime,
    endTime: period.endTime,
    periodType: period.periodType.storageKey,
    courseName: '数学',
    className: '高一(1)班',
    classColor: 'FF26A69A',
    templateId: templateId,
  );
}

/// 取某个星期列表头所在列的宽度（`_DayHeaderCell` 里包裹胶囊的那个 SizedBox）。
///
/// 手风琴是改"列宽"的，所以直接量表头所在列的宽度最贴近用户看到的观感。
double _columnWidth(WidgetTester tester, String weekdayLabel) {
  return tester
      .getSize(
        find
            .ancestor(
              of: find.text(weekdayLabel),
              matching: find.byType(SizedBox),
            )
            .first,
      )
      .width;
}

/// 取课程格子身上的**课程色**（描边的 RGB，透明度去掉）。
///
/// 只看"用的是哪一支颜色"，不看透明度——描边浓淡属于视觉微调，
/// 不该让"颜色取自课程还是班级"这条断言跟着抖。
Color _cellAccent(WidgetTester tester, String label) {
  final container = tester.widget<Container>(
    find.ancestor(of: find.text(label), matching: find.byType(Container)).first,
  );
  final decoration = container.decoration! as BoxDecoration;
  return decoration.border!.top.color.withValues(alpha: 1);
}

String periodIndexLabelText(int index) => '第 $index 节';

void _noopAdd(int weekday, int periodIndex) {}
Future<void> _noopTapLesson(LessonWithTime lesson) async {}
void _noopTapPeriod(int weekday, int periodIndex) {}
