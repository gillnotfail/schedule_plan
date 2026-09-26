/// 班级（readme 3.3 表 class）。
class ClassInfo {
  const ClassInfo({
    this.id,
    required this.name,
    required this.grade,
    this.headTeacher,
    this.studentCount = 0,
    required this.color,
    required this.templateId,
    this.sortOrder = 0,
  });

  final int? id;

  /// 如「高一(3)班」
  final String name;

  /// 年级标识，用于批量按年级操作
  final String grade;

  /// 班主任姓名
  final String? headTeacher;

  /// 冗余字段，增删学生时同步更新
  final int studentCount;

  /// 十六进制色值字符串，用于课表格子配色
  final String color;

  /// 绑定的作息模板
  final int templateId;

  /// 班级列表拖拽排序用
  final int sortOrder;

  ClassInfo copyWith({
    int? id,
    String? name,
    String? grade,
    String? headTeacher,
    int? studentCount,
    String? color,
    int? templateId,
    int? sortOrder,
  }) {
    return ClassInfo(
      id: id ?? this.id,
      name: name ?? this.name,
      grade: grade ?? this.grade,
      headTeacher: headTeacher ?? this.headTeacher,
      studentCount: studentCount ?? this.studentCount,
      color: color ?? this.color,
      templateId: templateId ?? this.templateId,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  Map<String, Object?> toMap() => <String, Object?>{
        if (id != null) 'id': id,
        'name': name,
        'grade': grade,
        'head_teacher': headTeacher,
        'student_count': studentCount,
        'color': color,
        'template_id': templateId,
        'sort_order': sortOrder,
      };

  static ClassInfo fromMap(Map<String, Object?> map) => ClassInfo(
        id: map['id'] as int?,
        name: map['name'] as String,
        grade: map['grade'] as String,
        headTeacher: map['head_teacher'] as String?,
        studentCount: map['student_count'] as int? ?? 0,
        color: map['color'] as String,
        templateId: map['template_id'] as int,
        sortOrder: map['sort_order'] as int? ?? 0,
      );
}

/// 课程（readme 3.4 表 course + course_class 关联表）。
///
/// 用户规格：一门课可以挂在**多个班级**上（合班 / 大课），
/// 因此 `classIds` 是集合语义，`course.class_id` 仅作为向后兼容的「主班级」冗余列。
class Course {
  const Course({
    this.id,
    required this.name,
    required this.teacherName,
    this.classIds = const <int>[],
    this.description,
    this.room,
    this.color,
  });

  final int? id;
  final String name;
  final String teacherName;

  /// 上课班级（至少一个；合班场景为多个）
  final List<int> classIds;

  final String? description;

  /// 教室
  final String? room;

  /// 课程标记色（十六进制字符串）。
  ///
  /// `null` = 跟随所属班级的颜色；有值 = 老师给这门课单独指定的颜色。
  /// 课表格子、课程卡片、选课面板都用它决定配色。
  final String? color;

  /// 主班级：写库时同步到 course.class_id，兼容旧查询与旧索引。
  int? get primaryClassId => classIds.isEmpty ? null : classIds.first;

  bool hasClass(int classId) => classIds.contains(classId);

  Course copyWith({
    int? id,
    String? name,
    String? teacherName,
    List<int>? classIds,
    String? description,
    String? room,
    String? color,
  }) {
    return Course(
      id: id ?? this.id,
      name: name ?? this.name,
      teacherName: teacherName ?? this.teacherName,
      classIds: classIds ?? this.classIds,
      description: description ?? this.description,
      room: room ?? this.room,
      color: color ?? this.color,
    );
  }

  Map<String, Object?> toMap() => <String, Object?>{
        if (id != null) 'id': id,
        'name': name,
        'teacher_name': teacherName,
        'class_id': primaryClassId,
        'description': description,
        'room': room,
        'color': color,
      };

  static Course fromMap(
    Map<String, Object?> map, {
    List<int> classIds = const <int>[],
  }) =>
      Course(
        id: map['id'] as int?,
        name: map['name'] as String,
        teacherName: map['teacher_name'] as String,
        classIds: classIds.isNotEmpty
            ? classIds
            : <int>[
                if (map['class_id'] != null) map['class_id'] as int,
              ],
        description: map['description'] as String?,
        room: map['room'] as String?,
        color: map['color'] as String?,
      );
}
