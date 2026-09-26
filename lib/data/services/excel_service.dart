import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:schedule_plan/core/logging/app_logger.dart';
import 'package:schedule_plan/data/models/attendance.dart';
import 'package:schedule_plan/data/models/import_log.dart';
import 'package:schedule_plan/data/models/student.dart';
import 'package:schedule_plan/data/services/xlsx_repair.dart';

/// 学生名单文件无法解析。
///
/// 具体原因（不是 xlsx、结构损坏、样式表非法且修复后仍失败……）留在 [cause] 里
/// 供日志排查；给用户看的提示由调用方用自己的文案键渲染，
/// 不要把这条技术信息直接抛给用户。
class ExcelParseException implements Exception {
  const ExcelParseException(this.cause);

  final Object cause;

  @override
  String toString() => 'ExcelParseException($cause)';
}

/// Excel 导入导出（readme 模块三 3.6 / 模块六 6.3）。
class ExcelService {
  ExcelService();

  static const List<String> _nameHeaders = <String>['姓名', '名字', '学生姓名', 'name', 'student'];
  static const List<String> _noHeaders = <String>['学号', '编号', 'studentno', 'no', 'id'];
  static const List<String> _classHeaders = <String>['班级', '班级名称', 'class', 'classname'];
  static const List<String> _genderHeaders = <String>['性别', 'gender', 'sex'];

  /// 学生名单导入模板的列口径（用于「文件格式说明」与示例展示）。
  static const List<String> requiredHeaders = <String>['姓名', '班级'];
  static const List<String> optionalHeaders = <String>['学号', '性别'];

  /// 导出三个 Sheet：考勤汇总 / 异常明细 / 学生排名。
  ///
  /// 返回生成的文件路径，调用方再交给系统分享面板。
  Future<String> exportAttendanceWorkbook({
    required List<Map<String, Object?>> summaryRows,
    required List<Map<String, Object?>> abnormalRows,
    required List<RiskStudent> ranking,
    required String fromDate,
    required String toDate,
  }) async {
    final book = Excel.createExcel();
    book.rename(book.getDefaultSheet() ?? 'Sheet1', '考勤汇总');

    final summary = book['考勤汇总'];
    summary.appendRow(<CellValue?>[
      TextCellValue('班级'),
      TextCellValue('课程'),
      TextCellValue('日期'),
      TextCellValue('状态'),
      TextCellValue('人数'),
    ]);
    for (final row in summaryRows) {
      summary.appendRow(<CellValue?>[
        TextCellValue('${row['class_name'] ?? ''}'),
        TextCellValue('${row['course_name'] ?? ''}'),
        TextCellValue('${row['date'] ?? ''}'),
        TextCellValue('${row['status'] ?? ''}'),
        IntCellValue((row['cnt'] as int?) ?? 0),
      ]);
    }

    final abnormal = book['异常明细'];
    abnormal.appendRow(<CellValue?>[
      TextCellValue('日期'),
      TextCellValue('学生'),
      TextCellValue('学号'),
      TextCellValue('班级'),
      TextCellValue('课程'),
      TextCellValue('上课时间'),
      TextCellValue('状态'),
      TextCellValue('备注'),
    ]);
    for (final row in abnormalRows) {
      abnormal.appendRow(<CellValue?>[
        TextCellValue('${row['date'] ?? ''}'),
        TextCellValue('${row['student_name'] ?? ''}'),
        TextCellValue('${row['student_no'] ?? ''}'),
        TextCellValue('${row['class_name'] ?? ''}'),
        TextCellValue('${row['course_name'] ?? ''}'),
        TextCellValue('${row['start_time'] ?? ''}-${row['end_time'] ?? ''}'),
        TextCellValue('${row['status'] ?? ''}'),
        TextCellValue('${row['note'] ?? ''}'),
      ]);
    }

    final rank = book['学生排名'];
    rank.appendRow(<CellValue?>[
      TextCellValue('排名'),
      TextCellValue('学生'),
      TextCellValue('学号'),
      TextCellValue('班级ID'),
      TextCellValue('缺勤次数'),
      TextCellValue('迟到次数'),
      TextCellValue('早退次数'),
      TextCellValue('风险分'),
    ]);
    var index = 1;
    for (final item in ranking) {
      rank.appendRow(<CellValue?>[
        IntCellValue(index),
        TextCellValue(item.student.name),
        TextCellValue(item.student.studentNo ?? ''),
        IntCellValue(item.student.classId),
        IntCellValue(item.absentCount),
        IntCellValue(item.lateCount),
        IntCellValue(item.earlyLeaveCount),
        IntCellValue(item.riskScore),
      ]);
      index++;
    }

    final bytes = book.encode();
    if (bytes == null) {
      throw const FormatException('Excel 编码失败');
    }
    final directory = await getApplicationDocumentsDirectory();
    final exportDir = Directory(p.join(directory.path, 'exports'));
    if (!exportDir.existsSync()) {
      exportDir.createSync(recursive: true);
    }
    final file = File(
      p.join(exportDir.path, 'attendance_${fromDate}_$toDate.xlsx'),
    );
    await file.writeAsBytes(Uint8List.fromList(bytes), flush: true);
    AppLogger.i('Excel 导出成功：${file.path}');
    return file.path;
  }

  /// 解析学生名单文件，自动识别列名（表头关键词模糊匹配）。
  ///
  /// 返回预览行，供用户在导入前核对班级匹配关系。
  ///
  /// 解析失败统一抛 [ExcelParseException]，调用方据此给出本地化提示。
  List<ImportPreviewRow> parseStudentRows(Uint8List bytes) {
    try {
      return _parseStudentRows(bytes);
    } catch (error, stack) {
      AppLogger.e('Excel 解析失败', error: error, stack: stack);
      throw ExcelParseException(error);
    }
  }

  List<ImportPreviewRow> _parseStudentRows(Uint8List bytes) {
    final book = decodeWorkbook(bytes);
    if (book.tables.isEmpty) {
      return const <ImportPreviewRow>[];
    }
    final sheet = book.tables[book.getDefaultSheet() ?? book.tables.keys.first]!;
    final rows = sheet.rows;
    if (rows.isEmpty) {
      return const <ImportPreviewRow>[];
    }
    var nameColumn = -1;
    var noColumn = -1;
    var classColumn = -1;
    var genderColumn = -1;
    var headerRow = 0;

    for (var r = 0; r < rows.length && r < 5; r++) {
      final cells = rows[r];
      for (var c = 0; c < cells.length; c++) {
        final text = _cellText(cells[c]).trim().toLowerCase();
        if (text.isEmpty) {
          continue;
        }
        if (_matchHeader(text, _nameHeaders)) {
          nameColumn = c;
          headerRow = r;
        } else if (_matchHeader(text, _noHeaders)) {
          noColumn = c;
          headerRow = r;
        } else if (_matchHeader(text, _classHeaders)) {
          classColumn = c;
          headerRow = r;
        } else if (_matchHeader(text, _genderHeaders)) {
          genderColumn = c;
          headerRow = r;
        }
      }
      if (nameColumn >= 0) {
        break;
      }
    }
    if (nameColumn < 0) {
      // 找不到姓名列时，退化为取第一列
      nameColumn = 0;
      headerRow = 0;
    }

    final result = <ImportPreviewRow>[];
    for (var r = headerRow + 1; r < rows.length; r++) {
      final cells = rows[r];
      final name = nameColumn < cells.length ? _cellText(cells[nameColumn]).trim() : '';
      if (name.isEmpty) {
        continue;
      }
      final no = noColumn >= 0 && noColumn < cells.length ? _cellText(cells[noColumn]).trim() : '';
      final className =
          classColumn >= 0 && classColumn < cells.length ? _cellText(cells[classColumn]).trim() : '';
      final genderRaw =
          genderColumn >= 0 && genderColumn < cells.length ? _cellText(cells[genderColumn]) : '';
      result.add(
        ImportPreviewRow(
          rowIndex: r + 1,
          name: name,
          studentNo: no.isEmpty ? null : no,
          gender: StudentGender.parse(genderRaw),
          className: className.isEmpty ? null : className,
        ),
      );
    }
    return result;
  }

  /// 打开工作簿：先按原样解析，失败后修一遍样式表再重试。
  ///
  /// 为什么要修：部分 WPS / 老版 Excel / 报表系统导出时，会把内置数字格式
  /// 又写一遍到 `xl/styles.xml` 的 `<numFmts>` 里（例如 `numFmtId="41"`）。
  /// `excel` 4.x 对此**直接抛异常**
  /// （`custom numFmtId starts at 164 but found a value of 41`），
  /// 导致整份名单一个字都读不出来。修复逻辑见 [repairXlsxNumberFormats]。
  ///
  /// 正常文件走不到重试分支，只有踩到这个坑的文件才会多解一次 zip。
  Excel decodeWorkbook(Uint8List bytes) {
    try {
      return Excel.decodeBytes(bytes);
    } catch (error, stack) {
      AppLogger.w('Excel 首次解析失败，尝试修复样式表后重试：$error');
      final repaired = repairXlsxNumberFormats(bytes);
      if (repaired == null) {
        Error.throwWithStackTrace(error, stack);
      }
      return Excel.decodeBytes(repaired);
    }
  }

  bool _matchHeader(String text, List<String> keywords) {
    for (final keyword in keywords) {
      if (text.contains(keyword.toLowerCase())) {
        return true;
      }
    }
    return false;
  }

  String _cellText(Data? data) {
    final value = data?.value;
    if (value == null) {
      return '';
    }
    if (value is TextCellValue) {
      return value.value.toString();
    }
    if (value is IntCellValue) {
      return value.value.toString();
    }
    if (value is DoubleCellValue) {
      return value.value.toString();
    }
    return value.toString();
  }
}
