import 'package:flutter/material.dart';

import 'package:schedule_plan/core/constants/app_constants.dart';
import 'package:schedule_plan/core/l10n/l10n_extensions.dart';
import 'package:schedule_plan/core/widgets/app_card.dart';
import 'package:schedule_plan/l10n/generated/app_localizations.dart';

/// 打开「考勤率怎么算」的说明（`docs/SPEC.md` 3.10）。
///
/// 用户规格：*"要在功能上向用户说明，考勤率是怎么算的"*。所以它不是藏在
/// 设置里的帮助文档，而是**每一处出现百分比的地方都能点开**的一张卡片 ——
/// 概览卡片、档案汇总条、排行表头，三处调的是同一个函数，文案只有一份。
///
/// 第 5 条（改课表会重算）不许删：那是这套算法唯一的硬伤，
/// 藏起来比说出来更伤信任。
Future<void> showAttendanceFormulaSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => _AttendanceFormulaSheet(l10n: context.l10n),
  );
}

class _AttendanceFormulaSheet extends StatelessWidget {
  const _AttendanceFormulaSheet({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lines = <String>[
      l10n.statFormulaLine1,
      l10n.statFormulaLine2,
      l10n.statFormulaLine3,
      l10n.statFormulaLine4,
      l10n.statFormulaLine5,
    ];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppConstants.spaceL,
          0,
          AppConstants.spaceL,
          AppConstants.spaceL,
        ),
        child: AppCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(l10n.statFormulaTitle, style: theme.textTheme.titleMedium),
              const SizedBox(height: AppConstants.spaceM),
              for (var i = 0; i < lines.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppConstants.spaceS),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      SizedBox(
                        width: 20,
                        child: Text(
                          '${i + 1}.',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          lines[i],
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 表头旁边那个小问号：点开就是 [showAttendanceFormulaSheet]。
class AttendanceFormulaButton extends StatelessWidget {
  const AttendanceFormulaButton({super.key, this.size = 16});

  final double size;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      icon: Icon(
        Icons.help_outline,
        size: size,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      tooltip: context.l10n.statFormulaTitle,
      onPressed: () => showAttendanceFormulaSheet(context),
    );
  }
}
