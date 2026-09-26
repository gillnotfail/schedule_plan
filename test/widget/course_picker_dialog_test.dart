import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:schedule_plan/core/constants/app_constants.dart';
import 'package:schedule_plan/core/theme/app_colors.dart';
import 'package:schedule_plan/core/theme/app_theme.dart';
import 'package:schedule_plan/core/theme/theme_controller.dart';
import 'package:schedule_plan/data/models/class_course.dart';
import 'package:schedule_plan/data/models/course_detail.dart';
import 'package:schedule_plan/data/repositories/settings_repository.dart';
import 'package:schedule_plan/features/schedule/course_picker_dialog.dart';
import 'package:schedule_plan/l10n/generated/app_localizations.dart';

/// 「选一门课放进这一格」对话框测试。
///
/// 用户规格（本轮第 4 点）：空白格子改成**对话框**（原来是底部抽屉），
/// 里面用小卡片 / **带颜色的课程名字**上下滑动选择。
///
/// 对话框底色与阴影取自 [ThemeController.tokens]，宿主必须挂上它
/// （真实 App 里它在 `AppDependenciesScope`，位于 MaterialApp 之上）。
Widget _host(Widget child) {
  return ChangeNotifierProvider<ThemeController>.value(
    value: ThemeController(SettingsRepository()),
    child: MaterialApp(
      theme: AppTheme.build(AppColorTokens.of(AppThemeKind.mint)),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('zh'),
      home: Scaffold(body: child),
    ),
  );
}

CourseDetail _course({
  required int id,
  required String name,
  required String color,
  required List<String> classNames,
  required int studentCount,
}) {
  return CourseDetail(
    course: Course(
      id: id,
      name: name,
      teacherName: '李老师',
      classIds: <int>[for (var i = 0; i < classNames.length; i++) id * 10 + i],
      room: '实验楼 302',
      color: color,
    ),
    classNames: classNames,
    headTeachers: const <String>['王老师'],
    studentCount: studentCount,
    color: color,
  );
}

final _math = _course(
  id: 7,
  name: '数学',
  color: 'FFE53935',
  classNames: <String>['高一(1)班'],
  studentCount: 42,
);
final _physics = _course(
  id: 8,
  name: '物理',
  color: 'FF1E88E5',
  classNames: <String>['高一(2)班', '高一(3)班'],
  studentCount: 86,
);

Future<void> _pumpOpener(
  WidgetTester tester,
  List<CourseDetail?> sink, {
  List<CourseDetail>? courses,
}) async {
  await tester.pumpWidget(
    _host(
      Builder(
        builder: (context) => Center(
          child: FilledButton(
            onPressed: () async {
              final picked = await showCoursePickerDialog(
                context,
                courses: courses ?? <CourseDetail>[_math, _physics],
                slotLabel: '周一 · 第 3 节',
              );
              sink.add(picked);
            },
            child: const Text('打开'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开'));
  await tester.pumpAndSettle();
}

Color _textColor(WidgetTester tester, String text) {
  return tester.widget<Text>(find.text(text)).style!.color!;
}

/// 卡片（AnimatedContainer 内部那个 Container）的描边宽度：选中时更粗。
double _cardBorderWidth(WidgetTester tester, String courseName) {
  final container = tester.widget<Container>(
    find
        .ancestor(of: find.text(courseName), matching: find.byType(Container))
        .first,
  );
  final decoration = container.decoration! as BoxDecoration;
  return decoration.border!.top.width;
}

void main() {
  testWidgets('用对话框（不是底部抽屉）+ 圆角 + 阴影 + 主题底色', (tester) async {
    final results = <CourseDetail?>[];
    await _pumpOpener(tester, results);

    // 底部抽屉会带 BottomSheet；这里必须没有
    expect(find.byType(BottomSheet), findsNothing, reason: '用户规格：改成对话式弹窗');

    final decorated = tester.widget<DecoratedBox>(
      find
          .ancestor(
            of: find.text('选一门课放进这一格'),
            matching: find.byType(DecoratedBox),
          )
          .last,
    );
    final decoration = decorated.decoration as BoxDecoration;
    expect(decoration.borderRadius, AppRadii.dialogAll);
    expect(decoration.boxShadow, isNotEmpty);
    expect(decoration.color, AppColorTokens.of(AppThemeKind.mint).surface);
  });

  testWidgets('课程名带各自颜色，卡片上带人数与班级', (tester) async {
    final results = <CourseDetail?>[];
    await _pumpOpener(tester, results);

    // 用户规格：带颜色的课程名字
    expect(_textColor(tester, '数学'), const Color(0xFFE53935));
    expect(_textColor(tester, '物理'), const Color(0xFF1E88E5));

    expect(find.textContaining('42 人'), findsOneWidget);
    expect(find.textContaining('高一(2)班、高一(3)班'), findsOneWidget);
  });

  testWidgets('点卡片选中，再点右下角「放进这一格」返回那一门课', (tester) async {
    final results = <CourseDetail?>[];
    await _pumpOpener(tester, results);

    // 默认选中第一门：选中的那门卡片描边更粗
    expect(_cardBorderWidth(tester, '数学'), greaterThan(1));
    expect(_cardBorderWidth(tester, '物理'), 1);

    await tester.tap(find.text('物理'));
    await tester.pumpAndSettle();
    expect(_cardBorderWidth(tester, '物理'), greaterThan(1));
    expect(_cardBorderWidth(tester, '数学'), 1);

    await tester.tap(find.text('放进这一格'));
    await tester.pumpAndSettle();

    expect(results.length, 1);
    expect(results.single?.name, '物理');
  });

  testWidgets('左下角「取消」返回 null，不往课表里放东西', (tester) async {
    final results = <CourseDetail?>[];
    await _pumpOpener(tester, results);

    final cancel = tester.getRect(find.text('取消'));
    final place = tester.getRect(find.text('放进这一格'));
    expect(cancel.left, lessThan(place.left), reason: '取消在左、放进这一格在右');

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(results, <CourseDetail?>[null]);
  });

  testWidgets('课程很多时列表可上下滚动，不会把对话框撑出屏幕', (tester) async {
    final results = <CourseDetail?>[];
    await _pumpOpener(
      tester,
      results,
      courses: <CourseDetail>[
        for (var i = 0; i < 12; i++)
          _course(
            id: 100 + i,
            name: '课程$i',
            color: 'FF26A69A',
            classNames: const <String>['高一(1)班'],
            studentCount: 40 + i,
          ),
      ],
    );

    final dialogRect = tester.getRect(find.byType(Dialog));
    expect(dialogRect.top, greaterThanOrEqualTo(0));
    expect(dialogRect.bottom, lessThanOrEqualTo(tester.view.physicalSize.height));

    // 列表可滚：最后一门课初始不在视口内，滚动后才可见
    expect(find.text('课程11'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('课程11'),
      260,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    expect(find.text('课程11'), findsOneWidget);
  });
}
