import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:schedule_plan/core/theme/app_colors.dart';
import 'package:schedule_plan/core/theme/app_theme.dart';
import 'package:schedule_plan/data/services/quote_service.dart';
import 'package:schedule_plan/features/toolbox/quote_card.dart';
import 'package:schedule_plan/l10n/generated/app_localizations.dart';

/// 工具箱首屏「每日一句」大卡片（用户规格第 21 轮）。
///
/// 这一块的验收点全在**行为与排版口径**上，颜色/造型靠肉眼看，测试钉死四条：
/// 1. 抽到哪句就显示哪句（正文 + 出处）；
/// 2. 点一下必须换一句（语料只有两条时就是必然换）；
/// 3. 外部换页信号（`rerollToken`）也必须换一句 —— 这是"切换到这一页
///    就随机跳出来"那条规格的落点，断了就等于功能没了；
/// 4. 正文与出处**居中**排 —— 用户明确说过"字体居中吧，轻松一点，不要太刻板"，
///    以后谁手滑改回左对齐，这条会拦住他。
void main() {
  const first = '大鹏一日同风起';
  const second = '会当凌绝顶';
  const all = <String>[first, second];

  /// 造一个语料只有两条的服务：两条的语料下"换句"是必然事件，断言才成立。
  QuoteService twoQuoteService({bool empty = false}) => QuoteService(
        assetLoader: () async => empty
            ? '[]'
            : jsonEncode(<Object?>[
                <String, Object?>{'text': first, 'from': '李白《上李邕》'},
                <String, Object?>{'text': second, 'from': '杜甫《望岳》'},
              ]),
        userFileLoader: () async => null,
        userPathResolver: () async => '/tmp/quotes.json',
      );

  Widget host(Widget child) => MaterialApp(
        theme: AppTheme.build(AppColorTokens.of(AppThemeKind.mint)),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: child,
          ),
        ),
      );

  /// 当前屏幕上出现的那一句（两条语料里挑出实际存在的那个）。
  String visibleQuote(WidgetTester tester, List<String> all) {
    final shown = all.where((text) => find.text(text).evaluate().isNotEmpty);
    expect(shown, hasLength(1), reason: '同一时刻只应显示一句，实际：$shown');
    return shown.first;
  }

  testWidgets('抽到哪句显示哪句，并带上出处', (tester) async {
    await tester.pumpWidget(
      host(QuoteCard(service: twoQuoteService())),
    );
    await tester.pumpAndSettle();

    final shown = visibleQuote(tester, all);
    expect(shown, isNotEmpty);
    // 出处一行带「—— 」前缀
    expect(find.textContaining('—— '), findsOneWidget);
  });

  testWidgets('点一下换一句', (tester) async {
    await tester.pumpWidget(
      host(QuoteCard(service: twoQuoteService())),
    );
    await tester.pumpAndSettle();

    final before = visibleQuote(tester, all);
    await tester.tap(find.byType(QuoteCard));
    await tester.pumpAndSettle();

    final after = visibleQuote(tester, all);
    expect(after, isNot(before), reason: '点了"轻触换一句"却没换，用户会以为点坏了');
  });

  testWidgets('外部换页信号（rerollToken）也会换一句', (tester) async {
    final service = twoQuoteService();
    await tester.pumpWidget(
      host(QuoteCard(service: service, rerollToken: 0)),
    );
    await tester.pumpAndSettle();

    final before = visibleQuote(tester, all);
    await tester.pumpWidget(
      host(QuoteCard(service: service, rerollToken: 1)),
    );
    await tester.pumpAndSettle();

    final after = visibleQuote(tester, all);
    expect(after, isNot(before));
  });

  testWidgets('rerollToken 不变时不会自己跳句', (tester) async {
    final service = twoQuoteService();
    await tester.pumpWidget(
      host(QuoteCard(service: service, rerollToken: 3)),
    );
    await tester.pumpAndSettle();
    final first = visibleQuote(tester, all);

    // 位置与结构都不变地重建一次，token 也没变 —— 状态该原样留着，不该重新抽
    await tester.pumpWidget(
      host(QuoteCard(service: service, rerollToken: 3)),
    );
    await tester.pumpAndSettle();
    expect(
      visibleQuote(tester, all),
      first,
    );
  });

  testWidgets('正文与出处都是居中排的', (tester) async {
    await tester.pumpWidget(
      host(QuoteCard(service: twoQuoteService())),
    );
    await tester.pumpAndSettle();

    final texts = tester
        .widgetList<Text>(
          find.descendant(
            of: find.byType(QuoteCard),
            matching: find.byType(Text),
          ),
        )
        .where((text) => text.data != null)
        .toList();

    final shown = texts.firstWhere((text) => all.contains(text.data));
    expect(shown.textAlign, TextAlign.center, reason: '正文要居中，不要顶左边');

    final from = texts.firstWhere((text) => text.data!.startsWith('—— '));
    expect(from.textAlign, TextAlign.center, reason: '出处要跟着居中');
  });

  testWidgets('卡片明显比工具卡高一档，撑得起"大卡片"', (tester) async {
    await tester.pumpWidget(
      host(QuoteCard(service: twoQuoteService())),
    );
    await tester.pumpAndSettle();

    // 工具卡是 158×152 上下（见 AppConstants.toolCardAspectRatio），
    // 语录卡矮了就不像"大卡片"，高了则会把首屏顶到需要滚动。
    expect(tester.getSize(find.byType(QuoteCard)).height, inInclusiveRange(180, 215));
  });

  testWidgets('语料没写出处时不冒半截破折号', (tester) async {
    await tester.pumpWidget(
      host(
        QuoteCard(
          service: QuoteService(
            assetLoader: () async => jsonEncode(<Object?>[
              <String, Object?>{'text': first},
            ]),
            userFileLoader: () async => null,
            userPathResolver: () async => '/tmp/quotes.json',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(first), findsOneWidget);
    expect(find.textContaining('——'), findsNothing);
  });

  testWidgets('语料读不到时整块卡片收起来，不留一张空壳', (tester) async {
    await tester.pumpWidget(
      host(QuoteCard(service: twoQuoteService(empty: true))),
    );
    await tester.pumpAndSettle();

    expect(find.byType(QuoteCard), findsOneWidget);
    expect(tester.getSize(find.byType(QuoteCard)).height, 0);
  });

  testWidgets('长按能看到"句子从哪来"，这是自己加内容的唯一出口', (tester) async {
    await tester.pumpWidget(
      host(QuoteCard(service: twoQuoteService())),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.byType(QuoteCard));
    await tester.pumpAndSettle();

    expect(find.text('语录来源'), findsOneWidget);
    expect(find.textContaining('/tmp/quotes.json'), findsOneWidget);
    // 内置那一条的说明里要报出条数
    expect(find.textContaining('内置'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('语录来源'), findsNothing);
  });
}
