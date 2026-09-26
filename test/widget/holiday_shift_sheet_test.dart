import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:schedule_plan/core/theme/app_colors.dart';
import 'package:schedule_plan/core/theme/app_theme.dart';
import 'package:schedule_plan/features/toolbox/holiday_shift_sheet.dart';
import 'package:schedule_plan/l10n/generated/app_localizations.dart';

/// 调休"上周几的课"选择弹层（第 13 轮）。
///
/// 这是本轮唯一一个不碰数据库、又直接决定"课时怎么算"的界面，
/// 所以它的**返回值契约**必须锁死：
/// - `null` = 取消（什么都不改）
/// - `HolidayShiftChoice(null)` = 不调整
/// - `HolidayShiftChoice(n)` = 上周 n 的课
///
/// 三者混淆过来，老师的课时就会莫名其妙多一节或少一节。
void main() {
  Widget host(Widget child) => MaterialApp(
        theme: AppTheme.build(AppColorTokens.of(AppThemeKind.mint)),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: Scaffold(body: child),
      );

  /// 挂一个按钮把弹层开起来，结果写进 [result]。
  Future<void> open(
    WidgetTester tester, {
    required DateTime date,
    int? currentWeekday,
    int? suggestWeekday,
    required ValueNotifier<HolidayShiftChoice?> result,
  }) async {
    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result.value = await showHolidayShiftSheet(
                context,
                date: date,
                currentWeekday: currentWeekday,
                suggestWeekday: suggestWeekday,
              );
            },
            child: const Text('开弹层'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('开弹层'));
    await tester.pumpAndSettle();
  }

  testWidgets('七个星期都在，默认落在「不调整」上', (tester) async {
    final result = ValueNotifier<HolidayShiftChoice?>(null);
    await open(
      tester,
      date: DateTime(2026, 9, 20),
      currentWeekday: null,
      result: result,
    );

    expect(find.text('这天上周几的课？'), findsOneWidget);
    for (final label in <String>['周一', '周二', '周三', '周四', '周五', '周六', '周日']) {
      expect(find.text(label), findsOneWidget, reason: '缺了 $label');
    }
    expect(find.text('不调整（按当天）'), findsOneWidget);

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(result.value, isNotNull);
    expect(result.value!.weekday, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('点周三再保存 → 得到「上周三的课」', (tester) async {
    final result = ValueNotifier<HolidayShiftChoice?>(null);
    await open(
      tester,
      date: DateTime(2026, 9, 20),
      result: result,
    );

    await tester.tap(find.text('周三'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(result.value?.weekday, DateTime.wednesday);
  });

  testWidgets('已有确认值时回显；改回「不调整」→ 返回 null 而不是取消', (tester) async {
    final result = ValueNotifier<HolidayShiftChoice?>(null);
    await open(
      tester,
      date: DateTime(2026, 10, 10),
      currentWeekday: DateTime.thursday,
      result: result,
    );

    await tester.tap(find.text('不调整（按当天）'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(result.value, isNotNull, reason: '选"不调整"是一个有效结果，不是取消');
    expect(result.value!.weekday, isNull);
  });

  testWidgets('上次选过的星期几会作为预选（老师少点一下）', (tester) async {
    final result = ValueNotifier<HolidayShiftChoice?>(null);
    await open(
      tester,
      date: DateTime(2026, 10, 10),
      suggestWeekday: DateTime.friday,
      result: result,
    );

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(result.value?.weekday, DateTime.friday);
  });

  testWidgets('取消（关掉弹层）时什么都不返回', (tester) async {
    final result = ValueNotifier<HolidayShiftChoice?>(null);
    var finished = false;
    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result.value = await showHolidayShiftSheet(
                context,
                date: DateTime(2026, 9, 20),
                currentWeekday: null,
              );
              finished = true;
            },
            child: const Text('开弹层'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('开弹层'));
    await tester.pumpAndSettle();
    expect(finished, isFalse);

    // 点遮罩关闭
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(finished, isTrue);
    expect(result.value, isNull, reason: '取消不该被当成"不调整"写库');
  });
}
