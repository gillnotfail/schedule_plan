import 'package:schedule_plan/data/models/student.dart';

/// 单行导入结果（写入 import_log.detail_json）。
class ImportRowResult {
  const ImportRowResult({
    required this.rowIndex,
    required this.status,
    this.reason,
    this.studentName,
  });

  final int rowIndex;

  /// success / fail / skip
  final String status;

  /// 失败行给出具体失败原因，而非笼统报错（模块六 6.3）
  final String? reason;
  final String? studentName;

  Map<String, Object?> toMap() => <String, Object?>{
        'row': rowIndex,
        'status': status,
        if (reason != null) 'reason': reason,
        if (studentName != null) 'name': studentName,
      };

  static ImportRowResult fromMap(Map<String, Object?> map) => ImportRowResult(
        rowIndex: map['row'] as int? ?? 0,
        status: map['status'] as String? ?? 'skip',
        reason: map['reason'] as String?,
        studentName: map['name'] as String?,
      );
}

/// 批量导入日志（readme 3.13 表 import_log）。
class ImportLog {
  const ImportLog({
    this.id,
    required this.fileName,
    required this.importedAt,
    required this.successCount,
    required this.failCount,
    this.detailJson,
  });

  final int? id;
  final String fileName;
  final int importedAt;
  final int successCount;
  final int failCount;
  final String? detailJson;

  Map<String, Object?> toMap() => <String, Object?>{
        if (id != null) 'id': id,
        'file_name': fileName,
        'imported_at': importedAt,
        'success_count': successCount,
        'fail_count': failCount,
        'detail_json': detailJson,
      };

  static ImportLog fromMap(Map<String, Object?> map) => ImportLog(
        id: map['id'] as int?,
        fileName: map['file_name'] as String,
        importedAt: map['imported_at'] as int,
        successCount: map['success_count'] as int? ?? 0,
        failCount: map['fail_count'] as int? ?? 0,
        detailJson: map['detail_json'] as String?,
      );
}

/// 待导入的学生行（模块六 6.3 导入预览用）。
class ImportPreviewRow {
  const ImportPreviewRow({
    required this.rowIndex,
    required this.name,
    this.studentNo,
    this.gender,
    this.className,
    this.matchedClassId,
    this.errorKey,
  });

  final int rowIndex;
  final String name;
  final String? studentNo;

  /// 性别（选填，Excel 里可为「男 / 女 / M / F」）
  final StudentGender? gender;

  /// Excel 中的班级列（导入时用于自动建立班级）
  final String? className;
  final int? matchedClassId;

  /// i18n key：预览阶段就把问题暴露出来，而不是导入时才报错。
  final String? errorKey;

  bool get hasError => errorKey != null;

  ImportPreviewRow copyWith({
    int? rowIndex,
    String? name,
    String? studentNo,
    StudentGender? gender,
    String? className,
    int? matchedClassId,
    String? errorKey,
  }) {
    return ImportPreviewRow(
      rowIndex: rowIndex ?? this.rowIndex,
      name: name ?? this.name,
      studentNo: studentNo ?? this.studentNo,
      gender: gender ?? this.gender,
      className: className ?? this.className,
      matchedClassId: matchedClassId ?? this.matchedClassId,
      errorKey: errorKey ?? this.errorKey,
    );
  }
}
