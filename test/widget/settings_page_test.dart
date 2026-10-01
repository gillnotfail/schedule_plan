import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:schedule_plan/core/i18n/locale_controller.dart';
import 'package:schedule_plan/core/theme/app_colors.dart';
import 'package:schedule_plan/core/theme/app_theme.dart';
import 'package:schedule_plan/core/theme/theme_controller.dart';
import 'package:schedule_plan/data/db/schema.dart';
import 'package:schedule_plan/data/repositories/attendance_repository.dart';
import 'package:schedule_plan/data/repositories/class_repository.dart';
import 'package:schedule_plan/data/repositories/holiday_repository.dart';
import 'package:schedule_plan/data/repositories/import_log_repository.dart';
import 'package:schedule_plan/data/repositories/lesson_repository.dart';
import 'package:schedule_plan/data/repositories/schedule_event_repository.dart';
import 'package:schedule_plan/data/repositories/settings_repository.dart';
import 'package:schedule_plan/data/repositories/student_repository.dart';
import 'package:schedule_plan/data/services/cleanup_service.dart';
import 'package:schedule_plan/data/services/holiday_sync_service.dart';
import 'package:schedule_plan/data/services/notification_service.dart';
import 'package:schedule_plan/data/services/reminder_scheduler.dart';
import 'package:schedule_plan/data/services/update_service.dart';
import 'package:schedule_plan/data/settings_state.dart';
import 'package:schedule_plan/features/settings/settings_page.dart';
import 'package:schedule_plan/features/settings/system_settings_page.dart';
import 'package:schedule_plan/l10n/generated/app_localizations.dart';

/// 设置页重排（第 22 轮）的回归护栏。
///
/// 用户规格：
/// - 第一页**只有四块**：课表与名单 / 系统设置（一条入口）/ 显示与语言 / 关于；
/// - 原来平铺的「教学参数」「权限」「数据维护」整体搬进新的**系统设置页**；
/// - 最上面那张**彩色标题卡挪到页面最底部**；
/// - 「拍照生成课表」与「统计设置」两条入口从设置页删除；
/// - 「关于」里的「技术栈」一行删除。
///
/// 这些约束光靠人工看界面很容易在后续改动里被悄悄破坏（比如顺手把标题卡
/// 挪回顶部、把节假日那三条又摊回第一页），所以在这里一次性钉死。
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
  // 用 **同 isolate** 的实现：默认的 databaseFactoryFfi 会把 sqlite 放到独立
  // isolate 上跑，查询只能靠真实时间完成 —— widget 测试推的是假时钟，于是
  // sqflite 内部的锁超时 Timer 会一直挂到测试结束，被判成 pending timer。
  // 同 isolate 版走微任务，pumpAndSettle 就能把它们放完。
  databaseFactory = databaseFactoryFfiNoIsolate;

  /// 设置页整页比默认的 800×600 测试窗口高得多。List 类 sliver 只会在元素
  /// 真正进入视口时才创建子 widget，窗口不够高时「关于」「标题卡」这些
  /// 靠后的行根本不在 element 树里，`find.text` 会误判成"不存在"。
  /// 所以先把测试窗口拉高，保证整页一次建完。
  void useTallWindow(WidgetTester tester) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 3000);
    addTearDown(tester.view.reset);
  }

  late Database db;

  setUp(() async {
    db = await _openMemoryDb();
  });

  tearDown(() async {
    await db.close();
  });

  /// 设置页用到的全部依赖（第一页 + 点进系统设置页后那一页要用的）。
  Widget host(Widget child) {
    final settings = SettingsRepository(database: db);
    final notifications = NotificationService.instance;
    return MultiProvider(
      providers: [
        Provider<ClassRepository>.value(value: ClassRepository(database: db)),
        Provider<StudentRepository>.value(
          value: StudentRepository(database: db),
        ),
        Provider<NotificationService>.value(value: notifications),
        Provider<ReminderScheduler>.value(
          value: ReminderScheduler(
            lessonRepository: LessonRepository(database: db),
            eventRepository: ScheduleEventRepository(database: db),
            notificationService: notifications,
          ),
        ),
        Provider<CleanupService>.value(
          value: CleanupService(
            attendanceRepository: AttendanceRepository(database: db),
            importLogRepository: ImportLogRepository(database: db),
            settingsRepository: settings,
          ),
        ),
        ChangeNotifierProvider<SettingsState>.value(
          value: SettingsState(settings),
        ),
        ChangeNotifierProvider<ThemeController>.value(
          value: ThemeController(settings),
        ),
        ChangeNotifierProvider<LocaleController>.value(
          value: LocaleController(settings),
        ),
        ChangeNotifierProvider<HolidaySyncService>.value(
          value: HolidaySyncService(
            repository: HolidayRepository(database: db),
            settings: settings,
          ),
        ),
        ChangeNotifierProvider<UpdateService>.value(value: UpdateService()),
      ],
      child: MaterialApp(
        theme: AppTheme.build(AppColorTokens.of(AppThemeKind.mint)),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: child,
      ),
    );
  }

  testWidgets('第一页只留四块，被搬走的项不再出现在这里', (tester) async {
    useTallWindow(tester);
    await tester.pumpWidget(host(const SettingsPage()));
    await tester.pumpAndSettle();

    // ---- 四块标题都在 ----
    for (final title in <String>['课表与名单', '系统设置', '显示与语言', '关于']) {
      expect(find.text(title), findsWidgets, reason: '缺少分组：$title');
    }

    // ---- 课表与名单内部按新顺序：学生名单 → 导入 → 班级 → 课程 ----
    final roster = tester.getTopLeft(find.text('学生名单')).dy;
    final import = tester.getTopLeft(find.text('Excel 批量导入学生名单')).dy;
    final classes = tester.getTopLeft(find.text('班级管理')).dy;
    final courses = tester.getTopLeft(find.text('课程管理')).dy;
    expect(roster, lessThan(import));
    expect(import, lessThan(classes));
    expect(classes, lessThan(courses));

    // ---- 系统设置入口排在「课表与名单」之后、「显示与语言」之前 ----
    final system = tester.getTopLeft(find.text('系统设置')).dy;
    expect(courses, lessThan(system));
    expect(system, lessThan(tester.getTopLeft(find.text('显示与语言')).dy));

    // ---- 关于里的四行 ----
    for (final title in <String>['检查更新', '更新说明', '开发者']) {
      expect(find.text(title), findsOneWidget);
    }

    // ---- 这些项全被搬走 / 删掉，第一页不能再出现 ----
    const gone = <String>[
      '拍照生成课表', // 课表页已有该功能
      '统计设置', // 挪进工具箱的统计卡片
      '技术栈', // 按规格删除
      '未记录日期的默认状态',
      '时间列级联更新',
      '节假日与调休',
      '自动获取节假日安排',
      '节假日数据',
      '通知权限',
      '前往系统设置开启',
      '提前提醒分钟数',
      '立即重算提醒',
      '清理过期数据',
      '清空全部数据',
    ];
    for (final title in gone) {
      expect(find.text(title), findsNothing, reason: '$title 不该留在第一页');
    }
  });

  testWidgets('彩色标题卡沉到页面最底部（关于之后）', (tester) async {
    useTallWindow(tester);
    await tester.pumpWidget(host(const SettingsPage()));
    await tester.pumpAndSettle();

    // 标题卡是整个第一页唯一带「认证」小图标的地方，拿它定位最稳。
    final brand = find.byIcon(Icons.verified_outlined);
    expect(brand, findsOneWidget);

    final lastAboutRow = tester.getTopLeft(find.text('开发者')).dy;
    expect(
      tester.getTopLeft(brand).dy,
      greaterThan(lastAboutRow),
      reason: '标题卡必须在「关于」下面，进来先看到基础设置',
    );
  });

  testWidgets('点「系统设置」进新页，三组 + 两条单行都在那一页', (tester) async {
    useTallWindow(tester);
    await tester.pumpWidget(host(const SettingsPage()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('系统设置'));
    await tester.pumpAndSettle();

    expect(find.byType(SystemSettingsPage), findsOneWidget);

    // 三个组标题
    for (final group in <String>['调休', '通知权限', '清空数据']) {
      expect(find.text(group), findsWidgets, reason: '缺少分组：$group');
    }
    // 两条无组标题的单行
    expect(find.text('未记录日期的默认状态'), findsOneWidget);
    expect(find.text('时间列级联更新'), findsOneWidget);
    // 三组里的具体行
    for (final row in <String>[
      '节假日与调休',
      '自动获取节假日安排',
      '节假日数据',
      '前往系统设置开启',
      '提前提醒分钟数',
      '立即重算提醒',
      '清理过期数据',
      '清空全部数据',
    ]) {
      expect(find.text(row), findsOneWidget, reason: '系统设置页缺少：$row');
    }
  });
}
