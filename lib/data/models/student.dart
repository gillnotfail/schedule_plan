/// 学生（readme 3.6 表 student）。
///
/// 字段必填口径（用户规格）：**姓名、班级必填；性别、学号选填**。
class Student {
  const Student({
    this.id,
    required this.name,
    this.studentNo,
    this.gender,
    required this.classId,
  });

  final int? id;
  final String name;

  /// 学号（选填）
  final String? studentNo;

  /// 性别（选填）
  final StudentGender? gender;

  final int classId;

  Student copyWith({
    int? id,
    String? name,
    String? studentNo,
    StudentGender? gender,
    int? classId,
    bool clearStudentNo = false,
    bool clearGender = false,
  }) {
    return Student(
      id: id ?? this.id,
      name: name ?? this.name,
      studentNo: clearStudentNo ? null : (studentNo ?? this.studentNo),
      gender: clearGender ? null : (gender ?? this.gender),
      classId: classId ?? this.classId,
    );
  }

  Map<String, Object?> toMap() => <String, Object?>{
        if (id != null) 'id': id,
        'name': name,
        'student_no': studentNo,
        'gender': gender?.storageKey,
        'class_id': classId,
      };

  static Student fromMap(Map<String, Object?> map) => Student(
        id: map['id'] as int?,
        name: map['name'] as String,
        studentNo: map['student_no'] as String?,
        gender: StudentGender.fromStorage(map['gender'] as String?),
        classId: map['class_id'] as int,
      );
}

/// 性别（选填，落库为 'male' / 'female'）。
enum StudentGender {
  male,
  female;

  String get storageKey => name;

  static StudentGender? fromStorage(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }
    for (final item in StudentGender.values) {
      if (item.name == value) {
        return item;
      }
    }
    return null;
  }

  /// Excel 导入时对「男 / 女 / M / F / 1 / 0」等写法的容错识别。
  static StudentGender? parse(String? raw) {
    final value = (raw ?? '').trim().toLowerCase();
    if (value.isEmpty) {
      return null;
    }
    if (value.startsWith('男') || value == 'm' || value == 'male' || value == '1') {
      return StudentGender.male;
    }
    if (value.startsWith('女') || value == 'f' || value == 'female' || value == '0') {
      return StudentGender.female;
    }
    return null;
  }
}

/// 学生列表排序方式（模块二 2.4：排序方式记忆在本地）。
enum StudentSortMode {
  namePinyin,
  studentNo,
  attendanceStatus;

  String get storageKey => name;

  static StudentSortMode fromStorage(String? value) => StudentSortMode.values.firstWhere(
        (item) => item.name == value,
        orElse: () => StudentSortMode.namePinyin,
      );
}
