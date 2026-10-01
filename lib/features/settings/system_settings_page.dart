import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:schedule_plan/core/constants/app_constants.dart';
import 'package:schedule_plan/core/constants/setting_keys.dart';
import 'package:schedule_plan/core/l10n/l10n_extensions.dart';
import 'package:schedule_plan/core/logging/app_logger.dart';
import 'package:schedule_plan/core/utils/date_utils.dart' as app_dates;
import 'package:schedule_plan/core/widgets/app_snackbar.dart';
import 'package:schedule_plan/core/widgets/confirm_dialog.dart';
import 'package:schedule_plan/core/widgets/settings_tile.dart';
import 'package:schedule_plan/data/models/attendance.dart';
import 'package:schedule_plan/data/repositories/maintenance_repository.dart';
import 'package:schedule_plan/data/services/cleanup_service.dart';
import 'package:schedule_plan/data/services/holiday_sync_service.dart';
import 'package:schedule_plan/data/services/notification_service.dart';
import 'package:schedule_plan/data/services/reminder_scheduler.dart';
import 'package:schedule_plan/data/settings_state.dart';
import 'package:schedule_plan/features/attendance/attendance_status_strip.dart';

/// 系统设置页（第 22 轮由设置第一页拆出）。
///
/// 用户规格：设置第一页只留「课表与名单 / 系统设置 / 显示与语言 / 关于」，
/// 原来平铺在第一页的**教学参数、权限、数据维护**三块整体搬到这里，
/// 页内按「调休 / 通知权限 / 清空数据」重新分组。
///
/// 分组顺序严格照规格：
/// 未记录日期的默认状态 → 调休 → 通知权限 → 时间列级联更新 → 清空数据。
class SystemSettingsPage extends StatefulWidget {
  const SystemSettingsPage({super.key});

  @override
  State<SystemSettingsPage> createState() => _SystemSettingsPageState();
}

class _SystemSettingsPageState extends State<SystemSettingsPage> {
  bool _permissionGranted = false;
  bool _checking = true;

  /// 节假日数据的覆盖年份与上次检查时间（"节假日数据"那行的副标题）。
  Set<int> _holidayYears = const <int>{};
  DateTime? _holidayCheckedAt;

  /// 正在手动更新节假日数据（防止连点）。
  bool _syncingHolidays = false;

  @override
  void initState() {
    super.initState();
    _checkPermission();
    _loadHolidayInfo();
  }

  Future<void> _checkPermission() async {
    // 通知插件在桌面 / 测试环境里可能整个不可用（初始化会抛异常）。读不到权限
    // 只能当作"没授权"继续画页面，绝不能让这一页卡在 loading 上。
    var granted = false;
    try {
      granted = await context.read<NotificationService>().checkPermission();
    } catch (error, stack) {
      AppLogger.e('读取通知权限失败', error: error, stack: stack);
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _permissionGranted = granted;
      _checking = false;
    });
  }

  Future<void> _requestPermission() async {
    final l10n = context.l10n;
    final granted =
        await context.read<NotificationService>().requestPermission();
    if (!mounted) {
      return;
    }
    setState(() => _permissionGranted = granted);
    if (!granted) {
      // 权限被拒绝时引导跳转系统设置页，而不是仅文字提示
      await context.read<NotificationService>().openSystemSettings();
      return;
    }
    showAppSnackBar(context, l10n.notificationGranted);
  }

  Future<void> _rebuildReminders() async {
    final l10n = context.l10n;
    final settings = context.read<SettingsState>();
    final count = await context
        .read<ReminderScheduler>()
        .refreshAll(minutesBefore: settings.reminderMinutesBefore);
    if (!mounted) {
      return;
    }
    showAppSnackBar(context, l10n.reminderRegenerated(count));
  }

  Future<void> _cleanupNow() async {
    final l10n = context.l10n;
    final result = await context.read<CleanupService>().run();
    if (!mounted) {
      return;
    }
    showAppSnackBar(
      context,
      result.abortedBecauseBackupFailed
          ? l10n.cleanupAborted
          : l10n.cleanupResult(
              result.deletedAttendance,
              result.deletedImportLogs,
            ),
      long: true,
    );
  }

  Future<void> _clearAll() async {
    final l10n = context.l10n;
    final confirmed = await showAppConfirm(
      context: context,
      title: l10n.clearAllData,
      body: l10n.clearAllDataConfirm,
      danger: true,
    );
    if (!confirmed) {
      return;
    }
    try {
      await MaintenanceRepository().clearAllData();
      if (!mounted) {
        return;
      }
      showAppSnackBar(context, l10n.clearAllData);
    } catch (error, stack) {
      AppLogger.e('清空数据失败', error: error, stack: stack);
      if (!mounted) {
        return;
      }
      showAppSnackBar(context, l10n.operationFailed('$error'));
    }
  }

  /// 读一次节假日数据的覆盖年份与上次检查时间。
  Future<void> _loadHolidayInfo() async {
    try {
      final sync = context.read<HolidaySyncService>();
      final years = await sync.coveredYears();
      final checked = await sync.lastCheckedAt();
      if (!mounted) {
        return;
      }
      setState(() {
        _holidayYears = years;
        _holidayCheckedAt = checked;
      });
    } catch (error, stack) {
      AppLogger.e('读取节假日数据状态失败', error: error, stack: stack);
    }
  }

  /// 手动更新节假日数据：跳过自动节流，把今年 + 明年整份重取一遍。
  Future<void> _syncHolidays() async {
    if (_syncingHolidays) {
      return;
    }
    final l10n = context.l10n;
    final sync = context.read<HolidaySyncService>();
    setState(() => _syncingHolidays = true);

    HolidaySyncResult? result;
    try {
      result = await sync.refresh(force: true);
    } catch (error, stack) {
      AppLogger.e('手动更新节假日数据失败', error: error, stack: stack);
    }
    if (!mounted) {
      return;
    }
    setState(() => _syncingHolidays = false);
    await _loadHolidayInfo();
    if (!mounted) {
      return;
    }
    final years = (result?.years.toList() ?? <int>[])..sort();
    final span = years.join('、');
    final message = result == null
        ? l10n.holidaySyncFailed
        : switch (result.status) {
            HolidaySyncStatus.updated => l10n.holidaySyncUpdated(span),
            HolidaySyncStatus.notPublished => l10n.holidaySyncNotPublished(span),
            HolidaySyncStatus.disabled => l10n.holidaySyncDisabled,
            HolidaySyncStatus.failed => l10n.holidaySyncFailed,
            HolidaySyncStatus.skipped => l10n.holidaySyncUpToDate,
          };
    showAppSnackBar(context, message, long: true);
  }

  /// 「节假日数据」那行的副标题：覆盖到哪几年 + 上次什么时候检查的。
  String _holidayDataSummary() {
    final l10n = context.l10n;
    final years = _holidayYears.toList()..sort();
    if (years.isEmpty) {
      return l10n.holidayDataUnknown;
    }
    final span =
        years.length == 1 ? '${years.first}' : '${years.first}-${years.last}';
    final checked = _holidayCheckedAt;
    if (checked == null) {
      return l10n.holidayDataSummary(span);
    }
    return l10n.holidayDataSummaryChecked(
      span,
      app_dates.DateUtils.formatDate(checked),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final settings = context.watch<SettingsState>();

    return Scaffold(
      appBar: AppBar(title: Text(l10n.groupSystem)),
      body: ListView(
        padding: const EdgeInsets.only(
          top: AppConstants.spaceS,
          bottom: AppConstants.spaceXl,
        ),
        children: <Widget>[
          // ---------------- 未记录日期的默认状态（无组标题，单行） ----------------
          SettingsGroup(
            children: <Widget>[
              SettingsTile(
                icon: Icons.how_to_reg_outlined,
                title: l10n.defaultAttendanceStatus,
                subtitle: _statusLabel(settings.defaultAttendanceStatus),
                showChevron: false,
                trailing: DropdownButton<AttendanceStatus>(
                  value: settings.defaultAttendanceStatus,
                  underline: const SizedBox.shrink(),
                  items: <DropdownMenuItem<AttendanceStatus>>[
                    // 默认状态只可能是「日常状态」（含"未标记"）：
                    // 休学 / 免修是逐生逐课手工点的长期状态，
                    // 把它设成全班默认显然不是老师的本意。
                    for (final status in _defaultStatusChoices)
                      DropdownMenuItem<AttendanceStatus>(
                        value: status,
                        child: Text(_statusLabel(status)),
                      ),
                  ],
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    settings.update(
                      SettingKeys.defaultAttendanceStatus,
                      value.storageKey,
                    );
                  },
                ),
              ),
            ],
          ),

          // ---------------- 调休 ----------------
          GroupHeader(
            title: l10n.groupHoliday,
            icon: Icons.beach_access_outlined,
          ),
          SettingsGroup(
            children: <Widget>[
              // 这个开关决定"节假日算不算进课表"，下面两行负责
              // "数据本身别过期"——内置表只抄到发过通知的年份，
              // 跨年之后就得靠联网把新一年的安排取回来。
              SettingsTile(
                icon: Icons.beach_access_outlined,
                title: l10n.holidayAwareSwitch,
                subtitle: l10n.holidayAwareDesc,
                showChevron: false,
                trailing: Switch(
                  value: settings.holidayAwareEnabled,
                  onChanged: (value) => settings.update(
                    SettingKeys.holidayAwareEnabled,
                    value ? '1' : '0',
                  ),
                ),
              ),
              SettingsTile(
                icon: Icons.cloud_sync_outlined,
                title: l10n.holidayRemoteSwitch,
                subtitle: l10n.holidayRemoteDesc,
                showChevron: false,
                trailing: Switch(
                  value: settings.holidayRemoteEnabled,
                  onChanged: (value) => settings.update(
                    SettingKeys.holidayRemoteEnabled,
                    value ? '1' : '0',
                  ),
                ),
              ),
              SettingsTile(
                icon: Icons.event_available_outlined,
                title: l10n.holidayDataTitle,
                subtitle: _holidayDataSummary(),
                showChevron: false,
                onTap: _syncingHolidays ? null : _syncHolidays,
                trailing: _syncingHolidays
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : TextButton(
                        onPressed: _syncHolidays,
                        child: Text(l10n.holidaySyncNow),
                      ),
              ),
            ],
          ),

          // ---------------- 通知权限 ----------------
          GroupHeader(
            title: l10n.groupPermission,
            icon: Icons.notifications_outlined,
          ),
          SettingsGroup(
            children: <Widget>[
              SettingsTile(
                icon: Icons.notifications_active_outlined,
                title: l10n.notificationPermission,
                subtitle: _checking
                    ? l10n.loading
                    : (_permissionGranted
                        ? l10n.notificationGranted
                        : l10n.notificationDenied),
                showChevron: false,
                gradient: const <Color>[Color(0xFFF06292), Color(0xFFC8377B)],
                trailing: Switch(
                  value: _permissionGranted,
                  onChanged: (_) => _requestPermission(),
                ),
              ),
              SettingsTile(
                icon: Icons.settings_suggest_outlined,
                title: l10n.notificationOpenSettings,
                subtitle: l10n.notificationCheck,
                showChevron: true,
                onTap: () =>
                    context.read<NotificationService>().openSystemSettings(),
              ),
              _ReminderSlider(
                label: l10n.reminderMinutesBefore,
                value: settings.reminderMinutesBefore,
                onChanged: (value) => settings.update(
                  SettingKeys.reminderMinutesBefore,
                  value.toString(),
                ),
              ),
              SettingsTile(
                icon: Icons.refresh,
                title: l10n.reminderRegenerate,
                subtitle: l10n.lessonReminder,
                onTap: _rebuildReminders,
              ),
            ],
          ),

          // ---------------- 时间列级联更新（无组标题，单行） ----------------
          SettingsGroup(
            children: <Widget>[
              SettingsTile(
                icon: Icons.linear_scale_outlined,
                title: l10n.cascadeSwitch,
                subtitle: l10n.editPeriodTimeDesc,
                showChevron: false,
                trailing: Switch(
                  value: settings.cascadeUpdateEnabled,
                  onChanged: (value) => settings.update(
                    SettingKeys.cascadeUpdateEnabled,
                    value ? '1' : '0',
                  ),
                ),
              ),
            ],
          ),

          // ---------------- 清空数据 ----------------
          GroupHeader(
            title: l10n.groupClearData,
            icon: Icons.storage_outlined,
          ),
          SettingsGroup(
            children: <Widget>[
              SettingsTile(
                icon: Icons.cleaning_services_outlined,
                title: l10n.cleanupNow,
                subtitle: l10n.retentionDays,
                onTap: _cleanupNow,
              ),
              SettingsTile(
                icon: Icons.delete_forever_outlined,
                title: l10n.clearAllData,
                subtitle: l10n.clearAllDataConfirm,
                danger: true,
                onTap: _clearAll,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 「默认考勤状态」下拉的可选项：日常五态 + 未标记。
  static const List<AttendanceStatus> _defaultStatusChoices =
      <AttendanceStatus>[
    ...AttendanceStatus.dailyChoices,
    AttendanceStatus.unmarked,
  ];

  /// 状态文案统一走 `statusLabelOf`（与考勤页 / 统计页同一份映射）。
  String _statusLabel(AttendanceStatus status) => statusLabelOf(context, status);
}

/// 课前提醒提前量滑块。
class _ReminderSlider extends StatelessWidget {
  const _ReminderSlider({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final safe = value.clamp(
      AppConstants.reminderMinutesMin,
      AppConstants.reminderMinutesMax,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.spaceL,
        AppConstants.spaceM,
        AppConstants.spaceL,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppConstants.spaceM,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer.withValues(alpha: 0.75),
                  borderRadius: AppRadii.stadiumAll,
                ),
                child: Text(
                  '$safe${context.l10n.unitMinutes}',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onPrimaryContainer,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          Slider(
            value: safe.toDouble(),
            min: AppConstants.reminderMinutesMin.toDouble(),
            max: AppConstants.reminderMinutesMax.toDouble(),
            divisions:
                AppConstants.reminderMinutesMax - AppConstants.reminderMinutesMin,
            label: '$safe',
            onChanged: (next) => onChanged(next.round()),
          ),
        ],
      ),
    );
  }
}
