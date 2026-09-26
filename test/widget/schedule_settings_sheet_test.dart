import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:schedule_plan/core/theme/app_colors.dart';
import 'package:schedule_plan/core/theme/app_theme.dart';
import 'package:schedule_plan/features/schedule/schedule_settings_sheet.dart';
import 'package:schedule_plan/l10n/generated/app_localizations.dart';

/// 「课表设置」弹层的回归测试。
///
/// 用户报的 bug：一键生成里选了周一~周五，课表是 5 天；再选周一~周日变成 7 天；
/// 再改回周一~周五**还是 7 天**。根因是生成时只写选中的星期、不清理没选的，
/// 以及弹层每次打开都退回"周一到周五"的出厂值，看不到当前真实状态。
///
/// 这个用例守的是**后半段**：弹层打开时必须回显"现在到底是几天"。
/// 前半段（生成时清空未选中的星期）在
/// `test/unit/schedule_authority_test.dart` 里验证。
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
  testWidgets('打开时回显当前模板已经配置过的星期', (tester) async {
    late BuildContext pageContext;
    await tester.pumpWidget(
      _host(
        Builder(
          builder: (context) {
            pageContext = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    // 不 await：弹层要等 pump 才会出现在树上
    showScheduleSettingsSheet(
      pageContext,
      templateName: '默认作息',
      periodCount: 8,
      initialWeekdays: const <int>[1, 2, 3],
      initialStartTime: '09:10',
      initialLessonMinutes: 45,
      initialBreakMinutes: 5,
      onGenerate: ({
        required String startTime,
        required int lessonMinutes,
        required int breakMinutes,
        required int count,
        required List<int> weekdays,
      }) {},
      onEditDefault: () async {},
      onClear: () async {},
    );
    await tester.pumpAndSettle();

    final chips = tester.widgetList<FilterChip>(find.byType(FilterChip));
    final selected = chips.where((chip) => chip.selected).length;
    expect(selected, 3, reason: '当前只配了 3 天，弹层就该只勾这 3 天');
  });

  testWidgets('没有已配置的星期时回落到周一~周五', (tester) async {
    late BuildContext pageContext;
    await tester.pumpWidget(
      _host(
        Builder(
          builder: (context) {
            pageContext = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    showScheduleSettingsSheet(
      pageContext,
      templateName: '默认作息',
      periodCount: 8,
      initialWeekdays: const <int>[],
      onGenerate: ({
        required String startTime,
        required int lessonMinutes,
        required int breakMinutes,
        required int count,
        required List<int> weekdays,
      }) {},
      onEditDefault: () async {},
      onClear: () async {},
    );
    await tester.pumpAndSettle();

    final chips =
        tester.widgetList<FilterChip>(find.byType(FilterChip)).toList();
    expect(chips.where((chip) => chip.selected).length, 5);
  });
}
