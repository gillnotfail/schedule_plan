import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:schedule_plan/app/app_navigation.dart';
import 'package:schedule_plan/core/l10n/l10n_extensions.dart';
import 'package:schedule_plan/core/theme/app_motion.dart';
import 'package:schedule_plan/data/services/reminder_scheduler.dart';
import 'package:schedule_plan/data/settings_state.dart';
import 'package:schedule_plan/features/attendance/attendance_page.dart';
import 'package:schedule_plan/features/schedule/schedule_page.dart';
import 'package:schedule_plan/features/settings/settings_page.dart';
import 'package:schedule_plan/features/toolbox/toolbox_page.dart';

/// 底部导航（用户规格：课表 - 考勤 - 工具箱 - 设置 四个 Tab）。
///
/// 统计 / 待办 / 专注 / 笔记 / 日程 / 私人清单统一收纳进「工具箱」，
/// 避免一级导航过长；设置页只保留 App 级配置。
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with WidgetsBindingObserver {
  static const List<Widget> _pages = <Widget>[
    SchedulePage(),
    AttendancePage(),
    ToolboxPage(),
    SettingsPage(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    // readme 第六章：观察者必须显式移除
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      return;
    }
    // 回到前台时按**当前生效的作息模板**重算提醒，避免学校中途调整作息后提醒过时。
    final reminders = context.read<ReminderScheduler>();
    final settings = context.read<SettingsState>();
    reminders.refreshAll(minutesBefore: settings.reminderMinutesBefore);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    // 当前 Tab 由共享导航状态决定：课表页点「去点名」时
    // 会同时切 Tab 并投递定位意图（IndexedStack 下两页是平级的，不能 push）
    final navigation = context.watch<AppNavigationState>();
    return Scaffold(
      // IndexedStack 保留各 Tab 的滚动位置与输入状态，切回时不重建
      body: IndexedStack(index: navigation.tabIndex, children: _pages),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLowest,
          border: Border(
            top: BorderSide(
              color: scheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
        ),
        child: NavigationBar(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          selectedIndex: navigation.tabIndex,
          onDestinationSelected: (index) {
            if (index == navigation.tabIndex) {
              return;
            }
            AppMotion.tap();
            navigation.switchTab(index);
          },
          destinations: <NavigationDestination>[
            NavigationDestination(
              icon: const Icon(Icons.calendar_month_outlined),
              selectedIcon: const Icon(Icons.calendar_month),
              label: l10n.tabSchedule,
            ),
            NavigationDestination(
              icon: const Icon(Icons.fact_check_outlined),
              selectedIcon: const Icon(Icons.fact_check),
              label: l10n.tabAttendance,
            ),
            NavigationDestination(
              icon: const Icon(Icons.widgets_outlined),
              selectedIcon: const Icon(Icons.widgets),
              label: l10n.tabToolbox,
            ),
            NavigationDestination(
              icon: const Icon(Icons.tune_outlined),
              selectedIcon: const Icon(Icons.tune),
              label: l10n.tabSettings,
            ),
          ],
        ),
      ),
    );
  }
}
