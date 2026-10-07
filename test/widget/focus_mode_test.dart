import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:schedule_plan/core/theme/app_colors.dart';
import 'package:schedule_plan/core/theme/app_theme.dart';
import 'package:schedule_plan/data/db/schema.dart';
import 'package:schedule_plan/data/repositories/schedule_event_repository.dart';
import 'package:schedule_plan/data/repositories/settings_repository.dart';
import 'package:schedule_plan/data/settings_state.dart';
import 'package:schedule_plan/features/toolbox/focus/focus_done_view.dart';
import 'package:schedule_plan/features/toolbox/focus/focus_exit_sheet.dart';
import 'package:schedule_plan/features/toolbox/focus/focus_presets.dart';
import 'package:schedule_plan/features/toolbox/focus/focus_setup_view.dart';
import 'package:schedule_plan/features/toolbox/focus_timer_page.dart';
import 'package:schedule_plan/l10n/generated/app_localizations.dart';

/// 专注模式（第 23 轮）的回归护栏。
///
/// 这一版有几条**用户明确点名**的约束，光靠人工看界面很容易在后续改动里
/// 被悄悄破坏，所以在这里钉死：
/// - 时长是 `00:00:00` 三列滚轮，不是两个数字输入框；
/// - 命名分健康 / 工作效率 / 生活应用三类，**落库的是稳定 id 而不是中文名**；
/// - 退出必须"先劝一句、二次确认才放行"，不能点一下就走了；
/// - 完成之后要给回报（本次 / 今日累计 / 连续），不是弹个 toast 就完事。
///
/// 这些用例都只驱动界面，不去碰真实的锁屏通道 —— 测试环境里那条
/// MethodChannel 不存在，服务会安全降级成"不支持"。
Widget wrap(Widget child) {
  return MaterialApp(
    theme: AppTheme.build(AppColorTokens.of(AppThemeKind.mint)),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('zh'),
    home: child,
  );
}

Future<Database> _openMemoryDb() {
  return databaseFactory.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: DatabaseSchema.version,
      singleInstance: false,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, _) => DatabaseSchema.createAll(db),
    ),
  );
}

void main() {
  sqfliteFfiInit();
  // 同 isolate 的 FFI 实现：默认那套把 sqlite 放到独立 isolate，
  // 查询只能靠真实时间完成，而 widget 测试推的是假时钟 ——
  // 内部锁超时的 Timer 会一直挂到测试结束被判成 pending timer。
  databaseFactory = databaseFactoryFfiNoIsolate;

  /// 准备态一屏内容不少（预览环 + 命名卡 + 时长滚轮 + 选项 + 按钮）。
  /// 默认 800×600 会让靠后的内容根本不在 element 树里，`find` 就会误判。
  void useTallWindow(WidgetTester tester) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 2600);
    addTearDown(tester.view.reset);
  }

  /// 直接渲染准备态，省掉整个页面的依赖。
  Future<void> pumpSetup(
    WidgetTester tester, {
    required Duration total,
    required TextEditingController controller,
    FocusCategory? category,
    String? label,
    ValueChanged<Duration>? onTotalChanged,
    ValueChanged<FocusCategory?>? onCategoryChanged,
    ValueChanged<String?>? onLabelChanged,
    VoidCallback? onStart,
  }) async {
    await tester.pumpWidget(
      wrap(
        Scaffold(
          body: FocusSetupView(
            total: total,
            category: category,
            label: label,
            labelController: controller,
            soundEnabled: true,
            strongLockEnabled: false,
            onTotalChanged: onTotalChanged ?? (_) {},
            onCategoryChanged: onCategoryChanged ?? (_) {},
            onLabelChanged: onLabelChanged ?? (_) {},
            onSoundChanged: (_) {},
            onStrongLockChanged: (_) {},
            onStart: onStart ?? () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('准备态：时长以 00:00:00 呈现，三级分类与预设都在', (tester) async {
    useTallWindow(tester);
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await pumpSetup(
      tester,
      total: const Duration(minutes: 25),
      controller: controller,
    );

    // 预览与卡片上各有一处时长
    expect(find.text('00:25:00'), findsOneWidget);
    expect(find.text('25 分钟'), findsOneWidget);

    // 三级分类
    for (final name in <String>['健康', '工作效率', '生活应用']) {
      expect(find.text(name), findsOneWidget, reason: '缺少类别：$name');
    }

    // 没选类别时，全部预设都要露出来 —— "先选类别"不能成为必须的第一步
    for (final name in <String>[
      '运动',
      '冥想引导',
      '呼吸训练',
      '番茄工作法',
      '会议计时',
      '演讲计时',
      '练字',
      '打扫卫生',
      '休息提醒',
      '烹饪计时',
      '游戏计时',
    ]) {
      expect(find.text(name), findsOneWidget, reason: '缺少预设：$name');
    }

    expect(find.text('开始专注'), findsOneWidget);
  });

  testWidgets('时长为 0 时不允许开始，并说明原因', (tester) async {
    useTallWindow(tester);
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    var started = 0;

    await pumpSetup(
      tester,
      total: Duration.zero,
      controller: controller,
      onStart: () => started++,
    );

    expect(find.text('至少 1 分钟才能开始'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '开始专注'),
    );
    expect(button.onPressed, isNull, reason: '00:00:00 时开始按钮必须是禁用的');

    await tester.tap(find.text('开始专注'));
    await tester.pumpAndSettle();
    expect(started, 0);
  });

  testWidgets('点预设报上去的是稳定 id，输入框里显示的是中文名', (tester) async {
    // 这条是数据口径的护栏：写进数据库的必须是 `handwriting` 这样的稳定 id，
    // 否则换语言之后历史记录里的名字就翻不动了。
    useTallWindow(tester);
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    String? label;
    FocusCategory? category;

    await pumpSetup(
      tester,
      total: const Duration(minutes: 25),
      controller: controller,
      onLabelChanged: (value) => label = value,
      onCategoryChanged: (value) => category = value,
    );

    await tester.tap(find.text('练字'));
    await tester.pumpAndSettle();

    expect(label, 'handwriting');
    expect(category, FocusCategory.life);
    expect(controller.text, '练字');
  });

  testWidgets('退出拦截：先说清已坚持多久，只认二次确认', (tester) async {
    bool? result;
    await tester.pumpWidget(
      wrap(
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await showFocusExitSheet(
                    context,
                    elapsed: const Duration(minutes: 8),
                    remaining: const Duration(minutes: 17),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('要结束这次专注吗？'), findsOneWidget);
    expect(find.text('你已经坚持了 8 分钟'), findsOneWidget);
    expect(find.text('距离目标只差 17 分钟'), findsOneWidget);

    // 只把浮层划掉 = 没走成
    await tester.tap(find.text('继续专注'));
    await tester.pumpAndSettle();
    expect(result, isFalse, reason: '点「继续专注」不该放行');

    // 再来一次，这次真的确认
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('结束本次'));
    await tester.pumpAndSettle();
    expect(result, isTrue, reason: '二次确认后才放行');
  });

  testWidgets('完成态：给出本次 / 今日累计 / 连续三个数字与鼓励语', (tester) async {
    await tester.pumpWidget(
      wrap(
        Scaffold(
          body: FocusDoneView(
            sessionDuration: const Duration(minutes: 25),
            todayTotal: const Duration(hours: 1, minutes: 20),
            streakDays: 3,
            praise: '碎片化夺不走你的生活。',
            accent: Colors.teal,
            onBreak: () {},
            onAgain: () {},
            onFinish: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('你做到了'), findsOneWidget);
    expect(find.text('碎片化夺不走你的生活。'), findsOneWidget);

    expect(find.text('本次'), findsOneWidget);
    expect(find.text('25 分钟'), findsOneWidget);
    expect(find.text('今日累计'), findsOneWidget);
    // 满一小时要进位说，不写「80 分钟」
    expect(find.text('1 小时 20 分'), findsOneWidget);
    expect(find.text('连续专注'), findsOneWidget);
    expect(find.text('3 天'), findsOneWidget);

    expect(find.text('休息 5 分钟'), findsOneWidget);
    expect(find.text('再来一次'), findsOneWidget);
  });

  testWidgets('整页：进来停在准备态，标题是「专注模式」', (tester) async {
    useTallWindow(tester);
    final db = await _openMemoryDb();
    addTearDown(db.close);
    final settings = SettingsRepository(database: db);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<SettingsRepository>.value(value: settings),
          Provider<ScheduleEventRepository>.value(
            value: ScheduleEventRepository(database: db),
          ),
          ChangeNotifierProvider<SettingsState>.value(
            value: SettingsState(settings),
          ),
        ],
        child: wrap(const FocusTimerPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('专注模式'), findsWidgets);
    expect(find.text('开始专注'), findsOneWidget);
    // 锁屏提示必须写出来 —— 用户点下去之前得知道屏幕会被锁住
    expect(
      find.text('开始后屏幕会一直亮着并锁住，直到本次结束或你主动退出'),
      findsOneWidget,
    );
  });
}
