import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:schedule_plan/core/constants/app_constants.dart';
import 'package:schedule_plan/core/constants/setting_keys.dart';
import 'package:schedule_plan/core/logging/app_logger.dart';
import 'package:schedule_plan/core/utils/date_utils.dart';
import 'package:schedule_plan/data/repositories/attendance_repository.dart';
import 'package:schedule_plan/data/repositories/llm_repository.dart';
import 'package:schedule_plan/data/repositories/settings_repository.dart';

/// 本地数据自动清理（readme 模块七 7.6）。
///
/// - 考勤记录保留 180 天，超期自动清理（**清理前先做本地备份文件**，防止误删无法恢复）
/// - 导入日志保留 360 天，超期自动清理
class CleanupService {
  CleanupService({
    required AttendanceRepository attendanceRepository,
    required ImportLogRepository importLogRepository,
    required SettingsRepository settingsRepository,
  })  : _attendance = attendanceRepository,
        _importLogs = importLogRepository,
        _settings = settingsRepository;

  final AttendanceRepository _attendance;
  final ImportLogRepository _importLogs;
  final SettingsRepository _settings;

  /// 执行清理，返回本次删除的考勤记录条数。
  ///
  /// 顺序：读取保留天数 -> 计算截止日期 -> 备份 -> 删除。
  /// 备份失败时**中止删除**，绝不冒进。
  Future<CleanupResult> run() async {
    final attendanceDays = await _settings.readInt(SettingKeys.attendanceRetentionDays);
    final importLogDays = await _settings.readInt(SettingKeys.importLogRetentionDays);
    final retentionDays =
        attendanceDays > 0 ? attendanceDays : AppConstants.attendanceRetentionDays;
    final logRetentionDays =
        importLogDays > 0 ? importLogDays : AppConstants.importLogRetentionDays;

    final cutoffDate = DateUtils.formatDate(
      DateTime.now().subtract(Duration(days: retentionDays)),
    );
    final expired = await _attendance.recordsBefore(cutoffDate);

    var backupPath = '';
    var deletedAttendance = 0;
    if (expired.isNotEmpty) {
      backupPath = await _backup(expired, cutoffDate);
      if (backupPath.isEmpty) {
        AppLogger.w('备份失败，已取消本次考勤清理，避免误删');
        return const CleanupResult(
          deletedAttendance: 0,
          deletedImportLogs: 0,
          backupPath: '',
          abortedBecauseBackupFailed: true,
        );
      }
      deletedAttendance = await _attendance.deleteBefore(cutoffDate);
    }

    final logCutoff = DateTime.now()
        .subtract(Duration(days: logRetentionDays))
        .millisecondsSinceEpoch;
    final deletedLogs = await _importLogs.deleteBefore(logCutoff);

    AppLogger.i(
      '自动清理完成：考勤 $deletedAttendance 条（截止 $cutoffDate），'
      '导入日志 $deletedLogs 条',
    );
    return CleanupResult(
      deletedAttendance: deletedAttendance,
      deletedImportLogs: deletedLogs,
      backupPath: backupPath,
      abortedBecauseBackupFailed: false,
    );
  }

  /// 把即将删除的记录写入本地 JSON 备份文件。
  Future<String> _backup(List<Map<String, Object?>> records, String cutoffDate) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final backupDir = Directory(p.join(directory.path, 'backups'));
      if (!backupDir.existsSync()) {
        backupDir.createSync(recursive: true);
      }
      final file = File(
        p.join(backupDir.path, 'attendance_before_$cutoffDate.json'),
      );
      await file.writeAsString(
        jsonEncode(<String, Object?>{
          'created_at': DateTime.now().millisecondsSinceEpoch,
          'cutoff_date': cutoffDate,
          'count': records.length,
          'records': records,
        }),
      );
      AppLogger.i('清理前备份已写入：${file.path}');
      return file.path;
    } catch (error, stack) {
      AppLogger.e('写入清理前备份失败', error: error, stack: stack);
      return '';
    }
  }
}

/// 清理结果。
class CleanupResult {
  const CleanupResult({
    required this.deletedAttendance,
    required this.deletedImportLogs,
    required this.backupPath,
    required this.abortedBecauseBackupFailed,
  });

  final int deletedAttendance;
  final int deletedImportLogs;
  final String backupPath;
  final bool abortedBecauseBackupFailed;
}
