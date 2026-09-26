import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_plan/core/constants/app_constants.dart';
import 'package:schedule_plan/core/theme/app_colors.dart';
import 'package:schedule_plan/core/theme/app_theme.dart';
import 'package:schedule_plan/core/widgets/app_card.dart';
import 'package:schedule_plan/core/widgets/confirm_dialog.dart';
import 'package:schedule_plan/core/widgets/pulse_loading.dart';
import 'package:schedule_plan/core/widgets/scale_tap.dart';
import 'package:schedule_plan/core/widgets/wheel_time_picker.dart';
import 'package:schedule_plan/l10n/generated/app_localizations.dart';

/// 统一的测试宿主：注入全局本地化，保证组件内 `context.l10n` 可用。
Widget _host(Widget child, {ThemeData? theme}) {
  return MaterialApp(
    theme: theme ?? AppTheme.build(AppColorTokens.of(AppThemeKind.mint)),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('zh'),
    home: Scaffold(body: Center(child: child)),
  );
}

void main() {
  group('AppCard', () {
    testWidgets('渲染子元素且使用统一圆角', (tester) async {
      await tester.pumpWidget(_host(const AppCard(child: Text('卡片内容'))));
      expect(find.text('卡片内容'), findsOneWidget);

      final container = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(AppCard),
              matching: find.byType(Container),
            )
            .first,
      );
      final decoration = container.decoration;
      expect(decoration, isA<BoxDecoration>());
      final radius = (decoration! as BoxDecoration).borderRadius;
      // Material 3 Expressive：卡片统一使用高曲率 Squircel 圆角
      expect(radius, BorderRadius.circular(AppRadii.squircelAll.topLeft.x));
      expect(AppRadii.squircel, 22.0);
    });
  });

  group('PulseLoading', () {
    testWidgets('显示加载指示且能正常构建', (tester) async {
      await tester.pumpWidget(_host(const PulseLoading()));
      await tester.pump();
      expect(find.byType(PulseLoading), findsOneWidget);
    });

    testWidgets('动画推进后不抛异常', (tester) async {
      await tester.pumpWidget(_host(const PulseLoading()));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
    });
  });

  group('ScaleTap', () {
    testWidgets('点击回调被触发', (tester) async {
      var tapped = 0;
      await tester.pumpWidget(_host(ScaleTap(
        onTap: () => tapped++,
        child: const Text('点我'),
      )));
      await tester.tap(find.text('点我'));
      await tester.pumpAndSettle();
      expect(tapped, 1);
    });

    testWidgets('onTap 为空时不可点击（禁用态）', (tester) async {
      await tester.pumpWidget(_host(const ScaleTap(child: Text('禁用'))));
      await tester.tap(find.text('禁用'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('showAppConfirm', () {
    testWidgets('点击确认返回 true', (tester) async {
      bool? result;
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: Builder(builder: (context) {
          return TextButton(
            onPressed: () async {
              result = await showAppConfirm(
                context: context,
                title: '删除作息模板',
                body: '删除后绑定该模板的 3 个班级将回落到默认模板，此操作不可撤销。',
              );
            },
            child: const Text('打开'),
          );
        }),
      ));

      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      expect(find.text('删除作息模板'), findsOneWidget);
      expect(
        find.text('删除后绑定该模板的 3 个班级将回落到默认模板，此操作不可撤销。'),
        findsOneWidget,
      );

      await tester.tap(find.text('确认'));
      await tester.pumpAndSettle();
      expect(result, isTrue);
    });

    testWidgets('点击取消返回 false', (tester) async {
      bool? result;
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: Builder(builder: (context) {
          return TextButton(
            onPressed: () async {
              result = await showAppConfirm(
                context: context,
                title: '清空考勤记录',
                body: '本月 128 条记录将被永久删除。',
              );
            },
            child: const Text('打开'),
          );
        }),
      ));

      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(result, isFalse);
    });

    testWidgets('危险操作使用自定义确认文案', (tester) async {
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: Builder(builder: (context) {
          return TextButton(
            onPressed: () => showAppConfirm(
              context: context,
              title: '删除班级',
              body: '该班级下 42 名学生与 56 条考勤记录将一并删除。',
              confirmLabel: '永久删除',
              danger: true,
            ),
            child: const Text('打开'),
          );
        }),
      ));

      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      expect(find.text('永久删除'), findsOneWidget);
    });
  });

  group('WheelTimePicker', () {
    testWidgets('按初始值渲染小时/分钟两列', (tester) async {
      var value = '08:30';
      await tester.pumpWidget(_host(WheelTimePicker(
        initialTime: '08:30',
        onChanged: (next) => value = next,
      )));
      await tester.pumpAndSettle();

      expect(find.byType(ListWheelScrollView), findsNWidgets(2));
      expect(value, '08:30');
    });

    testWidgets('非法初始值回落到 00:00 而不崩溃', (tester) async {
      var value = '';
      await tester.pumpWidget(_host(WheelTimePicker(
        initialTime: '不合法',
        onChanged: (next) => value = next,
      )));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(value, '');
    });

    testWidgets('滚动分钟列后吸附到 5 分钟刻度', (tester) async {
      final values = <String>[];
      await tester.pumpWidget(_host(WheelTimePicker(
        initialTime: '08:00',
        onChanged: values.add,
      )));
      await tester.pumpAndSettle();

      final wheel = find.byType(ListWheelScrollView).last;
      await tester.drag(wheel, const Offset(0, -220));
      // 等待 120ms 吸附定时器 + 200ms 吸附动画
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();

      expect(values, isNotEmpty, reason: '滚动分钟列应当触发 onChanged');
      for (final value in values) {
        expect(RegExp(r'^\d{2}:\d{2}$').hasMatch(value), isTrue);
      }
      final minutePart = int.parse(values.last.split(':').last);
      expect(minutePart % AppConstants.wheelSnapMinutes, 0);
    });
  });
}
