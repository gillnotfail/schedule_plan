import 'package:flutter/foundation.dart';

/// 一条语录（诗词 / 格言 / 歌词 / 祝福）。
///
/// 数据来自 JSON，**不落库**——用户规格（第 21 轮）说"这里可以直接加个 json，
/// 我自己后续可以往里面加"，所以语录是**随包走的资源**而不是用户数据：
/// 改 `assets/data/quotes.json` 重新打包就换一批，不牵动数据库与迁移。
@immutable
class Quote {
  const Quote({required this.text, this.from});

  /// 正文。
  final String text;

  /// 出处：可以是诗人、篇名、书名、歌名；没有出处时为 null。
  final String? from;

  /// 出处是否为空（空串按没有处理）。
  bool get hasFrom => from != null && from!.trim().isNotEmpty;

  /// 宽容解析**单条**：接受三种写法。
  ///
  /// ```json
  /// "大鹏一日同风起，扶摇直上九万里。"
  /// { "text": "…", "from": "李白《上李邕》" }
  /// { "text": "…", "author": "李白" }
  /// ```
  ///
  /// 解析不出来（缺 text / text 不是字符串 / text 全空白）时返回 `null`
  /// 而不是抛异常：这份 JSON 是留给用户自己手写的，写坏一行不该让整块卡片消失。
  static Quote? tryParse(Object? raw) {
    if (raw is String) {
      final text = raw.trim();
      return text.isEmpty ? null : Quote(text: text);
    }
    if (raw is Map) {
      final text = raw['text'] ?? raw['content'] ?? raw['quote'];
      if (text is! String || text.trim().isEmpty) {
        return null;
      }
      final from = raw['from'] ?? raw['author'] ?? raw['source'];
      final fromText = from is String ? from.trim() : '';
      return Quote(
        text: text.trim(),
        from: fromText.isEmpty ? null : fromText,
      );
    }
    return null;
  }

  /// 宽容解析**整份文件**：
  /// - 顶层是数组 → 逐条解析；
  /// - 顶层是对象 → 读 `quotes` / `list` / `items` 里那个数组；
  /// - 其他情况 → 空列表。
  ///
  /// 单条解析失败只跳过那一条，其余照收。
  static List<Quote> parseAll(Object? raw) {
    final List<Object?> items;
    if (raw is List) {
      items = raw;
    } else if (raw is Map) {
      final nested = raw['quotes'] ?? raw['list'] ?? raw['items'];
      items = nested is List ? nested : const <Object?>[];
    } else {
      items = const <Object?>[];
    }
    return <Quote>[
      for (final item in items) ?tryParse(item),
    ];
  }

  @override
  bool operator ==(Object other) =>
      other is Quote && other.text == text && other.from == from;

  @override
  int get hashCode => Object.hash(text, from);

  @override
  String toString() => hasFrom ? '$text —— $from' : text;
}
