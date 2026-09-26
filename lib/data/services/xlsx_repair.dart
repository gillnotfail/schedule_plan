import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// OOXML：自定义数字格式 id 的起点，低于它的都是内置格式。
const int _firstCustomNumFmtId = 164;

/// `excel` 包内部已经支持的内置数字格式 id。
///
/// 取值来源：excel 4.0.6 `lib/src/number_format/num_format.dart`
/// 里的 `_standardNumFormats`。低于 164 但**不在**这个集合里的 id，
/// excel 查不到格式表后会走到 `assert(false, 'missing numFmt for ...')`
/// —— debug 构建直接崩，release 构建才静默兜底。
/// 所以修复时也要把这类 id 一并改写掉，保证两种构建行为一致。
const Set<int> _supportedBuiltinNumFmtIds = <int>{
  0, 1, 2, 3, 4, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, //
  37, 38, 39, 40, 45, 46, 47, 48, 49,
};

const String _stylesEntryPath = 'xl/styles.xml';

/// 修复 xlsx 中「非法的自定义数字格式 id」。
///
/// ## 为什么要修
///
/// OOXML 规定 `<numFmts>` 里只允许出现 id ≥ 164 的自定义格式；内置格式
/// （0~163）不允许在里面重复声明。但现实中 WPS、部分老版本 Excel、以及
/// 一些报表系统导出时会把内置格式又写一遍，例如：
///
/// ```xml
/// <numFmts count="1">
///   <numFmt numFmtId="41" formatCode="_(* #,##0_);_(* \(#,##0\);_(* &quot;-&quot;_)"/>
/// </numFmts>
/// ```
///
/// `excel` 4.x 的样式解析对这种情况是**直接抛异常**的：
///
/// ```text
/// custom numFmtId starts at 164 but found a value of 41
/// ```
///
/// 于是「导入 Excel 名单」整个功能直接失败，而且错误文本是英文技术细节，
/// 用户完全无法自查。
///
/// ## 怎么修
///
/// xlsx 本质是 zip，这里只动 `xl/styles.xml`：
///
/// 1. 声明侧 `<numFmt numFmtId="N">`
///    - `N >= 164`：合法，不动；
///    - `N < 164` 且是 excel 包已支持的内置格式：**删掉这条冗余声明**
///      （内置格式表里本来就有，删掉不影响引用）；
///    - `N < 164` 且不受支持（如 41/42/43/44）：改成 ≥164 的空闲 id，
///      并同步改写引用侧。
/// 2. 引用侧 `<xf numFmtId="N">`
///    - 若 `N` 被重映射则改成新 id；
///    - 若 `N` 既没声明又不受支持，归零为 General —— 这正是 excel 包在
///      release 下的兜底行为，区别只是不会再把 debug 构建打断。
///
/// 返回修复后的文件字节；**无需修复或修复失败时返回 null**，
/// 调用方按原样处理即可，不要把它当成错误。
Uint8List? repairXlsxNumberFormats(Uint8List bytes) {
  final Archive source;
  try {
    source = ZipDecoder().decodeBytes(bytes);
  } catch (_) {
    return null; // 不是 zip（比如 xls / csv），交给上层报错
  }

  final XmlDocument document;
  try {
    final styles = source.files.where(
      (file) => file.isFile && file.name == _stylesEntryPath,
    );
    if (styles.isEmpty) {
      return null; // 没有样式表，不可能是这个报错
    }
    document = XmlDocument.parse(
      utf8.decode(styles.first.content as List<int>),
    );
  } catch (_) {
    return null;
  }

  if (!_patchStylesSheet(document)) {
    return null;
  }

  final encodedStyles = utf8.encode(_documentToXml(document));
  final rebuilt = Archive();
  for (final file in source.files) {
    // 目录项对 xlsx 读取没有意义（按路径查表），重建时直接丢掉
    if (!file.isFile) {
      continue;
    }
    if (file.name == _stylesEntryPath) {
      rebuilt.addFile(
        ArchiveFile(file.name, encodedStyles.length, encodedStyles),
      );
      continue;
    }
    final content = file.content as List<int>;
    rebuilt.addFile(ArchiveFile(file.name, content.length, content));
  }

  final encoded = ZipEncoder().encode(rebuilt);
  return encoded == null ? null : Uint8List.fromList(encoded);
}

/// 就地修正 styles.xml 的文档树。
///
/// 返回 `true` 表示确实改动了内容（调用方才需要重新打包 zip）。
bool _patchStylesSheet(XmlDocument document) {
  final root = document.rootElement;

  final declarations = <XmlElement>[];
  final groups = <XmlElement>[];
  for (final group in root.findAllElements('numFmts')) {
    groups.add(group);
    declarations.addAll(group.findElements('numFmt'));
  }

  // 现有自定义 id 的最大值之后才是安全的重映射区间，避免撞号
  var nextCustomId = _firstCustomNumFmtId;
  for (final node in declarations) {
    final id = int.tryParse(node.getAttribute('numFmtId') ?? '');
    if (id != null && id >= nextCustomId) {
      nextCustomId = id + 1;
    }
  }

  var changed = false;
  final remap = <int, int>{};
  for (final node in declarations) {
    final id = int.tryParse(node.getAttribute('numFmtId') ?? '');
    if (id == null) {
      node.remove(); // 缺 id 的畸形节点，留着只会继续触发校验
      changed = true;
      continue;
    }
    if (id >= _firstCustomNumFmtId) {
      continue; // 合法的自定义格式
    }
    if (_supportedBuiltinNumFmtIds.contains(id)) {
      // 内置格式的重复声明：删掉即可，excel 包自带这张表
      node.remove();
      changed = true;
      continue;
    }
    final replacement = nextCustomId++;
    remap[id] = replacement;
    node.setAttribute('numFmtId', '$replacement');
    changed = true;
  }

  for (final node in root.findAllElements('xf')) {
    final id = int.tryParse(node.getAttribute('numFmtId') ?? '');
    if (id == null || id >= _firstCustomNumFmtId) {
      continue;
    }
    final replacement = remap[id];
    if (replacement != null) {
      node.setAttribute('numFmtId', '$replacement');
      changed = true;
      continue;
    }
    if (!_supportedBuiltinNumFmtIds.contains(id)) {
      // 悬空引用：归零成 General，与 excel 包 release 下的兜底保持一致
      node.setAttribute('numFmtId', '0');
      changed = true;
    }
  }

  if (changed) {
    // count 是给人看的，改完顺手对齐，免得打开文件时被办公软件提示格式异常
    for (final group in groups) {
      group.setAttribute(
        'count',
        '${group.findElements('numFmt').length}',
      );
    }
  }
  return changed;
}

/// 序列化回 XML 文本，并确保声明里写的是 UTF-8（我们按 UTF-8 重新编码字节）。
String _documentToXml(XmlDocument document) {
  final declaration = document.declaration;
  if (declaration != null) {
    declaration.encoding = 'UTF-8';
  }
  return document.toXmlString();
}
