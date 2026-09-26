import 'dart:ui' show Locale;

import 'package:flutter/foundation.dart';

import 'package:schedule_plan/core/constants/setting_keys.dart';
import 'package:schedule_plan/core/logging/app_logger.dart';
import 'package:schedule_plan/data/repositories/settings_repository.dart';

/// 语言控制器（模块七 7.4：切换后无需重启应用立即生效）。
class LocaleController extends ChangeNotifier {
  LocaleController(this._settings);

  final SettingsRepository _settings;

  Locale _locale = const Locale('zh');

  Locale get locale => _locale;

  bool get isEnglish => _locale.languageCode == 'en';

  Future<void> load() async {
    try {
      final stored = await _settings.read(SettingKeys.language);
      _locale = Locale(stored.isEmpty ? 'zh' : stored);
      notifyListeners();
    } catch (error, stack) {
      AppLogger.e('读取语言设置失败，回退为简体中文', error: error, stack: stack);
    }
  }

  Future<void> setLocale(Locale locale) async {
    if (_locale == locale) {
      return;
    }
    _locale = locale;
    notifyListeners();
    try {
      await _settings.write(SettingKeys.language, locale.languageCode);
    } catch (error, stack) {
      AppLogger.e('保存语言设置失败', error: error, stack: stack);
    }
  }
}
