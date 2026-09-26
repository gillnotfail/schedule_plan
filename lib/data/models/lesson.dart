import 'package:schedule_plan/core/utils/time_utils.dart';

/// 课表条目（readme 3.5 表 lesson）。
///
/// 注意：period_index 是**相对于 class.template_id 所指模板**的节次编号，
/// 不是全局节次，也不存绝对时间；真实时间必须联查 template_period 解析。
class Lesson {
  const Lesson({
    this.id,
    required this.courseId,
    required this.classId,
    required this.teacherId,
    required this.weekday,
    required this.periodIndex,
  });

  final int? id;
  final int courseId;

  /// 冗余存储便于查询，须与 course.class_id 保持一致
  final int classId;
  final int teacherId;

  /// 1 = 周一 ... 7 = 周日
  final int weekday;
  final int periodIndex;

  Lesson copyWith({
    int? id,
    int? courseId,
    int? classId,
    int? teacherId,
    int? weekday,
    int? periodIndex,
  }) {
    return Lesson(
      id: id ?? this.id,
      courseId: courseId ?? this.courseId,
      classId: classId ?? this.classId,
      teacherId: teacherId ?? this.teacherId,
      weekday: weekday ?? this.weekday,
      periodIndex: periodIndex ?? this.periodIndex,
    );
  }

  Map<String, Object?> toMap() => <String, Object?>{
        if (id != null) 'id': id,
        'course_id': courseId,
        'class_id': classId,
        'teacher_id': teacherId,
        'weekday': weekday,
        'period_index': periodIndex,
      };

  static Lesson fromMap(Map<String, Object?> map) => Lesson(
        id: map['id'] as int?,
        courseId: map['course_id'] as int,
        classId: map['class_id'] as int,
        teacherId: map['teacher_id'] as int,
        weekday: map['weekday'] as int,
        periodIndex: map['period_index'] as int,
      );
}

/// 联查模板后解析出真实时间的课表条目。
///
/// readme 3.5 给出的标准查询模式即为此结构：
/// `lesson JOIN class JOIN template_period ON tp.template_id = c.template_id
///  AND tp.weekday = l.weekday AND tp.period_index = l.period_index`
class LessonWithTime {
  const LessonWithTime({
    required this.lesson,
    required this.startTime,
    required this.endTime,
    required this.periodType,
    required this.courseName,
    required this.className,
    required this.classColor,
    required this.templateId,
  });

  final Lesson lesson;
  final String startTime;
  final String endTime;
  final String periodType;
  final String courseName;
  final String className;
  final String classColor;
  final int templateId;

  int get startMinutes => TimeUtils.parseMinutes(startTime);

  int get endMinutes => TimeUtils.parseMinutes(endTime);

  /// 冲突判定必须基于真实时间区间重叠，禁止直接比较 period_index
  /// （readme 第六章「多模板聚合视图冲突检测误判」）。
  bool overlapsWith(LessonWithTime other) =>
      lesson.weekday == other.lesson.weekday &&
      TimeUtils.overlaps(startMinutes, endMinutes, other.startMinutes, other.endMinutes);

  /// 色块内展示的「真实起止时间」，不展示裸的节次编号。
  String get timeRangeText => '$startTime-$endTime';
}

/// 课程格子交换的候选（模块一 1.8）。
class LessonSwapResult {
  const LessonSwapResult({required this.a, required this.b});

  final Lesson a;
  final Lesson b;
}

/// 冲突检测（readme 3.4 节要求编写单元测试覆盖本逻辑）。
///
/// 设计为纯函数，不依赖数据库，便于单元测试直接验证。
abstract final class LessonConflictDetector {
  /// 判断候选课表条目与已有条目是否存在**真实时间区间重叠**。
  ///
  /// - [candidate] 候选条目（含解析后的真实时间）
  /// - [existing] 同一教师同一天的已有条目（含解析后的真实时间）
  /// - [ignoreLessonId] 编辑自身时排除自身
  static List<LessonWithTime> findConflicts({
    required LessonWithTime candidate,
    required List<LessonWithTime> existing,
    int? ignoreLessonId,
  }) {
    final conflicts = <LessonWithTime>[];
    for (final item in existing) {
      if (ignoreLessonId != null && item.lesson.id == ignoreLessonId) {
        continue;
      }
      if (candidate.overlapsWith(item)) {
        conflicts.add(item);
      }
    }
    return conflicts;
  }

  /// 同一班级同一天同一节次是否重复排课（同一模板内节次编号语义一致，可直接比较）。
  static bool hasSameSlot({
    required Lesson candidate,
    required List<Lesson> existing,
    int? ignoreLessonId,
  }) {
    for (final item in existing) {
      if (ignoreLessonId != null && item.id == ignoreLessonId) {
        continue;
      }
      if (item.classId == candidate.classId &&
          item.weekday == candidate.weekday &&
          item.periodIndex == candidate.periodIndex) {
        return true;
      }
    }
    return false;
  }

  /// 交换是否合法：仅允许同一班级同一模板内交换（模块一 1.8）。
  static bool canSwap({
    required LessonWithTime source,
    required LessonWithTime target,
  }) =>
      source.lesson.classId == target.lesson.classId &&
      source.templateId == target.templateId;
}
