import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:schedule_plan/core/constants/app_constants.dart';
import 'package:schedule_plan/core/l10n/l10n_extensions.dart';
import 'package:schedule_plan/core/logging/app_logger.dart';
import 'package:schedule_plan/core/widgets/app_card.dart';
import 'package:schedule_plan/core/widgets/app_snackbar.dart';
import 'package:schedule_plan/core/widgets/confirm_dialog.dart';
import 'package:schedule_plan/data/models/attendance.dart';
import 'package:schedule_plan/data/models/student.dart';
import 'package:schedule_plan/data/repositories/attendance_repository.dart';

/// 表现标签弹层（模块二 2.10）：7 种预设标签 + 星级评分 + 文字备注。
Future<void> showStudentTagSheet(
  BuildContext context, {
  required Student student,
  required String date,
}) {
  return showAppSheet<void>(
    context: context,
    builder: (_) => _StudentTagBody(student: student, date: date),
  );
}

class _StudentTagBody extends StatefulWidget {
  const _StudentTagBody({required this.student, required this.date});

  final Student student;
  final String date;

  @override
  State<_StudentTagBody> createState() => _StudentTagBodyState();
}

class _StudentTagBodyState extends State<_StudentTagBody> {
  PerformanceTag _tag = PerformanceTag.activeSpeaking;
  int _stars = 3;
  final TextEditingController _remark = TextEditingController();

  @override
  void dispose() {
    _remark.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l10n = context.l10n;
    try {
      await context.read<AttendanceRepository>().upsertTag(
            StudentTagRecord(
              studentId: widget.student.id!,
              date: widget.date,
              tag: _tag,
              starRating: _stars,
              remark: _remark.text.trim().isEmpty ? null : _remark.text.trim(),
            ),
          );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop();
      showAppSnackBar(context, l10n.attendanceSaved);
    } catch (error, stack) {
      AppLogger.e('保存表现标签失败', error: error, stack: stack);
      if (!mounted) {
        return;
      }
      showAppSnackBar(context, l10n.operationFailed('$error'));
    }
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
            '${widget.student.name} · ${l10n.tagTitle}',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: AppConstants.spaceM),
          Wrap(
            spacing: AppConstants.spaceS,
            children: <Widget>[
              for (final tag in PerformanceTag.values)
                ChoiceChip(
                  label: Text(_tagLabel(tag)),
                  selected: _tag == tag,
                  onSelected: (_) => setState(() => _tag = tag),
                ),
            ],
          ),
          const SizedBox(height: AppConstants.spaceM),
          Text(l10n.starRating),
          Row(
            children: <Widget>[
              for (var star = 1; star <= 5; star++)
                IconButton(
                  icon: Icon(
                    star <= _stars ? Icons.star : Icons.star_border,
                    color: star <= _stars
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  onPressed: () => setState(() => _stars = star),
                ),
            ],
          ),
          TextField(
            controller: _remark,
            decoration: InputDecoration(labelText: l10n.remark),
          ),
          const SizedBox(height: AppConstants.spaceL),
          FilledButton(onPressed: _save, child: Text(l10n.save)),
        ],
      ),
    );
  }

  String _tagLabel(PerformanceTag tag) {
    final l10n = context.l10n;
    return switch (tag) {
      PerformanceTag.activeSpeaking => l10n.tagActiveSpeaking,
      PerformanceTag.homeworkOnTime => l10n.tagHomeworkOnTime,
      PerformanceTag.focusedListening => l10n.tagFocusedListening,
      PerformanceTag.helpingOthers => l10n.tagHelpingOthers,
      PerformanceTag.goodQuestion => l10n.tagGoodQuestion,
      PerformanceTag.neatHandwriting => l10n.tagNeatHandwriting,
      PerformanceTag.teamLeader => l10n.tagTeamLeader,
    };
  }
}
