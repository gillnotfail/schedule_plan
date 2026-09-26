import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:schedule_plan/core/constants/app_constants.dart';
import 'package:schedule_plan/core/theme/app_colors.dart';
import 'package:schedule_plan/core/theme/app_theme.dart';
import 'package:schedule_plan/core/widgets/sort_arrow.dart';
import 'package:schedule_plan/data/models/student.dart';
import 'package:schedule_plan/features/attendance/class_group_band.dart';
import 'package:schedule_plan/l10n/generated/app_localizations.dart';

/// 考勤名单「班级分组横带」回归测试。
///
/// 用户规格（含参考图）："最好如图，按班级排序，每个班的学生划在区分线。
/// ui 还是你的 ui 那一套，只是思路是，按照班级分类学生，
/// 同时每个班支持姓名，学号，考勤等排序。"
///
/// 参考图里一条横带 = 左边班名，右边「姓名 ↑ / 学号 / 考勤」三枚，
/// 激活的那一枚是高亮胶囊。
///
/// 这个文件守住四件事：
/// 1. 横带上有班名 + 人数，且三枚排序列都在场；
/// 2. **激活的那一枚是高亮胶囊**，其余是透明的 —— 老师一眼看得出按什么排的；
/// 3. 点某一枚就回调对应的排序列；
/// 4. 横带是全页最挤的一行，在 393 真机宽度下**不溢出**（这条是它单独抽成
///    一个文件、能被 widget 测试直接渲染的主要原因）。
Widget _host(Widget child) {
  return MaterialApp(
    theme: AppTheme.build(AppColorTokens.of(AppThemeKind.mint)),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('zh'),
    home: Scaffold(body: child),
  );
}

Widget _band({
  String className = '高一6班',
  int count = 4,
  StudentSortMode sortMode = StudentSortMode.namePinyin,
  SortDirection direction = SortDirection.ascending,
  ValueChanged<StudentSortMode>? onSortTap,
}) {
  return ClassGroupBand(
    className: className,
    fallbackLabel: '班级管理',
    count: count,
    sortMode: sortMode,
    direction: direction,
    onSortTap: onSortTap ?? (_) {},
  );
}

/// 取某一枚排序列按钮的底色（激活 = 高亮胶囊，未激活 = 透明）。
Color? _chipColor(WidgetTester tester, String label) {
  final container = tester.widget<AnimatedContainer>(
    find
        .ancestor(
          of: find.text(label),
          matching: find.byType(AnimatedContainer),
        )
        .first,
  );
  return (container.decoration! as BoxDecoration).color;
}

void main() {
  testWidgets('横带上有班名、人数和三枚排序列（姓名 / 学号 / 考勤）', (tester) async {
    await tester.pumpWidget(_host(_band(count: 4)));

    expect(find.text('高一6班'), findsOneWidget);
    expect(find.text('4 人'), findsOneWidget);
    for (final label in <String>['姓名', '学号', '考勤']) {
      expect(find.text(label), findsOneWidget, reason: '$label 这一列必须能点');
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('激活的那一枚是高亮胶囊，其余是透明的', (tester) async {
    final scheme =
        AppTheme.build(AppColorTokens.of(AppThemeKind.mint)).colorScheme;

    await tester.pumpWidget(
      _host(_band(sortMode: StudentSortMode.studentNo)),
    );

    // 参考图里激活项是一枚实心胶囊（这里用 secondaryContainer）
    expect(
      _chipColor(tester, '学号'),
      scheme.secondaryContainer.withValues(alpha: 0.75),
      reason: '当前排序方式必须一眼看得出来',
    );
    expect(_chipColor(tester, '姓名'), Colors.transparent);
    expect(_chipColor(tester, '考勤'), Colors.transparent);
  });

  testWidgets('点某一枚就回调对应的排序列（排序状态由页面统一持有）', (tester) async {
    final picked = <StudentSortMode>[];
    await tester.pumpWidget(_host(_band(onSortTap: picked.add)));

    await tester.tap(find.text('考勤'));
    await tester.pump();
    await tester.tap(find.text('学号'));
    await tester.pump();

    expect(picked, <StudentSortMode>[
      StudentSortMode.attendanceStatus,
      StudentSortMode.studentNo,
    ]);
  });

  testWidgets('393 真机宽度下横带不溢出（班名 + 人数 + 三枚排序列并排）', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 852);
    addTearDown(tester.view.reset);

    // 393 - 名单左右各 spaceL，就是横带真正拿到的宽度
    final bandWidth = 393 - AppConstants.spaceL * 2;
    await tester.pumpWidget(
      _host(
        SizedBox(
          width: bandWidth,
          // 参考图里最长的班名情况
          child: _band(className: '高三年级实验班', count: 152),
        ),
      ),
    );

    expect(tester.takeException(), isNull, reason: '横带不能把一行挤爆');
    expect(
      tester.getSize(find.byType(ClassGroupBand)).height,
      AppConstants.rosterGroupBandHeight + AppConstants.spaceXs + AppConstants.spaceS,
    );
    // 挤到极限时班名可以省略号，但三枚排序列必须还在
    for (final label in <String>['姓名', '学号', '考勤']) {
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('班名查不到时回落到兜底文案（横带不会变成一条空白）', (tester) async {
    await tester.pumpWidget(_host(_band(className: '   ')));
    expect(find.text('班级管理'), findsOneWidget);
  });

  testWidgets('排序列的显示名走 l10n（禁止硬编码）', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      _host(
        Builder(
          builder: (context) {
            ctx = context;
            return _band();
          },
        ),
      ),
    );

    expect(studentSortLabelOf(ctx, StudentSortMode.namePinyin), '姓名');
    expect(studentSortLabelOf(ctx, StudentSortMode.studentNo), '学号');
    expect(studentSortLabelOf(ctx, StudentSortMode.attendanceStatus), '考勤');
  });
}
