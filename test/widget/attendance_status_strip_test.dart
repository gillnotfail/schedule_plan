import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:schedule_plan/core/constants/app_constants.dart';
import 'package:schedule_plan/core/theme/app_colors.dart';
import 'package:schedule_plan/core/theme/app_theme.dart';
import 'package:schedule_plan/data/models/attendance.dart';
import 'package:schedule_plan/features/attendance/attendance_status_strip.dart';
import 'package:schedule_plan/l10n/generated/app_localizations.dart';

/// 「一键考勤状态」回归测试。
///
/// 用户规格：考勤状态迟到、早退、缺勤、请假要**平铺在某条学生信息后**，
/// 不能让老师滑动或者循环点击一个一个去选 —— 那太浪费时间。
/// 位置不够就简化成一个字。
///
/// 这个用例守住四件事：
/// 1. 七个状态同时在场（日常五种 + 休学 / 免修）、名字够短（一个字）；
/// 2. **一次点击 = 一次落库**，点哪个就是哪个，不需要"点三下才轮到请假"；
/// 3. 在真机宽度下和「姓名 + 学号」并排也放得下，不会溢出；
/// 4. 学生处于休学 / 免修时日常五态被锁住（点不动），只有长期状态本身可点。
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
  final tokens = AppColorTokens.of(AppThemeKind.mint);

  testWidgets('七个状态平铺在场（日常五 + 休学 / 免修），且都是一个字', (tester) async {
    await tester.pumpWidget(
      _host(
        AttendanceStatusStrip(
          status: AttendanceStatus.present,
          tokens: tokens,
          onPick: (_) {},
        ),
      ),
    );

    for (final label in <String>['出', '迟', '早', '缺', '假', '休', '免']) {
      expect(find.text(label), findsOneWidget, reason: '状态 $label 必须平铺出来');
    }
    // "未标记"只是显示态，不该作为一个可选项摊在行上
    expect(find.text('—'), findsNothing);
  });

  testWidgets('学生在休学 / 免修期间：日常五态点不动，长期状态本身可以点', (tester) async {
    final picked = <AttendanceStatus>[];
    await tester.pumpWidget(
      _host(
        AttendanceStatusStrip(
          status: AttendanceStatus.suspended,
          tokens: tokens,
          locked: true,
          onPick: picked.add,
        ),
      ),
    );

    await tester.tap(find.text('缺'));
    await tester.tap(find.text('假'));
    await tester.pump();
    expect(picked, isEmpty, reason: '长期状态期间日常点名要锁住，否则会把"休学"冲掉');

    // 再点一次长期状态本身 = 取消（由页面弹确认），所以它必须仍然可点
    await tester.tap(find.text('休'));
    await tester.pump();
    expect(picked, <AttendanceStatus>[AttendanceStatus.suspended]);
  });

  testWidgets('点哪个状态就是哪个状态（一次点击即落库）', (tester) async {
    final picked = <AttendanceStatus>[];
    await tester.pumpWidget(
      _host(
        AttendanceStatusStrip(
          status: AttendanceStatus.present,
          tokens: tokens,
          onPick: picked.add,
        ),
      ),
    );

    await tester.tap(find.text('缺'));
    await tester.tap(find.text('假'));
    await tester.tap(find.text('迟'));
    await tester.pump();

    expect(picked, <AttendanceStatus>[
      AttendanceStatus.absent,
      AttendanceStatus.leave,
      AttendanceStatus.late,
    ]);
  });

  testWidgets('选中态跟着传入的状态走', (tester) async {
    await tester.pumpWidget(
      _host(
        AttendanceStatusStrip(
          status: AttendanceStatus.leave,
          tokens: tokens,
          onPick: (_) {},
        ),
      ),
    );

    final leave = tester.widget<AnimatedContainer>(
      find
          .ancestor(
            of: find.text('假'),
            matching: find.byType(AnimatedContainer),
          )
          .first,
    );
    final present = tester.widget<AnimatedContainer>(
      find
          .ancestor(
            of: find.text('出'),
            matching: find.byType(AnimatedContainer),
          )
          .first,
    );
    // 选中的用实色，没选中的是 10% 淡色 —— 一眼能看出当前状态
    expect((leave.decoration! as BoxDecoration).color, tokens.attendanceLeave);
    expect(
      (present.decoration! as BoxDecoration).color,
      tokens.attendancePresent.withValues(alpha: 0.10),
    );
  });

  testWidgets('和「姓名 + 学号」并排时放得下（393 真机宽度不溢出）', (tester) async {
    tester.view.physicalSize = const Size(393 * 3, 852 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _host(
        // 393 - 页面左右各 16 - 行内左右各 12 = 337，就是学生行真正的内容宽度
        SizedBox(
          width: 337,
          child: Row(
            children: <Widget>[
              const Expanded(
                flex: 3,
                child: Text('欧阳建国', maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              const Expanded(
                flex: 2,
                child: Text('20260101', maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              AttendanceStatusStrip(
                status: AttendanceStatus.present,
                tokens: tokens,
                onPick: (_) {},
              ),
            ],
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull, reason: '状态平铺不能把一行挤爆');
    expect(
      tester.getSize(find.byType(AttendanceStatusStrip)).width,
      AppConstants.attendanceStatusStripWidth,
    );
  });
}
