import 'package:flutter/foundation.dart';

import 'package:schedule_plan/core/constants/app_constants.dart';
import 'package:schedule_plan/core/constants/setting_keys.dart';
import 'package:schedule_plan/core/logging/app_logger.dart';
import 'package:schedule_plan/data/models/attendance.dart';
import 'package:schedule_plan/data/models/student.dart';
import 'package:schedule_plan/data/repositories/settings_repository.dart';

/// 运行期设置状态。
///
/// 所有可调阈值集中在此（readme 第六章「魔法数字硬编码」规避策略），
/// 设置页修改后调用 [reload] 即可全局生效。
class SettingsState extends ChangeNotifier {
  SettingsState(this._settings);

  final SettingsRepository _settings;

  int riskAbsenceThreshold = AppConstants.riskAbsenceThreshold;
  double attendanceWarnRate = AppConstants.attendanceWarnRate;
  int riskWeightAbsent = AppConstants.riskWeightAbsent;
  int riskWeightLate = AppConstants.riskWeightLate;
  int riskWeightEarlyLeave = AppConstants.riskWeightEarlyLeave;
  int attendanceRetentionDays = AppConstants.attendanceRetentionDays;
  int importLogRetentionDays = AppConstants.importLogRetentionDays;
  bool cascadeUpdateEnabled = true;
  AttendanceStatus defaultAttendanceStatus = AttendanceStatus.present;
  int reminderMinutesBefore = AppConstants.reminderMinutesBefore;
  bool lessonReminderEnabled = true;
  int focusMinutes = AppConstants.focusDefaultMinutes;
  int focusBreakMinutes = AppConstants.focusDefaultBreakMinutes;
  StudentSortMode studentSortMode = StudentSortMode.namePinyin;
  String statisticsGranularity = 'week';
  int statisticsClassFilter = 0;

  /// 节假日 / 调休是否参与课表与课时结算（默认开启）。
  ///
  /// 关掉之后一律按"周六周日休息"处理 —— 给那些不按国家安排走（比如
  /// 民办校自己定校历）的老师留一个逃生口。
  bool holidayAwareEnabled = true;

  /// 是否每年自动联网取回新的节假日安排（默认开启）。
  ///
  /// 关掉只是不再联网，内置表照旧可用——不会让功能坏掉。
  bool holidayRemoteEnabled = true;

  Future<void> load() async {
    try {
      riskAbsenceThreshold = await _settings.readInt(SettingKeys.riskAbsenceThreshold);
      attendanceWarnRate = await _settings.readDouble(SettingKeys.attendanceWarnRate);
      riskWeightAbsent = await _settings.readInt(SettingKeys.riskWeightAbsent);
      riskWeightLate = await _settings.readInt(SettingKeys.riskWeightLate);
      riskWeightEarlyLeave = await _settings.readInt(SettingKeys.riskWeightEarlyLeave);
      attendanceRetentionDays =
          await _settings.readInt(SettingKeys.attendanceRetentionDays);
      importLogRetentionDays =
          await _settings.readInt(SettingKeys.importLogRetentionDays);
      cascadeUpdateEnabled = await _settings.readBool(SettingKeys.cascadeUpdateEnabled);
      defaultAttendanceStatus = AttendanceStatus.fromStorage(
        await _settings.read(SettingKeys.defaultAttendanceStatus),
      );
      reminderMinutesBefore =
          await _settings.readInt(SettingKeys.reminderMinutesBefore);
      lessonReminderEnabled =
          await _settings.readBool(SettingKeys.lessonReminderEnabled);
      focusMinutes = await _settings.readInt(SettingKeys.focusMinutes);
      focusBreakMinutes = await _settings.readInt(SettingKeys.focusBreakMinutes);
      studentSortMode = StudentSortMode.fromStorage(
        await _settings.read(SettingKeys.studentSortMode),
      );
      statisticsGranularity = await _settings.read(SettingKeys.statisticsGranularity);
      statisticsClassFilter =
          await _settings.readInt(SettingKeys.statisticsClassFilter);
      holidayAwareEnabled =
          await _settings.readBool(SettingKeys.holidayAwareEnabled);
      holidayRemoteEnabled =
          await _settings.readBool(SettingKeys.holidayRemoteEnabled);
      notifyListeners();
    } catch (error, stack) {
      AppLogger.e('加载应用设置失败，使用内置默认值', error: error, stack: stack);
    }
  }

  Future<void> update(String key, String value) async {
    await _settings.write(key, value);
    await load();
  }
}
