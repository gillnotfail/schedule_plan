import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:schedule_plan/core/theme/app_colors.dart';
import 'package:schedule_plan/core/theme/app_theme.dart';
import 'package:schedule_plan/features/schedule/schedule_settings_sheet.dart';
import 'package:schedule_plan/l10n/generated/app_localizations.dart';

/// 点课表第一列某个节次时的「修改本节时间」弹层（用户规格）。
///
/// 规格要点：**调整开始时间就够了**，结束时间按作息模板里这一节的课堂时长
/// 自动算；只有特地改过结束时间，它才脱离自动。
void main() {
  /// 打开弹层并等待落定。
  Future<void> openSheet(
    WidgetTester tester,
    void Function(({String start, String end, bool cascade, bool allDays})?)
        onResult,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(AppColorTokens.of(AppThemeKind.mint)),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  final result = await showPeriodTimeSheet(
                    context,
                    periodIndex: 1,
                    startTime: '08:00',
                    endTime: '08:40',
                    availableWeekdays: const <int>[1],
                    defaultApplyAllDays: false,
                  );
                  onResult(result);
                },
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
  }

  testWidgets('初始状态：结束时间标着「自动」', (tester) async {
    await openSheet(tester, (_) {});
    expect(find.text('08:00'), findsOneWidget);
    expect(find.text('08:40'), findsOneWidget);
    expect(find.text('自动'), findsOneWidget);
  });

  testWidgets('只想改开始时间：结束时间按本节 40 分钟自动跟算', (tester) async {
    ({String start, String end, bool cascade, bool allDays})? result;
    await openSheet(tester, (value) => result = value);

    // 点开始时间字段 → 弹出机械表盘
    await tester.tap(find.text('08:00'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('9'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('30'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    // 回到节次弹层：开始变 09:30，结束自动变成 10:10（40 分钟课堂）
    expect(find.text('09:30'), findsOneWidget);
    expect(find.text('10:10'), findsOneWidget);
    expect(find.text('自动'), findsOneWidget);

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(result, isNotNull);
    expect(result!.start, '09:30');
    expect(result!.end, '10:10');
  });

  testWidgets('特地改过结束时间后，再改开始时间不会把它覆盖掉', (tester) async {
    ({String start, String end, bool cascade, bool allDays})? result;
    await openSheet(tester, (value) => result = value);

    // 手动把结束时间改成 11:00
    await tester.tap(find.text('08:40'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('11'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('00'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    expect(find.text('11:00'), findsOneWidget);
    // 徽标从「自动」变成「自定义结束时间」
    expect(find.text('自定义结束时间'), findsOneWidget);

    // 再改开始时间：结束时间应该原地不动
    await tester.tap(find.text('08:00'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('7'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    expect(find.text('07:00'), findsOneWidget);
    expect(find.text('11:00'), findsOneWidget);

    // 「恢复自动」之后，结束时间重新跟着开始时间走
    await tester.tap(find.text('恢复自动'));
    await tester.pumpAndSettle();
    expect(find.text('自动'), findsOneWidget);
    expect(find.text('07:40'), findsOneWidget);

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(result, isNotNull);
    expect(result!.start, '07:00');
    expect(result!.end, '07:40');
  });
}
