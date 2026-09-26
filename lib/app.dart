import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:schedule_plan/core/i18n/locale_controller.dart';
import 'package:schedule_plan/core/l10n/l10n_extensions.dart';
import 'package:schedule_plan/core/theme/app_theme.dart';
import 'package:schedule_plan/core/theme/theme_controller.dart';
import 'package:schedule_plan/l10n/generated/app_localizations.dart';

import 'features/shell/main_shell.dart';

/// 应用根组件：主题、语言、路由都在这里统一装配。
class SchedulePlanApp extends StatelessWidget {
  const SchedulePlanApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeController = context.watch<ThemeController>();
    final localeController = context.watch<LocaleController>();
    return MaterialApp(
      onGenerateTitle: (context) => context.l10n.appTitle,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(themeController.tokens),
      locale: localeController.locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const MainShell(),
    );
  }
}
