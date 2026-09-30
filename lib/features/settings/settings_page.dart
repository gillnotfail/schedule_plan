import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import 'package:schedule_plan/core/constants/app_constants.dart';
import 'package:schedule_plan/core/constants/setting_keys.dart';
import 'package:schedule_plan/core/i18n/locale_controller.dart';
import 'package:schedule_plan/core/l10n/l10n_extensions.dart';
import 'package:schedule_plan/core/logging/app_logger.dart';
import 'package:schedule_plan/core/theme/app_colors.dart';
import 'package:schedule_plan/core/theme/app_motion.dart';
import 'package:schedule_plan/core/theme/app_page_route.dart';
import 'package:schedule_plan/core/theme/theme_controller.dart';
import 'package:schedule_plan/core/utils/date_utils.dart' as app_dates;
import 'package:schedule_plan/core/widgets/app_card.dart';
import 'package:schedule_plan/core/widgets/app_snackbar.dart';
import 'package:schedule_plan/core/widgets/confirm_dialog.dart';
import 'package:schedule_plan/core/widgets/settings_tile.dart';
import 'package:schedule_plan/data/models/attendance.dart';
import 'package:schedule_plan/data/repositories/class_repository.dart';
import 'package:schedule_plan/data/repositories/maintenance_repository.dart';
import 'package:schedule_plan/data/repositories/student_repository.dart';
import 'package:schedule_plan/data/services/cleanup_service.dart';
import 'package:schedule_plan/data/services/holiday_sync_service.dart';
import 'package:schedule_plan/data/services/notification_service.dart';
import 'package:schedule_plan/data/services/reminder_scheduler.dart';
import 'package:schedule_plan/data/services/update_service.dart';
import 'package:schedule_plan/data/settings_state.dart';
import 'package:schedule_plan/features/management/class_list_page.dart';
import 'package:schedule_plan/features/management/course_list_page.dart';
import 'package:schedule_plan/features/management/course_ocr_page.dart';
import 'package:schedule_plan/features/management/student_import_page.dart';
import 'package:schedule_plan/features/attendance/attendance_status_strip.dart';
import 'package:schedule_plan/features/management/student_list_page.dart';
import 'package:schedule_plan/features/settings/statistics_settings_page.dart';
import 'package:schedule_plan/features/settings/update_page.dart';

/// 设置页（模块七 + 用户规格）。
///
/// 只承载 **App 级设置**：课表与名单、教学参数、权限、显示与语言、
/// 智能能力、数据维护、关于。统计口径相关的配置已迁到
/// [StatisticsSettingsPage]，不再混在这里。
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _permissionGranted = false;
  bool _checking = true;
  String _version = AppConstants.fallbackVersionLabel;

  /// 学生 / 班级规模，用于名单入口右侧的胶囊标签。
  int _studentCount = 0;
  int _classCount = 0;

  /// 节假日数据的覆盖年份与上次检查时间（"数据维护"那行的副标题）。
  Set<int> _holidayYears = const <int>{};
  DateTime? _holidayCheckedAt;

  /// 正在手动更新节假日数据（防止连点）。
  bool _syncingHolidays = false;

  @override
  void initState() {
    super.initState();
    _checkPermission();
    _loadVersion();
    _loadRosterCounts();
    _loadHolidayInfo();
  }

  Future<void> _loadRosterCounts() async {
    try {
      final classRepo = context.read<ClassRepository>();
      final studentRepo = context.read<StudentRepository>();
      final classes = await classRepo.listClasses();
      final all = await studentRepo.listAll();
      if (!mounted) {
        return;
      }
      setState(() {
        _classCount = classes.length;
        _studentCount = all.length;
      });
    } catch (error, stack) {
      AppLogger.e('读取名单规模失败', error: error, stack: stack);
    }
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) {
        return;
      }
      setState(() {
        _version = info.buildNumber.isEmpty
            ? info.version
            : '${info.version}+${info.buildNumber}';
      });
    } catch (error) {
      // 桌面/测试环境下平台通道不可用，保留兜底版本号即可，不需要上报堆栈
      AppLogger.d('读取版本号失败，使用兜底值：$error');
    }
  }

  Future<void> _checkPermission() async {
    final granted = await context.read<NotificationService>().checkPermission();
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

  /// 「数据维护」那行的副标题：覆盖到哪几年 + 上次什么时候检查的。
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

  /// 「检查更新」入口。
  ///
  /// 有新版时把**入口本身**变成提示（换副文案 + 挂一个小圆点），
  /// 而不是在启动时弹窗打断——老师打开 App 通常是为了看课表，
  /// 不该被一个更新弹窗挡在门口。自动检查的结论就靠这里露出水面。
  Widget _buildUpdateTile(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final state = context.watch<UpdateService>().state;
    final latest = state.plan?.latest;
    final hasUpdate = state.phase == UpdatePhase.available && latest != null;

    return SettingsTile(
      icon: Icons.system_update_alt_rounded,
      title: l10n.updateTitle,
      subtitle: hasUpdate
          ? l10n.updateSettingsSubtitleAvailable(latest.versionName)
          : l10n.updateSettingsSubtitle(_version.isEmpty ? '—' : 'v$_version'),
      onTap: () => pushAppPage(context, const UpdatePage()),
      trailing: hasUpdate
          ? Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: scheme.primary,
                shape: BoxShape.circle,
              ),
            )
          : null,
    );
  }

  void _showChangelog() {
    final l10n = context.l10n;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: AppRadii.dialogAll),
        title: Text(l10n.aboutChangelog),
        content: Text(l10n.aboutChangelogBody),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.close),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = context.watch<ThemeController>();
    final localeController = context.watch<LocaleController>();
    final settings = context.watch<SettingsState>();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppConstants.spaceXl),
        children: <Widget>[
          _buildHeader(scheme, theme),

          // ---------------- 课表与名单 ----------------
          GroupHeader(
            title: l10n.groupScheduleData,
            icon: Icons.calendar_month_outlined,
          ),
          SettingsGroup(
            children: <Widget>[
              // 作息模板不在这里：用户规格要求撤掉这一项
              // （"课表页已经有一键生成和单独定制了，这个功能多余"），
              // 入口挪到课表页的「课表设置」半屏弹层里。
              // 名单相关的四步按「实际使用顺序」排：先导入 → 看名单 →
              // 班级是按名单归集的 → 最后才谈得上给这些班排课
              SettingsTile(
                icon: Icons.upload_file_outlined,
                title: l10n.importStudents,
                subtitle: l10n.importFormatLine4,
                gradient: const <Color>[Color(0xFF81C784), Color(0xFF2E7D32)],
                onTap: () async {
                  await pushAppPage(context, const StudentImportPage());
                  if (context.mounted) {
                    _loadRosterCounts();
                  }
                },
              ),
              // 拍照识别课表（第 11 轮）：本机离线 OCR，不接任何 AI / LLM 服务商。
              // 放在「导入名单」旁边，因为两者都是"把已有资料搬进来"的入口。
              SettingsTile(
                icon: Icons.document_scanner_outlined,
                title: l10n.ocrEntryTitle,
                subtitle: l10n.ocrEntryDesc,
                gradient: const <Color>[Color(0xFF4FC3B0), Color(0xFF00897B)],
                onTap: () async {
                  await pushAppPage(context, const CourseOcrPage());
                  if (context.mounted) {
                    _loadRosterCounts();
                  }
                },
              ),
              SettingsTile(
                icon: Icons.groups_outlined,
                title: l10n.studentRoster,
                subtitle: l10n.studentRosterDesc,
                trailing: _rosterBadge(scheme),
                gradient: const <Color>[Color(0xFF4FA8F5), Color(0xFF2A6FD9)],
                onTap: () async {
                  await pushAppPage(context, const StudentListPage());
                  if (context.mounted) {
                    _loadRosterCounts();
                  }
                },
              ),
              SettingsTile(
                icon: Icons.school_outlined,
                title: l10n.classManagement,
                subtitle: l10n.classManagementDesc,
                gradient: const <Color>[Color(0xFFB48CF0), Color(0xFF7A5CA8)],
                onTap: () async {
                  await pushAppPage(context, const ClassListPage());
                  if (context.mounted) {
                    _loadRosterCounts();
                  }
                },
              ),
              SettingsTile(
                icon: Icons.menu_book_outlined,
                title: l10n.courseManagement,
                subtitle: l10n.courseManagementDesc,
                gradient: const <Color>[Color(0xFFFFA94D), Color(0xFFE8710A)],
                onTap: () => pushAppPage(context, const CourseListPage()),
              ),
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
              // 节假日 / 调休（第 13 轮）：紧挨着级联开关，因为两者都是
              // "课表怎么算"的口径开关，放在一组里老师才找得到。
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
              // 上面那个开关决定"节假日算不算进课表"，下面这两行负责
              // "数据本身别过期"——内置表只抄到发过通知的年份，
              // 跨年之后就得靠联网把新一年的安排取回来。
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

          // ---------------- 教学参数 ----------------
          GroupHeader(
            title: l10n.groupTeaching,
            icon: Icons.rule_outlined,
          ),
          SettingsGroup(
            children: <Widget>[
              SettingsTile(
                icon: Icons.insights_outlined,
                title: l10n.statisticsSettings,
                subtitle: l10n.statisticsSettingsDesc,
                gradient: const <Color>[Color(0xFF64B5F6), Color(0xFF0E8AA8)],
                onTap: () =>
                    pushAppPage(context, const StatisticsSettingsPage()),
              ),
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

          // ---------------- 权限 ----------------
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

          // ---------------- 显示与语言 ----------------
          GroupHeader(
            title: l10n.groupDisplay,
            icon: Icons.palette_outlined,
          ),
          SettingsGroup(
            dividerIndent: AppConstants.spaceXl,
            children: <Widget>[
              _buildThemeRow(theme),
              _buildLanguageRow(localeController),
            ],
          ),

          // ---------------- 数据维护 ----------------
          GroupHeader(
            title: l10n.groupData,
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

          // ---------------- 关于 ----------------
          GroupHeader(title: l10n.groupAbout, icon: Icons.info_outline),
          SettingsGroup(
            children: <Widget>[
              SettingsTile(
                icon: Icons.apps_outlined,
                title: l10n.aboutAppName,
                subtitle: '${l10n.aboutVersion} $_version',
                showChevron: false,
                trailing: Text(
                  'v$_version',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ),
              _buildUpdateTile(context),
              SettingsTile(
                icon: Icons.new_releases_outlined,
                title: l10n.aboutChangelog,
                subtitle: l10n.aboutChangelogBody,
                onTap: _showChangelog,
              ),
              SettingsTile(
                icon: Icons.person_outline,
                title: l10n.aboutDeveloper,
                subtitle: l10n.aboutDeveloperName,
                showChevron: false,
                trailing: Text(
                  l10n.aboutDeveloperName,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ),
              SettingsTile(
                icon: Icons.code_outlined,
                title: l10n.aboutTechStack,
                subtitle: 'Flutter · sqflite · Material 3',
                showChevron: false,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(ColorScheme scheme, ThemeController theme) {
    final l10n = context.l10n;
    final tokens = theme.tokens;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.spaceL,
        AppConstants.spaceL,
        AppConstants.spaceL,
        0,
      ),
      child: AppCard(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: tokens.accentGradient,
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.22),
                borderRadius: AppRadii.innerAll,
              ),
              child: const Icon(
                Icons.school_rounded,
                color: Colors.white,
                size: 26,
              ),
            ),
            const SizedBox(width: AppConstants.spaceL),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    l10n.aboutAppName,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${l10n.settingsSubtitle} · v$_version',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.88),
                        ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.verified_outlined,
              color: Colors.white.withValues(alpha: 0.85),
              size: 18,
            ),
          ],
        ),
      ),
    );
  }

  /// 名单规模胶囊：一眼看清「几个班 / 多少人」，不用点进去才知道。
  Widget _rosterBadge(ColorScheme scheme) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.spaceS + 2,
            vertical: 2,
          ),
          decoration: BoxDecoration(
            color: scheme.secondaryContainer.withValues(alpha: 0.8),
            borderRadius: AppRadii.stadiumAll,
          ),
          child: Text(
            '$_classCount · $_studentCount',
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSecondaryContainer,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // 主题：一横列色块，点一下就换，不需要滚动很多
  // ---------------------------------------------------------------------------
  Widget _buildThemeRow(ThemeController theme) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.spaceM,
        AppConstants.spaceM,
        AppConstants.spaceM,
        AppConstants.spaceM,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                Icons.color_lens_outlined,
                size: 17,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                l10n.theme,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
          const SizedBox(height: AppConstants.spaceM),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: <Widget>[
                for (final kind in AppThemeKind.values)
                  Padding(
                    padding: const EdgeInsets.only(right: AppConstants.spaceM),
                    child: _ThemeSwatch(
                      kind: kind,
                      selected: theme.kind == kind,
                      label: _themeLabel(kind),
                      onTap: () => theme.setKind(kind),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLanguageRow(LocaleController controller) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.spaceM,
        0,
        AppConstants.spaceM,
        AppConstants.spaceM,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                Icons.translate_outlined,
                size: 17,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                l10n.language,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
          const SizedBox(height: AppConstants.spaceM),
          SegmentedButton<String>(
            segments: <ButtonSegment<String>>[
              ButtonSegment<String>(
                value: 'zh',
                label: Text(l10n.languageZh),
              ),
              ButtonSegment<String>(
                value: 'en',
                label: Text(l10n.languageEn),
              ),
            ],
            selected: <String>{controller.locale.languageCode},
            onSelectionChanged: (selection) {
              AppMotion.select();
              controller.setLocale(Locale(selection.first));
            },
          ),
        ],
      ),
    );
  }

  String _themeLabel(AppThemeKind kind) {
    final l10n = context.l10n;
    return switch (kind) {
      AppThemeKind.mint => l10n.themeMint,
      AppThemeKind.sunrise => l10n.themeSunrise,
      AppThemeKind.minimalGray => l10n.themeMinimalGray,
      AppThemeKind.oceanBlue => l10n.themeOceanBlue,
      AppThemeKind.sakura => l10n.themeSakura,
      AppThemeKind.nightCare => l10n.themeNightCare,
    };
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

/// 主题色卡：色轮 + 名称，选中时描边并加对勾。
class _ThemeSwatch extends StatelessWidget {
  const _ThemeSwatch({
    required this.kind,
    required this.selected,
    required this.label,
    required this.onTap,
  });

  final AppThemeKind kind;
  final bool selected;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppColorTokens.of(kind);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return GestureDetector(
      onTap: () {
        AppMotion.select();
        onTap();
      },
      child: Column(
        children: <Widget>[
          AnimatedContainer(
            duration: AppMotion.standard,
            curve: AppMotion.expressive,
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: tokens.accentGradient,
              ),
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? scheme.primary : Colors.transparent,
                width: 2.5,
              ),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: tokens.accentGradient.last.withValues(alpha: 0.35),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                  spreadRadius: -4,
                ),
              ],
            ),
            child: selected
                ? const Icon(Icons.check, color: Colors.white, size: 20)
                : null,
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: 58,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                color: selected ? scheme.primary : scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
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
