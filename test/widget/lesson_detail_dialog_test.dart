import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:schedule_plan/core/constants/app_constants.dart';
import 'package:schedule_plan/core/theme/app_colors.dart';
import 'package:schedule_plan/core/theme/app_theme.dart';
import 'package:schedule_plan/core/theme/theme_controller.dart';
import 'package:schedule_plan/data/models/class_course.dart';
import 'package:schedule_plan/data/models/course_detail.dart';
import 'package:schedule_plan/data/models/lesson.dart';
import 'package:schedule_plan/data/repositories/settings_repository.dart';
import 'package:schedule_plan/features/schedule/lesson_detail_dialog.dart';
import 'package:schedule_plan/l10n/generated/app_localizations.dart';

/// 课程详情**对话框**回归测试。
///
/// 用户规格（本轮反馈第 2 点）：
/// - 点课表里的某个课程 → 该列变大 + 弹出对话框（原来用底部抽屉，没有后续操作）；
/// - 对话框是圆角矩形、有阴影、底色跟主题；
/// - 中间是课程详情；**右下角「去点名」**跳考勤页；**左下角「取消」**退出并回到默认大小课表。
/// 对话框里的底色/阴影取自 [ThemeController.tokens]，所以宿主必须把它挂上去
/// （真实 App 里它在 `AppDependenciesScope`，位于 MaterialApp 之上，弹窗照样能读到）。
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

LessonWithTime _lesson() => LessonWithTime(
      lesson: const Lesson(
        id: 11,
        courseId: 7,
        classId: 3,
        teacherId: AppConstants.currentTeacherId,
        weekday: 1,
        periodIndex: 3,
      ),
      startTime: '09:50',
      endTime: '10:30',
      periodType: 'normal',
      courseName: '数学',
      className: '高一(1)班',
      classColor: 'FFE53935',
      templateId: 1,
    );

CourseDetail _detail() => const CourseDetail(
      course: Course(
        id: 7,
        name: '数学',
        teacherName: '李老师',
        classIds: <int>[3],
        room: '实验楼 302',
        color: 'FFE53935',
      ),
      classNames: <String>['高一(1)班'],
      headTeachers: <String>['王老师'],
      studentCount: 42,
      color: 'FFE53935',
    );

/// 挂一个按钮打开弹窗，并把结果写进 [sink]。
Future<void> _pumpOpener(
  WidgetTester tester,
  List<LessonDetailAction?> sink,
) async {
  await tester.pumpWidget(
    _host(
      Builder(
        builder: (context) => Center(
          child: FilledButton(
            onPressed: () async {
              final action = await showLessonDetailDialog(
                context,
                lesson: _lesson(),
                detail: _detail(),
              );
              sink.add(action);
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

void main() {
  testWidgets('中间是课程详情，右下角「去点名」返回 rollCall', (tester) async {
    final results = <LessonDetailAction?>[];
    await _pumpOpener(tester, results);

    // 中间：课程名 / 人数 / 班级 / 教室 / 班主任
    expect(find.text('数学'), findsOneWidget);
    expect(find.text('42 人'), findsOneWidget);
    expect(find.text('高一(1)班'), findsWidgets);
    expect(find.text('实验楼 302'), findsOneWidget);
    expect(find.text('王老师'), findsOneWidget);

    await tester.tap(find.text('去点名'));
    await tester.pumpAndSettle();

    expect(results, <LessonDetailAction?>[LessonDetailAction.rollCall]);
    expect(find.text('去点名'), findsNothing, reason: '点完要退出弹窗，不能停在原地');
  });

  testWidgets('左下角是「取消」，点它退出并回到课表（结果为 null）', (tester) async {
    final results = <LessonDetailAction?>[];
    await _pumpOpener(tester, results);

    final cancel = tester.getRect(find.text('取消'));
    final rollCall = tester.getRect(find.text('去点名'));
    expect(
      cancel.left,
      lessThan(rollCall.left),
      reason: '用户规格：取消在左下、去点名在右下',
    );
    expect(
      cancel.center.dy,
      closeTo(rollCall.center.dy, 4),
      reason: '两个按钮应该在同一行的左右两端',
    );

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(results, <LessonDetailAction?>[null]);
  });

  testWidgets('点弹窗外面的遮罩同样退出（用户规格：点其它区域恢复默认）', (tester) async {
    final results = <LessonDetailAction?>[];
    await _pumpOpener(tester, results);

    // 点左上角空白处（弹窗之外）
    await tester.tapAt(const Offset(12, 12));
    await tester.pumpAndSettle();

    expect(results, <LessonDetailAction?>[null]);
  });

  testWidgets('弹窗是圆角矩形 + 阴影 + 主题底色', (tester) async {
    final results = <LessonDetailAction?>[];
    await _pumpOpener(tester, results);

    final decorated = tester.widget<DecoratedBox>(
      find
          .ancestor(of: find.text('数学'), matching: find.byType(DecoratedBox))
          .last,
    );
    final decoration = decorated.decoration as BoxDecoration;
    expect(decoration.borderRadius, AppRadii.dialogAll, reason: '圆角矩形');
    expect(decoration.boxShadow, isNotEmpty, reason: '要有阴影层次');
    expect(
      decoration.color,
      AppColorTokens.of(AppThemeKind.mint).surface,
      reason: '底色走主题，深浅两套主题各自适配',
    );
  });

  testWidgets('信息行：标签靠左、内容居中，且各行的中线对齐（用户规格）', (tester) async {
    final results = <LessonDetailAction?>[];
    await _pumpOpener(tester, results);

    const labels = <String>['人数', '上课班级', '上课教室', '班主任'];
    final values = <String>['42 人', '高一(1)班', '实验楼 302', '王老师'];

    final labelRects = <Rect>[
      for (final label in labels) tester.getRect(find.text(label)),
    ];
    final valueRects = <Rect>[
      for (final value in values) tester.getRect(find.text(value)),
    ];

    // 标签等宽且左边缘对齐（"标题内容左侧"）
    for (var i = 1; i < labelRects.length; i++) {
      expect(
        labelRects[i].left,
        closeTo(labelRects[0].left, 0.5),
        reason: '各行的标签必须左对齐',
      );
    }
    // 内容居中：各行的内容中线是同一条，且都在标签右侧
    for (var i = 0; i < valueRects.length; i++) {
      expect(
        valueRects[i].center.dx,
        closeTo(valueRects[0].center.dx, 1),
        reason: '各行内容的居中中线必须一致',
      );
      expect(
        valueRects[i].center.dx,
        greaterThan(labelRects[i].right),
        reason: '内容在标签右侧居中，不能压到标签上',
      );
    }
  });

  testWidgets('次要动作（换课 / 移出）收在溢出菜单里，不占主操作位', (tester) async {
    final results = <LessonDetailAction?>[];
    await _pumpOpener(tester, results);

    expect(find.text('换个课程'), findsNothing);
    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await tester.pumpAndSettle();
    expect(find.text('换个课程'), findsOneWidget);
    expect(find.text('移出课表'), findsOneWidget);

    await tester.tap(find.text('移出课表'));
    await tester.pumpAndSettle();
    expect(results, <LessonDetailAction?>[LessonDetailAction.remove]);
  });
}
