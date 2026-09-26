import 'package:flutter/material.dart';

import 'package:schedule_plan/core/constants/setting_keys.dart';
import 'package:schedule_plan/core/logging/app_logger.dart';
import 'package:schedule_plan/core/theme/app_colors.dart';
import 'package:schedule_plan/data/repositories/settings_repository.dart';

/// 主题控制器（模块七 7.5：三套主题切换，切换后立即生效）。
class ThemeController extends ChangeNotifier {
  ThemeController(this._settings);

  final SettingsRepository _settings;

  AppThemeKind _kind = AppThemeKind.mint;

  AppThemeKind get kind => _kind;

  AppColorTokens get tokens => AppColorTokens.of(_kind);

  bool get isDark => tokens.isDark;

  /// 从 app_settings 恢复主题。
  Future<void> load() async {
    try {
      final stored = await _settings.read(SettingKeys.theme);
      _kind = AppThemeKind.fromStorage(stored);
      notifyListeners();
    } catch (error, stack) {
      AppLogger.e('读取主题设置失败，回退为清新薄荷', error: error, stack: stack);
    }
  }

  Future<void> setKind(AppThemeKind kind) async {
    if (_kind == kind) {
      return;
    }
    _kind = kind;
    notifyListeners();
    try {
      await _settings.write(SettingKeys.theme, kind.storageKey);
    } catch (error, stack) {
      AppLogger.e('保存主题设置失败', error: error, stack: stack);
    }
  }
}
