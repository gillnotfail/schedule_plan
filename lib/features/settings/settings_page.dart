import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import 'package:schedule_plan/core/constants/app_constants.dart';
import 'package:schedule_plan/core/i18n/locale_controller.dart';
import 'package:schedule_plan/core/l10n/l10n_extensions.dart';
import 'package:schedule_plan/core/logging/app_logger.dart';
import 'package:schedule_plan/core/theme/app_colors.dart';
import 'package:schedule_plan/core/theme/app_motion.dart';
import 'package:schedule_plan/core/theme/app_page_route.dart';
import 'package:schedule_plan/core/theme/theme_controller.dart';
import 'package:schedule_plan/core/widgets/app_card.dart';
import 'package:schedule_plan/core/widgets/settings_tile.dart';
import 'package:schedule_plan/data/repositories/class_repository.dart';
import 'package:schedule_plan/data/repositories/student_repository.dart';
import 'package:schedule_plan/data/services/update_service.dart';
import 'package:schedule_plan/features/management/class_list_page.dart';
import 'package:schedule_plan/features/management/course_list_page.dart';
import 'package:schedule_plan/features/management/student_import_page.dart';
import 'package:schedule_plan/features/management/student_list_page.dart';
import 'package:schedule_plan/features/settings/system_settings_page.dart';
import 'package:schedule_plan/features/settings/update_page.dart';

/// 设置页（模块七 + 用户规格）。
///
/// 用户规格（第 22 轮重排）：第一页**只有四块**，干净、简练、一眼看完——
/// 1. 课表与名单：学生名单 / Excel 批量导入学生名单 / 班级管理 / 课程管理；
/// 2. 系统设置：**一条入口**，点进 [SystemSettingsPage]（考勤默认状态、调休、
///    通知权限、时间列级联更新、清空数据都在那一页里）；
/// 3. 显示与语言：主题 / 语言；
/// 4. 关于：全面课表计划 / 检查更新 / 更新说明 / 开发者。
///
/// 原来摆在最上面那张**彩色标题卡挪到页面最底部**：进门先看到基础设置，
/// 品牌信息放在末尾收尾。拍照生成课表（课表页已有）与统计设置（挪进工具箱
/// 的统计卡片）两条入口已从本页删除。
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String _version = AppConstants.fallbackVersionLabel;

  /// 学生 / 班级规模，用于名单入口右侧的胶囊标签。
  int _studentCount = 0;
  int _classCount = 0;

  @override
  void initState() {
    super.initState();
    _loadVersion();
    _loadRosterCounts();
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
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppConstants.spaceXl),
        children: <Widget>[
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
              // 第 22 轮把「学生名单」提到第一位：老师进设置页多半是想看名单，
              // 导入是低频动作，排在后面。
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
            ],
          ),

          // ---------------- 系统设置（一条入口） ----------------
          SettingsGroup(
            children: <Widget>[
              SettingsTile(
                icon: Icons.tune_rounded,
                title: l10n.groupSystem,
                subtitle: l10n.systemSettingsDesc,
                gradient: const <Color>[Color(0xFF90A4AE), Color(0xFF546E7A)],
                onTap: () => pushAppPage(context, const SystemSettingsPage()),
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
            ],
          ),

          // ---------------- 品牌标题卡（第 22 轮挪到最底部） ----------------
          _buildHeader(scheme, theme),
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
        AppConstants.spaceXl,
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
