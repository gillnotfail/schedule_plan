import 'package:schedule_plan/data/models/class_course.dart';

/// 课程详情聚合（课表页的"课程详情弹窗"与"滑动选课面板"共用）。
///
/// 用户规格：课程弹窗要展示**课程名称、人数、班级、所在教室、班主任**，
/// 课表格子还要按颜色显示。这些字段分散在 `course` / `course_class` /
/// `class` 三张表里，所以在模型层聚合成一个只读视图，避免每个 UI 各拼一遍。
///
/// 配色规则：**课程自己的颜色优先**（新增课程时可单独挑一个），
/// 没挑过（`course.color` 为 NULL）就回落到所属班级的颜色。
/// 班主任始终取所属班级，不往 `student` 加列。
class CourseDetail {
  const CourseDetail({
    required this.course,
    required this.classNames,
    required this.headTeachers,
    required this.studentCount,
    required this.color,
  });

  final Course course;

  /// 上课班级名称，按班级 sort_order 排序
  final List<String> classNames;

  /// 班主任姓名（多个班级时去重），空字符串不参与
  final List<String> headTeachers;

  /// 人数：所选班级的学生数之和（合班课即各班相加，班级之间学生不重复）
  final int studentCount;

  /// 课表格子配色：课程自己指定的颜色 > 第一个所选班级的颜色
  final String color;

  int? get id => course.id;

  String get name => course.name;

  String get room => course.room ?? '';

  /// 颜色是否来自课程自身（而非回落到的班级色）。
  bool get hasOwnColor => (course.color ?? '').isNotEmpty;

  /// 主班级 id（合班课时取第一个），没有班级时返回 null。
  int? get primaryClassIdOrNull =>
      course.classIds.isEmpty ? null : course.classIds.first;

  /// 用已加载的班级列表拼装详情（纯函数，避免每个页面各写一份 JOIN）。
  factory CourseDetail.from(Course course, List<ClassInfo> classes) {
    final ordered = <ClassInfo>[
      for (final id in course.classIds)
        for (final item in classes)
          if (item.id == id) item,
    ];
    final heads = <String>[];
    for (final item in ordered) {
      final name = (item.headTeacher ?? '').trim();
      if (name.isNotEmpty && !heads.contains(name)) {
        heads.add(name);
      }
    }
    final ownColor = (course.color ?? '').trim();
    return CourseDetail(
      course: course,
      classNames: ordered.map((item) => item.name).toList(growable: false),
      headTeachers: heads,
      studentCount: ordered.fold<int>(0, (sum, item) => sum + item.studentCount),
      color: ownColor.isNotEmpty
          ? ownColor
          : (ordered.isEmpty ? '' : ordered.first.color),
    );
  }
}
