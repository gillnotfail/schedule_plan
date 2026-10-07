import 'package:flutter/material.dart';

import 'package:schedule_plan/core/constants/app_constants.dart';
import 'package:schedule_plan/core/l10n/l10n_extensions.dart';
import 'package:schedule_plan/core/widgets/app_card.dart';
import 'package:schedule_plan/core/widgets/confirm_dialog.dart';
import 'package:schedule_plan/features/toolbox/focus/focus_clock.dart';

/// 退出拦截：**先劝一句，再放行**。
///
/// 用户规格里这条写得很明确 —— 想退出时先告诉他"已经坚持了多久、还差多少"，
/// 二次确认之后才把屏幕还给他。所以返回 `true` 才表示真的结束，
/// 划掉浮层 / 点「继续专注」都算没走成。
Future<bool> showFocusExitSheet(
  BuildContext context, {
  required Duration elapsed,
  required Duration remaining,
}) async {
  final confirmed = await showAppSheet<bool>(
    context: context,
    builder: (sheetContext) {
      final l10n = sheetContext.l10n;
      final theme = Theme.of(sheetContext);
      final scheme = theme.colorScheme;
      // "就差一点点了"的判定：剩下不到一分钟，或不到全程的十分之一。
      final nearlyThere = remaining <= const Duration(minutes: 1) ||
          (remaining > Duration.zero && elapsed > remaining * 9);
      return AppCard(
        elevated: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.nightlight_round, color: scheme.primary),
                const SizedBox(width: AppConstants.spaceM),
                Expanded(
                  child: Text(
                    l10n.focusExitTitle,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppConstants.spaceL),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppConstants.spaceL,
                vertical: AppConstants.spaceM,
              ),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(AppRadii.inner),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    l10n.focusExitElapsed(formatFocusSpoken(elapsed)),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: AppConstants.spaceXs),
                  Text(
                    remaining > Duration.zero && !nearlyThere
                        ? l10n.focusExitRemaining(formatFocusSpoken(remaining))
                        : l10n.focusExitAlmostThere,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppConstants.spaceM),
            Text(
              l10n.focusExitEncourage,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppConstants.spaceL),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(sheetContext).pop(false),
                    child: Text(l10n.focusExitKeepGoing),
                  ),
                ),
                const SizedBox(width: AppConstants.spaceM),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(sheetContext).pop(true),
                    child: Text(l10n.focusExitConfirm),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );
  return confirmed ?? false;
}
