import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:schedule_plan/data/services/excel_service.dart';
import 'package:schedule_plan/data/services/xlsx_repair.dart';

/// 用给定的 styles.xml 换掉 xlsx 里的那一份。
Uint8List _replaceStyles(Uint8List bytes, String stylesXml) {
  final source = ZipDecoder().decodeBytes(bytes);
  final rebuilt = Archive();
  for (final file in source.files) {
    if (!file.isFile) {
      continue;
    }
    final List<int> content = file.name == 'xl/styles.xml'
        ? utf8.encode(stylesXml)
        : file.content as List<int>;
    rebuilt.addFile(ArchiveFile(file.name, content.length, content));
  }
  return Uint8List.fromList(ZipEncoder().encode(rebuilt)!);
}

/// 造一份「合法名单 + 非法样式表」的 xlsx。
///
/// 复刻的是 WPS / 老版 Excel / 报表系统的导出行为：把内置数字格式
/// （这里是 numFmtId=41）又写了一遍到 `<numFmts>` 里并在单元格上引用。
/// `excel` 4.x 遇到这种文件会直接抛
/// `custom numFmtId starts at 164 but found a value of 41`。
Uint8List _brokenWorkbook() {
  final book = Excel.createExcel();
  final sheet = book[book.getDefaultSheet()!];
  sheet.appendRow(<CellValue?>[
    TextCellValue('姓名'),
    TextCellValue('班级'),
    TextCellValue('学号'),
  ]);
  sheet.appendRow(<CellValue?>[
    TextCellValue('张三'),
    TextCellValue('高一(3)班'),
    TextCellValue('2026001'),
  ]);
  final bytes = Uint8List.fromList(book.encode()!);

  final source = ZipDecoder().decodeBytes(bytes);
  var xml = utf8.decode(
    source.files
        .firstWhere((file) => file.name == 'xl/styles.xml')
        .content as List<int>,
  );

  const numFmts = '<numFmts count="1">'
      '<numFmt numFmtId="41" formatCode="_(* #,##0_);_(* &#92;(#,##0&#92;);'
      '_(* &quot;-&quot;_)"/>'
      '</numFmts>';
  final openStart = xml.indexOf('<styleSheet');
  final openEnd = xml.indexOf('>', openStart) + 1;
  xml = xml.substring(0, openEnd) + numFmts + xml.substring(openEnd);

  const cellRef = 'numFmtId="0" xfId="0"';
  expect(xml.contains(cellRef), isTrue, reason: '模板样式表结构变了，请同步本用例');
  xml = xml.replaceFirst(cellRef, 'numFmtId="41" xfId="0"');

  return _replaceStyles(bytes, xml);
}

void main() {
  test('复现：非法 numFmtId 会让 excel 包直接抛异常（整份名单读不出来）', () {
    final broken = _brokenWorkbook();
    expect(
      () => Excel.decodeBytes(broken),
      throwsA(
        predicate(
          (Object? error) =>
              '$error'.contains('custom numFmtId starts at 164'),
          'excel 包应当因为非法 numFmtId 抛异常',
        ),
      ),
    );
  });

  test('修复后 excel 包能正常解析，且不再需要二次修复', () {
    final broken = _brokenWorkbook();
    final repaired = repairXlsxNumberFormats(broken);
    expect(repaired, isNotNull);
    final patched = repaired!;
    expect(() => Excel.decodeBytes(patched), returnsNormally);
    // 修完就是干净文件了，再来一次不应该有任何改动
    expect(repairXlsxNumberFormats(patched), isNull);
  });

  test('ExcelService 会把这类文件修好，学生名单照常导入', () {
    final rows = ExcelService().parseStudentRows(_brokenWorkbook());
    expect(rows, hasLength(1));
    expect(rows.first.name, '张三');
    expect(rows.first.className, '高一(3)班');
    expect(rows.first.studentNo, '2026001');
  });

  test('正常 xlsx 不需要修复', () {
    final book = Excel.createExcel();
    final sheet = book[book.getDefaultSheet()!];
    sheet.appendRow(<CellValue?>[TextCellValue('姓名'), TextCellValue('班级')]);
    sheet.appendRow(<CellValue?>[TextCellValue('李四'), TextCellValue('高一(1)班')]);
    final healthy = Uint8List.fromList(book.encode()!);
    expect(repairXlsxNumberFormats(healthy), isNull);
    final rows = ExcelService().parseStudentRows(healthy);
    expect(rows, hasLength(1));
    expect(rows.first.name, '李四');
  });

  test('彻底读不出来的文件抛 ExcelParseException，而不是把原始英文异常漏给用户', () {
    final garbage = Uint8List.fromList(utf8.encode('这不是一个 xlsx'));
    expect(repairXlsxNumberFormats(garbage), isNull);
    expect(
      () => ExcelService().parseStudentRows(garbage),
      throwsA(isA<ExcelParseException>()),
    );
  });
}
