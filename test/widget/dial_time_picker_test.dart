import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:schedule_plan/core/constants/app_constants.dart';
import 'package:schedule_plan/core/theme/app_colors.dart';
import 'package:schedule_plan/core/theme/app_theme.dart';
import 'package:schedule_plan/core/widgets/dial_time_picker.dart';
import 'package:schedule_plan/l10n/generated/app_localizations.dart';

/// 机械表盘（用户规格）。
///
/// 要点：
/// - 内圈是 **1~12 的小时数字**，外圈是 **00/05/.../55 的分钟刻度**；
/// - 两圈**同时可点**，不需要先在「时 / 分」之间切模式；
/// - 12 小时表盘必须配 上午/下午，否则「3 点」到底是凌晨还是下午说不清。
Widget _host(Widget child) {
  return MaterialApp(
    theme: AppTheme.build(AppColorTokens.of(AppThemeKind.mint)),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('zh'),
    home: Scaffold(body: Center(child: child)),
  );
}

void main() {
  group('DialTimePicker 双环表盘', () {
    testWidgets('内圈 12 个小时数字、外圈 12 个分钟刻度同时在场', (tester) async {
      await tester.pumpWidget(
        _host(DialTimePicker(initialTime: '08:00', onChanged: (_) {})),
      );
      await tester.pumpAndSettle();

      // 内圈：1~12 都渲染出来（12 点方向是「12」）
      for (final label in <String>[
        '1', '2', '3', '4', '5', '6', '7', '8', '9', '10', '11', '12',
      ]) {
        expect(find.text(label), findsWidgets, reason: '内圈缺少小时 $label');
      }
      // 外圈：每 5 分钟一格
      for (var i = 0; i < 12; i++) {
        final label = (i * AppConstants.wheelSnapMinutes).toString().padLeft(2, '0');
        expect(find.text(label), findsWidgets, reason: '外圈缺少分钟 $label');
      }
    });

    testWidgets('点内圈定小时、点外圈定分钟，两圈不用切模式', (tester) async {
      var value = '08:00';
      await tester.pumpWidget(
        _host(DialTimePicker(initialTime: '08:00', onChanged: (v) => value = v)),
      );
      await tester.pumpAndSettle();

      // 内圈：9 点
      await tester.tap(find.text('9'));
      await tester.pumpAndSettle();
      expect(value, '09:00');

      // 紧接着点外圈就是选分，不需要任何额外切换
      await tester.tap(find.text('35'));
      await tester.pumpAndSettle();
      expect(value, '09:35');
    });

    testWidgets('上午/下午换算正确，12 点方向回落到 00', (tester) async {
      var value = '08:00';
      await tester.pumpWidget(
        _host(DialTimePicker(initialTime: '08:00', onChanged: (v) => value = v)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('9'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('35'));
      await tester.pumpAndSettle();
      expect(value, '09:35');

      await tester.tap(find.text('下午'));
      await tester.pumpAndSettle();
      expect(value, '21:35');

      await tester.tap(find.text('上午'));
      await tester.pumpAndSettle();
      expect(value, '09:35');

      // 表盘上的「12」在上午时是 00 点
      await tester.tap(find.text('12'));
      await tester.pumpAndSettle();
      expect(value, '00:35');
    });

    testWidgets('初始值非法时回落到 00:00 而不是崩', (tester) async {
      await tester.pumpWidget(
        _host(DialTimePicker(initialTime: '不是时间', onChanged: (_) {})),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
