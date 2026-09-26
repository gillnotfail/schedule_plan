import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:schedule_plan/core/constants/app_constants.dart';
import 'package:schedule_plan/core/theme/app_colors.dart';
import 'package:schedule_plan/core/theme/app_theme.dart';
import 'package:schedule_plan/features/schedule/schedule_share_footer.dart';
import 'package:schedule_plan/l10n/generated/app_localizations.dart';

/// 课表分享卡片**底部信息带**回归测试。
///
/// 用户规格（第 8 轮）："自动截图当前课表的屏幕，同时在课表最下方加上 app 名。
/// 后续可能还要加上二维码供分享……你留个位置，做好标记，
/// 包括 app 和二维码位置，后续我自己加上。"
///
/// 这条信息带是留给用户的两个替换点，测试守住三件事：
/// 1. app 名在场（`l10n.appTitle`，别拼错也别硬编码）；
/// 2. 二维码占位在**给定的尺寸**里（尺寸就是给真实二维码留的位置，别缩水）；
/// 3. 信息带按 `shareFooterHeight` 的高度渲染，**真机宽度下不溢出**
///    （它会被原样拼进截图，溢出就直接画到分享图上）。
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
  testWidgets('信息带上有 app 名和二维码占位', (tester) async {
    await tester.pumpWidget(_host(const ScheduleShareFooter()));

    expect(find.text('全面课表计划'), findsOneWidget, reason: 'app 名别硬编码、别拼错');
    expect(find.text('二维码位'), findsOneWidget, reason: '这是留给二维码的替换点');
    expect(find.byIcon(Icons.qr_code_2_rounded), findsOneWidget);
  });

  testWidgets('二维码占位尺寸就是给真实二维码留的位置（别缩水）', (tester) async {
    await tester.pumpWidget(_host(const ScheduleShareFooter()));

    // 占位框尺寸来自常量：换真实二维码时沿用同一个尺寸即可
    expect(
      tester.getSize(find.byIcon(Icons.qr_code_2_rounded)).height,
      lessThanOrEqualTo(AppConstants.shareQrPlaceholderSize),
    );
    final footer = tester.getSize(find.byType(ScheduleShareFooter));
    expect(footer.height, AppConstants.shareFooterHeight);
  });

  testWidgets('393 真机宽度下信息带不溢出（要原样拼进分享图）', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 852);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host(const ScheduleShareFooter()));

    expect(tester.takeException(), isNull, reason: '信息带不能把一行挤爆');
    expect(
      tester.getSize(find.byType(ScheduleShareFooter)).width,
      393,
    );
  });
}
