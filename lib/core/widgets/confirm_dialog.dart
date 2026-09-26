import 'package:flutter/material.dart';

import 'package:schedule_plan/core/constants/app_constants.dart';
import 'package:schedule_plan/core/l10n/l10n_extensions.dart';

/// 二次确认弹窗。
///
/// 规范 4 / 模块八：危险操作必须二次确认，且弹窗文案需**具体说明后果**，
/// 不能只写「确定删除吗？」。
Future<bool> showAppConfirm({
  required BuildContext context,
  required String title,
  required String body,
  String? confirmLabel,
  bool danger = false,
}) async {
  final l10n = context.l10n;
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final theme = Theme.of(dialogContext);
      return AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            style: danger
                ? FilledButton.styleFrom(
                    backgroundColor: theme.colorScheme.error,
                    foregroundColor: theme.colorScheme.onError,
                  )
                : null,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(confirmLabel ?? l10n.confirm),
          ),
        ],
      );
    },
  );
  return result ?? false;
}

/// 圆角弹层（统一 16dp），用于承载表单。
Future<T?> showAppSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(AppConstants.radius),
      ),
    ),
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
      ),
      child: builder(sheetContext),
    ),
  );
}
