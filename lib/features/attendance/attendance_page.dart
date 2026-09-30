import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:schedule_plan/app/app_navigation.dart';
import 'package:schedule_plan/core/constants/app_constants.dart';
import 'package:schedule_plan/core/constants/setting_keys.dart';
import 'package:schedule_plan/core/l10n/l10n_extensions.dart';
import 'package:schedule_plan/core/logging/app_logger.dart';
import 'package:schedule_plan/core/theme/app_colors.dart';
import 'package:schedule_plan/core/theme/app_motion.dart';
import 'package:schedule_plan/core/theme/theme_controller.dart';
import 'package:schedule_plan/core/utils/date_utils.dart' as app_dates;
import 'package:schedule_plan/core/utils/pinyin_utils.dart';
import 'package:schedule_plan/core/widgets/app_card.dart';
import 'package:schedule_plan/core/widgets/app_snackbar.dart';
import 'package:schedule_plan/core/widgets/confirm_dialog.dart';
import 'package:schedule_plan/core/widgets/pulse_loading.dart';
import 'package:schedule_plan/core/widgets/sort_arrow.dart';
import 'package:schedule_plan/core/widgets/staggered_entrance.dart';
import 'package:schedule_plan/data/models/attendance.dart';
import 'package:schedule_plan/data/models/china_holiday.dart';
import 'package:schedule_plan/data/models/lesson.dart';
import 'package:schedule_plan/data/models/student.dart';
import 'package:schedule_plan/data/repositories/attendance_repository.dart';
import 'package:schedule_plan/data/repositories/class_repository.dart';
import 'package:schedule_plan/data/repositories/course_repository.dart';
import 'package:schedule_plan/data/repositories/lesson_repository.dart';
import 'package:schedule_plan/data/repositories/settings_repository.dart';
import 'package:schedule_plan/data/repositories/student_repository.dart';
import 'package:schedule_plan/data/services/holiday_service.dart';
import 'package:schedule_plan/data/settings_state.dart';
import 'package:schedule_plan/features/attendance/attendance_status_strip.dart';
import 'package:schedule_plan/features/attendance/calendar_marks.dart';
import 'package:schedule_plan/features/attendance/class_group_band.dart';
import 'package:schedule_plan/features/attendance/day_attendance_ring.dart';
import 'package:schedule_plan/features/attendance/roll_call_dialog.dart';
import 'package:schedule_plan/features/attendance/student_tag_sheet.dart';

/// 考勤页（模块二 + 用户规格）。
///
/// 结构：日历（**默认周视图**，可切月）→ 当日课程横滑条 →
/// 「姓名 / 学号 / 考勤」紧凑表格（表头带双三角排序）→ 点行循环切换考勤状态。
///
/// 跨 Tab 定位：课表页点课程格子的「去点名」会投递
/// [AppNavigationState.openAttendance]，本页消费后把日期切到
/// **这节课所在周几最近的日期**，并把课程选中、拉出学生名单与已保存的考勤状态。
class AttendancePage extends StatefulWidget {
  const AttendancePage({super.key});

  @override
  State<AttendancePage> createState() => _AttendancePageState();
}

class _AttendancePageState extends State<AttendancePage> {
  DateTime _selectedDate = DateTime.now();

  /// 用户规格：默认以**周日历**展开，避免一上来就占满屏幕；点右上角可切月。
  bool _monthView = false;

  /// 逐日考勤概览（日历圆环的数据源），key = "YYYY-MM-DD"。
  Map<String, AttendanceDayStat> _dayStats = <String, AttendanceDayStat>{};

  /// 节假日 / 调休服务。`kindOf` / `infoOf` 是纯静态查表（判断这天是放假
  /// 还是调休上班），`shiftMap` 一次取回整段区间的「调休日上周几的课」。
  final HolidayService _holidays = HolidayService();

  /// 节假日与调休总开关。关掉之后一律按「周六周日休息」看，日历不再标调休。
  bool _holidayAware = true;

  /// [_dayStats] 已覆盖的日期区间（"YYYY-MM-DD"）。切日期时若还在区间内就不重查。
  String? _statsFrom;
  String? _statsTo;
  List<LessonWithTime> _lessons = <LessonWithTime>[];
  LessonWithTime? _selectedLesson;
  List<Student> _students = <Student>[];
  Map<int, AttendanceRecord> _records = <int, AttendanceRecord>{};

  /// 学生在这门课上的**长期状态**（休学 / 免修），key = studentId。
  /// 只装当前选中日期处于生效区间内的那些（见 `AttendanceRepository.activeCourseStatuses`）。
  Map<int, CourseStudentStatus> _longTerm = <int, CourseStudentStatus>{};

  Map<int, bool> _highRisk = <int, bool>{};

  /// 班级 id → 名称 / 班级展示顺序（按班级管理里的排序）。
  /// 名单按班级分组时用它们做分组标题。
  Map<int, String> _classNames = <int, String>{};
  List<int> _classOrder = <int>[];

  bool _loading = true;

  /// 跨 Tab 定位请求里指定的课表条目 id；下次加载当日课程时优先选中它。
  int? _pendingLessonId;

  /// 跨 Tab 导航状态（由课表页投递定位意图）。
  AppNavigationState? _navigation;

  /// 上一个可见的 Tab 下标：用来感知"老师从别的 Tab 回到考勤页了"。
  int _lastTabIndex = AppNavigationState.attendanceTabIndex;

  /// 高风险检测的世代号：数字一变，尚未返回的旧计算就作废（见 [_refreshRisk]）。
  int _riskToken = 0;

  StudentSortMode _sortMode = StudentSortMode.namePinyin;
  SortDirection _sortDirection = SortDirection.ascending;

  @override
  void initState() {
    super.initState();
    _restoreSortPreferences();
    _loadAll();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final navigation = context.read<AppNavigationState>();
    if (!identical(navigation, _navigation)) {
      _navigation?.removeListener(_onNavigationChanged);
      _navigation = navigation;
      navigation.addListener(_onNavigationChanged);
      _lastTabIndex = navigation.tabIndex;
    }
    // 首帧之后再消费：定位过程包含 setState 与查库，不能在 build 期间跑
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _consumePendingAttendance();
    });
  }

  @override
  void dispose() {
    _navigation?.removeListener(_onNavigationChanged);
    super.dispose();
  }

  void _onNavigationChanged() {
    // 「去点名」跳转自己会重载当日课程，不必再走一遍回切刷新
    if (_consumePendingAttendance()) {
      return;
    }
    _reloadIfReturned();
  }

  /// 消费课表页投递的「去点名」请求（同一个请求只生效一次）。
  ///
  /// 返回值只表示"这次有没有真的消费掉一个请求"，供 [_onNavigationChanged]
  /// 判断要不要再做回切刷新；定位本身是异步的，这里不 await。
  bool _consumePendingAttendance() {
    final navigation = _navigation;
    if (navigation == null || !mounted) {
      return false;
    }
    final request = navigation.pendingAttendance;
    if (request == null) {
      return false;
    }
    navigation.consumeAttendance();
    // ignore: discarded_futures — _locateTo 自己 setState 驱动 UI
    _locateTo(request);
    return true;
  }

  /// 从别的 Tab 回到考勤页时刷新一次。
  ///
  /// `IndexedStack` 切回来**既不 `initState` 也不重读库**，所以要显式刷。
  /// 非刷不可的理由：调休映射可能在别的 Tab 被改掉（工具箱日历页 / 课表页的
  /// 调休提醒条），不刷的话日历上"哪天调休、那天上周几的课"还是改之前的样子。
  ///
  /// 只重算圆环与当日课程，**不置整页 `_loading`** —— 切个 Tab 就白屏一下太糙。
  void _reloadIfReturned() {
    final navigation = _navigation;
    if (navigation == null) {
      return;
    }
    final index = navigation.tabIndex;
    final previous = _lastTabIndex;
    _lastTabIndex = index;
    if (previous == index || index != AppNavigationState.attendanceTabIndex) {
      return;
    }
    if (!mounted) {
      return;
    }
    // 总开关可能刚被改过，先让服务里的缓存失效，再重算
    _holidays.invalidate();
    // ignore: discarded_futures — 由 setState 驱动 UI
    _refreshHolidayContext();
  }

  /// 重算调休相关的展示：日历标记 + 圆环 + 当日课程（不整页转圈）。
  Future<void> _refreshHolidayContext() async {
    final aware = await _holidays.isEnabled();
    if (!mounted) {
      return;
    }
    setState(() => _holidayAware = aware);
    await _loadDayStats(force: true);
    if (!mounted) {
      return;
    }
    await _loadDayLessons();
  }

  /// 定位到指定课表条目：切日期 → 选中课程 → 拉学生名单与已保存考勤。
  ///
  /// 用户规格（点课表格子 → 去点名）：
  /// - 名单是**这节课所在班级**的学生，**默认按姓名升序**排列 ——
  ///   老师一眼扫过去就能找到人，不用先在表头点两下排序；
  /// - 日期取"这节课所在周几**离今天最近**的那天"（课表页已经算好放进 [request]，
  ///   例：今天周六 9/19 点周一的课 → 打开 9/21 那一周周一）。
  Future<void> _locateTo(AttendanceRequest request) async {
    final date =
        app_dates.DateUtils.tryParseDate(request.date) ?? DateTime.now();
    if (!mounted) {
      return;
    }
    setState(() {
      _selectedDate = date;
      _selectedLesson = null;
      _pendingLessonId = request.lessonId;
      // 只改内存里的排序，**不写回设置** —— 老师在课表页跳过来时一定是
      // "按名字找人"，但这不应该覆盖她自己在考勤页选过的排序偏好。
      _sortMode = StudentSortMode.namePinyin;
      _sortDirection = SortDirection.ascending;
    });
    await _loadDayStats();
    if (!mounted) {
      return;
    }
    await _loadDayLessons();
    if (!mounted) {
      return;
    }
    showAppSnackBar(context, context.l10n.attendanceLocatedTo(request.date));
  }

  Future<void> _restoreSortPreferences() async {
    final repo = context.read<SettingsRepository>();
    final mode = await repo.read(SettingKeys.studentSortMode);
    final desc = await repo.readBool(SettingKeys.studentSortDescending);
    if (!mounted) {
      return;
    }
    setState(() {
      _sortMode = StudentSortMode.fromStorage(mode);
      _sortDirection = desc
          ? SortDirection.descending
          : SortDirection.ascending;
    });
  }

  Future<void> _loadAll() async {
    if (mounted) {
      setState(() => _loading = true);
    }
    try {
      _holidayAware = await _holidays.isEnabled();
      await _loadClasses();
      // 圆环要覆盖整个月视图（42 天），一次查完；周视图是它的子集，不用再查
      await _loadDayStats();
      await _loadDayLessons();
    } catch (error, stack) {
      AppLogger.e('加载考勤页数据失败', error: error, stack: stack);
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  /// 读取班级名称与顺序：名单按班级分组时，分组标题与分组顺序都由它决定。
  ///
  /// 顺序沿用班级管理里的 `sort_order`（`listClasses` 已排好），
  /// 这样考勤页的分班顺序和老师在班级管理里看到的顺序一致。
  Future<void> _loadClasses() async {
    try {
      final classes = await context.read<ClassRepository>().listClasses();
      if (!mounted) {
        return;
      }
      setState(() {
        _classNames = <int, String>{
          for (final item in classes)
            if (item.id != null) item.id!: item.name,
        };
        _classOrder = <int>[
          for (final item in classes)
            if (item.id != null) item.id!,
        ];
      });
    } catch (error, stack) {
      AppLogger.e('读取班级列表失败', error: error, stack: stack);
    }
  }

  /// 加载「日历圆环」需要的数据：整段可见区间内，每天的应点名人次 / 已点名 / 出勤。
  ///
  /// 只有两条聚合查询 + 一次调休映射读取（`shiftMap` 一次 LIKE 覆盖 42 天，
  /// 不是逐天查），所以切换日期时可以直接重算；已经覆盖当前日期就跳过，
  /// 免得点一下日期就跑一次无关的统计（用户规格：圆环要"一目了然"而不是"卡一下"）。
  Future<void> _loadDayStats({bool force = false}) async {
    if (!force && _statsCover(_selectedDate)) {
      return;
    }
    final days = _monthDays(_selectedDate);
    final from = app_dates.DateUtils.formatDate(days.first);
    final to = app_dates.DateUtils.formatDate(days.last);
    final repo = context.read<AttendanceRepository>();
    // 一次性取回整段的调休映射：圆环的「应点名」要按这天**实际上**的
    // 星期几去算（周六上周三的课 → 按周三算），否则调休日的圆环会是空的。
    final shifts = await _holidays.shiftMap(from: days.first, to: days.last);
    final stats = await repo.dayStats(
      fromDate: from,
      toDate: to,
      teacherId: AppConstants.currentTeacherId,
      weekdayOverrides: shifts,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _dayStats = stats;
      _statsFrom = from;
      _statsTo = to;
    });
  }

  /// 当前这次统计是否已经覆盖 [day]。
  bool _statsCover(DateTime day) {
    final from = app_dates.DateUtils.tryParseDate(_statsFrom);
    final to = app_dates.DateUtils.tryParseDate(_statsTo);
    if (from == null || to == null) {
      return false;
    }
    final target = app_dates.DateUtils.dateOnly(day);
    return !target.isBefore(from) && !target.isAfter(to);
  }

  Future<void> _loadDayLessons() async {
    final lessonsRepo = context.read<LessonRepository>();
    // **按调休映射取课**：这天若是调休上班日、学校通知上周三的课，那么要点名的
    // 就是周三排的那几节，而不是"周六的课"（周六通常压根没排课，会显示成
    // 「今天没有课」，老师反而以为漏了课）。没确认过映射时 labelWeekday
    // 自动回落成天然星期几，行为与以前完全一致。
    final weekday = (await _holidays.dayOf(_selectedDate)).labelWeekday;
    final lessons = await lessonsRepo.queryWithTime(
      teacherId: AppConstants.currentTeacherId,
      weekday: weekday,
    );
    // 按真实时间排序展示
    lessons.sort((a, b) => a.startMinutes.compareTo(b.startMinutes));
    // 优先选中跨 Tab 定位请求指定的那一节，其次保持当前选择，最后退回第一节
    final wantedId = _pendingLessonId ?? _selectedLesson?.lesson.id;
    final selected = lessons.isEmpty
        ? null
        : lessons.firstWhere(
            (item) => item.lesson.id == wantedId,
            orElse: () => lessons.first,
          );
    if (!mounted) {
      return;
    }
    setState(() {
      _lessons = lessons;
      _selectedLesson = selected;
      _pendingLessonId = null;
    });
    if (selected != null) {
      await _loadStudents(selected);
    } else if (mounted) {
      setState(() {
        _students = <Student>[];
        _records = <int, AttendanceRecord>{};
        _longTerm = <int, CourseStudentStatus>{};
        _highRisk = <int, bool>{};
      });
    }
  }

  /// 拉这节课的名单 + 已落库的考勤。
  ///
  /// **名单口径（用户规格，本轮修的就是这里）**：这门课在课程管理里勾了
  /// 几个班级，名单就是这几个班学生的**并集**。旧实现只取
  /// `lesson.class_id` 那一个班，所以合班课/大课点进来只看见一个班的人。
  ///
  /// 多个班时按「班级 → 姓名」排，老师可以一个班一个班地核对下去；
  /// 单班时退化成原来的 id 顺序（再由表格的排序开关决定展示顺序）。
  Future<void> _loadStudents(LessonWithTime lesson) async {
    final studentRepo = context.read<StudentRepository>();
    final attendanceRepo = context.read<AttendanceRepository>();
    final courseRepo = context.read<CourseRepository>();
    final classIds = await courseRepo.classIdsOfCourse(lesson.lesson.courseId);
    final students = await studentRepo.listByClasses(
      classIds.isEmpty ? <int>[lesson.lesson.classId] : classIds,
    );
    final date = app_dates.DateUtils.formatDate(_selectedDate);
    final records = await attendanceRepo.mapForLessonDate(
      lesson.lesson.id!,
      date,
    );
    // 这门课在当前日期生效中的休学 / 免修（点一次管 180 天，见 CourseStudentStatus）
    final longTerm = await attendanceRepo.activeCourseStatuses(
      courseId: lesson.lesson.courseId,
      date: date,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _students = students;
      _records = records;
      _longTerm = longTerm;
      // 先用「今天这一节」的记录做一次快速判断，逐生统计随后异步补上。
      // 休学的学生不算高风险（他们不来）；免修的仍会来上课，迟到缺勤照常算。
      _highRisk = <int, bool>{
        for (final student in students)
          student.id!:
              longTerm[student.id]?.status == AttendanceStatus.suspended
              ? false
              : (records[student.id!]?.status.countsAsAbsence ?? false),
      };
    });
    // 逐生查库较慢，放到第二阶段，避免拖住首屏渲染（模块二 2.9）
    await _refreshRisk(students);
  }

  Future<void> _refreshRisk(List<Student> students) async {
    if (students.isEmpty) {
      return;
    }
    // 逐生查库较慢，而用户可能连续切换班级 / 日期；
    // 用 token 让被顶替的那次计算直接作废（不能用「正在计算就跳过」的互斥，
    // 否则新班级的高风险标记会因为旧任务未完成而永远补不上）。
    final token = ++_riskToken;
    final attendanceRepo = context.read<AttendanceRepository>();
    final settings = context.read<SettingsState>();
    final weekStart = app_dates.DateUtils.formatDate(
      app_dates.DateUtils.startOfWeek(_selectedDate),
    );
    final weekEnd = app_dates.DateUtils.formatDate(
      app_dates.DateUtils.startOfWeek(
        _selectedDate,
      ).add(const Duration(days: 6)),
    );
    final risk = <int, bool>{};
    try {
      for (final student in students) {
        // 休学的学生不参与高风险判定：他们不在这门课的点名范围内。
        // 免修的仍会来上课，迟到缺勤照常累计，不跳过。
        if (_longTerm[student.id]?.status == AttendanceStatus.suspended) {
          risk[student.id!] = false;
          continue;
        }
        final counts = await attendanceRepo.statusCountsForStudent(
          student.id!,
          fromDate: weekStart,
          toDate: weekEnd,
        );
        final absent = counts[AttendanceStatus.absent.storageKey] ?? 0;
        risk[student.id!] = absent >= settings.riskAbsenceThreshold;
      }
    } catch (error, stack) {
      AppLogger.e('高风险学生检测失败', error: error, stack: stack);
      return;
    }
    if (!mounted || token != _riskToken) {
      return;
    }
    setState(() => _highRisk = risk);
  }

  Future<void> _onDateSelected(DateTime date) async {
    setState(() {
      _selectedDate = date;
      _selectedLesson = null;
    });
    // 翻到别的月份时圆环的统计区间要跟着换（同月内直接命中缓存，不多查）
    await _loadDayStats();
    if (!mounted) {
      return;
    }
    await _loadDayLessons();
  }

  Future<void> _onLessonSelected(LessonWithTime lesson) async {
    setState(() => _selectedLesson = lesson);
    await _loadStudents(lesson);
  }

  /// 点某个状态胶囊 → 直接落库那一个状态（用户规格：点一下即保存）。
  ///
  /// 替换掉旧的"点一下在六种状态之间循环"：循环意味着最多要点五次才能到
  /// 想要的"请假"，老师一节课 40 分钟根本点不过来。现在五个状态平铺在
  /// 每条学生信息后面，想点哪个点哪个，一次到位。
  Future<void> _setStatus(Student student, AttendanceStatus status) async {
    final lesson = _selectedLesson;
    final studentId = student.id;
    if (lesson == null || studentId == null) {
      return;
    }
    // 休学 / 免修：不是逐节记录，而是课程级长期状态（点一次管 180 天）
    if (status.isLongTerm) {
      await _toggleLongTerm(student, lesson, status);
      return;
    }
    final locked = _longTerm[studentId];
    if (locked != null && locked.status == AttendanceStatus.suspended) {
      // 只有休学才锁日常点名：休学期间这个学生不来了，点名没意义，
      // 想恢复就再点一下那枚休学胶囊（会弹「复学」确认）。
      // 免修不在此列——免修的学生仍会来上课，迟到早退照常标记。
      showAppSnackBar(
        context,
        context.l10n.attendanceLongTermLocked(
          student.name,
          statusLabelOf(context, locked.status),
          locked.endDate,
        ),
      );
      return;
    }
    final existing = _records[studentId];
    if (existing?.status == status) {
      // 已经就是这个状态：不重复写库，但仍给一次触觉反馈
      AppMotion.select();
      return;
    }
    final attendanceRepo = context.read<AttendanceRepository>();
    final date = app_dates.DateUtils.formatDate(_selectedDate);
    try {
      await attendanceRepo.mark(
        lesson: lesson,
        studentId: studentId,
        date: date,
        status: status,
      );
      AppMotion.select();
      if (!mounted) {
        return;
      }
      // 只更新这一行，**不重查整班**。
      // 之前每点一下都走一次 _loadStudents：一次点名要重拉名单 + 重读这一天的
      // 全部考勤，还要给每个学生各查一次本周状态（40 人 = 41 次查询）。
      // 顺着把全班点成出勤就会卡成幻灯片 —— 而"最快点名"正是这次改动的目标。
      setState(() {
        _records[studentId] = AttendanceRecord.forLesson(
          lesson: lesson,
          studentId: studentId,
          date: date,
          status: status,
        );
        // 本节的快速判断跟着走；周维度的精确统计留给下次整班加载时重算
        _highRisk[studentId] = status.countsAsAbsence;
        // 日历圆环**同步增量更新**：以前每点一下都 await 一次整月重算
        // （两条聚合 + 42 天循环），低端机上就是"圆环慢半拍"的来源。
        // 现在只改当天这一个 entry，圆环和行在同一帧刷新，零延迟。
        _applyRingDelta(date, status, existing?.status);
      });
    } catch (error, stack) {
      AppLogger.e('保存考勤失败', error: error, stack: stack);
      if (!mounted) {
        return;
      }
      showAppSnackBar(context, context.l10n.operationFailed('$error'));
    }
  }

  /// 点「休学 / 免修」胶囊（用户规格）。
  ///
  /// - 该生在这门课上还没有这个状态 → **一次点击直接生效 180 天**，
  ///   起始日取"正在查看的那一天"，之后不必每节课重复标记；
  /// - 已经就是这个状态 → 弹确认后取消（同状态再点是"取消"，不是"覆盖"，
  ///   否则老师没有出口把学生恢复成正常点名）。
  ///
  /// 落的是 `student_course_status`（课程级、带生效区间），**不写考勤记录** ——
  /// 这类状态不是"某一天的表现"，逐节记录既写不完也没有意义。
  Future<void> _toggleLongTerm(
    Student student,
    LessonWithTime lesson,
    AttendanceStatus status,
  ) async {
    final l10n = context.l10n;
    final studentId = student.id!;
    final courseId = lesson.lesson.courseId;
    final repo = context.read<AttendanceRepository>();
    final existing = _longTerm[studentId];

    if (existing != null && existing.status == status) {
      // 同状态再点 = 恢复，不是覆盖。休学恢复叫「复学」、免修恢复叫「取消免修」，
      // 两者措辞不同但都是「恢复正常点名」。老师必须有这条出口，否则学生被
      // 卡在长期状态里永远改不回来（这正是本次要修的 bug）。
      final isResume = status == AttendanceStatus.suspended;
      final confirmed = await showAppConfirm(
        context: context,
        title: isResume
            ? l10n.attendanceResumeTitle
            : l10n.attendanceLongTermClearTitle(statusLabelOf(context, status)),
        body: isResume
            ? l10n.attendanceResumeBody(student.name)
            : l10n.attendanceLongTermClearBody(student.name),
        confirmLabel: isResume ? l10n.attendanceResumeConfirm : null,
        danger: !isResume,
      );
      if (!confirmed || !mounted) {
        return;
      }
      try {
        await repo.clearCourseStatus(studentId: studentId, courseId: courseId);
        if (!mounted) {
          return;
        }
        AppMotion.confirm();
        setState(() => _longTerm.remove(studentId));
        showAppSnackBar(context, l10n.attendanceLongTermCleared(student.name));
      } catch (error, stack) {
        AppLogger.e('取消课程长期状态失败', error: error, stack: stack);
        if (!mounted) {
          return;
        }
        showAppSnackBar(context, l10n.operationFailed('$error'));
      }
      return;
    }

    // 起始日 = 正在查看的这一天：老师看到的是"从今天起他就不来了"
    final startDate = app_dates.DateUtils.formatDate(_selectedDate);
    try {
      final saved = await repo.setCourseStatus(
        studentId: studentId,
        courseId: courseId,
        status: status,
        startDate: startDate,
      );
      if (!mounted) {
        return;
      }
      AppMotion.confirm();
      setState(() {
        _longTerm[studentId] = saved;
        // 刚点上长期状态时先不亮红（还没记过迟到缺勤）；
        // 免修之后迟到缺勤会照常累计，由点名落库时更新 _highRisk。
        _highRisk[studentId] = false;
      });
      showAppSnackBar(
        context,
        l10n.attendanceLongTermSet(
          student.name,
          statusLabelOf(context, status),
          saved.endDate,
        ),
      );
    } catch (error, stack) {
      AppLogger.e('保存课程长期状态失败', error: error, stack: stack);
      if (!mounted) {
        return;
      }
      showAppSnackBar(context, l10n.operationFailed('$error'));
    }
  }

  /// 日历圆环的**同步增量更新**：点名落库后只改当天这一个 entry。
  ///
  /// 以前这里 `await _loadDayStats(force: true)` 整月重算（两条聚合 + 42 天循环），
  /// 每点一下学生都跑一次，低端机上圆环就"慢半拍"（用户反馈"日历上 ring 有延迟"）。
  /// 增量口径与 `AttendanceRepository.dayStats` 一致：
  /// - 新增记录：`marked + 1`；改状态：`marked` 不变；
  /// - `present` 按新旧状态是否出勤做 `+1/-1`。
  /// `expected`（应点名人次）只由排课决定，点名不会改它。
  void _applyRingDelta(
    String date,
    AttendanceStatus next,
    AttendanceStatus? prev,
  ) {
    final stat = _dayStats[date];
    if (stat == null) {
      // 该日还没加载（罕见），下一次整月加载会补齐，这里不硬造
      return;
    }
    final wasPresent = prev == AttendanceStatus.present;
    final isPresent = next == AttendanceStatus.present;
    final markedDelta = prev == null ? 1 : 0;
    final presentDelta = (isPresent ? 1 : 0) - (wasPresent ? 1 : 0);
    _dayStats[date] = AttendanceDayStat(
      hasLesson: stat.hasLesson,
      expected: stat.expected,
      marked: stat.marked + markedDelta,
      present: stat.present + presentDelta,
    );
  }

  /// 点整行 = 记「出勤」。
  ///
  /// 一天里绝大多数学生都是出勤，最快路径就是"顺着点下来"，
  /// 只有少数异常才去点对应的胶囊。
  Future<void> _markPresent(Student student) =>
      _setStatus(student, AttendanceStatus.present);

  Future<void> _openTags(Student student) async {
    final lesson = _selectedLesson;
    if (lesson == null) {
      return;
    }
    await showStudentTagSheet(
      context,
      student: student,
      date: app_dates.DateUtils.formatDate(_selectedDate),
    );
  }

  Future<void> _copySummary() async {
    final l10n = context.l10n;
    final lesson = _selectedLesson;
    if (lesson == null) {
      return;
    }
    final summary = _abnormalSummary();
    if (!mounted) {
      return;
    }
    // 用户规格：复制的是**特殊情况**（迟到/早退/缺勤/请假 + 休学/免修），
    // 默认就是出勤的学生不占篇幅；且要弹个对话框让老师先看清复制了什么。
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => _SummaryDialog(
        title: l10n.copySummary,
        summary: summary,
        emptyText: l10n.summaryNoAbnormal,
        onCopy: () async {
          final text = summary.isEmpty ? l10n.summaryNoAbnormal : summary;
          await Clipboard.setData(ClipboardData(text: text));
          if (dialogContext.mounted) {
            Navigator.of(dialogContext).pop();
          }
          if (mounted) {
            showAppSnackBar(context, l10n.copiedToClipboard);
          }
        },
      ),
    );
  }

  /// 组装「异常考勤」摘要：只列非出勤，格式 `迟到：班级 姓名、…`，某状态没有就省略。
  ///
  /// 用户规格："大部分情况需要的肯定是特殊情况，比方说迟到、早退这种，
  /// 而不是登记出勤情况，因为默认就是出勤。"
  String _abnormalSummary() {
    final settings = context.read<SettingsState>();
    final grouped = <AttendanceStatus, List<String>>{};
    for (final student in _students) {
      // 与名单行同一口径：休学显示为「休学」；免修不覆盖当天表现，
      // 迟到早退照常进摘要（免修本身不算异常）。
      final status = _effectiveStatus(student, settings);
      if (status == AttendanceStatus.present ||
          status == AttendanceStatus.unmarked) {
        continue;
      }
      final cls = _classNames[student.classId] ?? '';
      final label = cls.isEmpty ? student.name : '$cls ${student.name}';
      grouped.putIfAbsent(status, () => <String>[]).add(label);
    }
    if (grouped.isEmpty) {
      return '';
    }
    final buffer = StringBuffer();
    for (final status in AttendanceStatus.choices) {
      final list = grouped[status] ?? const <String>[];
      if (list.isEmpty) {
        continue;
      }
      buffer.writeln('${_statusLabel(status)}：${list.join('、')}');
    }
    return buffer.toString().trimRight();
  }

  Future<void> _openRollCall() async {
    final picked = await showRollCallDialog(context, _students);
    if (picked == null || !mounted) {
      return;
    }
    showAppSnackBar(context, picked.name);
  }

  Future<void> _onSortTap(StudentSortMode mode) async {
    // 同一列再点一次 = 翻转方向；换列 = 从升序开始
    final next = mode == _sortMode
        ? _sortDirection.toggled
        : SortDirection.ascending;
    setState(() {
      _sortMode = mode;
      _sortDirection = next;
    });
    final repo = context.read<SettingsRepository>();
    await repo.write(SettingKeys.studentSortMode, mode.storageKey);
    await repo.writeBool(
      SettingKeys.studentSortDescending,
      next == SortDirection.descending,
    );
  }

  String _statusLabel(AttendanceStatus status) =>
      statusLabelOf(context, status);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final tokens = context.watch<ThemeController>().tokens;
    final settings = context.watch<SettingsState>();
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.attendanceTitle),
        actions: <Widget>[
          IconButton(
            icon: Icon(
              _monthView
                  ? Icons.view_week_rounded
                  : Icons.calendar_month_rounded,
            ),
            tooltip: _monthView ? l10n.calendarWeek : l10n.calendarMonth,
            onPressed: () {
              AppMotion.select();
              setState(() => _monthView = !_monthView);
            },
          ),
        ],
      ),
      body: _loading
          ? PulseLoading(message: l10n.loading)
          : Column(
              children: <Widget>[
                _buildCalendar(tokens),
                _buildCourseChips(),
                _buildToolbar(tokens),
                Expanded(child: _buildStudentTable(tokens, settings)),
              ],
            ),
    );
  }

  // ---------------------------------------------------------------------------
  // 日历：默认周视图（一行 7 天），切到月视图时是完整的 6×7 网格
  // ---------------------------------------------------------------------------
  Widget _buildCalendar(AppColorTokens tokens) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = context.l10n;
    final weekStart = app_dates.DateUtils.startOfWeek(_selectedDate);
    final days = _monthView
        ? _monthDays(_selectedDate)
        : app_dates.DateUtils.weekDays(_selectedDate);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.spaceL,
        AppConstants.spaceS,
        AppConstants.spaceL,
        0,
      ),
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(
          AppConstants.spaceS,
          AppConstants.spaceS,
          AppConstants.spaceS,
          AppConstants.spaceM,
        ),
        child: Column(
          children: <Widget>[
            Row(
              children: <Widget>[
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.chevron_left_rounded),
                  onPressed: () => _onDateSelected(
                    _monthView
                        // 必须按月收敛，直接 DateTime(y, m-1, d) 会在 31 日溢出进到本月
                        ? app_dates.DateUtils.shiftMonth(_selectedDate, -1)
                        : _selectedDate.subtract(const Duration(days: 7)),
                  ),
                ),
                Expanded(
                  child: Column(
                    children: <Widget>[
                      Text(
                        _monthView
                            ? l10n.calendarMonthTitle(
                                _selectedDate.year,
                                _selectedDate.month,
                              )
                            : l10n.calendarWeekTitle(
                                app_dates.DateUtils.formatDate(weekStart),
                                app_dates.DateUtils.formatDate(
                                  weekStart.add(const Duration(days: 6)),
                                ),
                              ),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.2,
                        ),
                      ),
                      Text(
                        app_dates.DateUtils.formatDate(_selectedDate),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.chevron_right_rounded),
                  onPressed: () => _onDateSelected(
                    _monthView
                        ? app_dates.DateUtils.shiftMonth(_selectedDate, 1)
                        : _selectedDate.add(const Duration(days: 7)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppConstants.spaceS),
            if (_monthView)
              _buildMonthGrid(days, theme, tokens)
            else
              _buildWeekStrip(days, theme, tokens),
            const SizedBox(height: AppConstants.spaceS),
            // 图例：把日历上的四样标记一次讲清楚 —— 放假红点、调休紫点、
            // 未点名淡圈、出勤红弧。写在下面老师不用猜，也就不用再长按试探。
            AttendanceCalendarLegend(
              items: <CalendarLegendItem>[
                CalendarLegendItem(
                  glyph: CalendarLegendGlyph.dot,
                  color: CalendarMark.holidayColor(scheme),
                  label: l10n.attendanceLegendHoliday,
                ),
                CalendarLegendItem(
                  glyph: CalendarLegendGlyph.dot,
                  color: CalendarMark.makeupColor(scheme),
                  label: l10n.attendanceLegendMakeup,
                ),
                CalendarLegendItem(
                  glyph: CalendarLegendGlyph.ring,
                  color: scheme.outlineVariant,
                  label: l10n.attendanceLegendNoRecord,
                ),
                CalendarLegendItem(
                  glyph: CalendarLegendGlyph.arc,
                  color: tokens.nowLine,
                  label: l10n.attendanceLegendRate,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 周视图：一行 7 个「周几 + 日期」，高度固定，永远不占满屏。
  Widget _buildWeekStrip(
    List<DateTime> days,
    ThemeData theme,
    AppColorTokens tokens,
  ) {
    return Row(
      children: <Widget>[
        for (final day in days)
          Expanded(child: _buildDayTile(day, theme, tokens, monthGrid: false)),
      ],
    );
  }

  Widget _buildMonthGrid(
    List<DateTime> days,
    ThemeData theme,
    AppColorTokens tokens,
  ) {
    return Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            for (
              var weekday = 1;
              weekday <= AppConstants.weekdayCount;
              weekday++
            )
              Expanded(
                child: Center(
                  child: Text(
                    context.l10n.weekdayShort(weekday),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: AppConstants.spaceXs),
        for (var row = 0; row < days.length ~/ 7; row++)
          Row(
            children: <Widget>[
              for (var col = 0; col < 7; col++)
                Expanded(
                  child: _buildDayTile(
                    days[row * 7 + col],
                    theme,
                    tokens,
                    monthGrid: true,
                  ),
                ),
            ],
          ),
      ],
    );
  }

  Widget _buildDayTile(
    DateTime day,
    ThemeData theme,
    AppColorTokens tokens, {
    required bool monthGrid,
  }) {
    final scheme = theme.colorScheme;
    final isSelected = app_dates.DateUtils.isSameDay(day, _selectedDate);
    final isToday = app_dates.DateUtils.isSameDay(day, DateTime.now());
    final inMonth = !monthGrid || day.month == _selectedDate.month;
    final stat = _dayStats[app_dates.DateUtils.formatDate(day)];
    // 放假 / 调休上班的标记。总开关关掉时一律不标。
    final mark = _dayMark(
      _holidayAware ? HolidayService.kindOf(day) : null,
      scheme,
    );

    return InkWell(
      borderRadius: AppRadii.innerAll,
      onTap: () => _onDateSelected(day),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 1),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // 周视图把标记并进「周X」那一行，不额外占高度；
            // 月视图没有那一行，就在顶部留一条固定高度的标记带
            // （固定高度是为了让有标记/没标记的格子一样高，网格不会参差）。
            if (monthGrid)
              SizedBox(
                height: 6,
                child: mark == null ? null : Center(child: mark),
              )
            else
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    context.l10n.weekdayShort(day.weekday),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: isSelected
                          ? scheme.primary
                          : scheme.onSurfaceVariant,
                      fontWeight: isSelected
                          ? FontWeight.w800
                          : FontWeight.w500,
                    ),
                  ),
                  if (mark != null) ...<Widget>[const SizedBox(width: 3), mark],
                ],
              ),
            const SizedBox(height: 3),
            // 日期数字外面套一圈考勤进度环：**有课的日子才有环**
            // （有课没点名 = 淡圈；点过名 = 红弧按出勤率填充）。
            DayAttendanceRing(
              stat: stat,
              progressColor: tokens.nowLine,
              trackColor: scheme.outlineVariant,
              child: AnimatedContainer(
                duration: AppMotion.standard,
                curve: AppMotion.expressive,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isSelected
                      ? scheme.primary
                      : (isToday
                            ? scheme.primaryContainer.withValues(alpha: 0.55)
                            : Colors.transparent),
                  shape: BoxShape.circle,
                  border: isToday && !isSelected
                      ? Border.all(
                          color: scheme.primary.withValues(alpha: 0.6),
                          width: 1.5,
                        )
                      : null,
                ),
                child: Text(
                  '${day.day}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: isSelected
                        ? scheme.onPrimary
                        : (inMonth
                              ? scheme.onSurface
                              : scheme.onSurfaceVariant.withValues(
                                  alpha: 0.4,
                                )),
                    fontWeight: isSelected || isToday
                        ? FontWeight.w800
                        : FontWeight.w500,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 日历格子上表示「放假 / 调休上班」的小圆点 —— 语义见 [CalendarMark]。
  ///
  /// 放假 = 红点、调休上班 = 紫点。没有安排的日子返回 null，
  /// 连那条占位的高度条里都不落点。
  Widget? _dayMark(CalendarDayKind? kind, ColorScheme scheme) {
    final color = CalendarMark.colorOf(kind, scheme);
    if (color == null) {
      return null;
    }
    return Container(
      width: 5,
      height: 5,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }

  List<DateTime> _monthDays(DateTime month) {
    final first = DateTime(month.year, month.month, 1);
    final offset = first.weekday - 1;
    final start = first.subtract(Duration(days: offset));
    return List<DateTime>.generate(
      42,
      (index) => start.add(Duration(days: index)),
      growable: false,
    );
  }

  // ---------------------------------------------------------------------------
  // 当日课程横滑条
  // ---------------------------------------------------------------------------
  Widget _buildCourseChips() {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    if (_lessons.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(
          AppConstants.spaceL,
          AppConstants.spaceM,
          AppConstants.spaceL,
          0,
        ),
        child: Row(
          children: <Widget>[
            Icon(
              Icons.event_busy_outlined,
              size: 16,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(l10n.noData, style: theme.textTheme.bodySmall),
          ],
        ),
      );
    }
    return SizedBox(
      height: 50,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(
          horizontal: AppConstants.spaceL,
          vertical: AppConstants.spaceS,
        ),
        scrollDirection: Axis.horizontal,
        itemCount: _lessons.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppConstants.spaceS),
        itemBuilder: (context, index) {
          final lesson = _lessons[index];
          final selected = _selectedLesson?.lesson.id == lesson.lesson.id;
          final scheme = theme.colorScheme;
          return GestureDetector(
            onTap: () {
              AppMotion.select();
              _onLessonSelected(lesson);
            },
            child: AnimatedContainer(
              duration: AppMotion.standard,
              curve: AppMotion.expressive,
              padding: const EdgeInsets.symmetric(
                horizontal: AppConstants.spaceM,
                vertical: 6,
              ),
              decoration: BoxDecoration(
                color: selected
                    ? scheme.primaryContainer.withValues(alpha: 0.9)
                    : scheme.surfaceContainerHigh,
                borderRadius: AppRadii.stadiumAll,
                border: Border.all(
                  color: selected
                      ? scheme.primary.withValues(alpha: 0.65)
                      : Colors.transparent,
                  width: 1.4,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    lesson.timeRangeText,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: selected
                          ? scheme.onPrimaryContainer
                          : scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    lesson.courseName,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 顶部工具条：左侧「颜色 → 状态」图例，右侧点名 / 复制
  //
  // 排序控件已经下放到每个班级的分组横带里（用户规格："按照班级分类学生，
  // 同时每个班支持姓名、学号、考勤排序"）。这里再摆一份会打架：
  // 两处都叫"姓名"，老师不知道点哪个才是给这个班排序。
  // ---------------------------------------------------------------------------
  Widget _buildToolbar(AppColorTokens tokens) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.spaceL,
        AppConstants.spaceS,
        AppConstants.spaceS,
        AppConstants.spaceS,
      ),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.7),
          ),
        ),
      ),
      child: Row(
        children: <Widget>[
          // 图例：点名的七个状态各自是什么颜色，一眼对得上
          Expanded(
            child: Wrap(
              spacing: AppConstants.spaceS,
              runSpacing: 2,
              children: <Widget>[
                for (final status in AttendanceStatus.choices)
                  _StatusLegend(
                    label: statusLabelOf(context, status),
                    color: statusColorOf(tokens, status),
                  ),
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.casino_outlined, size: 20),
            tooltip: l10n.rollCall,
            onPressed: _students.isEmpty ? null : _openRollCall,
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.copy_all_outlined, size: 20),
            tooltip: l10n.copySummary,
            onPressed: _students.isEmpty ? null : _copySummary,
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 学生表：**按班级分组**（用户规格：每个班的学生划在区分线里），
  // 组内按当前排序方式排，休学 / 免修自动沉到本班末尾。
  // ---------------------------------------------------------------------------
  Widget _buildStudentTable(AppColorTokens tokens, SettingsState settings) {
    final l10n = context.l10n;
    if (_students.isEmpty) {
      return EmptyView(
        message: l10n.noStudentsHint,
        icon: Icons.people_outline_rounded,
      );
    }
    final rows = _rosterRows();
    // 入场动画的序号只数学生行：分组横带不该占它的节拍
    var studentIndex = 0;
    return ListView.builder(
      cacheExtent: AppConstants.listCacheExtent.toDouble(),
      padding: const EdgeInsets.fromLTRB(
        AppConstants.spaceL,
        AppConstants.spaceS,
        AppConstants.spaceL,
        AppConstants.spaceL,
      ),
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final row = rows[index];
        final group = row.group;
        if (row.student == null) {
          return ClassGroupBand(
            className: group.className,
            fallbackLabel: l10n.classManagement,
            count: group.students.length,
            sortMode: _sortMode,
            direction: _sortDirection,
            onSortTap: _onSortTap,
            topGap: index > 0,
          );
        }
        final student = row.student!;
        return StaggeredEntrance(
          index: studentIndex++,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: _StudentRow(
              student: student,
              status: _effectiveStatus(student, settings),
              longTerm: _longTerm[student.id!],
              risk: _highRisk[student.id!] ?? false,
              tokens: tokens,
              // 只有休学才锁日常五态（免修仍可标记迟到早退），
              // 休学的唯一出口是「再点一次休学胶囊 → 复学」。
              locked:
                  _longTerm[student.id]?.status == AttendanceStatus.suspended,
              onStatusPick: (picked) => _setStatus(student, picked),
              onTap: () => _markPresent(student),
              onLongPress: () => _openTags(student),
            ),
          ),
        );
      },
    );
  }

  /// 渲染用的扁平行序列：每个班先来一条分组横带，再排这个班的学生。
  ///
  /// 用扁平序列 + `ListView.builder` 而不是嵌套列表，是为了保持名单的懒构建
  /// （一个年级几百人时，嵌套的 `Column` 会一次性把整份名单建出来）。
  List<_RosterRow> _rosterRows() {
    final rows = <_RosterRow>[];
    for (final group in _groupedStudents()) {
      rows.add(_RosterRow.band(group));
      for (final student in group.students) {
        rows.add(_RosterRow.student(group, student));
      }
    }
    return rows;
  }

  /// 按班级把名单拆开（用户规格："按照班级分类学生"）。
  ///
  /// 分组顺序沿用**班级管理里的顺序**（`listClasses` 已按 sort_order 排好），
  /// 这样老师在哪一页看到的班次是一样的；名单里出现但班级表里查不到的
  /// （理论上只可能是数据被外部改坏）补在末尾，宁可多显示一组也不要漏人。
  List<_RosterGroup> _groupedStudents() {
    final buckets = <int, List<Student>>{};
    for (final student in _students) {
      buckets.putIfAbsent(student.classId, () => <Student>[]).add(student);
    }
    final ids = <int>[
      for (final id in _classOrder)
        if (buckets.containsKey(id)) id,
      for (final id in buckets.keys)
        if (!_classOrder.contains(id)) id,
    ];
    return <_RosterGroup>[
      for (final id in ids)
        _RosterGroup(
          classId: id,
          className: _classNames[id] ?? '',
          students: _sortedWithin(buckets[id]!),
        ),
    ];
  }

  /// 这一行的**有效状态**：休学 > 已落库的考勤 > 默认状态。
  ///
  /// 「免修」**不**覆盖日常状态：免修的学生仍会来上课，也可能迟到早退，
  /// 所以它只是名单里的一个角标（见 `_StudentRow.longTerm`），有效状态
  /// 仍按「当天记录 / 默认出勤」算。
  ///
  /// "默认出勤"是刻意的：老师点名时先假设全员到齐，只去点少数异常，
  /// 一节课的名单扫一遍就完事（用户规格：以最快点名的方式）。因此表头
  /// 不需要"全部出勤"按钮 —— 未标记的行本来就显示为出勤。
  AttendanceStatus _effectiveStatus(Student student, SettingsState settings) {
    final longTerm = _longTerm[student.id!];
    if (longTerm?.status == AttendanceStatus.suspended) {
      return AttendanceStatus.suspended;
    }
    return _records[student.id!]?.status ?? settings.defaultAttendanceStatus;
  }

  /// 班内排序（用户规格：每个班支持姓名 / 学号 / 考勤排序）。
  ///
  /// **休学 / 免修一律沉底**（用户规格："这个学生就在这个课程里排到后面"），
  /// 而且不能靠"先按名字排、再按长期状态排"这种两趟排序实现 ——
  /// Dart 的 `List.sort` 不保证稳定，第二趟会把第一趟的顺序打乱。
  /// 所以把"沉底优先"写进同一个比较器的最前面。
  List<Student> _sortedWithin(List<Student> list) {
    final sorted = <Student>[...list];
    sorted.sort(
      (a, b) => compareRosterStudents(
        a,
        b,
        mode: _sortMode,
        direction: _sortDirection,
        isLongTerm: (student) => _longTerm.containsKey(student.id),
        statusIndexOf: (student) =>
            (_records[student.id!]?.status ?? AttendanceStatus.unmarked).index,
      ),
    );
    return sorted;
  }
}

/// 考勤名单「班内排序」的比较器（纯函数，单独可测）。
///
/// 规则（用户规格："每个班支持姓名，学号，考勤排序" +
/// "休学 / 免修的学生就在这个课程里排到后面"）：
/// 1. **休学 / 免修永远沉底**，且不随升降序翻转 ——
///    升序降序翻转的是"怎么排正常学生"，不该把不在这门课上的学生翻到最前面；
/// 2. 其余按 [mode] 排，[direction] 决定升降。
///
/// 为什么要把两件事合进**一个**比较器：Dart 的 `List.sort` 不保证稳定，
/// "先按姓名排一趟、再按长期状态排一趟"会让第一趟的结果被打乱。
int compareRosterStudents(
  Student a,
  Student b, {
  required StudentSortMode mode,
  required SortDirection direction,
  required bool Function(Student student) isLongTerm,
  required int Function(Student student) statusIndexOf,
}) {
  final rank = (isLongTerm(a) ? 1 : 0) - (isLongTerm(b) ? 1 : 0);
  if (rank != 0) {
    return rank;
  }
  final sign = direction == SortDirection.ascending ? 1 : -1;
  return switch (mode) {
    StudentSortMode.namePinyin =>
      sign * PinyinUtils.compareByName(a.name, b.name),
    StudentSortMode.studentNo =>
      sign * (a.studentNo ?? '').compareTo(b.studentNo ?? ''),
    StudentSortMode.attendanceStatus =>
      sign * statusIndexOf(a).compareTo(statusIndexOf(b)),
  };
}

/// 考勤页的一次渲染单元：一条分组横带，或横带下的一个学生。
class _RosterRow {
  const _RosterRow.band(this.group) : student = null;
  const _RosterRow.student(this.group, Student this.student);

  final _RosterGroup group;

  /// 为空表示这是该班的分组横带
  final Student? student;
}

/// 一个班级的分组：班级 + 这个班（已排好序）的学生。
class _RosterGroup {
  const _RosterGroup({
    required this.classId,
    required this.className,
    required this.students,
  });

  final int classId;
  final String className;
  final List<Student> students;
}

/// 图例项：一个小色点 + 状态名，说明"这个颜色代表什么状态"。
class _StatusLegend extends StatelessWidget {
  const _StatusLegend({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 3),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 10.5,
          ),
        ),
      ],
    );
  }
}

/// 复制考勤摘要的对话框：先让老师看清**具体复制了什么**，再点「复制」。
///
/// 用户规格："现在是复制好了，没有对话框，最好有个对话框，告知具体的复制内容。"
/// 内容是最简化的一行一状态（`迟到：班级 姓名、…`），没异常时给一句全员出勤。
class _SummaryDialog extends StatelessWidget {
  const _SummaryDialog({
    required this.title,
    required this.summary,
    required this.emptyText,
    required this.onCopy,
  });

  final String title;
  final String summary;
  final String emptyText;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isEmpty = summary.isEmpty;
    return AlertDialog(
      title: Text(title),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: isEmpty
            ? Text(emptyText, style: Theme.of(context).textTheme.bodyMedium)
            : SingleChildScrollView(
                child: SelectableText(
                  summary,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(height: 1.5),
                ),
              ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
          onPressed: onCopy,
          child: Text(l10n.copyAction),
        ),
      ],
    );
  }
}

/// 一行学生：小号字姓名 / 学号 + **平铺的七个一键状态胶囊**。
///
/// 用户规格（本次改动的核心）：考勤状态不要再让老师"滑动一个个选"，
/// 也不要循环点击四五次才到"请假"。七种状态（日常五种 + 休学 / 免修）
/// 摊开摆在学生信息后面（见 [AttendanceStatusStrip]），想点哪个点哪个，
/// 日常状态点一下就落库，长期状态点一下就管 180 天。
class _StudentRow extends StatelessWidget {
  const _StudentRow({
    required this.student,
    required this.status,
    required this.risk,
    required this.tokens,
    required this.onStatusPick,
    required this.onTap,
    required this.onLongPress,
    this.longTerm,
    this.locked = false,
  });

  final Student student;

  /// 该行当前的有效状态（已落库状态，或设置里的默认状态）
  final AttendanceStatus status;
  final bool risk;
  final AppColorTokens tokens;
  final ValueChanged<AttendanceStatus> onStatusPick;

  /// 这门课上生效中的长期状态（休学 / 免修），为空表示正常点名。
  /// 免修时它只作为角标展示（副标题「免修 · 至 …」+ 免修胶囊高亮），
  /// 日常点名不受影响。
  final CourseStudentStatus? longTerm;

  /// 休学时锁住日常五态与免修胶囊（只有"再点一次休学胶囊 → 复学"这一条出口）。
  /// 免修不锁：免修学生仍会来上课，迟到早退照常标记。
  final bool locked;

  /// 点整行 = 记「出勤」（一天里绝大多数人是出勤，顺着点下来最快）
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final longTerm = this.longTerm;
    return Material(
      color: risk
          ? scheme.errorContainer.withValues(alpha: 0.32)
          : (locked
                ? scheme.surfaceContainerHighest.withValues(alpha: 0.55)
                : scheme.surfaceContainerLow),
      borderRadius: AppRadii.tileAll,
      child: InkWell(
        borderRadius: AppRadii.tileAll,
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.spaceM,
            vertical: AppConstants.spaceS + 2,
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                flex: 3,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Flexible(
                          child: Text(
                            student.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (risk) ...<Widget>[
                          const SizedBox(width: 4),
                          Icon(
                            Icons.warning_amber_rounded,
                            size: 14,
                            color: scheme.error,
                          ),
                        ],
                      ],
                    ),
                    // 休学 / 免修要写清"管到哪天"，否则老师不知道它什么时候失效
                    if (longTerm != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: Text(
                          context.l10n.attendanceLongTermUntil(
                            statusLabelOf(context, longTerm.status),
                            longTerm.endDate,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontSize: 9.5,
                            height: 1.1,
                            color: statusColorOf(tokens, longTerm.status),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  student.studentNo ?? '—',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              AttendanceStatusStrip(
                status: status,
                activeLongTerm: longTerm?.status,
                tokens: tokens,
                locked: locked,
                onPick: onStatusPick,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
