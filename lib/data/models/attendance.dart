import 'package:schedule_plan/data/models/lesson.dart';
import 'package:schedule_plan/data/models/student.dart';

/// 考勤状态（readme 3.7 表 / 模块二 2.5 + 用户规格）。
///
/// 分两类：
/// - **日常状态**：[present] / [late] / [earlyLeave] / [absent] / [leave]，
///   逐节课点名，一次点击落一条 `attendance_record`；
/// - **长期状态**（用户规格）：[suspended] 休学 / [exempt] 免修，
///   点一次就在**这门课**上生效 180 天（见 [CourseStudentStatus]），
///   期间该生沉到名单末尾、不用每节课重复标记；
/// - [unmarked] 只是"还没有记录"的显示态，不作为可选项。
enum AttendanceStatus {
  present,
  late,
  earlyLeave,
  absent,
  leave,
  suspended,
  exempt,
  unmarked;

  String get storageKey => switch (this) {
        AttendanceStatus.present => 'present',
        AttendanceStatus.late => 'late',
        AttendanceStatus.earlyLeave => 'early_leave',
        AttendanceStatus.absent => 'absent',
        AttendanceStatus.leave => 'leave',
        AttendanceStatus.suspended => 'suspended',
        AttendanceStatus.exempt => 'exempt',
        AttendanceStatus.unmarked => 'unmarked',
      };

  /// 是不是「长期状态」（休学 / 免修）：点一次管很久，不逐节课标记。
  bool get isLongTerm =>
      this == AttendanceStatus.suspended || this == AttendanceStatus.exempt;

  /// 日常可点名的五种状态（不含长期状态与"未标记"）。
  static const List<AttendanceStatus> dailyChoices = <AttendanceStatus>[
    AttendanceStatus.present,
    AttendanceStatus.late,
    AttendanceStatus.earlyLeave,
    AttendanceStatus.absent,
    AttendanceStatus.leave,
  ];

  /// 长期状态（休学 / 免修）。
  static const List<AttendanceStatus> longTermChoices = <AttendanceStatus>[
    AttendanceStatus.suspended,
    AttendanceStatus.exempt,
  ];

  /// 一键胶囊上平铺的全部七种状态：日常五种 + 长期两种。
  static const List<AttendanceStatus> choices = <AttendanceStatus>[
    ...dailyChoices,
    ...longTermChoices,
  ];

  static AttendanceStatus fromStorage(String? value) =>
      AttendanceStatus.values.firstWhere(
        (item) => item.storageKey == value,
        orElse: () => AttendanceStatus.unmarked,
      );

  /// 点击学生条目时循环切换的顺序（模块二 2.5：点击快速切换）。
  ///
  /// 长期状态自成一个小环（休学 ⇄ 免修），不会混进日常五态的循环里 ——
  /// 否则顺着点一圈就会莫名其妙把学生标成休学。
  AttendanceStatus get next => switch (this) {
        AttendanceStatus.present => AttendanceStatus.late,
        AttendanceStatus.late => AttendanceStatus.earlyLeave,
        AttendanceStatus.earlyLeave => AttendanceStatus.absent,
        AttendanceStatus.absent => AttendanceStatus.leave,
        AttendanceStatus.leave => AttendanceStatus.present,
        AttendanceStatus.suspended => AttendanceStatus.exempt,
        AttendanceStatus.exempt => AttendanceStatus.suspended,
        AttendanceStatus.unmarked => AttendanceStatus.present,
      };

  /// 是否计入异常出勤（模块三 3.3：列出所有非「出勤」状态的记录）。
  ///
  /// 休学 / 免修**不算异常** —— 它们是有依据的长期状态，不是"这个学生出问题了"，
  /// 混进异常明细只会把真正需要关注的缺勤记录淹掉。
  bool get isAbnormal => this != AttendanceStatus.present && !isLongTerm;

  /// 是否计入缺勤次数（高风险检测口径）。
  bool get countsAsAbsence => this == AttendanceStatus.absent;
}

/// 学生在**某门课程**上的长期状态（休学 / 免修）。
///
/// 用户规格："学生休学，或者体育老师的免修……如果用户一次点了这个学生免修/免修，
/// 那么这个学生就在这个课程里排到后面，不用再每节课标记，时间跨到 180 天。"
///
/// 为什么单开一张表而不是写进 `attendance_record`：
/// 那张表的唯一键是 `(student_id, lesson_id, date)`，天生是**逐节**记录 ——
/// 想让它"管 180 天"就得为未来每一节课预写一条，既写不完也会被课表改动冲掉。
/// 所以长期状态存成一条**带生效区间的课程级记录**，展示时按 `date` 落到区间里判定。
///
/// 区间取闭区间 [startDate, endDate]；日期是 "YYYY-MM-DD" 字符串，
/// 直接按字典序比较即可（与全项目的日期存储口径一致，也规避了时区问题）。
class CourseStudentStatus {
  const CourseStudentStatus({
    this.id,
    required this.studentId,
    required this.courseId,
    required this.status,
    required this.startDate,
    required this.endDate,
    this.note,
  });

  final int? id;
  final int studentId;
  final int courseId;

  /// 只可能是长期状态（休学 / 免修）
  final AttendanceStatus status;

  /// 生效起始日（含）
  final String startDate;

  /// 生效截止日（含）
  final String endDate;
  final String? note;

  /// [date] 这一天是否处于生效区间内。
  bool coversDate(String date) =>
      date.compareTo(startDate) >= 0 && date.compareTo(endDate) <= 0;

  CourseStudentStatus copyWith({
    int? id,
    int? studentId,
    int? courseId,
    AttendanceStatus? status,
    String? startDate,
    String? endDate,
    String? note,
  }) {
    return CourseStudentStatus(
      id: id ?? this.id,
      studentId: studentId ?? this.studentId,
      courseId: courseId ?? this.courseId,
      status: status ?? this.status,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      note: note ?? this.note,
    );
  }

  Map<String, Object?> toMap() => <String, Object?>{
        if (id != null) 'id': id,
        'student_id': studentId,
        'course_id': courseId,
        'status': status.storageKey,
        'start_date': startDate,
        'end_date': endDate,
        'note': note,
      };

  static CourseStudentStatus fromMap(Map<String, Object?> map) =>
      CourseStudentStatus(
        id: map['id'] as int?,
        studentId: map['student_id'] as int,
        courseId: map['course_id'] as int,
        status: AttendanceStatus.fromStorage(map['status'] as String?),
        startDate: map['start_date'] as String,
        endDate: map['end_date'] as String,
        note: map['note'] as String?,
      );
}

/// 考勤记录（readme 3.7 表 attendance_record）。
///
/// 唯一键是 (student_id, lesson_id, date) 而不是 (student_id, course_id, date)，
/// 确保同一天同一门课排两节时两次考勤互不覆盖（模块二 2.7）。
///
/// **为什么要存快照**（用户规格："保存考勤信息后就应该放好久，只要调用就
/// 应该可以立刻读取"）：`lesson_id` 指向的课表条目是**可变的**——老师在课表页
/// 「移出课表」、改课程挂载班级、删除课程，都会让条目消失。如果考勤只存一个
/// 外键，历史记录要么被级联删掉，要么变成一条读不懂的孤儿数据。
/// 所以写入时把「哪天第几节上什么课、哪个班」一起**冗余落库**：
/// - `lesson_id` 可空，条目没了就置空（ON DELETE SET NULL），记录本身留下；
/// - [className] / [courseName] / [weekday] / [periodIndex] / 起止时间
///   是写入那一刻的快照，专供历史查询与导出使用；
/// - [recordedAt] 是**首次标记**的时间戳，[updatedAt] 是最后一次改动 ——
///   重复点名只刷新后者，前者不动，方便追溯"这节课到底什么时候点的名"。
class AttendanceRecord {
  const AttendanceRecord({
    this.id,
    required this.studentId,
    this.lessonId,
    this.classId,
    this.courseId,
    required this.date,
    this.weekday,
    this.periodIndex,
    this.startTime,
    this.endTime,
    this.courseName,
    this.className,
    required this.status,
    this.note,
    this.recordedAt,
    this.updatedAt,
  });

  final int? id;
  final int studentId;

  /// 课表条目 id。条目被删除后置空（历史记录不跟着消失）
  final int? lessonId;

  /// 上课班级 / 课程快照（外键，班级或课程删除后置空）
  final int? classId;
  final int? courseId;

  /// "YYYY-MM-DD"
  final String date;

  /// 1 = 周一 ... 7 = 周日
  final int? weekday;

  /// 第几节（相对 `class.template_id` 指向的作息模板）
  final int? periodIndex;

  /// 该节次的起止时间快照（"HH:mm"）
  final String? startTime;
  final String? endTime;

  /// 课程名 / 班级名快照
  final String? courseName;
  final String? className;

  final AttendanceStatus status;
  final String? note;

  /// 首次标记时间（毫秒时间戳）
  final int? recordedAt;

  /// 最后一次修改时间（毫秒时间戳）
  final int? updatedAt;

  AttendanceRecord copyWith({
    int? id,
    int? studentId,
    int? lessonId,
    int? classId,
    int? courseId,
    String? date,
    int? weekday,
    int? periodIndex,
    String? startTime,
    String? endTime,
    String? courseName,
    String? className,
    AttendanceStatus? status,
    String? note,
    int? recordedAt,
    int? updatedAt,
  }) {
    return AttendanceRecord(
      id: id ?? this.id,
      studentId: studentId ?? this.studentId,
      lessonId: lessonId ?? this.lessonId,
      classId: classId ?? this.classId,
      courseId: courseId ?? this.courseId,
      date: date ?? this.date,
      weekday: weekday ?? this.weekday,
      periodIndex: periodIndex ?? this.periodIndex,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      courseName: courseName ?? this.courseName,
      className: className ?? this.className,
      status: status ?? this.status,
      note: note ?? this.note,
      recordedAt: recordedAt ?? this.recordedAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toMap() => <String, Object?>{
        if (id != null) 'id': id,
        'student_id': studentId,
        'lesson_id': lessonId,
        'class_id': classId,
        'course_id': courseId,
        'date': date,
        'weekday': weekday,
        'period_index': periodIndex,
        'start_time': startTime,
        'end_time': endTime,
        'course_name': courseName,
        'class_name': className,
        'status': status.storageKey,
        'note': note,
        'recorded_at': recordedAt,
        'updated_at': updatedAt,
      };

  /// 从课表条目 + 学生 + 状态，生成一条**带完整快照**的考勤记录。
  ///
  /// 这是"点名"这条路径上唯一该用的构造方式：所有快照字段都从
  /// [LessonWithTime] 一次取齐，避免每个调用点各自拼一遍、漏字段。
  factory AttendanceRecord.forLesson({
    required LessonWithTime lesson,
    required int studentId,
    required String date,
    required AttendanceStatus status,
    String? note,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return AttendanceRecord(
      studentId: studentId,
      lessonId: lesson.lesson.id,
      classId: lesson.lesson.classId,
      courseId: lesson.lesson.courseId,
      date: date,
      weekday: lesson.lesson.weekday,
      periodIndex: lesson.lesson.periodIndex,
      startTime: lesson.startTime,
      endTime: lesson.endTime,
      courseName: lesson.courseName,
      className: lesson.className,
      status: status,
      note: note,
      recordedAt: now,
      updatedAt: now,
    );
  }

  static AttendanceRecord fromMap(Map<String, Object?> map) => AttendanceRecord(
        id: map['id'] as int?,
        studentId: map['student_id'] as int,
        lessonId: map['lesson_id'] as int?,
        classId: map['class_id'] as int?,
        courseId: map['course_id'] as int?,
        date: map['date'] as String,
        weekday: map['weekday'] as int?,
        periodIndex: map['period_index'] as int?,
        startTime: map['start_time'] as String?,
        endTime: map['end_time'] as String?,
        courseName: map['course_name'] as String?,
        className: map['class_name'] as String?,
        status: AttendanceStatus.fromStorage(map['status'] as String?),
        note: map['note'] as String?,
        recordedAt: map['recorded_at'] as int?,
        updatedAt: map['updated_at'] as int?,
      );
}

/// 7 种预设表现标签（readme 3.8 表 / 模块二 2.10）。
enum PerformanceTag {
  activeSpeaking,
  homeworkOnTime,
  focusedListening,
  helpingOthers,
  goodQuestion,
  neatHandwriting,
  teamLeader;

  String get storageKey => name;

  static PerformanceTag fromStorage(String? value) =>
      PerformanceTag.values.firstWhere(
        (item) => item.name == value,
        orElse: () => PerformanceTag.activeSpeaking,
      );

  /// i18n key，界面文案统一走资源文件，禁止拼接。
  String get l10nKey => switch (this) {
        PerformanceTag.activeSpeaking => 'tagActiveSpeaking',
        PerformanceTag.homeworkOnTime => 'tagHomeworkOnTime',
        PerformanceTag.focusedListening => 'tagFocusedListening',
        PerformanceTag.helpingOthers => 'tagHelpingOthers',
        PerformanceTag.goodQuestion => 'tagGoodQuestion',
        PerformanceTag.neatHandwriting => 'tagNeatHandwriting',
        PerformanceTag.teamLeader => 'tagTeamLeader',
      };

  static PerformanceTag? fromL10nKey(String key) {
    for (final tag in PerformanceTag.values) {
      if (tag.l10nKey == key) {
        return tag;
      }
    }
    return null;
  }
}

/// 表现标签记录（readme 3.8 表 student_tag_record）。
class StudentTagRecord {
  const StudentTagRecord({
    this.id,
    required this.studentId,
    required this.date,
    required this.tag,
    this.starRating = 0,
    this.remark,
  });

  final int? id;
  final int studentId;

  /// "YYYY-MM-DD"
  final String date;
  final PerformanceTag tag;

  /// 1-5 星
  final int starRating;
  final String? remark;

  Map<String, Object?> toMap() => <String, Object?>{
        if (id != null) 'id': id,
        'student_id': studentId,
        'date': date,
        'tag': tag.storageKey,
        'star_rating': starRating,
        'remark': remark,
      };

  static StudentTagRecord fromMap(Map<String, Object?> map) => StudentTagRecord(
        id: map['id'] as int?,
        studentId: map['student_id'] as int,
        date: map['date'] as String,
        tag: PerformanceTag.fromStorage(map['tag'] as String?),
        starRating: map['star_rating'] as int? ?? 0,
        remark: map['remark'] as String?,
      );
}

/// 某一天的考勤概览（日历上的「考勤进度圆环」用）。
///
/// 用户规格：日历上的红点换成圆环，**用进度表现当天考勤的百分比**：
/// - 当天没课 → 不画圆环；
/// - 有课但一条记录都没有 → 只有一圈透明描边；
/// - 有记录 → 红色圆弧按 _出勤率_（出勤人次 ÷ 应点名人次）填充。
///
/// 口径解释（一个「人次」= 一节课上的一名学生）：
/// - [expected] 应点名人次 = 当天每节课所属**课程的全部班级**的学生数之和；
///   一门合班课算两个班的学生，与「去点名」里看到的名单完全一致；
/// - [marked] 已点名人次 = 当天落库的考勤记录数（唯一键保证一人一节最多一条）；
/// - [present] 出勤人次 = 其中状态为「出勤」的条数。
///
/// 之所以用**出勤率**而不是"点名完成度"：老师扫一眼月历，想看出的是
/// "哪天班上出勤不正常"，而不是"哪天我忘了点名"——后者从 [hasRecord] 就能看出来。
class AttendanceDayStat {
  const AttendanceDayStat({
    required this.hasLesson,
    required this.expected,
    required this.marked,
    required this.present,
  });

  /// 当天（这个星期几）排了课
  final bool hasLesson;

  /// 应点名人次
  final int expected;

  /// 已点名人次
  final int marked;

  /// 出勤人次
  final int present;

  /// 当天没有课：日历上不画任何标记
  static const AttendanceDayStat none = AttendanceDayStat(
    hasLesson: false,
    expected: 0,
    marked: 0,
    present: 0,
  );

  /// 有没有点过名（决定圆环是"透明描边"还是"红色进度"）
  bool get hasRecord => marked > 0;

  /// 出勤率 0~1。没课或没有应点名人数时返回 0。
  double get rate {
    if (expected <= 0) {
      return 0;
    }
    final value = present / expected;
    if (value.isNaN) {
      return 0;
    }
    return value.clamp(0.0, 1.0);
  }
}

/// 高风险学生条目（模块二 2.9 / 模块三 3.4）。
class RiskStudent {
  const RiskStudent({
    required this.student,
    required this.absentCount,
    required this.lateCount,
    required this.earlyLeaveCount,
    required this.riskScore,
  });

  final Student student;
  final int absentCount;
  final int lateCount;
  final int earlyLeaveCount;

  /// 缺勤 ×3 + 迟到 ×1 + 早退 ×1（权重可在设置中调整）
  final int riskScore;

  bool get isHighRisk => riskScore > 0;
}
