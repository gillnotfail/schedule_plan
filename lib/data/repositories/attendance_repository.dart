import 'package:sqflite/sqflite.dart' hide DatabaseException;

import 'package:schedule_plan/core/constants/app_constants.dart';
import 'package:schedule_plan/core/error/app_exceptions.dart';
import 'package:schedule_plan/core/logging/app_logger.dart';
import 'package:schedule_plan/core/utils/date_utils.dart';
import 'package:schedule_plan/data/db/app_database.dart';
import 'package:schedule_plan/data/models/attendance.dart';
import 'package:schedule_plan/data/models/lesson.dart';
import 'package:schedule_plan/data/models/student.dart';

/// 考勤记录数据访问层（readme 3.7 表）。
///
/// 唯一键 (student_id, lesson_id, date)：同天同课程不同节次考勤独立记录，
/// 互不覆盖（模块二 2.7）。
class AttendanceRepository {
  AttendanceRepository({Database? database}) : _db = database;

  Database? _db;

  Future<Database> get _database async => _db ??= await AppDatabase.instance();

  /// 某一节课某一天的全部考勤记录。
  Future<List<AttendanceRecord>> forLessonDate(
    int lessonId,
    String date,
  ) async {
    final db = await _database;
    final rows = await db.query(
      'attendance_record',
      where: 'lesson_id = ? AND date = ?',
      whereArgs: <Object?>[lessonId, date],
    );
    return rows.map(AttendanceRecord.fromMap).toList();
  }

  /// 写入/更新一条考勤记录（按唯一键 UPSERT）。
  ///
  /// 用 `ON CONFLICT ... DO UPDATE` 而不是 `ConflictAlgorithm.replace`：
  /// replace 是"删掉旧行再插新行"，会把 `recorded_at`（首次标记时间）一起重置成
  /// 现在，追溯"这节课什么时候点的名"就永远查不到了。这里只刷新
  /// status / note / updated_at，首次标记时间原地不动。
  Future<void> upsert(AttendanceRecord record) async {
    final db = await _database;
    final now = DateTime.now().millisecondsSinceEpoch;
    try {
      await db.rawInsert(
        '''
        INSERT INTO attendance_record (
          student_id, lesson_id, class_id, course_id, date, weekday, period_index,
          start_time, end_time, course_name, class_name, status, note,
          recorded_at, updated_at
        ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
        ON CONFLICT(student_id, lesson_id, date) DO UPDATE SET
          class_id = excluded.class_id,
          course_id = excluded.course_id,
          weekday = excluded.weekday,
          period_index = excluded.period_index,
          start_time = excluded.start_time,
          end_time = excluded.end_time,
          course_name = excluded.course_name,
          class_name = excluded.class_name,
          status = excluded.status,
          note = excluded.note,
          updated_at = excluded.updated_at
        ''',
        <Object?>[
          record.studentId,
          record.lessonId,
          record.classId,
          record.courseId,
          record.date,
          record.weekday,
          record.periodIndex,
          record.startTime,
          record.endTime,
          record.courseName,
          record.className,
          record.status.storageKey,
          record.note,
          record.recordedAt ?? now,
          record.updatedAt ?? now,
        ],
      );
    } catch (error, stack) {
      AppLogger.e('写入考勤记录失败', error: error, stack: stack);
      throw DatabaseException('写入考勤记录失败：$error', cause: error);
    }
  }

  /// 点一下就把某个学生在这节课上的状态落库（用户规格：状态一个一个点，点完即存）。
  ///
  /// 写的是 [AttendanceRecord.forLesson] 生成的**带完整快照**的记录，
  /// 这样课表条目将来被清空 / 课程被删除，历史考勤依旧能独立读懂。
  Future<void> mark({
    required LessonWithTime lesson,
    required int studentId,
    required String date,
    required AttendanceStatus status,
    String? note,
  }) => upsert(
    AttendanceRecord.forLesson(
      lesson: lesson,
      studentId: studentId,
      date: date,
      status: status,
      note: note,
    ),
  );

  Future<void> deleteRecord(int id) async {
    final db = await _database;
    await db.delete(
      'attendance_record',
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  /// 未记录过的日期默认全部学生状态由调用方决定（present 或 unmarked）。
  /// 此处只返回已落库的记录，缺省由上层按设置填充。
  Future<Map<int, AttendanceRecord>> mapForLessonDate(
    int lessonId,
    String date,
  ) async {
    final records = await forLessonDate(lessonId, date);
    return <int, AttendanceRecord>{
      for (final record in records) record.studentId: record,
    };
  }

  /// 表现标签记录（readme 3.8 表）。
  Future<List<StudentTagRecord>> tagsForStudentDate(
    int studentId,
    String date,
  ) async {
    final db = await _database;
    final rows = await db.query(
      'student_tag_record',
      where: 'student_id = ? AND date = ?',
      whereArgs: <Object?>[studentId, date],
    );
    return rows.map(StudentTagRecord.fromMap).toList();
  }

  Future<void> upsertTag(StudentTagRecord record) async {
    final db = await _database;
    await db.insert(
      'student_tag_record',
      record.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 统计某学生在某时间范围内的各状态次数（高风险检测用）。
  Future<Map<String, int>> statusCountsForStudent(
    int studentId, {
    required String fromDate,
    required String toDate,
  }) async {
    final db = await _database;
    final rows = await db.rawQuery(
      '''
      SELECT status, COUNT(*) AS cnt
      FROM attendance_record
      WHERE student_id = ? AND date BETWEEN ? AND ?
      GROUP BY status
      ''',
      <Object?>[studentId, fromDate, toDate],
    );
    return <String, int>{
      for (final row in rows)
        row['status'] as String: (row['cnt'] as int?) ?? 0,
    };
  }

  /// 高风险学生排名（模块三 3.4）：按加权计分降序。
  ///
  /// 分数 = 缺勤 × wAbsent + 迟到 × wLate + 早退 × wEarly（权重来自设置）。
  Future<List<RiskStudent>> riskRanking({
    int? classId,
    int? courseId,
    required String fromDate,
    required String toDate,
    required int weightAbsent,
    required int weightLate,
    required int weightEarlyLeave,
  }) async {
    final db = await _database;
    final where = <String>['a.date BETWEEN ? AND ?'];
    final args = <Object?>[fromDate, toDate];
    if (classId != null) {
      where.add('s.class_id = ?');
      args.add(classId);
    }
    if (courseId != null) {
      // attendance_record 冗余了 course_id 快照，无需再 join lesson
      where.add('a.course_id = ?');
      args.add(courseId);
    }
    final rows = await db.rawQuery('''
      SELECT s.id, s.name, s.student_no, s.class_id,
             SUM(CASE WHEN a.status = 'absent' THEN 1 ELSE 0 END) AS absent_count,
             SUM(CASE WHEN a.status = 'late' THEN 1 ELSE 0 END) AS late_count,
             SUM(CASE WHEN a.status = 'early_leave' THEN 1 ELSE 0 END) AS early_count
      FROM student s
      JOIN attendance_record a ON a.student_id = s.id
      WHERE ${where.join(' AND ')}
      GROUP BY s.id
      ''', args);
    final result = rows.map((row) {
      final absent = (row['absent_count'] as int?) ?? 0;
      final late = (row['late_count'] as int?) ?? 0;
      final early = (row['early_count'] as int?) ?? 0;
      return RiskStudent(
        student: Student(
          id: row['id'] as int,
          name: row['name'] as String,
          studentNo: row['student_no'] as String?,
          classId: row['class_id'] as int,
        ),
        absentCount: absent,
        lateCount: late,
        earlyLeaveCount: early,
        riskScore:
            absent * weightAbsent +
            late * weightLate +
            early * weightEarlyLeave,
      );
    }).toList();
    result.sort((a, b) => b.riskScore.compareTo(a.riskScore));
    return result;
  }

  /// 某班级某时间范围内的各状态计数（出勤摘要 / 出勤率用）。
  Future<Map<String, int>> summaryForClass(
    int classId, {
    required String fromDate,
    required String toDate,
  }) async {
    final db = await _database;
    final rows = await db.rawQuery(
      '''
      SELECT a.status AS status, COUNT(*) AS cnt
      FROM attendance_record a
      JOIN student s ON s.id = a.student_id
      WHERE s.class_id = ? AND a.date BETWEEN ? AND ?
      GROUP BY a.status
      ''',
      <Object?>[classId, fromDate, toDate],
    );
    return <String, int>{
      for (final row in rows)
        row['status'] as String: (row['cnt'] as int?) ?? 0,
    };
  }

  /// 导出考勤汇总行（模块三 3.6 Sheet1）。
  ///
  /// 全部用 LEFT JOIN + COALESCE：课表条目 / 课程 / 班级被删掉之后，
  /// 记录里冗余的快照照旧能把这一行讲清楚（见 [AttendanceRecord] 的说明）。
  Future<List<Map<String, Object?>>> exportSummary({
    required String fromDate,
    required String toDate,
    int? classId,
    int? courseId,
  }) async {
    final db = await _database;
    final where = <String>['a.date BETWEEN ? AND ?'];
    final args = <Object?>[fromDate, toDate];
    if (classId != null) {
      where.add('COALESCE(a.class_id, l.class_id) = ?');
      args.add(classId);
    }
    if (courseId != null) {
      where.add('COALESCE(a.course_id, l.course_id) = ?');
      args.add(courseId);
    }
    return db.rawQuery('''
      SELECT COALESCE(a.class_name, c.name) AS class_name,
             COALESCE(a.course_name, co.name) AS course_name,
             a.date AS date, a.status AS status, COUNT(*) AS cnt
      FROM attendance_record a
      LEFT JOIN lesson l ON l.id = a.lesson_id
      LEFT JOIN course co ON co.id = COALESCE(a.course_id, l.course_id)
      LEFT JOIN class c ON c.id = COALESCE(a.class_id, l.class_id)
      WHERE ${where.join(' AND ')}
      GROUP BY COALESCE(a.class_name, c.name),
               COALESCE(a.course_name, co.name),
               a.date, a.status
      ORDER BY a.date ASC, class_name ASC
      ''', args);
  }

  /// 异常出勤明细（模块三 3.3：所有非 present 状态的记录）。
  Future<List<Map<String, Object?>>> abnormalDetails({
    required String fromDate,
    required String toDate,
    int? classId,
    int? courseId,
    AttendanceStatus? status,
  }) async {
    final db = await _database;
    final clauses = <String>['a.date BETWEEN ? AND ?', "a.status <> 'present'"];
    final args = <Object?>[fromDate, toDate];
    if (classId != null) {
      clauses.add('COALESCE(a.class_id, l.class_id) = ?');
      args.add(classId);
    }
    if (courseId != null) {
      clauses.add('COALESCE(a.course_id, l.course_id) = ?');
      args.add(courseId);
    }
    if (status != null) {
      clauses.add('a.status = ?');
      args.add(status.storageKey);
    }
    return db.rawQuery('''
      SELECT a.date AS date, s.name AS student_name, s.student_no AS student_no,
             COALESCE(a.class_name, c.name) AS class_name,
             COALESCE(a.course_name, co.name) AS course_name,
             COALESCE(a.start_time, tp.start_time) AS start_time,
             COALESCE(a.end_time, tp.end_time) AS end_time,
             a.status AS status, a.note AS note
      FROM attendance_record a
      JOIN student s ON s.id = a.student_id
      LEFT JOIN lesson l ON l.id = a.lesson_id
      LEFT JOIN course co ON co.id = COALESCE(a.course_id, l.course_id)
      LEFT JOIN class c ON c.id = COALESCE(a.class_id, l.class_id)
      LEFT JOIN template_period tp
        ON tp.template_id = c.template_id
       AND tp.weekday = COALESCE(a.weekday, l.weekday)
       AND tp.period_index = COALESCE(a.period_index, l.period_index)
      WHERE ${clauses.join(' AND ')}
      ORDER BY a.date DESC, COALESCE(a.start_time, tp.start_time) ASC
      ''', args);
  }

  /// 「受益学生数」：给定区间内**被点过名的去重总人数**（教学成果的情绪价值指标）。
  ///
  /// 用户规格（第 10 轮）："受益学生数可以是去重统计过的总人数。"
  /// 一个学生被点过 5 节课也只算 1 个 —— 用 `COUNT(DISTINCT student_id)`。
  Future<int> distinctStudentCount({
    required String fromDate,
    required String toDate,
  }) async {
    final db = await _database;
    final rows = await db.rawQuery(
      '''
      SELECT COUNT(DISTINCT student_id) AS cnt
      FROM attendance_record
      WHERE date BETWEEN ? AND ?
      ''',
      <Object?>[fromDate, toDate],
    );
    return (rows.isEmpty ? 0 : (rows.first['cnt'] as int? ?? 0));
  }

  /// 按**班级**的出勤率（教学成果页"出勤率最高 / 最低的班级"数据源）。
  ///
  /// 与 [attendanceRateByCourse] 的差别只在分组维度：那个按"班级 × 课程"分，
  /// 适合柱状图；这里按班级合并，一个班一行，用来挑最好的和最差的。
  /// 班级名一律走 `COALESCE(a.class_name, c.name)`——课程被删掉之后
  /// 记录里冗余的快照还认得出是哪个班。
  Future<List<Map<String, Object?>>> attendanceRateByClass({
    required String fromDate,
    required String toDate,
  }) async {
    final db = await _database;
    return db.rawQuery(
      '''
      SELECT COALESCE(a.class_name, c.name) AS class_name,
             SUM(CASE WHEN a.status = 'present' THEN 1 ELSE 0 END) AS present_count,
             COUNT(*) AS total_count
      FROM attendance_record a
      LEFT JOIN lesson l ON l.id = a.lesson_id
      LEFT JOIN class c ON c.id = COALESCE(a.class_id, l.class_id)
      WHERE a.date BETWEEN ? AND ?
      GROUP BY COALESCE(a.class_name, c.name)
      ORDER BY class_name ASC
      ''',
      <Object?>[fromDate, toDate],
    );
  }

  /// 按日/周/月的出勤率序列（模块三 3.1 折线图）。
  Future<List<Map<String, Object?>>> attendanceRateSeries({
    required String fromDate,
    required String toDate,
    int? classId,
  }) async {
    final db = await _database;
    return db.rawQuery(
      '''
      SELECT a.date AS date,
             SUM(CASE WHEN a.status = 'present' THEN 1 ELSE 0 END) AS present_count,
             COUNT(*) AS total_count
      FROM attendance_record a
      JOIN student s ON s.id = a.student_id
      WHERE a.date BETWEEN ? AND ? ${classId == null ? '' : 'AND s.class_id = ?'}
      GROUP BY a.date
      ORDER BY a.date ASC
      ''',
      classId == null
          ? <Object?>[fromDate, toDate]
          : <Object?>[fromDate, toDate, classId],
    );
  }

  /// 按课程/班级的出勤率（模块三 3.2 柱状图）。
  Future<List<Map<String, Object?>>> attendanceRateByCourse({
    required String fromDate,
    required String toDate,
    int? classId,
    int? courseId,
  }) async {
    final db = await _database;
    final where = <String>['a.date BETWEEN ? AND ?'];
    final args = <Object?>[fromDate, toDate];
    if (classId != null) {
      where.add('COALESCE(a.class_id, l.class_id) = ?');
      args.add(classId);
    }
    if (courseId != null) {
      where.add('COALESCE(a.course_id, l.course_id) = ?');
      args.add(courseId);
    }
    return db.rawQuery('''
      SELECT COALESCE(a.class_name, c.name) AS class_name,
             COALESCE(a.course_name, co.name) AS course_name,
             SUM(CASE WHEN a.status = 'present' THEN 1 ELSE 0 END) AS present_count,
             COUNT(*) AS total_count
      FROM attendance_record a
      LEFT JOIN lesson l ON l.id = a.lesson_id
      LEFT JOIN course co ON co.id = COALESCE(a.course_id, l.course_id)
      LEFT JOIN class c ON c.id = COALESCE(a.class_id, l.class_id)
      WHERE ${where.join(' AND ')}
      GROUP BY COALESCE(a.class_name, c.name), COALESCE(a.course_name, co.name)
      ORDER BY class_name ASC, course_name ASC
      ''', args);
  }

  /// 按「日期 × 课程」的出勤率序列（模块三 3.1 折线图的多课程曲线数据源）。
  ///
  /// 用户规格："出勤率折线图……最好可以有多条曲线，多个课程同时展现。"
  /// 一条课程一条曲线，同一横轴（按日/周/月聚合在页面侧做）。
  Future<List<Map<String, Object?>>> attendanceRateSeriesByCourse({
    required String fromDate,
    required String toDate,
    int? courseId,
  }) async {
    final db = await _database;
    final where = <String>['a.date BETWEEN ? AND ?'];
    final args = <Object?>[fromDate, toDate];
    if (courseId != null) {
      where.add('COALESCE(a.course_id, l.course_id) = ?');
      args.add(courseId);
    }
    return db.rawQuery('''
      SELECT a.date AS date,
             COALESCE(a.course_id, l.course_id) AS course_id,
             COALESCE(a.course_name, co.name) AS course_name,
             SUM(CASE WHEN a.status = 'present' THEN 1 ELSE 0 END) AS present_count,
             COUNT(*) AS total_count
      FROM attendance_record a
      LEFT JOIN lesson l ON l.id = a.lesson_id
      LEFT JOIN course co ON co.id = COALESCE(a.course_id, l.course_id)
      WHERE ${where.join(' AND ')}
      GROUP BY a.date, COALESCE(a.course_id, l.course_id), COALESCE(a.course_name, co.name)
      ORDER BY a.date ASC, course_name ASC
      ''', args);
  }

  /// 某班级某周内出现的缺勤次数（模块四 4.1 待办自动生成规则）。
  Future<Map<int, int>> weeklyAbsenceCountByClass({
    required String fromDate,
    required String toDate,
  }) async {
    final db = await _database;
    final rows = await db.rawQuery(
      '''
      SELECT COALESCE(a.class_id, l.class_id) AS class_id, COUNT(*) AS cnt
      FROM attendance_record a
      LEFT JOIN lesson l ON l.id = a.lesson_id
      WHERE a.status = 'absent' AND a.date BETWEEN ? AND ?
        AND COALESCE(a.class_id, l.class_id) IS NOT NULL
      GROUP BY COALESCE(a.class_id, l.class_id)
      ''',
      <Object?>[fromDate, toDate],
    );
    return <int, int>{
      for (final row in rows) row['class_id'] as int: (row['cnt'] as int?) ?? 0,
    };
  }

  /// 逐日考勤概览（日历上的「考勤进度圆环」数据源）。
  ///
  /// 只跑两条聚合查询，覆盖整段日期范围（月视图 42 天也是两次），
  /// 因此可以在每次切换日期/月份时放心重算。
  ///
  /// - 「应点名人次」按 `weekday` 算：把这天排的每节课所属**课程的全部班级**
  ///   的学生数加起来（合班课算全部班的人，与「去点名」看到的名单同一口径）；
  ///   课程一个班都没挂时回落成 `lesson.class_id`，避免算成 0；
  /// - 「已点名/出勤人次」按 `date` 算，直接数考勤记录（唯一键保证一人一节一条）。
  ///
  /// [weekdayOverrides] 是「调休日实际上周几的课」的覆盖表（key = `"YYYY-MM-DD"`，
  /// value = 实际执行的星期几，来自 `HolidayService.shiftMap`）。调休上班日照常
  /// 要上课，但上的是**别的星期几**的课表，所以那几天的 [AttendanceDayStat.expected]
  /// 必须按覆盖后的星期几去取，否则「周六上星期三的课」会算成 0 个应点名
  /// —— 圆环于是变成一个空圈，和当天真实要点的名完全对不上。
  /// 传空表 = 全部按天然星期几，行为与旧版一致。
  Future<Map<String, AttendanceDayStat>> dayStats({
    required String fromDate,
    required String toDate,
    required int teacherId,
    Map<String, int> weekdayOverrides = const <String, int>{},
  }) async {
    final db = await _database;
    // 每个 weekday 的应点名人次
    final expectedRows = await db.rawQuery(
      '''
      SELECT l.weekday AS weekday,
             SUM(
               COALESCE(
                 NULLIF(
                   (SELECT COUNT(*)
                      FROM student s
                      JOIN course_class cc ON cc.class_id = s.class_id
                     WHERE cc.course_id = l.course_id), 0),
                 (SELECT COUNT(*) FROM student s WHERE s.class_id = l.class_id)
               )
             ) AS expected
      FROM lesson l
      WHERE l.teacher_id = ?
      GROUP BY l.weekday
      ''',
      <Object?>[teacherId],
    );
    final expectedByWeekday = <int, int>{
      for (final row in expectedRows)
        (row['weekday'] as int? ?? 0): (row['expected'] as int?) ?? 0,
    };

    // 每天实际点了多少、其中多少是出勤
    final actualRows = await db.rawQuery(
      '''
      SELECT date,
             COUNT(*) AS marked,
             SUM(CASE WHEN status = 'present' THEN 1 ELSE 0 END) AS present
      FROM attendance_record
      WHERE date BETWEEN ? AND ?
      GROUP BY date
      ''',
      <Object?>[fromDate, toDate],
    );
    final actualByDate = <String, (int, int)>{
      for (final row in actualRows)
        (row['date'] as String? ?? ''): (
          (row['marked'] as int?) ?? 0,
          (row['present'] as int?) ?? 0,
        ),
    };

    final start = DateTime.tryParse(fromDate);
    final end = DateTime.tryParse(toDate);
    if (start == null || end == null || end.isBefore(start)) {
      return const <String, AttendanceDayStat>{};
    }
    final result = <String, AttendanceDayStat>{};
    for (
      var day = start;
      !day.isAfter(end);
      day = day.add(const Duration(days: 1))
    ) {
      final key = DateUtils.formatDate(day);
      // 调休上班日按老师确认的映射取课（周六上周三的课 → 取周三那套）
      final weekday = weekdayOverrides[key] ?? day.weekday;
      final hasLesson = expectedByWeekday.containsKey(weekday);
      final actual = actualByDate[key];
      final marked = actual?.$1 ?? 0;
      final present = actual?.$2 ?? 0;
      if (!hasLesson && marked == 0) {
        // 没课也没记录：占绝大多数，不往 map 里塞，日历直接按「无课」处理
        continue;
      }
      result[key] = AttendanceDayStat(
        hasLesson: hasLesson,
        expected: expectedByWeekday[weekday] ?? 0,
        marked: marked,
        present: present,
      );
    }
    return result;
  }

  // ---------------------------------------------------------------------------
  // 课程级长期状态：休学 / 免修（用户规格）
  //
  // 这类状态点一次管 180 天，不逐节课标记，所以它**不落在 attendance_record**
  // （那张表唯一键是 (student, lesson, date)，天生逐节），而是单独一条带
  // 生效区间的课程级记录。展示时按当天的日期落进区间里判定。
  // ---------------------------------------------------------------------------

  /// 某门课在 [date] 当天**生效中**的长期状态，key = studentId。
  ///
  /// 区间是闭区间：`start_date <= date <= end_date`。日期是 "YYYY-MM-DD"
  /// 字符串，字典序即时间序，所以能直接在 SQL 里比。
  Future<Map<int, CourseStudentStatus>> activeCourseStatuses({
    required int courseId,
    required String date,
  }) async {
    final db = await _database;
    final rows = await db.query(
      'student_course_status',
      where: 'course_id = ? AND start_date <= ? AND end_date >= ?',
      whereArgs: <Object?>[courseId, date, date],
    );
    return <int, CourseStudentStatus>{
      for (final row in rows)
        (row['student_id'] as int): CourseStudentStatus.fromMap(row),
    };
  }

  /// 批量取某个学生全部生效中的长期状态（设置页 / 统计展示用）。
  Future<List<CourseStudentStatus>> courseStatusesForStudent(
    int studentId,
  ) async {
    final db = await _database;
    final rows = await db.query(
      'student_course_status',
      where: 'student_id = ?',
      whereArgs: <Object?>[studentId],
      orderBy: 'course_id ASC',
    );
    return rows.map(CourseStudentStatus.fromMap).toList();
  }

  /// 设置（或覆盖）某个学生在某门课上的长期状态，返回落库后的那条记录。
  ///
  /// 用 `ON CONFLICT(student_id, course_id) DO UPDATE` 而不是 replace：
  /// 同一个学生在同一门课上只该有一条长期状态，再次点击是"改"不是"叠"。
  /// 截止日 = 起始日 + [days]（默认 180 天）。
  Future<CourseStudentStatus> setCourseStatus({
    required int studentId,
    required int courseId,
    required AttendanceStatus status,
    required String startDate,
    int days = AppConstants.longTermStatusDays,
    String? note,
  }) async {
    final db = await _database;
    if (!status.isLongTerm) {
      throw ValidationException('${status.storageKey} 不是长期状态');
    }
    final endDate = DateUtils.addDays(startDate, days);
    final now = DateTime.now().millisecondsSinceEpoch;
    try {
      await db.rawInsert(
        '''
        INSERT INTO student_course_status (
          student_id, course_id, status, start_date, end_date, note,
          created_at, updated_at
        ) VALUES (?,?,?,?,?,?,?,?)
        ON CONFLICT(student_id, course_id) DO UPDATE SET
          status = excluded.status,
          start_date = excluded.start_date,
          end_date = excluded.end_date,
          note = excluded.note,
          updated_at = excluded.updated_at
        ''',
        <Object?>[
          studentId,
          courseId,
          status.storageKey,
          startDate,
          endDate,
          note,
          now,
          now,
        ],
      );
    } catch (error, stack) {
      AppLogger.e('写入课程长期状态失败', error: error, stack: stack);
      throw DatabaseException('写入课程长期状态失败：$error', cause: error);
    }
    return CourseStudentStatus(
      studentId: studentId,
      courseId: courseId,
      status: status,
      startDate: startDate,
      endDate: endDate,
      note: note,
    );
  }

  /// 取消某个学生在某门课上的长期状态（恢复正常点名）。
  Future<void> clearCourseStatus({
    required int studentId,
    required int courseId,
  }) async {
    final db = await _database;
    await db.delete(
      'student_course_status',
      where: 'student_id = ? AND course_id = ?',
      whereArgs: <Object?>[studentId, courseId],
    );
  }

  /// 读取超期记录（清理前先备份，readme 7.6）。
  Future<List<Map<String, Object?>>> recordsBefore(String cutoffDate) async {
    final db = await _database;
    return db.query(
      'attendance_record',
      where: 'date < ?',
      whereArgs: <Object?>[cutoffDate],
    );
  }

  /// 删除超期记录，整段包在事务中。
  Future<int> deleteBefore(String cutoffDate) async {
    final db = await _database;
    try {
      return await db.transaction((txn) async {
        return txn.delete(
          'attendance_record',
          where: 'date < ?',
          whereArgs: <Object?>[cutoffDate],
        );
      });
    } catch (error, stack) {
      AppLogger.e('清理超期考勤记录失败', error: error, stack: stack);
      throw DatabaseException('清理超期考勤记录失败：$error', cause: error);
    }
  }
}
