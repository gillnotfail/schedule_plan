import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:schedule_plan/core/constants/app_constants.dart';
import 'package:schedule_plan/core/l10n/l10n_extensions.dart';
import 'package:schedule_plan/core/logging/app_logger.dart';
import 'package:schedule_plan/core/utils/date_utils.dart' as app_dates;
import 'package:schedule_plan/core/utils/file_naming.dart';
import 'package:schedule_plan/core/widgets/app_snackbar.dart';
import 'package:schedule_plan/core/widgets/confirm_dialog.dart';
import 'package:schedule_plan/core/widgets/settings_tile.dart';
import 'package:schedule_plan/data/services/backup_service.dart';
import 'package:schedule_plan/data/services/share_service.dart';

/// 数据备份 / 恢复页（用户规格第 36 轮）。
///
/// 用户原话：重装一次数据就没了，所以得能自己把东西存出来。
/// 因此这一页只做两件事，其余全部删掉：
/// 1. **备份**：按条目勾选（学生、班级、课程、课表、考勤、标签、偏好），
///    默认全选，点一下存成 `.json` 文件；
/// 2. **恢复**：挑一个之前存出来的文件，看清里面是什么再盖回去。
///
/// 两处刻意的设计：
/// - 勾了「考勤记录」会把学生、课程、课表**一起勾上**（[BackupService.resolve]），
///   否则恢复时外键过不去、整份文件被挡回来。这些行标成「已包含」而不是灰掉消失，
///   让老师知道"我备份的东西比我想的多"，不至于以为被偷偷塞了内容。
/// - 备份文件**先写应用内一份**再弹系统保存对话框。对话框在某些机型上会失败或被
///   取消，应用内那份至少还在，SnackBar 上给一个「分享」把文件发到微信/网盘。
class BackupPage extends StatefulWidget {
  const BackupPage({super.key, this.service});

  /// 测试注入：落盘与选文件都要走平台通道，widget 测试里换成替身。
  final BackupService? service;

  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  late final BackupService _service;

  /// 用户直接勾的条目（依赖自动补齐在 [BackupService.resolve] 里做）。
  final Set<BackupSlice> _selected = <BackupSlice>{...BackupSlice.values};

  Map<BackupSlice, int> _counts = <BackupSlice, int>{};

  /// 备份 / 恢复进行中：所有入口一起禁用，避免连点生成两份文件。
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? context.read<BackupService>();
    _load();
  }

  Future<void> _load() async {
    try {
      final counts = await _service.countRows();
      if (!mounted) {
        return;
      }
      setState(() => _counts = counts);
    } catch (error, stack) {
      AppLogger.e('读取各条目数据量失败', error: error, stack: stack);
    }
  }

  // ---------------------------------------------------------------------------
  // 备份
  // ---------------------------------------------------------------------------

  Future<void> _backup() async {
    final l10n = context.l10n;
    final slices = _service.resolve(_selected);
    setState(() => _busy = true);
    try {
      final bundle = await _service.collect(
        slices,
        appVersion: await _service.appVersion(),
      );
      // 判空看的是**条目主表**的行数，不是 bundle.totalRows：
      // 新装的库里作息模板自带 50 行，按总行数判会永远"有数据"，
      // 于是空库也能导出一份只有出厂作息的文件。
      final hasData = slices.any((slice) => (_counts[slice] ?? 0) > 0);
      if (!hasData) {
        if (!mounted) {
          return;
        }
        showAppSnackBar(context, l10n.backupNoData, long: true);
        return;
      }
      final content = _service.encode(bundle);
      final subject = _subjectOf(slices);
      final localPath = await _service.saveLocal(content, subject: subject);
      final uri = await _service.saveToDevice(
        fileName: buildExportFileName(
          kind: '数据备份',
          subject: subject,
          extension: 'json',
        ),
        bytes: Uint8List.fromList(utf8.encode(content)),
        dialogTitle: l10n.backupSaveDialogTitle,
      );
      if (!mounted) {
        return;
      }
      if (uri == null) {
        // 用户取消了系统对话框：文件还在应用内，给一条"分享出去"的出路
        showAppSnackBar(
          context,
          l10n.backupSavedInApp,
          long: true,
          onRetry: () => ShareService.shareFile(
            path: localPath,
            subject: l10n.backupTitle,
          ),
          retryLabel: l10n.backupShare,
        );
        return;
      }
      showAppSnackBar(context, l10n.backupSaved, long: true);
    } catch (error, stack) {
      AppLogger.e('备份失败', error: error, stack: stack);
      if (!mounted) {
        return;
      }
      showAppSnackBar(context, l10n.backupFailed('$error'), long: true);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  /// 文件名中间那段"给谁导的"：全选叫「全部数据」，只选几项就拼条目名。
  String _subjectOf(List<BackupSlice> slices) {
    final l10n = context.l10n;
    if (slices.length == BackupSlice.values.length) {
      return l10n.backupSubjectAll;
    }
    if (slices.length <= 2) {
      return slices.map(_sliceTitle).join('+');
    }
    // 三项以上用「名单等多项」，否则文件名会长到看不见时间
    return l10n.backupSubjectMixed(slices.length);
  }

  // ---------------------------------------------------------------------------
  // 恢复
  // ---------------------------------------------------------------------------

  Future<void> _restore() async {
    final l10n = context.l10n;
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    String? raw;
    try {
      raw = await _service.pickBackupFile();
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
    if (!mounted || raw == null) {
      return;
    }

    BackupBundle bundle;
    try {
      bundle = _service.decode(raw);
    } on BackupFormatException catch (error) {
      showAppSnackBar(context, _problemText(error.problem), long: true);
      return;
    }

    if (bundle.totalRows == 0) {
      showAppSnackBar(context, l10n.backupRestoreEmpty, long: true);
      return;
    }

    final confirmed = await showAppConfirm(
      context: context,
      title: l10n.backupRestoreConfirmTitle,
      body: _restoreBody(bundle),
      confirmLabel: l10n.backupRestoreConfirmAction,
    );
    if (!confirmed || !mounted) {
      return;
    }

    setState(() => _busy = true);
    try {
      final report = await _service.restore(bundle);
      if (!mounted) {
        return;
      }
      showAppSnackBar(
        context,
        l10n.backupRestoreDone(report.totalRows),
        long: true,
      );
      // 恢复完计数会变，顺手刷新本页的"当前 N 条"
      await _load();
    } catch (error, stack) {
      AppLogger.e('恢复备份失败', error: error, stack: stack);
      if (!mounted) {
        return;
      }
      showAppSnackBar(context, l10n.backupRestoreFailed('$error'), long: true);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  String _restoreBody(BackupBundle bundle) {
    final l10n = context.l10n;
    final time = DateTime.fromMillisecondsSinceEpoch(
      bundle.createdAt.millisecondsSinceEpoch,
    );
    final body = l10n.backupRestoreConfirmBody(
      _formatDateTime(time),
      bundle.slices.isEmpty ? BackupSlice.values.length : bundle.slices.length,
      bundle.totalRows,
    );
    if (bundle.schemaVersion == 0 ||
        bundle.schemaVersion == _service.currentSchemaVersion) {
      return body;
    }
    return '$body\n\n${l10n.backupRestoreSchemaWarn(bundle.schemaVersion)}';
  }

  String _formatDateTime(DateTime time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '${app_dates.DateUtils.formatDate(time)} $hour:$minute';
  }

  String _problemText(BackupProblem problem) {
    final l10n = context.l10n;
    return switch (problem) {
      BackupProblem.notBackup => l10n.backupErrorNotBackup,
      BackupProblem.newerFormat => l10n.backupErrorNewer,
      BackupProblem.broken => l10n.backupErrorBroken,
    };
  }

  // ---------------------------------------------------------------------------
  // 条目文案
  // ---------------------------------------------------------------------------

  String _sliceTitle(BackupSlice slice) {
    final l10n = context.l10n;
    return switch (slice) {
      BackupSlice.students => l10n.backupSliceStudents,
      BackupSlice.classes => l10n.backupSliceClasses,
      BackupSlice.courses => l10n.backupSliceCourses,
      BackupSlice.timetable => l10n.backupSliceTimetable,
      BackupSlice.attendance => l10n.backupSliceAttendance,
      BackupSlice.tags => l10n.backupSliceTags,
      BackupSlice.settings => l10n.backupSliceSettings,
    };
  }

  String _sliceDesc(BackupSlice slice) {
    final l10n = context.l10n;
    return switch (slice) {
      BackupSlice.students => l10n.backupSliceStudentsDesc,
      BackupSlice.classes => l10n.backupSliceClassesDesc,
      BackupSlice.courses => l10n.backupSliceCoursesDesc,
      BackupSlice.timetable => l10n.backupSliceTimetableDesc,
      BackupSlice.attendance => l10n.backupSliceAttendanceDesc,
      BackupSlice.tags => l10n.backupSliceTagsDesc,
      BackupSlice.settings => l10n.backupSliceSettingsDesc,
    };
  }

  IconData _sliceIcon(BackupSlice slice) => switch (slice) {
        BackupSlice.students => Icons.groups_outlined,
        BackupSlice.classes => Icons.school_outlined,
        BackupSlice.courses => Icons.menu_book_outlined,
        BackupSlice.timetable => Icons.calendar_month_outlined,
        BackupSlice.attendance => Icons.how_to_reg_outlined,
        BackupSlice.tags => Icons.star_outline_rounded,
        BackupSlice.settings => Icons.tune_rounded,
      };

  // ---------------------------------------------------------------------------
  // 构建
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final resolved = _service.resolve(_selected).toSet();
    final allSelected = _selected.length == BackupSlice.values.length;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.backupTitle)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppConstants.spaceXl),
        children: <Widget>[
          _buildIntroCard(theme),

          GroupHeader(
            title: l10n.backupGroupPick,
            icon: Icons.checklist_rounded,
          ),
          SettingsGroup(
            children: <Widget>[
              _SliceRow(
                icon: Icons.done_all_rounded,
                title: l10n.backupSliceAll,
                subtitle: l10n.backupSliceAllDesc,
                checked: allSelected,
                tristate: !allSelected && _selected.isNotEmpty,
                indeterminate: !allSelected && _selected.isNotEmpty,
                onChanged: _busy
                    ? null
                    : (value) => setState(() {
                          _selected.clear();
                          if (value) {
                            _selected.addAll(BackupSlice.values);
                          }
                        }),
              ),
              for (final slice in BackupSlice.values)
                _SliceRow(
                  icon: _sliceIcon(slice),
                  title: _sliceTitle(slice),
                  subtitle: _sliceDesc(slice),
                  count: _counts[slice] ?? 0,
                  checked: resolved.contains(slice),
                  // 只有"在结果里、但不是自己勾的"才算被依赖带上。
                  // 少判 resolved 这一半，清空全选之后每一行都会被当成"已包含"
                  // 而变成点不动 —— 用户就再也勾不回来了。
                  implied:
                      resolved.contains(slice) && !_selected.contains(slice),
                  onChanged: _busy
                      ? null
                      : (value) => setState(() {
                            if (value) {
                              _selected.add(slice);
                            } else {
                              _selected.remove(slice);
                            }
                          }),
                ),
            ],
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppConstants.spaceL,
              AppConstants.spaceL,
              AppConstants.spaceL,
              0,
            ),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _busy || _selected.isEmpty ? null : _backup,
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_alt_rounded, size: 20),
                label: Text(_busy ? l10n.backupActionBusy : l10n.backupAction),
              ),
            ),
          ),

          GroupHeader(
            title: l10n.backupGroupRestore,
            icon: Icons.restore_rounded,
          ),
          SettingsGroup(
            children: <Widget>[
              SettingsTile(
                icon: Icons.folder_open_outlined,
                title: l10n.backupRestoreAction,
                subtitle: l10n.backupRestoreActionDesc,
                gradient: const <Color>[Color(0xFF90A4AE), Color(0xFF546E7A)],
                onTap: _busy ? null : _restore,
              ),
            ],
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppConstants.spaceXl,
              AppConstants.spaceL,
              AppConstants.spaceXl,
              0,
            ),
            child: Text(
              l10n.backupRestoreNote,
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIntroCard(ThemeData theme) {
    final l10n = context.l10n;
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.spaceL,
        AppConstants.spaceL,
        AppConstants.spaceL,
        0,
      ),
      child: Container(
        padding: const EdgeInsets.all(AppConstants.spaceL),
        decoration: BoxDecoration(
          color: scheme.primaryContainer.withValues(alpha: 0.45),
          borderRadius: AppRadii.squircelAll,
          border: Border.all(color: scheme.primary.withValues(alpha: 0.18)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(
              Icons.shield_outlined,
              size: 20,
              color: scheme.primary,
            ),
            const SizedBox(width: AppConstants.spaceM),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    l10n.backupIntroTitle,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    l10n.backupIntroBody,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 一个可勾选的备份条目。
///
/// [implied] = 这一项是**被依赖自动带上**的（不是用户直接勾的）：复选框照样
/// 显示为选中，但按不动——它由上面勾的那几项决定。
class _SliceRow extends StatelessWidget {
  const _SliceRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.count,
    required this.checked,
    this.implied = false,
    this.tristate = false,
    this.indeterminate = false,
    this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  /// 当前有多少条；null 表示这一行不是数据条目（"全选"那行）。
  final int? count;

  final bool checked;
  final bool implied;
  final bool tristate;

  /// 部分选中（只在"全选"那行出现）：复选框画成横杠而不是空框。
  final bool indeterminate;

  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = context.l10n;
    final effective = implied ? null : onChanged;
    final rowCount = count;

    return InkWell(
      borderRadius: AppRadii.tileAll,
      onTap: effective == null
          ? null
          : () => effective(!checked),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppConstants.spaceM,
          vertical: AppConstants.spaceM,
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: checked
                    ? scheme.primary.withValues(alpha: 0.14)
                    : scheme.surfaceContainerHighest.withValues(alpha: 0.7),
                borderRadius: AppRadii.smallAll,
              ),
              child: Icon(
                icon,
                size: 18,
                color: checked ? scheme.primary : scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: AppConstants.spaceM),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
            if (rowCount != null) ...<Widget>[
              const SizedBox(width: AppConstants.spaceS),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppConstants.spaceS,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: scheme.secondaryContainer.withValues(alpha: 0.7),
                  borderRadius: AppRadii.stadiumAll,
                ),
                child: Text(
                  implied
                      ? l10n.backupSliceImpliedChip(rowCount)
                      : (rowCount == 0
                          ? l10n.backupSliceEmptyChip
                          : l10n.backupSliceCountChip(rowCount)),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSecondaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
            const SizedBox(width: AppConstants.spaceXs),
            // 三态只在"全选"那行出现，且不能是 implied
            Checkbox(
              value: indeterminate ? null : checked,
              tristate: tristate,
              onChanged: effective == null
                  ? null
                  : (value) => effective(value ?? false),
            ),
          ],
        ),
      ),
    );
  }
}
