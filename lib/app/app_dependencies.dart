import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:schedule_plan/app/app_navigation.dart';
import 'package:schedule_plan/core/i18n/locale_controller.dart';
import 'package:schedule_plan/core/logging/app_logger.dart';
import 'package:schedule_plan/core/theme/theme_controller.dart';
import 'package:schedule_plan/data/repositories/attendance_repository.dart';
import 'package:schedule_plan/data/repositories/class_repository.dart';
import 'package:schedule_plan/data/repositories/course_repository.dart';
import 'package:schedule_plan/data/repositories/lesson_repository.dart';
import 'package:schedule_plan/data/repositories/llm_repository.dart';
import 'package:schedule_plan/data/repositories/note_repository.dart';
import 'package:schedule_plan/data/repositories/settings_repository.dart';
import 'package:schedule_plan/data/repositories/student_repository.dart';
import 'package:schedule_plan/data/repositories/template_repository.dart';
import 'package:schedule_plan/data/repositories/todo_repository.dart';
import 'package:schedule_plan/data/services/cleanup_service.dart';
import 'package:schedule_plan/data/services/holiday_sync_service.dart';
import 'package:schedule_plan/data/services/llm_service.dart';
import 'package:schedule_plan/data/services/notification_service.dart';
import 'package:schedule_plan/data/services/reminder_scheduler.dart';
import 'package:schedule_plan/data/settings_state.dart';

/// 应用级依赖容器：仓储、服务与全局控制器。
///
/// 在 [AppDependencies.init] 中一次性构建，之后通过 Provider 向下传递，
/// 便于页面复用与测试替换。
class AppDependencies {
  AppDependencies._();

  late final SettingsRepository settings;
  late final SettingsState settingsState;
  late final ThemeController themeController;
  late final LocaleController localeController;

  /// 跨 Tab 导航状态（课表页 → 考勤页「去点名」）
  late final AppNavigationState navigation;

  late final TemplateRepository templates;
  late final ClassRepository classes;
  late final CourseRepository courses;
  late final LessonRepository lessons;
  late final StudentRepository students;
  late final AttendanceRepository attendance;
  late final TodoRepository todos;
  late final NoteRepository notes;
  late final ScheduleEventRepository events;
  late final LlmProviderRepository llmProviders;
  late final ImportLogRepository importLogs;

  late final NotificationService notifications;
  late final ReminderScheduler reminders;
  late final CleanupService cleanup;
  late final LlmService llm;

  /// 节假日数据的联网保鲜（内置表兜底 + 每年自动取回新年度安排）。
  late final HolidaySyncService holidaySync;

  static Future<AppDependencies> init() async {
    final deps = AppDependencies._();
    deps.settings = SettingsRepository();
    deps.settingsState = SettingsState(deps.settings);
    deps.themeController = ThemeController(deps.settings);
    deps.localeController = LocaleController(deps.settings);
    // 跨 Tab 导航状态：纯内存对象，不落库，重启即回到课表页
    deps.navigation = AppNavigationState();

    deps.templates = TemplateRepository();
    deps.classes = ClassRepository();
    deps.courses = CourseRepository();
    deps.lessons = LessonRepository();
    deps.students = StudentRepository();
    deps.attendance = AttendanceRepository();
    deps.todos = TodoRepository();
    deps.notes = NoteRepository();
    deps.events = ScheduleEventRepository();
    deps.llmProviders = LlmProviderRepository();
    deps.importLogs = ImportLogRepository();

    deps.notifications = NotificationService.instance;
    deps.reminders = ReminderScheduler(
      lessonRepository: deps.lessons,
      eventRepository: deps.events,
      notificationService: deps.notifications,
    );
    deps.cleanup = CleanupService(
      attendanceRepository: deps.attendance,
      importLogRepository: deps.importLogs,
      settingsRepository: deps.settings,
    );
    deps.llm = LlmService();
    deps.holidaySync = HolidaySyncService();

    await deps.settingsState.load();
    await deps.themeController.load();
    await deps.localeController.load();

    // 节假日：先把已取回的缓存灌进内存（纯本地读，很快，必须等），
    // 本次会话立刻就能用上已有的年度数据。
    await deps.holidaySync.bootstrap();

    // 再按节流策略决定要不要联网补缺的年份。**故意不 await**：
    // 网络慢的时候不能把启动卡住，等它回来自己会 notifyListeners 让页面重画。
    // 绝大多数启动都不会真发请求——该有的年份都在缓存里时 shouldFetch 直接返回 false。
    unawaited(deps.holidaySync.refreshQuietly());

    // 通知初始化失败不能阻塞启动（记录日志后继续）
    try {
      await deps.notifications.initialize();
      await deps.reminders.refreshAll(
        minutesBefore: deps.settingsState.reminderMinutesBefore,
      );
    } catch (error, stack) {
      AppLogger.e('通知服务初始化或提醒重算失败', error: error, stack: stack);
    }

    // 启动阶段执行一次过期数据清理（清理前会自动备份）
    try {
      await deps.cleanup.run();
    } catch (error, stack) {
      AppLogger.e('启动清理失败', error: error, stack: stack);
    }
    return deps;
  }
}

/// 把依赖注入到组件树。
class AppDependenciesScope extends StatelessWidget {
  const AppDependenciesScope({
    super.key,
    required this.dependencies,
    required this.child,
  });

  final AppDependencies dependencies;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<AppDependencies>.value(value: dependencies),
        Provider<SettingsRepository>.value(value: dependencies.settings),
        Provider<TemplateRepository>.value(value: dependencies.templates),
        Provider<ClassRepository>.value(value: dependencies.classes),
        Provider<CourseRepository>.value(value: dependencies.courses),
        Provider<LessonRepository>.value(value: dependencies.lessons),
        Provider<StudentRepository>.value(value: dependencies.students),
        Provider<AttendanceRepository>.value(value: dependencies.attendance),
        Provider<TodoRepository>.value(value: dependencies.todos),
        Provider<NoteRepository>.value(value: dependencies.notes),
        Provider<ScheduleEventRepository>.value(value: dependencies.events),
        Provider<LlmProviderRepository>.value(value: dependencies.llmProviders),
        Provider<ImportLogRepository>.value(value: dependencies.importLogs),
        Provider<ReminderScheduler>.value(value: dependencies.reminders),
        Provider<CleanupService>.value(value: dependencies.cleanup),
        Provider<LlmService>.value(value: dependencies.llm),
        Provider<NotificationService>.value(value: dependencies.notifications),
        ChangeNotifierProvider<SettingsState>.value(value: dependencies.settingsState),
        ChangeNotifierProvider<ThemeController>.value(value: dependencies.themeController),
        ChangeNotifierProvider<LocaleController>.value(value: dependencies.localeController),
        ChangeNotifierProvider<AppNavigationState>.value(value: dependencies.navigation),
        // 节假日数据更新完成后靠它通知常驻页面重画（课表页 / 日历页）
        ChangeNotifierProvider<HolidaySyncService>.value(value: dependencies.holidaySync),
      ],
      child: child,
    );
  }
}
