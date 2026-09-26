/// 快速笔记（readme 3.10 表 note，模块五 5.2）。
class Note {
  const Note({
    this.id,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
  });

  final int? id;
  final String content;
  final int createdAt;
  final int updatedAt;

  Note copyWith({
    int? id,
    String? content,
    int? createdAt,
    int? updatedAt,
  }) {
    return Note(
      id: id ?? this.id,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toMap() => <String, Object?>{
        if (id != null) 'id': id,
        'content': content,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  static Note fromMap(Map<String, Object?> map) => Note(
        id: map['id'] as int?,
        content: map['content'] as String,
        createdAt: map['created_at'] as int,
        updatedAt: map['updated_at'] as int,
      );
}

/// AI 拓写操作类型（模块五 5.2：扩写/润色/总结）。
enum AiWritingAction {
  expand,
  polish,
  summarize;

  /// i18n key，界面文案统一走资源文件。
  String get l10nKey => switch (this) {
        AiWritingAction.expand => 'aiActionExpand',
        AiWritingAction.polish => 'aiActionPolish',
        AiWritingAction.summarize => 'aiActionSummarize',
      };
}
