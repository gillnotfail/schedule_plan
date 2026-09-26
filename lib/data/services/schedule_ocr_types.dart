/// 拍照识别课表（第 11 轮）的数据类型。
///
/// 单独一个文件是为了让**解析层**（`schedule_ocr_parser.dart`，纯 Dart）
/// 和**引擎层**（`schedule_ocr_service.dart`，碰原生插件）解耦：
/// 解析层只依赖这里的模型，测试里不 import 任何插件代码。
library;

/// 识别出的一节课（还没落库的草稿）。
class OcrLessonDraft {
  const OcrLessonDraft({
    required this.weekday,
    required this.periodIndex,
    required this.courseName,
    this.startTime,
    this.endTime,
    this.room,
  });

  /// 周几（1~7）。
  final int weekday;

  /// 第几节（相对所绑定的作息模板）。
  final int periodIndex;

  /// 课程名（可能带班级后缀，如"高等数学 3班"）。
  final String courseName;

  /// 识别到的起止时间（可选，格式 "HH:mm"）。
  ///
  /// 有值说明这张课表上印了作息时间，落库时会拿它去校准模板的节次时间。
  final String? startTime;
  final String? endTime;

  /// 识别到的教室（可选）。
  ///
  /// 课表里常写成"数学@101" / "数学 (101)" / "数学 101室"，
  /// 解析不出就不写，落库时保持为空。
  final String? room;

  OcrLessonDraft copyWith({
    int? weekday,
    int? periodIndex,
    String? courseName,
    String? startTime,
    String? endTime,
    String? room,
  }) {
    return OcrLessonDraft(
      weekday: weekday ?? this.weekday,
      periodIndex: periodIndex ?? this.periodIndex,
      courseName: courseName ?? this.courseName,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      room: room ?? this.room,
    );
  }

  /// 稳定的去重键：同一天同一节只保留一条。
  String get slotKey => '$weekday-$periodIndex';

  @override
  String toString() =>
      'OcrLessonDraft($weekday, 第$periodIndex节, $courseName)';
}

/// 一次识别的完整结果。
class ScheduleOcrResult {
  const ScheduleOcrResult({
    required this.drafts,
    required this.weekdayColumns,
    required this.periodRows,
    required this.sourceLineCount,
    required this.warnings,
    required this.confidence,
  });

  const ScheduleOcrResult.empty()
      : drafts = const <OcrLessonDraft>[],
        weekdayColumns = const <int>[],
        periodRows = const <int>[],
        sourceLineCount = 0,
        warnings = const <String>['ocrWarnNoLesson'],
        confidence = 0;

  /// 解析出的课程草稿（已按周几、节次排序）。
  final List<OcrLessonDraft> drafts;

  /// 认出来的星期列（1~7，升序）。
  final List<int> weekdayColumns;

  /// 认出来的节次行（升序）。
  final List<int> periodRows;

  /// 引擎一共吐出多少行文字（用来判断"是不是根本没识别到"）。
  final int sourceLineCount;

  /// 警告键（i18n key），UI 直接翻。
  final List<String> warnings;

  /// 信心分 0~100；-1 表示"没打分"。
  final int confidence;

  bool get isEmpty => drafts.isEmpty;

  /// 涉及多少门不同的课（导入前给老师看的口径）。
  int get distinctCourseCount =>
      drafts.map((item) => item.courseName).toSet().length;

  /// 覆盖了几天。
  int get dayCount => drafts.map((item) => item.weekday).toSet().length;

  ScheduleOcrResult copyWith({
    List<OcrLessonDraft>? drafts,
    List<int>? weekdayColumns,
    List<int>? periodRows,
    int? sourceLineCount,
    List<String>? warnings,
    int? confidence,
  }) {
    return ScheduleOcrResult(
      drafts: drafts ?? this.drafts,
      weekdayColumns: weekdayColumns ?? this.weekdayColumns,
      periodRows: periodRows ?? this.periodRows,
      sourceLineCount: sourceLineCount ?? this.sourceLineCount,
      warnings: warnings ?? this.warnings,
      confidence: confidence ?? this.confidence,
    );
  }
}
