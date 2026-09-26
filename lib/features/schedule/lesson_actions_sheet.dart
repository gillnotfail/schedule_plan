import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:schedule_plan/core/constants/app_constants.dart';
import 'package:schedule_plan/core/constants/setting_keys.dart';
import 'package:schedule_plan/core/error/app_exceptions.dart';
import 'package:schedule_plan/core/l10n/l10n_extensions.dart';
import 'package:schedule_plan/core/logging/app_logger.dart';
import 'package:schedule_plan/core/widgets/app_card.dart';
import 'package:schedule_plan/core/widgets/app_snackbar.dart';
import 'package:schedule_plan/core/widgets/confirm_dialog.dart';
import 'package:schedule_plan/core/widgets/wheel_time_picker.dart';
import 'package:schedule_plan/data/models/lesson.dart';
import 'package:schedule_plan/data/repositories/lesson_repository.dart';
import 'package:schedule_plan/data/repositories/settings_repository.dart';
import 'package:schedule_plan/data/repositories/template_repository.dart';

/// 课表条目操作：修改时间 / 删除。
///
/// 「一键修改课表时间」（模块一 1.6）使用滚轮选择器；
/// 修改后按模块一 1.7 弹出「仅修改本节 / 同步修改后续所有节次」选项。
Future<void> showLessonActionsSheet(
  BuildContext context,
  LessonWithTime lesson,
) {
  return showAppSheet<void>(
    context: context,
    builder: (sheetContext) => _LessonActionsBody(lesson: lesson),
  );
}

class _LessonActionsBody extends StatefulWidget {
  const _LessonActionsBody({required this.lesson});

  final LessonWithTime lesson;

  @override
  State<_LessonActionsBody> createState() => _LessonActionsBodyState();
}

class _LessonActionsBodyState extends State<_LessonActionsBody> {
  bool _busy = false;

  Future<void> _delete() async {
    final l10n = context.l10n;
    final lessonRepo = context.read<LessonRepository>();
    final confirmed = await showAppConfirm(
      context: context,
      title: l10n.deleteLesson,
      body: l10n.deleteLessonConfirmBody,
      danger: true,
    );
    if (!confirmed) {
      return;
    }
    setState(() => _busy = true);
    try {
      await lessonRepo.deleteLesson(widget.lesson.lesson.id!);
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop();
      showAppSnackBar(context, l10n.lessonDeleted);
    } catch (error, stack) {
      AppLogger.e('删除课表失败', error: error, stack: stack);
      if (!mounted) {
        return;
      }
      setState(() => _busy = false);
      showAppSnackBar(context, l10n.operationFailed('$error'));
    }
  }

  Future<void> _editTime() async {
    final l10n = context.l10n;
    // 仓储在 await 之前取好，避免跨异步间隙使用 context
    final settingsRepo = context.read<SettingsRepository>();
    final templateRepo = context.read<TemplateRepository>();
    final picked = await showWheelTimePicker(
      context,
      initialTime: widget.lesson.startTime,
      title: l10n.editLessonTime,
    );
    if (picked == null || picked == widget.lesson.startTime) {
      return;
    }
    if (!mounted) {
      return;
    }
    final cascade = await showAppSheet<bool>(
      context: context,
      builder: (sheetContext) => AppCard(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(l10n.cascadeTitle,
                style: Theme.of(sheetContext).textTheme.titleMedium),
            const SizedBox(height: AppConstants.spaceM),
            FilledButton(
              onPressed: () => Navigator.of(sheetContext).pop(false),
              child: Text(l10n.cascadeOnlyThis),
            ),
            const SizedBox(height: AppConstants.spaceS),
            OutlinedButton(
              onPressed: () => Navigator.of(sheetContext).pop(true),
              child: Text(l10n.cascadeAllFollowing),
            ),
          ],
        ),
      ),
    );
    if (cascade == null) {
      return;
    }
    setState(() => _busy = true);
    try {
      // 级联开关可在作息模板编辑页统一开启/关闭（默认开启）；
      // 关闭时即便用户选择「同步后续」，也只改本节。
      final enabled = await settingsRepo.readBool(
        SettingKeys.cascadeUpdateEnabled,
      );
      final duration = widget.lesson.endMinutes - widget.lesson.startMinutes;
      await templateRepo.cascadeUpdatePeriods(
            templateId: widget.lesson.templateId,
            weekday: widget.lesson.lesson.weekday,
            fromPeriodIndex: widget.lesson.lesson.periodIndex,
            newStartTime: picked,
            newEndTime: _endTimeFrom(picked, duration),
            cascade: enabled && cascade,
          );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop();
      showAppSnackBar(context, l10n.lessonSaved);
    } on AppException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _busy = false);
      showAppSnackBar(context, error.message);
    } catch (error, stack) {
      AppLogger.e('修改课表时间失败', error: error, stack: stack);
      if (!mounted) {
        return;
      }
      setState(() => _busy = false);
      showAppSnackBar(context, l10n.unexpectedError);
    }
  }

  String _endTimeFrom(String newStart, int duration) {
    final startMinutes = _parse(newStart);
    final total = startMinutes + duration;
    final hour = (total ~/ 60).toString().padLeft(2, '0');
    final minute = (total % 60).toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  int _parse(String value) {
    final parts = value.split(':');
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return AppCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            '${widget.lesson.courseName} · ${widget.lesson.className}',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            widget.lesson.timeRangeText,
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: AppConstants.spaceL),
          OutlinedButton.icon(
            onPressed: _busy ? null : _editTime,
            icon: const Icon(Icons.schedule_outlined),
            label: Text(l10n.editLessonTime),
          ),
          const SizedBox(height: AppConstants.spaceS),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: theme.colorScheme.error,
            ),
            onPressed: _busy ? null : _delete,
            icon: const Icon(Icons.delete_outline),
            label: Text(l10n.deleteLesson),
          ),
        ],
      ),
    );
  }
}
