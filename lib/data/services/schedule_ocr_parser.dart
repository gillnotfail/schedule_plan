/// 课表照片 → 结构化课表 的**纯解析层**（第 11 轮）。
///
/// 设计前提（很重要）：**识别引擎只负责把图片变成一行行文字 + 坐标，
/// 所有"这一行到底是周几、第几节、叫什么课"的判断都在这里**。
///
/// 这样做有三个好处：
/// 1. 纯 Dart、零插件依赖 —— 可以在 `flutter test` 里直接跑，不触碰任何原生能力；
/// 2. 引擎换掉（ML Kit ⇄ PaddleOCR ⇄ 系统 Vision）时这层不用动；
/// 3. 解析规则本身可测：手机拍照识别最大的风险不是"认不出字"，
///    而是"字认出来了但排到了错误的格子里"，后者必须靠单测守住。
///
/// 解析流程见 [ScheduleOcrParser.parse]。
library;

import 'dart:math' as math;

import 'package:schedule_plan/data/services/schedule_ocr_types.dart';

/// 单行文字的原始识别结果（坐标归一化到 0~1，原点左上）。
class OcrTextLine {
  const OcrTextLine({
    required this.text,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  /// 识别出的文本。
  final String text;

  /// 归一化坐标（图片宽高各为 1）。
  final double left;
  final double top;
  final double right;
  final double bottom;

  double get centerX => (left + right) / 2;
  double get centerY => (top + bottom) / 2;
  double get width => right - left;
  double get height => bottom - top;

  @override
  String toString() => 'OcrTextLine(${text.trim()} @ ${centerX.toStringAsFixed(3)},'
      '${centerY.toStringAsFixed(3)})';
}

/// 课表照片识别结果的解析器。
///
/// 提供两个入口：
/// - [analyze]：只做"结构化理解"，产出草稿 + 提示，不打分；
/// - [parse]：在 [analyze] 基础上附带置信度评估（UI 用来提示"请核对"）。
class ScheduleOcrParser {
  const ScheduleOcrParser._();

  /// 表头文字里出现这些词，就认为这一行是"周几"表头。
  static const List<List<String>> _weekdayAliases = <List<String>>[
    <String>['星期一', '周一', '礼拜一'],
    <String>['星期二', '周二', '礼拜二'],
    <String>['星期三', '周三', '礼拜三'],
    <String>['星期四', '周四', '礼拜四'],
    <String>['星期五', '周五', '礼拜五'],
    <String>['星期六', '周六', '礼拜六'],
    <String>['星期日', '星期天', '周日', '周天', '礼拜日', '礼拜天'],
  ];

  /// 时间行：08:00-08:40 / 8:00~8:40 / 08:00—08:40（半角全角破折号都认）。
  static final RegExp _timeRangePattern = RegExp(
    r'([0-2]?\d)\s*[:：]\s*([0-5]\d)\s*[-~～—–－至到]\s*'
    r'([0-2]?\d)\s*[:：]\s*([0-5]\d)',
  );

  /// 「1-2」这种"连堂"节次标记。
  static final RegExp _periodRangePattern =
      RegExp(r'^\s*([0-9]{1,2})\s*[-~～—–]\s*([0-9]{1,2})\s*$');

  /// 这些词出现在单元格里就认为**不是**课程名（是排版噪声或栏目标题）。
  ///
  /// 注意：**不要把「早读 / 自习 / 晚自习 / 升旗」放进来**——
  /// 它们在国内课表里是真正占一节的条目，滤掉就等于丢课。
  static const List<String> _noiseWords = <String>[
    '午休',
    '午间',
    '午餐',
    '课间',
    '大课间',
    '休息',
    '放学',
    '备注',
    '课程表',
    '课表',
    '星期',
    '时间',
    '节次',
    '上午',
    '下午',
    '晚上',
    '教师',
    '班级',
    '姓名',
    '合计',
  ];

  /// 结构化理解：把识别出的文字行按位置还原成"周几 × 节次 × 课程名"。
  ///
  /// 算法（不依赖任何列宽假设，因为手机拍的照片会有透视变形）：
  /// 1. 找出所有能识别成周几的行 → 取它们中心的 x 作为列锚点，**按 x 排序**；
  /// 2. 找出所有能识别成节次或时间段的行 → 取中心 y 作为行锚点，**按 y 排序**；
  /// 3. 剩下的行就是"内容行"，把它分配给**最近的列锚点**，
  ///    y 落在哪两行锚点之间就归哪一节；
  /// 4. 同一格出现多行时按 y 顺序拼接（"高等数学"+"3班" → "高等数学 3班"）。
  static ScheduleOcrResult analyze(List<OcrTextLine> lines) {
    final warnings = <String>{};

    // ---- 1. 列锚点（周几） ----
    // 别只看"第一个命中的别名"：「周日」被识别成「周日」还是「星期天」都行，
    // 但一行里同时出现「周一」和「周日」时（有些表头写"周一~周日"），
    // 必须按**最长别名**判定，否则「周日」会被「周一」抢走（子串命中）。
    final columns = <_Anchor>[];
    for (final line in lines) {
      final weekday = _weekdayOf(line.text);
      if (weekday != null) {
        columns.add(_Anchor(position: line.centerX, index: weekday));
      }
    }
    // 同一周几被重复识别（表头两行）时保留最上面那个
    final columnByWeekday = <int, _Anchor>{};
    for (final anchor in columns) {
      final current = columnByWeekday[anchor.index];
      if (current == null || anchor.position < current.position) {
        columnByWeekday[anchor.index] = anchor;
      }
    }
    final orderedColumns = columnByWeekday.values.toList()
      ..sort((a, b) => a.position.compareTo(b.position));

    // ---- 2. 行锚点（节次） ----
    // 时间段既可能跟在节次同一行（"第1节 08:00-08:40"），
    // 也可能被引擎拆成单独一行（"第1节" / "08:00-08:40"）——两种都要认。
    // 拆成两行的情况用 y 就近挂到节次锚点上（后面统一处理）。
    final rowAnchors = <_Anchor>[];
    final looseTimes = <({double y, _MinuteRange range})>[];
    for (final line in lines) {
      final period = _periodOf(line.text);
      if (period != null) {
        rowAnchors.add(_Anchor(position: line.centerY, index: period));
        final inline = _timeRangeOf(line.text);
        if (inline != null) {
          looseTimes.add((y: line.centerY, range: inline));
        }
        continue;
      }
      final standalone = _timeRangeOf(line.text);
      if (standalone != null) {
        looseTimes.add((y: line.centerY, range: standalone));
      }
    }
    final rowByPeriod = <int, _Anchor>{};
    for (final anchor in rowAnchors) {
      final current = rowByPeriod[anchor.index];
      if (current == null || anchor.position < current.position) {
        rowByPeriod[anchor.index] = anchor;
      }
    }
    final orderedRows = rowByPeriod.values.toList()
      ..sort((a, b) => a.position.compareTo(b.position));

    // 把收集到的时间段挂到最近的节次行上（同一节多次出现时保留更近的那条）
    final timeRanges = <int, _MinuteRange>{};
    final timeDistance = <int, double>{};
    for (final item in looseTimes) {
      final row = _rowFor(orderedRows, item.y);
      if (row == null) {
        continue;
      }
      final distance = (row.position - item.y).abs();
      final best = timeDistance[row.index];
      if (best == null || distance < best) {
        timeDistance[row.index] = distance;
        timeRanges[row.index] = item.range;
      }
    }

    // ---- 3. 内容行分配 ----
    final buckets = <int, Map<int, List<OcrTextLine>>>{};
    for (final line in lines) {
      if (_weekdayOf(line.text) != null) {
        continue;
      }
      if (_periodOf(line.text) != null) {
        continue;
      }
      final text = _clean(line.text);
      if (text.isEmpty || _isNoise(text)) {
        continue;
      }
      if (orderedColumns.isEmpty || orderedRows.isEmpty) {
        continue;
      }
      final column = _nearest(orderedColumns, line.centerX);
      final row = _rowFor(orderedRows, line.centerY);
      if (column == null || row == null) {
        continue;
      }
      // 离得太远说明这一行落在表格外面（页眉页脚 / 手写批注）
      if ((line.centerX - column.position).abs() > _columnTolerance(orderedColumns)) {
        continue;
      }
      buckets
          .putIfAbsent(row.index, () => <int, List<OcrTextLine>>{})
          .putIfAbsent(column.index, () => <OcrTextLine>[])
          .add(line);
    }

    // ---- 4. 组装草稿 ----
    // 注意 buckets 的键序是 **[节次][周几]**（上面先 putIfAbsent(row) 再 putIfAbsent(column)）。
    // 组装时把它摊平后按 **周几 → 节次** 排序输出：UI 是按天分段展示的，
    // 先按周几分组才是"读起来顺"的顺序（曾经把键序搞反，导致第 2 节被写成第 1 节）。
    final slots = <({int weekday, int period, List<OcrTextLine> items})>[];
    for (final period in buckets.keys) {
      for (final weekday in buckets[period]!.keys) {
        final items = buckets[period]![weekday]!
          ..sort((a, b) => a.centerY.compareTo(b.centerY));
        slots.add((weekday: weekday, period: period, items: items));
      }
    }
    slots.sort((a, b) {
      final byDay = a.weekday.compareTo(b.weekday);
      return byDay != 0 ? byDay : a.period.compareTo(b.period);
    });

    final drafts = <OcrLessonDraft>[];
    for (final slot in slots) {
      final name = slot.items
          .map((item) => _clean(item.text))
          .where((item) => item.isNotEmpty)
          .join(' ')
          .trim();
      if (name.isEmpty) {
        continue;
      }
      final split = _splitRoom(name);
      drafts.add(
        OcrLessonDraft(
          weekday: slot.weekday,
          periodIndex: slot.period,
          courseName: _truncate(split.courseName),
          startTime: timeRanges[slot.period]?.start,
          endTime: timeRanges[slot.period]?.end,
          room: split.room,
        ),
      );
    }

    if (orderedColumns.isEmpty) {
      warnings.add('ocrWarnNoWeekday');
    } else if (orderedColumns.length < 7) {
      warnings.add('ocrWarnPartialWeekday');
    }
    if (orderedRows.isEmpty) {
      warnings.add('ocrWarnNoPeriod');
    }
    if (drafts.isEmpty) {
      warnings.add('ocrWarnNoLesson');
    }

    return ScheduleOcrResult(
      drafts: drafts,
      weekdayColumns: orderedColumns.map((item) => item.index).toList()..sort(),
      periodRows: orderedRows.map((item) => item.index).toList()..sort(),
      sourceLineCount: lines.length,
      warnings: warnings.toList(),
      // analyze 不带信心分：需要打分的场景调 [parse]
      confidence: drafts.isEmpty ? 0 : -1,
    );
  }

  /// 结构化 + 置信度评估（UI 用它决定要不要把"请核对"提示挂出来）。
  static ScheduleOcrResult parse(List<OcrTextLine> lines) {
    final base = analyze(lines);
    if (base.drafts.isEmpty) {
      return base;
    }
    return base.copyWith(confidence: _score(base));
  }

  /// 信心分口径（0~100，纯启发式，**只用来决定提示强度，不拦截导入**）。
  ///
  /// - 认出 5 天以上 +30；认出 3 天以上 +18
  /// - 认出 5 节以上 +25；认出 3 节以上 +15
  /// - 每 5 条课程 +10，封顶 35
  /// - 有真实时间段 +10（说明识别到了作息，不是纯格子）
  static int _score(ScheduleOcrResult result) {
    var score = 0;
    final days = result.weekdayColumns.length;
    if (days >= 5) {
      score += 30;
    } else if (days >= 3) {
      score += 18;
    } else if (days > 0) {
      score += 8;
    }
    final periods = result.periodRows.length;
    if (periods >= 5) {
      score += 25;
    } else if (periods >= 3) {
      score += 15;
    } else if (periods > 0) {
      score += 6;
    }
    score += math.min(35, (result.drafts.length ~/ 5) * 10);
    if (result.drafts.any((item) => item.startTime != null)) {
      score += 10;
    }
    return math.min(100, score);
  }

  // ---------------------------------------------------------------------------
  // 词法识别
  // ---------------------------------------------------------------------------

  /// 「周一」「星期一」「礼拜一」→ 1~7；认不出返回 null。
  ///
  /// **必须按最长别名判定**：`indexOf` 式的"第一个命中"会让「周日」里的
  /// "周"被「周一」抢走（"周日".contains("周一") 为 false，但
  /// "周一、周二、周日"这种合并成一行的情况，"周一"会先命中而丢掉"周日"）。
  static int? _weekdayOf(String raw) {
    final text = _clean(raw).replaceAll(' ', '');
    if (text.isEmpty) {
      return null;
    }
    var bestLength = 0;
    int? bestWeekday;
    for (var i = 0; i < _weekdayAliases.length; i++) {
      for (final alias in _weekdayAliases[i]) {
        if (alias.length > bestLength && text.contains(alias)) {
          bestLength = alias.length;
          bestWeekday = i + 1;
        }
      }
    }
    return bestWeekday;
  }

  /// 「第 3 节」「3」「三」→ 3；认不出返回 null。
  ///
  /// 注意两点：
  /// - 「1-2」这种连堂标记取起始节；
  /// - **别把时间段里的数字当节次**：`08:50-09:30` 里 50、09、30 都是数字，
  ///   只有"带「节」字"或"整行就是一个孤立数字"才算节次。
  static int? _periodOf(String raw) {
    final text = _clean(raw);
    if (text.isEmpty) {
      return null;
    }
    // 先剔掉时间片段，避免 "第1节 08:00-08:40" 之外那种纯时间行（"08:00-08:40"）
    // 被下面的裸数字规则误判成第 8 节
    final withoutTime = text.replaceAll(_timeRangePattern, ' ').trim();
    if (withoutTime.isEmpty) {
      return null;
    }
    final compact = withoutTime.replaceAll(' ', '');

    // 「1-2」连堂
    final range = _periodRangePattern.firstMatch(compact);
    if (range != null) {
      return _validPeriod(int.tryParse(range.group(1)!));
    }
    // 「第N节」
    final numbered = RegExp(r'第\s*([0-9]{1,2})\s*节').firstMatch(compact);
    if (numbered != null) {
      return _validPeriod(int.tryParse(numbered.group(1)!));
    }
    // 整行就是「N节」（OCR 常把"第"丢字）
    final bare = RegExp(r'^([0-9]{1,2})\s*节$').firstMatch(compact);
    if (bare != null) {
      return _validPeriod(int.tryParse(bare.group(1)!));
    }
    // 整行就是一个孤立数字 / 中文数字（早读那一行只有"1"）
    if (RegExp(r'^[0-9]{1,2}$').hasMatch(compact)) {
      return _validPeriod(int.tryParse(compact));
    }
    return _validPeriod(_chineseNumber(compact));
  }

  static int? _validPeriod(int? value) {
    if (value == null || value < 1 || value > 20) {
      return null;
    }
    return value;
  }

  /// 中文数字（一二三……十五）转 int，认不出返回 null。
  static int? _chineseNumber(String text) {
    const digits = <String, int>{
      '一': 1, '二': 2, '三': 3, '四': 4, '五': 5,
      '六': 6, '七': 7, '八': 8, '九': 9, '十': 10,
    };
    if (text.isEmpty) {
      return null;
    }
    if (text.length == 1) {
      return digits[text];
    }
    // 十一 ~ 十九 / 二十
    if (text.startsWith('十')) {
      return 10 + (digits[text.substring(1)] ?? 0);
    }
    if (text.startsWith('二') && text.endsWith('十')) {
      return 20;
    }
    if (text.contains('十')) {
      final parts = text.split('十');
      final tens = digits[parts.first] ?? 1;
      final ones = parts.length > 1 ? (digits[parts[1]] ?? 0) : 0;
      return tens * 10 + ones;
    }
    return null;
  }

  /// 从一行文字里抽出「HH:mm ~ HH:mm」。
  static _MinuteRange? _timeRangeOf(String raw) {
    final match = _timeRangePattern.firstMatch(_clean(raw));
    if (match == null) {
      return null;
    }
    final start = int.parse(match.group(1)!) * 60 + int.parse(match.group(2)!);
    final end = int.parse(match.group(3)!) * 60 + int.parse(match.group(4)!);
    if (end <= start || start < 0 || end > 24 * 60) {
      return null;
    }
    return _MinuteRange(start: _asHhMm(start), end: _asHhMm(end));
  }

  static String _asHhMm(int minutes) {
    final hour = (minutes ~/ 60).toString().padLeft(2, '0');
    final minute = (minutes % 60).toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  // ---------------------------------------------------------------------------
  // 工具
  // ---------------------------------------------------------------------------

  /// 去空白 + 去常见排版噪声字符（表格线、项目符号识别出来会混进文字）。
  static String _clean(String raw) {
    return raw
        .replaceAll(RegExp(r'[\u0000-\u001f]'), '')
        .replaceAll(RegExp(r'[|｜\[\]【】<>《》]'), '')
        .replaceAll(RegExp(r'[·•·‥…]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// 明显不是课程名的内容（午休、备注、花体表头残留等）。
  static bool _isNoise(String text) {
    final compact = text.replaceAll(' ', '');
    for (final word in _noiseWords) {
      if (compact == word) {
        return true;
      }
    }
    // 纯标点 / 纯数字（页码、日期）也不是课程名
    if (!compact.contains(RegExp(r'[\u4e00-\u9fa5A-Za-z]'))) {
      return true;
    }
    // 太短的单字（识别碎片）
    return compact.length < 2;
  }

  /// 课程名上限，太长的多半是把相邻几格拼在一起了。
  static String _truncate(String text) =>
      text.length <= _maxCourseNameLength ? text : text.substring(0, _maxCourseNameLength);

  static const int _maxCourseNameLength = 30;

  /// 从"数学@101""数学(101)""数学 101室"里拆出课程名与教室。
  ///
  /// 只要不确信就**不动原文**：把"高一(3)班"里的"(3)"当成教室是最典型的误伤，
  /// 所以只有"括号里是纯数字/字母房间号"或"明确带 @ 或「室/楼」后缀"才拆。
  static ({String courseName, String? room}) _splitRoom(String text) {
    // 带 @ 的写法最明确
    final at = RegExp(r'^(.+?)\s*[@＠]\s*([0-9A-Za-z\-]{1,12})$').firstMatch(text);
    if (at != null) {
      return (courseName: at.group(1)!.trim(), room: at.group(2)!.trim());
    }
    // 「101室 / 教学楼 / A栋」这类带房间特征后缀的写法
    final suffix = RegExp(r'^(.+?)\s+([0-9A-Za-z\-]{1,6}(?:室|楼|栋))$').firstMatch(text);
    if (suffix != null) {
      return (courseName: suffix.group(1)!.trim(), room: suffix.group(2)!.trim());
    }
    // 括号里全是房间号特征（数字为主，可带字母/短横）
    final paren = RegExp(r'^(.+?)\s*[（(]\s*([0-9A-Za-z\-]{1,8})\s*[)）]$').firstMatch(text);
    if (paren != null && RegExp(r'\d').hasMatch(paren.group(2)!)) {
      return (courseName: paren.group(1)!.trim(), room: paren.group(2)!.trim());
    }
    return (courseName: text, room: null);
  }

  static _Anchor? _nearest(List<_Anchor> anchors, double position) {
    _Anchor? best;
    var bestDistance = double.infinity;
    for (final anchor in anchors) {
      final distance = (anchor.position - position).abs();
      if (distance < bestDistance) {
        bestDistance = distance;
        best = anchor;
      }
    }
    return best;
  }

  /// 行锚点：取中心 y 落在哪两个锚点的"分界线"之内。
  ///
  /// 用中点分界而不是"最近锚点"，因为节次行高不均匀（早读常压缩成一行），
  /// 中点分界对不均匀行高更宽容。
  ///
  /// 首尾锚点之外**不直接丢弃**：OCR 给的包围盒常常比表格行窄一点点，
  /// 第一格里那句"高等数学"的 y 中心可能比"第1节"表头高几个像素。
  /// 所以只在超出"半行"容量时才判定落在表外。
  static _Anchor? _rowFor(List<_Anchor> anchors, double position) {
    if (anchors.isEmpty) {
      return null;
    }
    final first = anchors.first;
    if (position < first.position) {
      final slack = anchors.length > 1
          ? (anchors[1].position - first.position) / 2
          : _singleRowSlack;
      return (first.position - position) <= slack ? first : null;
    }
    final last = anchors.last;
    if (position > last.position) {
      final slack = anchors.length > 1
          ? (last.position - anchors[anchors.length - 2].position) / 2
          : _singleRowSlack;
      return (position - last.position) <= slack ? last : null;
    }
    for (var i = 0; i < anchors.length - 1; i++) {
      final middle = (anchors[i].position + anchors[i + 1].position) / 2;
      if (position <= middle) {
        return anchors[i];
      }
    }
    return last;
  }

  /// 表里只认出一个节次锚点时的上下容差（归一化坐标，约半行高）。
  static const double _singleRowSlack = 0.04;

  /// 列容差：列锚点平均间距的一半（再留 5% 余量给透视变形）。
  static double _columnTolerance(List<_Anchor> columns) {
    if (columns.length < 2) {
      return 0.5;
    }
    var total = 0.0;
    for (var i = 0; i < columns.length - 1; i++) {
      total += columns[i + 1].position - columns[i].position;
    }
    return (total / (columns.length - 1)) * 0.6;
  }
}

class _Anchor {
  const _Anchor({required this.position, required this.index});

  final double position;
  final int index;
}

class _MinuteRange {
  const _MinuteRange({required this.start, required this.end});

  final String start;
  final String end;
}
