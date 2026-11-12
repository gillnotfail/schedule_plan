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
/// 这个用例守住五件事：
/// 1. 七个状态同时在场（日常五种 + 休学 / 免修）、名字够短（一个字）；
/// 2. **一次点击 = 一次落库**，点哪个就是哪个，不需要"点三下才轮到请假"；
/// 3. 「迟」「早」是 **and 不是 or**：点完迟到再点早退 = 两个都占（不会互相顶掉）；
/// 4. 在真机宽度下和「姓名 + 学号」并排也放得下，不会溢出；
/// 5. 休学时日常状态与免修被锁住（点不动，只有休学胶囊可点、用于「复学」）；
///    免修**不锁**日常状态，只作为角标与日常状态并存。
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
    // 迟到+早退不单独占一枚胶囊（行内不臃肿），它由「迟」「早」两枚同亮表示
    expect(find.text('迟早'), findsNothing);
  });

  testWidgets('迟到与早退是 and 不是 or：点完迟到再点早退 = 两个都占', (tester) async {
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

    await tester.tap(find.text('迟'));
    await tester.pump();
    expect(picked.last, AttendanceStatus.late, reason: '第一次点是纯迟到');

    // 换成"已经迟到"的行，再点早退：应该是**加上**早退，而不是切换成早退
    await tester.pumpWidget(
      _host(
        AttendanceStatusStrip(
          status: AttendanceStatus.late,
          tokens: tokens,
          onPick: picked.add,
        ),
      ),
    );
    await tester.tap(find.text('早'));
    await tester.pump();
    expect(
      picked.last,
      AttendanceStatus.lateAndEarly,
      reason: '点早退不能把已经标好的迟到冲掉',
    );
  });

  testWidgets('组合态时「迟」「早」两枚同时亮，出勤不亮', (tester) async {
    await tester.pumpWidget(
      _host(
        AttendanceStatusStrip(
          status: AttendanceStatus.lateAndEarly,
          tokens: tokens,
          onPick: (_) {},
        ),
      ),
    );

    Color fillOf(String label) {
      final box = tester.widget<AnimatedContainer>(
        find
            .ancestor(
              of: find.text(label),
              matching: find.byType(AnimatedContainer),
            )
            .first,
      );
      return (box.decoration! as BoxDecoration).color!;
    }

    expect(fillOf('迟'), tokens.attendanceLate);
    expect(fillOf('早'), tokens.attendanceEarlyLeave);
    expect(
      fillOf('出'),
      tokens.attendancePresent.withValues(alpha: 0.10),
      reason: '两枚都亮才叫"迟到+早退"，出勤不该同时亮',
    );
  });

  testWidgets('组合态下再点已亮的那一枚 = 减掉这一头', (tester) async {
    final picked = <AttendanceStatus>[];
    await tester.pumpWidget(
      _host(
        AttendanceStatusStrip(
          status: AttendanceStatus.lateAndEarly,
          tokens: tokens,
          onPick: picked.add,
        ),
      ),
    );

    await tester.tap(find.text('迟'));
    await tester.pump();
    expect(picked.last, AttendanceStatus.earlyLeave, reason: '去掉迟到，只剩早退');

    await tester.tap(find.text('早'));
    await tester.pump();
    expect(picked.last, AttendanceStatus.late, reason: '去掉早退，只剩迟到');
  });

  testWidgets('单迟到再点「迟」不会把学生抹成出勤（只回传原状态）', (tester) async {
    final picked = <AttendanceStatus>[];
    await tester.pumpWidget(
      _host(
        AttendanceStatusStrip(
          status: AttendanceStatus.late,
          tokens: tokens,
          onPick: picked.add,
        ),
      ),
    );

    await tester.tap(find.text('迟'));
    await tester.pump();
    // 回传的仍是"迟到"，页面按"同状态再点"处理：只给一次触觉反馈、不写库。
    // 手指抖一下就把迟到抹掉，代价太大；要恢复出勤请显式点「出」。
    expect(picked, <AttendanceStatus>[AttendanceStatus.late]);
  });

  testWidgets('点「出」「缺」「假」仍是单选，迟到早退一起清掉', (tester) async {
    final picked = <AttendanceStatus>[];
    await tester.pumpWidget(
      _host(
        AttendanceStatusStrip(
          status: AttendanceStatus.lateAndEarly,
          tokens: tokens,
          onPick: picked.add,
        ),
      ),
    );

    await tester.tap(find.text('出'));
    await tester.tap(find.text('缺'));
    await tester.pump();
    expect(picked, <AttendanceStatus>[
      AttendanceStatus.present,
      AttendanceStatus.absent,
    ]);
  });

  testWidgets('休学期间：日常五态与免修都点不动，休学胶囊可点（复学）', (tester) async {
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
    expect(picked, isEmpty, reason: '休学期间日常点名要锁住，否则会把"休学"冲掉');

    // 休学期间免修胶囊也锁死：不能直接从休学跳到免修，必须先复学
    await tester.tap(find.text('免'));
    await tester.pump();
    expect(picked, isEmpty, reason: '休学期间不能直接点免修，得先复学');

    // 再点一次休学胶囊 = 复学（由页面弹确认），所以它必须仍然可点
    await tester.tap(find.text('休'));
    await tester.pump();
    expect(picked, <AttendanceStatus>[AttendanceStatus.suspended]);
  });

  testWidgets('免修期间：日常五态照常可点，免修只作为角标、不锁', (tester) async {
    final picked = <AttendanceStatus>[];
    await tester.pumpWidget(
      _host(
        AttendanceStatusStrip(
          status: AttendanceStatus.present,
          activeLongTerm: AttendanceStatus.exempt,
          tokens: tokens,
          onPick: picked.add,
        ),
      ),
    );

    // 免修的学生仍会来上课，迟到照常能标
    await tester.tap(find.text('迟'));
    await tester.pump();
    expect(picked, <AttendanceStatus>[AttendanceStatus.late]);

    // 免修胶囊自身也可点（再点 = 取消免修，由页面弹确认）
    await tester.tap(find.text('免'));
    await tester.pump();
    expect(picked, <AttendanceStatus>[
      AttendanceStatus.late,
      AttendanceStatus.exempt,
    ]);
  });

  testWidgets('免修 + 迟到时，两枚胶囊同时高亮（角标与日常状态并存）', (tester) async {
    await tester.pumpWidget(
      _host(
        AttendanceStatusStrip(
          status: AttendanceStatus.late,
          activeLongTerm: AttendanceStatus.exempt,
          tokens: tokens,
          onPick: (_) {},
        ),
      ),
    );

    Color fillOf(String label) {
      final box = tester.widget<AnimatedContainer>(
        find
            .ancestor(
              of: find.text(label),
              matching: find.byType(AnimatedContainer),
            )
            .first,
      );
      return (box.decoration! as BoxDecoration).color!;
    }

    // 选中的用实色，没选中的是 10% 淡色
    expect(fillOf('迟'), tokens.attendanceLate);
    expect(fillOf('免'), tokens.attendanceExempt);
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
                child: Text(
                  '欧阳建国',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Expanded(
                flex: 2,
                child: Text(
                  '20260101',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
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
