import 'package:flutter/material.dart';

import 'package:schedule_plan/core/constants/app_constants.dart';

/// SnackBar 统一样式与展示时长（规范 8：默认 3 秒，重要操作可延长）。
void showAppSnackBar(
  BuildContext context,
  String message, {
  bool long = false,
  VoidCallback? onRetry,
  String? retryLabel,
}) {
  final theme = Theme.of(context);
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        duration: long
            ? AppConstants.snackBarLongDuration
            : AppConstants.snackBarDuration,
        action: onRetry == null
            ? null
            : SnackBarAction(
                label: retryLabel ?? '',
                textColor: theme.colorScheme.surface,
                onPressed: onRetry,
              ),
      ),
    );
}
