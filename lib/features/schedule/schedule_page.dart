import 'package:flutter/material.dart';
import 'package:app_settings/app_settings.dart';
import 'package:gal/gal.dart';
import 'package:provider/provider.dart';

import 'package:schedule_plan/app/app_navigation.dart';
import 'package:schedule_plan/core/constants/app_constants.dart';
import 'package:schedule_plan/core/constants/setting_keys.dart';
import 'package:schedule_plan/core/error/app_exceptions.dart';
import 'package:schedule_plan/core/l10n/l10n_extensions.dart';
import 'package:schedule_plan/core/logging/app_logger.dart';
import 'package:schedule_plan/core/theme/app_motion.dart';
import 'package:schedule_plan/core/theme/app_page_route.dart';
import 'package:schedule_plan/core/theme/theme_controller.dart';
import 'package:schedule_plan/core/utils/date_utils.dart' as app_dates;
import 'package:schedule_plan/core/widgets/app_card.dart';
import 'package:schedule_plan/core/widgets/app_snackbar.dart';
import 'package:schedule_plan/core/widgets/confirm_dialog.dart';
import 'package:schedule_plan/core/widgets/pulse_loading.dart';
import 'package:schedule_plan/data/models/china_holiday.dart';
import 'package:schedule_plan/data/models/class_course.dart';
import 'package:schedule_plan/data/models/course_detail.dart';
import 'package:schedule_plan/data/models/lesson.dart';
import 'package:schedule_plan/data/models/schedule_event.dart';
import 'package:schedule_plan/data/models/schedule_template.dart';
import 'package:schedule_plan/data/repositories/class_repository.dart';
import 'package:schedule_plan/data/repositories/course_repository.dart';
import 'package:schedule_plan/data/repositories/lesson_repository.dart';
import 'package:schedule_plan/data/repositories/schedule_event_repository.dart';
import 'package:schedule_plan/data/repositories/settings_repository.dart';
import 'package:schedule_plan/data/repositories/template_repository.dart';
import 'package:schedule_plan/data/services/holiday_service.dart';
import 'package:schedule_plan/data/services/holiday_sync_service.dart';
import 'package:schedule_plan/data/settings_state.dart';
import 'package:schedule_plan/features/management/class_list_page.dart';
import 'package:schedule_plan/features/management/course_list_page.dart';
import 'package:schedule_plan/features/management/course_ocr_page.dart';
import 'package:schedule_plan/features/schedule/class_grid_view.dart';
import 'package:schedule_plan/features/schedule/course_picker_dialog.dart';
import 'package:schedule_plan/features/schedule/lesson_actions_sheet.dart';
import 'package:schedule_plan/features/schedule/lesson_detail_dialog.dart';
import 'package:schedule_plan/features/schedule/lesson_quick_add_sheet.dart';
import 'package:schedule_plan/features/schedule/schedule_settings_sheet.dart';
import 'package:schedule_plan/features/schedule/schedule_share.dart';
import 'package:schedule_plan/features/schedule/schedule_share_footer.dart';
import 'package:schedule_plan/features/schedule/timeline_view.dart';
import 'package:schedule_plan/features/templates/template_editor_page.dart';
import 'package:schedule_plan/features/templates/template_list_page.dart';
import 'package:schedule_plan/features/toolbox/holiday_shift_sheet.dart';
import 'package:schedule_plan/l10n/generated/app_localizations.dart';

/// 课表页（模块一 + 用户规格）。
///
/// 版式：
/// - **默认是表格视图**——第一行星期几，第一列节次与上课时间，
///   点第一列的节次即可改这一节的时间并顺延后续；
///   整表宽度按可用空间自适应、行高等比压缩，**永远一屏放得下**，
///   不需要横向滚动也不需要双指缩放；每列还是一个横向手风琴
///   （默认等宽只显示课程名，点开的课所在列变宽并延迟淡入人数 / 班级）；
/// - 表格骨架来自作息模板（**上次展示的那套**，没有则用默认模板），
///   作息为空时自动补一份出厂作息，**保证任何时候打开都是一张完整的表**；
/// - 右上角两个入口：**作息切换**（传统 / 错峰等多套作息之间切换）
///   与 **课表设置**（一键生成作息 / 默认作息修改 / 一键清空 / 拍照导入）；
///   设置页不再重复放作息模板入口；
/// - 表格上方**不再有班级切换条**（用户规格：课程不针对某个班级，
///   课表是一张表，表格上不需要显示导入的班级），
///   只在"一个班级都没有"时给一条提示；
/// - 另保留「教师聚合时间轴」作为第二视图，用于看跨班级的整体排布。
///
/// 格子点击（用户规格，本页的核心交互）：
/// - **空格子**：课程管理里已有课程 → 底部滑动挑选课程并直接排进这一格
///   （**不再要求先选班级**）；一门课都没有 → 先引导去课程管理建课，
///   连班级都没有则先引导建班级（课程必须挂班级）；
/// - **有课的格子**：第一次点 → 该列展开并显示课程详情（人数 / 班级）；
///   再点同一格 → 弹出课程信息（名称 / 人数 / 班级 / 教室 / 班主任），
///   右下角「去点名」跳到考勤页并定位到这节课所在周几最近的日期。
///
/// 课程与班级的关系：课程管理里一门课可以挂多个班级（合班），但**课表页
/// 不按班级切分**——格子里显示的是这张课表的全部课，空格子选课时列出的是
/// 全量课程。排课时 `lesson.class_id` 取**课程自己挂载的班级**。
///
/// 数据新鲜度：本页与考勤 / 工具箱 / 设置是 `IndexedStack` 里的平级 Tab，
/// 切走再切回**不会重建页面**。所以除了 `initState`，还要在
/// 「切回课表 Tab」时重新读库（见 [_SchedulePageState._onNavigationChanged]），
/// 否则老师刚在设置页建好的课程在课表页里"看不见"，
/// 点空格子会一直提示"还没有添加课程"。
///
/// 冷存储：**展示用的作息模板 id 落库**（`SettingKeys.scheduleDisplayTemplateId`）。
/// 早期版本每次进入都按「选中班级 -> is_default 的模板」临时推导，
/// 只要库里多出一套默认模板，重启后就会静默换成另一套作息，
/// 用户看到的现象就是「我改的时间又变回默认了」。
class SchedulePage extends StatefulWidget {
  const SchedulePage({super.key});

  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

/// 课表展示模式。
enum _ViewMode {
  /// 表格课表（单班级，第一列节次时间 / 第一行星期）
  grid,

  /// 教师聚合时间轴（跨班级按真实时间排布）
  timeline,
}

class _SchedulePageState extends State<SchedulePage> {
  _ViewMode _mode = _ViewMode.grid;
  bool _loading = true;
  Object? _error;
  _ScheduleData? _data;

  /// 日程安排活动：错峰课表（曲线档）上用小方块标记（单次 / 隔周 / 隔月）。
  List<ScheduleEvent> _events = const <ScheduleEvent>[];

  /// 今天是调休上班日的话，这里放着"补哪个节日的班 + 上周几的课"。
  ///
  /// 用户规格（第 13 轮）："如果周六日轮到调休，最好有个功能，
  /// 在调休那天提醒老师上周几的课。" 只在调休当天才非空。
  HolidayDay? _makeupToday;
  final HolidayService _holidays = HolidayService();

  /// 今天**实际照着上哪一天的课表**（调休上班日按老师确认的映射走）。
  ///
  /// 表头的「今天」圆点画在这一列上：今天周六上周三的课，圆点就落在
  /// 「周三」列 —— 那才是今天要上的内容，周六列通常压根没排课。
  int _todayLabelWeekday = DateTime.now().weekday;

  /// 本周调休落点：**列（weekday）→ 那一列的调休日**。
  ///
  /// 本周有调休上班日时，把它记在「它实际上课的那一天」上，
  /// 表头于是在那一列画角标（周六补周三的课 → 标在周三列）。
  /// 只收「老师确认过映射」的调休日：没确认等于不调整，没什么可提前说的。
  Map<int, HolidayDay> _makeupColumns = const <int, HolidayDay>{};

  /// 分享截图用的两块 `RepaintBoundary`：
  /// 一块是**屏幕上真实显示的课表正文**（错峰 / 常规以当前为准），
  /// 一块是**离屏的底部信息带**（app 名 + 二维码位，见 [ScheduleShareFooter]）。
  final GlobalKey _captureBodyKey = GlobalKey();
  final GlobalKey _captureFooterKey = GlobalKey();
  bool _sharing = false;

  /// 跨 Tab 的导航状态：用来感知"老师从别的 Tab 回到课表了"。
  AppNavigationState? _navigation;
  int _lastTabIndex = AppNavigationState.scheduleTabIndex;

  /// 节假日数据保鲜服务：后台取回新数据时通知这里重算"今天是不是调休日"。
  HolidaySyncService? _holidaySync;

  @override
  void initState() {
    super.initState();
    // ignore: discarded_futures — 首帧由 _loading 承载，不需要 await
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bindHolidaySync();
    final navigation = context.read<AppNavigationState>();
    if (identical(navigation, _navigation)) {
      return;
    }
    _navigation?.removeListener(_onNavigationChanged);
    _navigation = navigation..addListener(_onNavigationChanged);
    _lastTabIndex = navigation.tabIndex;
  }

  @override
  void dispose() {
    _navigation?.removeListener(_onNavigationChanged);
    _holidaySync?.removeListener(_onHolidayDataChanged);
    super.dispose();
  }

  /// 订阅节假日数据变化。
  ///
  /// 为什么非订不可：**首次安装又正好跨年**时（比如 2027 年 1 月才装 App），
  /// 内置表只抄到 2026，缓存也是空的，启动那一刻"今天是不是调休上班日"
  /// 只能按"周末休息"回落——判断不出来。后台把 2027 的安排取回来之后，
  /// 必须重算一次，否则顶部那条"今天要上周几的课"的提醒永远不会出现。
  void _bindHolidaySync() {
    final sync = context.read<HolidaySyncService>();
    if (identical(sync, _holidaySync)) {
      return;
    }
    _holidaySync?.removeListener(_onHolidayDataChanged);
    _holidaySync = sync..addListener(_onHolidayDataChanged);
  }

  void _onHolidayDataChanged() {
    if (!mounted) {
      return;
    }
    // ignore: discarded_futures — 由 _loading/_data 驱动 UI
    _load();
  }

  /// 从其他 Tab 切回课表时重新读库。
  ///
  /// 课表 / 考勤 / 工具箱 / 设置是 `IndexedStack` 里的平级 Tab，切走再切回来
  /// **不会重建页面、也不会重新走 initState**。老师在设置页新建了班级或课程再回来，
  /// 手里还是切走前那份数据，点空格子就会一直提示"还没有课程"——
  /// 这正是"课程管理里建好课程，回来点这格不对"的原因。
  void _onNavigationChanged() {
    final navigation = _navigation;
    if (navigation == null) {
      return;
    }
    final index = navigation.tabIndex;
    final previous = _lastTabIndex;
    _lastTabIndex = index;
    if (previous == index || index != AppNavigationState.scheduleTabIndex) {
      return;
    }
    if (!mounted) {
      return;
    }
    // ignore: discarded_futures — 由 _loading/_data 驱动 UI
    _load();
  }

  Future<void> _load() async {
    if (!mounted) {
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final classesRepo = context.read<ClassRepository>();
    final lessonsRepo = context.read<LessonRepository>();
    final templatesRepo = context.read<TemplateRepository>();
    final coursesRepo = context.read<CourseRepository>();
    final settingsRepo = context.read<SettingsRepository>();
    final eventsRepo = context.read<ScheduleEventRepository>();
    try {
      final classes = await classesRepo.listClasses();
      final templates = await templatesRepo.listTemplates();
      final events = await eventsRepo.listEvents();
      final lessons = await lessonsRepo.queryWithTime(
        teacherId: AppConstants.currentTeacherId,
      );
      final courseCounts = await coursesRepo.studentCountByCourse();

      // 课表**不再按班级切分**（用户规格：一张表、课程不针对某个班、
      // 表格上也不需要显示所有班级）。这里只留一个"兜底班级"：
      // `lesson.class_id` 是外键，排课时最终仍要落到课程自己挂载的班级上。
      final selectedClass = classes.isEmpty ? null : classes.first;
      final selectedId = selectedClass?.id;

      // 展示用的作息模板（第一列「第 N 节 + 起止时间」完全由它决定）：
      // **持久化的展示模板优先** —— 这是修掉「改完时间重启又变回默认」的关键；
      // 没有再退到班级绑定 / is_default。课表既然不分班，
      // 作息就由这张表自己决定，不再跟着某个班走。
      final storedTemplateId = await settingsRepo.readInt(
        SettingKeys.scheduleDisplayTemplateId,
      );
      bool templateExists(int id) => templates.any((item) => item.id == id);

      int? templateId;
      if (templateExists(storedTemplateId)) {
        templateId = storedTemplateId;
      }
      templateId ??= selectedClass?.templateId;
      if (templateId == null || !templateExists(templateId)) {
        templateId = templates.isEmpty
            ? null
            : templates
                  .firstWhere(
                    (item) => item.isDefault,
                    orElse: () => templates.first,
                  )
                  .id;
      }

      // 骨架不能是空的：老版本建库没写过出厂作息、旧版「一键清空课表」
      // 又把作息整段删掉，这类模板在这里补一次，否则第一列会一片空白。
      if (templateId != null) {
        await templatesRepo.ensureFactorySchedule(templateId);
      }

      final periodsByWeekday = <int, List<TemplatePeriod>>{};
      var maxPeriodCount = AppConstants.defaultDayPeriodCount;
      if (templateId != null) {
        // 节次数按 (template_id, weekday) 单独取 —— 一周内各天不一定相同
        for (var day = 1; day <= AppConstants.weekdayCount; day++) {
          final periods = await templatesRepo.periodsForWeekday(
            templateId,
            day,
          );
          if (periods.isEmpty) {
            continue;
          }
          periodsByWeekday[day] = periods;
          if (periods.length > maxPeriodCount) {
            maxPeriodCount = periods.length;
          }
        }
      }

      // 格子里显示的是**这张课表的全部课**（教师维度），与班级无关。
      // 排课冲突检测本来就是教师维度（同一天真实时间重叠即冲突），
      // 所以整表展示和判定口径是一致的。
      final gridLessons = lessons;

      // 空格子里「滑动选课」的候选：**全量课程**（用户规格：不针对某个班级）。
      // 早期版本按"当前选中班级"过滤，老师在课程管理里给别的班建了课，
      // 回到课表页点格子依然查不到 → 又被提示"去添加课程"，就是这个根因。
      final courses = <CourseDetail>[
        for (final course in await coursesRepo.listCourses())
          CourseDetail.from(course, classes),
      ];

      // 非 normal 时段（午休 / 大课间）：聚合视图里以浅色条带标注
      final templateIds = <int>{
        ...classes.map((item) => item.templateId),
        ?templateId,
      };
      final breakPeriods = <TemplatePeriod>[];
      for (final id in templateIds) {
        breakPeriods.addAll(await templatesRepo.allPeriods(id));
      }

      final result = _ScheduleData(
        classes: classes,
        templates: templates,
        selectedClass: selectedClass,
        templateId: templateId,
        lessons: lessons,
        breakPeriods: breakPeriods,
        periodsByWeekday: periodsByWeekday,
        gridLessons: gridLessons,
        courses: courses,
        courseCounts: courseCounts,
        maxPeriodCount: maxPeriodCount,
      );
      if (!mounted) {
        return;
      }
      // 调休提醒：只有今天正好是"周六周日要上班"的调休日才会拿到值
      final makeup = await _holidays.todayMakeupWorkday();
      if (!mounted) {
        return;
      }
      // 表头要的两件事都看「这一周」：今天实际执行星期几 + 本周调休落在哪一列
      final now = DateTime.now();
      final week = await _holidays.weekOf(now);
      if (!mounted) {
        return;
      }
      // weekOf 的 days 恒为「周一起的七天」，所以今天就在它自己的 weekday 位置上
      final todayDay = week.days[now.weekday - DateTime.monday];
      setState(() {
        _data = result;
        _events = events;
        _makeupToday = makeup;
        _todayLabelWeekday = todayDay.labelWeekday;
        _makeupColumns = <int, HolidayDay>{
          for (final item in week.days)
            if (item.kind == CalendarDayKind.makeupWorkday &&
                item.shiftOverridden)
              item.labelWeekday: item,
        };
        _loading = false;
      });
      // 把「这次真正展示的」记下来，下次启动直接复原（冷存储）
      // ignore: discarded_futures — 落盘失败不影响本次渲染
      _persistDisplay(templateId: templateId, classId: selectedId);
    } catch (error, stack) {
      AppLogger.e('加载课表失败', error: error, stack: stack);
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  /// 记住当前展示的作息模板与班级，供下次启动复原。
  Future<void> _persistDisplay({
    required int? templateId,
    required int? classId,
  }) async {
    if (!mounted) {
      return;
    }
    try {
      final repo = context.read<SettingsRepository>();
      await repo.writeInt(
        SettingKeys.scheduleDisplayTemplateId,
        templateId ?? 0,
      );
      await repo.writeInt(SettingKeys.scheduleSelectedClassId, classId ?? 0);
    } catch (error, stack) {
      AppLogger.e('保存课表展示状态失败', error: error, stack: stack);
    }
  }

  /// 当前展示的作息模板（跟随选中班级，没有班级时用持久化/默认模板）。
  ScheduleTemplate? _currentTemplate(_ScheduleData data) {
    final templateId = data.templateId;
    if (templateId == null) {
      return null;
    }
    for (final template in data.templates) {
      if (template.id == templateId) {
        return template;
      }
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // 作息切换（传统 / 错峰等多套作息）
  // ---------------------------------------------------------------------------
  Future<void> _switchTemplate(_ScheduleData data, int templateId) async {
    final classInfo = data.selectedClass;
    final settingsRepo = context.read<SettingsRepository>();
    try {
      if (classInfo == null) {
        // 没有班级时只切「展示的作息」，不写库里的班级绑定
        await settingsRepo.writeInt(
          SettingKeys.scheduleDisplayTemplateId,
          templateId,
        );
        await _load();
        return;
      }
      if (classInfo.templateId == templateId) {
        return;
      }
      await context.read<ClassRepository>().updateClass(
        classInfo.copyWith(templateId: templateId),
      );
      await settingsRepo.writeInt(
        SettingKeys.scheduleDisplayTemplateId,
        templateId,
      );
      await _load();
    } catch (error, stack) {
      AppLogger.e('切换作息失败', error: error, stack: stack);
      if (!mounted) {
        return;
      }
      showAppSnackBar(context, context.l10n.operationFailed('$error'));
    }
  }

  // ---------------------------------------------------------------------------
  // 课表设置
  // ---------------------------------------------------------------------------
  /// 「一键生成作息」表单的初值：全部来自**当前正在展示的作息**。
  ///
  /// 用户规格：「一键生成作息权限最大，随后才是个别课的调整时间」。
  /// 既然如此，表单必须能反映现状——第二次打开时要看到"现在是 5 天"，
  /// 而不是每次都退回出厂值让人以为改动丢了。
  ({String start, int lessonMinutes, int gapMinutes, List<int> weekdays})
  _generateDefaults(_ScheduleData data) {
    final weekdays = data.periodsByWeekday.keys.toList()..sort();
    var start = AppConstants.defaultDayStartTime;
    var lesson = AppConstants.defaultLessonMinutes;
    var gap = AppConstants.defaultBreakMinutes;
    if (weekdays.isNotEmpty) {
      final periods =
          data.periodsByWeekday[weekdays.first] ?? const <TemplatePeriod>[];
      if (periods.isNotEmpty) {
        start = periods.first.startTime;
        final duration = periods.first.endMinutes - periods.first.startMinutes;
        if (duration > 0) {
          lesson = duration;
        }
        if (periods.length > 1) {
          final spacing = periods[1].startMinutes - periods.first.endMinutes;
          if (spacing >= 0) {
            gap = spacing;
          }
        }
      }
    }
    return (
      start: start,
      lessonMinutes: lesson,
      gapMinutes: gap,
      weekdays: weekdays,
    );
  }

  Future<void> _openSettings(_ScheduleData data) async {
    final templateId = data.templateId;
    if (templateId == null) {
      return;
    }
    final template = _currentTemplate(data);
    final defaults = _generateDefaults(data);

    Future<void>? pendingGenerate;
    final changed = await showScheduleSettingsSheet(
      context,
      templateName: template?.name ?? '',
      periodCount: data.maxPeriodCount,
      initialWeekdays: defaults.weekdays,
      initialStartTime: defaults.start,
      initialLessonMinutes: defaults.lessonMinutes,
      initialBreakMinutes: defaults.gapMinutes,
      onGenerate:
          ({
            required String startTime,
            required int lessonMinutes,
            required int breakMinutes,
            required int count,
            required List<int> weekdays,
          }) {
            pendingGenerate = _generatePeriods(
              templateId: templateId,
              startTime: startTime,
              lessonMinutes: lessonMinutes,
              breakMinutes: breakMinutes,
              periodCount: count,
              weekdays: weekdays,
            );
          },
      onEditDefault: () async {
        await pushAppPage<void>(
          context,
          TemplateEditorPage(templateId: templateId),
        );
      },
      onManageTemplates: () async {
        await pushAppPage<void>(context, const TemplateListPage());
      },
      onClear: () => _clearSchedule(templateId),
      onQuickAdd: () => _openQuickAdd(data),
      onImportPhoto: _openOcrImport,
    );
    // 生成是异步写库的，等它落盘再刷新，避免读到旧数据
    await pendingGenerate;
    if (changed || pendingGenerate != null) {
      await _load();
    }
  }

  Future<void> _generatePeriods({
    required int templateId,
    required String startTime,
    required int lessonMinutes,
    required int breakMinutes,
    required int periodCount,
    required List<int> weekdays,
  }) async {
    try {
      await context.read<TemplateRepository>().generatePeriods(
        templateId: templateId,
        weekdays: weekdays,
        startTime: startTime,
        lessonMinutes: lessonMinutes,
        breakMinutes: breakMinutes,
        periodCount: periodCount,
        // 一键生成是最高权限：没勾的星期要一并清掉，
        // 否则"先选 7 天再改回 5 天"永远停在 7 列
        clearUnselected: true,
      );
      if (!mounted) {
        return;
      }
      showAppSnackBar(context, context.l10n.scheduleGenerated(periodCount));
    } catch (error, stack) {
      AppLogger.e('一键生成作息失败', error: error, stack: stack);
      if (!mounted) {
        return;
      }
      showAppSnackBar(context, context.l10n.operationFailed('$error'));
    }
  }

  Future<void> _clearSchedule(int templateId) async {
    final l10n = context.l10n;
    final repo = context.read<TemplateRepository>();
    final confirmed = await showAppConfirm(
      context: context,
      title: l10n.clearSchedule,
      body: l10n.clearScheduleConfirm,
      danger: true,
    );
    if (!confirmed) {
      return;
    }
    try {
      await repo.clearTemplateSchedule(templateId);
      if (!mounted) {
        return;
      }
      showAppSnackBar(context, l10n.scheduleCleared);
      await _load();
    } catch (error, stack) {
      AppLogger.e('清空课表失败', error: error, stack: stack);
      if (!mounted) {
        return;
      }
      showAppSnackBar(context, l10n.operationFailed('$error'));
    }
  }

  // ---------------------------------------------------------------------------
  // 节次时间修改（点第一列的某一节）
  // ---------------------------------------------------------------------------
  Future<void> _editPeriodTime(
    _ScheduleData data,
    int weekday,
    int periodIndex,
  ) async {
    final templateId = data.templateId;
    if (templateId == null) {
      return;
    }
    final periods = data.periodsByWeekday[weekday] ?? const <TemplatePeriod>[];
    final target = periods.where((item) => item.periodIndex == periodIndex);
    if (target.isEmpty) {
      return;
    }
    final period = target.first;
    final weekdays = data.periodsByWeekday.keys.toList()..sort();

    final result = await showPeriodTimeSheet(
      context,
      periodIndex: periodIndex,
      startTime: period.startTime,
      endTime: period.endTime,
      availableWeekdays: weekdays,
      defaultApplyAllDays: true,
    );
    if (result == null) {
      return;
    }
    if (!mounted) {
      return;
    }

    // 全局级联开关关闭时，一律只改本节
    final cascadeAllowed = context.read<SettingsState>().cascadeUpdateEnabled;
    final cascade = result.cascade && cascadeAllowed;
    final repo = context.read<TemplateRepository>();
    try {
      final targets = result.allDays && weekdays.isNotEmpty
          ? weekdays
          : <int>[weekday];
      for (final day in targets) {
        await repo.cascadeUpdatePeriods(
          templateId: templateId,
          weekday: day,
          fromPeriodIndex: periodIndex,
          newStartTime: result.start,
          newEndTime: result.end,
          cascade: cascade,
        );
      }
      if (!mounted) {
        return;
      }
      showAppSnackBar(context, context.l10n.periodTimeSaved);
      await _load();
    } catch (error, stack) {
      AppLogger.e('修改节次时间失败', error: error, stack: stack);
      if (!mounted) {
        return;
      }
      showAppSnackBar(context, context.l10n.operationFailed('$error'));
    }
  }

  // ---------------------------------------------------------------------------
  // 格子点击：空格子
  // ---------------------------------------------------------------------------
  /// 空格子：**只要课程管理里已经有课程，就直接弹出滑动选课**。
  ///
  /// 用户规格（第三次强调）："是点击单元格，跳出已添加课程，滑动选择。
  /// 课程管理里没有课程资料，再提醒新增课程。不需要针对某个班级新增课程。"
  /// 所以这里的判定只有一条：**全库有没有课程**——不再看"当前选中班级"，
  /// 也不再要求先选班级。
  ///
  /// 这里刻意**不直接信任** `data.courses`：老师很可能刚在设置页的课程管理里
  /// 建完课再切回来，而两个页面是平级 Tab（切 Tab 不重建页面）。
  /// 遇到"看起来一门课都没有"的情况，先重新读一次库再下结论，
  /// 宁可多一次查询，也不要对着已有课程提示"还没有添加课程"。
  Future<void> _onEmptyCellTap(
    _ScheduleData data,
    int weekday,
    int periodIndex,
  ) async {
    var current = data;
    if (current.courses.isEmpty) {
      await _load();
      if (!mounted) {
        return;
      }
      final refreshed = _data;
      if (refreshed == null) {
        return;
      }
      current = refreshed;
    }

    if (current.courses.isEmpty) {
      _promptNoCourse(current);
      return;
    }
    await _pickAndPlace(current, weekday, periodIndex);
  }

  /// 一门课都没有时的引导。
  ///
  /// 课程必须挂至少一个班级（`CourseRepository.createCourse` 的约束），
  /// 所以连班级都没有时先去建班级，否则直接去课程管理加课。
  void _promptNoCourse(_ScheduleData data) {
    final l10n = context.l10n;
    if (data.classes.isEmpty) {
      showAppSnackBar(
        context,
        l10n.cellNeedsClassBody,
        onRetry: _openClassManagement,
        retryLabel: l10n.goCreateClass,
      );
      return;
    }
    showAppSnackBar(
      context,
      l10n.cellNoCourseBody,
      onRetry: _openCourseManagement,
      retryLabel: l10n.goAddCourse,
    );
  }

  /// 打开课程管理（**不按班级过滤**：课程管理里能看到的课，课表页都能排）。
  Future<void> _openCourseManagement() async {
    await pushAppPage<void>(context, const CourseListPage());
    if (!mounted) {
      return;
    }
    await _load();
  }

  Future<void> _openClassManagement() async {
    await pushAppPage<void>(context, const ClassListPage());
    if (!mounted) {
      return;
    }
    await _load();
  }

  /// 滑动挑选课程 → 放进这一格；[replacing] 非空表示「换个课程」。
  Future<void> _pickAndPlace(
    _ScheduleData data,
    int weekday,
    int periodIndex, {
    LessonWithTime? replacing,
  }) async {
    final l10n = context.l10n;
    if (data.courses.isEmpty) {
      _promptNoCourse(data);
      return;
    }

    final picked = await showCoursePickerDialog(
      context,
      courses: data.courses,
      slotLabel: l10n.weekdayPeriodLabel(weekday, periodIndex),
    );
    if (picked == null || !mounted) {
      return;
    }
    final courseId = picked.id;
    if (courseId == null) {
      return;
    }
    if (replacing != null && replacing.lesson.courseId == courseId) {
      return;
    }

    final lessonsRepo = context.read<LessonRepository>();
    try {
      if (replacing != null) {
        // 换课：同一格只改课程，**不动班级也不动时间** ——
        // 那一格的节次骨架由原班级的作息决定，跟着新课程改班级会让
        // (weekday, period_index) 在新的模板里找不到对应节次而"消失"。
        await lessonsRepo.updateLesson(
          replacing.lesson.copyWith(courseId: courseId),
        );
      } else {
        // 排新课时 lesson.class_id 取**课程自己挂载的班级**（第一顺位）。
        // 这样"课程不针对某个班级"也能落库，且时间解析有据可依。
        final targetClassId =
            picked.primaryClassIdOrNull ?? data.selectedClass?.id;
        if (targetClassId == null) {
          showAppSnackBar(
            context,
            l10n.cellNeedsClassBody,
            onRetry: _openClassManagement,
            retryLabel: l10n.goCreateClass,
          );
          return;
        }
        await lessonsRepo.placeLesson(
          courseId: courseId,
          classId: targetClassId,
          weekday: weekday,
          periodIndex: periodIndex,
        );
      }
      if (!mounted) {
        return;
      }
      showAppSnackBar(context, l10n.placedToSchedule);
      await _load();
    } on AppException catch (error) {
      if (!mounted) {
        return;
      }
      showAppSnackBar(context, error.message);
    } catch (error, stack) {
      AppLogger.e('排课失败', error: error, stack: stack);
      if (!mounted) {
        return;
      }
      showAppSnackBar(context, l10n.operationFailed('$error'));
    }
  }

  // ---------------------------------------------------------------------------
  // 格子点击：已有课程的格子
  // ---------------------------------------------------------------------------
  Future<void> _onLessonTap(_ScheduleData data, LessonWithTime lesson) async {
    final action = await showLessonDetailDialog(
      context,
      lesson: lesson,
      detail: data.detailFor(lesson.lesson.courseId),
    );
    if (action == null || !mounted) {
      return;
    }
    switch (action) {
      case LessonDetailAction.rollCall:
        _goRollCall(lesson);
      case LessonDetailAction.changeCourse:
        await _pickAndPlace(
          data,
          lesson.lesson.weekday,
          lesson.lesson.periodIndex,
          replacing: lesson,
        );
      case LessonDetailAction.remove:
        await _removeLesson(lesson);
    }
  }

  /// 去点名：投递跳转意图，考勤页接管定位（本页与考勤页是平级 Tab）。
  void _goRollCall(LessonWithTime lesson) {
    final lessonId = lesson.lesson.id;
    if (lessonId == null) {
      return;
    }
    // 「这节课所在周几最近的日期」：本周还没到就用本周，已经过了就用下周
    final date = app_dates.DateUtils.nearestWeekdayDate(
      DateTime.now(),
      lesson.lesson.weekday,
    );
    context.read<AppNavigationState>().openAttendance(
      AttendanceRequest(
        lessonId: lessonId,
        classId: lesson.lesson.classId,
        weekday: lesson.lesson.weekday,
        date: app_dates.DateUtils.formatDate(date),
      ),
    );
  }

  Future<void> _removeLesson(LessonWithTime lesson) async {
    final l10n = context.l10n;
    try {
      await context.read<LessonRepository>().clearSlot(
        classId: lesson.lesson.classId,
        weekday: lesson.lesson.weekday,
        periodIndex: lesson.lesson.periodIndex,
      );
      if (!mounted) {
        return;
      }
      showAppSnackBar(context, l10n.removedFromSchedule);
      await _load();
    } catch (error, stack) {
      AppLogger.e('移出课表失败', error: error, stack: stack);
      if (!mounted) {
        return;
      }
      showAppSnackBar(context, l10n.operationFailed('$error'));
    }
  }

  /// 「一键新增课表」向导（readme 模块一 1.5），入口挪进课表设置。
  Future<void> _openQuickAdd(_ScheduleData data) async {
    if (data.selectedClass == null) {
      // 课表骨架可以没有班级先看着，但"往格子里排课"必须落到具体班级上
      showAppSnackBar(context, context.l10n.scheduleNoClassHint);
      return;
    }
    final added = await showLessonQuickAddSheet(context);
    if (added) {
      await _load();
    }
  }

  /// 「拍照导入课表」（第 11 轮）：手机本机识别课表照片 → 核对 → 排进课表。
  ///
  /// 用户规格（第 12 轮）："既然这个功能可以跑通，集成到课表页-右上角的
  /// 课表设置-拍照导入课表中。" —— 所以这里是课表设置弹层里那一行的唯一出口，
  /// 不再只是设置页 / 课程管理页里的独立入口。
  ///
  /// 导入成功后页面会 pop 一个 `true`，此时必须重新读库，
  /// 否则老师刚导进来的课在格子里"看不见"（本页与设置页是平级 Tab，不会重建）。
  Future<void> _openOcrImport() async {
    final imported = await pushAppPage<bool>(context, const CourseOcrPage());
    if (!mounted || imported != true) {
      return;
    }
    await _load();
  }

  Future<void> _onSwap(
    _ScheduleData data,
    LessonWithTime source,
    LessonWithTime target,
  ) async {
    try {
      await context.read<LessonRepository>().swapLessons(
        source: source,
        target: target,
      );
      await _load();
    } catch (error, stack) {
      AppLogger.e('交换课表失败', error: error, stack: stack);
      if (!mounted) {
        return;
      }
      showAppSnackBar(context, context.l10n.operationFailed('$error'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final data = _data;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.scheduleTitle),
        actions: <Widget>[
          // 多套作息时总是可切：没有班级时切的是「展示的作息」，
          // 有班级时切的是班级绑定（并同步展示作息）
          if (data != null && data.templates.length > 1)
            _TemplateSwitcher(
              templates: data.templates,
              currentTemplateId: data.templateId,
              onSelected: (id) => _switchTemplate(data, id),
            ),
          IconButton(
            tooltip: l10n.scheduleSettings,
            icon: const Icon(Icons.tune_rounded),
            onPressed: data == null || data.templateId == null
                ? null
                : () => _openSettings(data),
          ),
          IconButton(
            tooltip: _mode == _ViewMode.grid
                ? l10n.scheduleAggregateView
                : l10n.scheduleClassView,
            icon: Icon(
              _mode == _ViewMode.grid
                  ? Icons.timeline_rounded
                  : Icons.grid_on_rounded,
            ),
            onPressed: () {
              AppMotion.select();
              setState(() {
                _mode = _mode == _ViewMode.grid
                    ? _ViewMode.timeline
                    : _ViewMode.grid;
              });
            },
          ),
          // 分享：截图**当前显示的课表**（错峰 / 常规以现在屏幕上的为准），
          // 底部拼上 app 名 + 二维码位，存相册 / 唤起系统分享。
          IconButton(
            tooltip: l10n.shareSchedule,
            icon: _sharing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.share_outlined),
            onPressed: data == null || data.templateId == null || _sharing
                ? null
                : _shareSchedule,
          ),
        ],
      ),
      // 右下角**不再有悬浮按钮**（用户规格）：那个「添加课程」胶囊浮在课表上，
      // 正好压住最后一两节课的内容。加课的入口改由设置页承接
      // （设置 → 课程管理 / 班级管理），课表页只在"点空格子但一门课都没有"
      // 的时候才弹一次去加课的提示（见 [_promptNoCourse]）。
      // 课表正文包在 RepaintBoundary 里供分享截图（以当前显示为准）；
      // 另有一块**离屏**的底部信息带（app 名 + 二维码位），平时看不见也不占布局，
      // 只在截图时被 `ScheduleShare` 拼到课表图的最下方。
      body: Stack(
        children: <Widget>[
          Positioned.fill(
            child: RepaintBoundary(
              key: _captureBodyKey,
              child: _buildBody(l10n),
            ),
          ),
          Positioned(
            left: -10000,
            top: 0,
            child: RepaintBoundary(
              key: _captureFooterKey,
              child: SizedBox(
                width: MediaQuery.sizeOf(context).width,
                child: const ScheduleShareFooter(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 分享当前课表：截图 → 底部拼 app 名 + 二维码位 → 存相册 → 唤起系统分享。
  ///
  /// 权限（用户规格："如果需要权限，记的提醒"）：
  /// - Android 10+ 保存相册不需要权限；
  /// - Android 9- 需要存储权限，被拒时给一条带「去设置」的提示
  ///   （系统分享面板不需要权限，始终是兜底出口）。
  Future<void> _shareSchedule() async {
    if (_sharing) {
      return;
    }
    setState(() => _sharing = true);
    try {
      final bytes = await ScheduleShare.capture(
        bodyKey: _captureBodyKey,
        footerKey: _captureFooterKey,
      );
      if (!mounted) {
        return;
      }
      if (bytes == null) {
        showAppSnackBar(context, context.l10n.shareCaptureFailed);
        return;
      }
      var saved = false;
      try {
        await ScheduleShare.saveToGallery(bytes);
        saved = true;
      } on GalException catch (error) {
        // 只有权限被拒才需要打断用户；别的失败（空间不足等）交给分享面板兜底
        if (error.type == GalExceptionType.accessDenied && mounted) {
          showAppSnackBar(
            context,
            context.l10n.shareGalleryPermissionDenied,
            onRetry: AppSettings.openAppSettings,
            retryLabel: context.l10n.shareOpenSettings,
          );
        }
      }
      if (!mounted) {
        return;
      }
      if (saved) {
        showAppSnackBar(context, context.l10n.shareSavedToGallery);
      }
      await ScheduleShare.openShareSheet(bytes, text: context.l10n.appTitle);
    } catch (error, stack) {
      AppLogger.e('分享课表失败', error: error, stack: stack);
      if (mounted) {
        showAppSnackBar(context, context.l10n.shareCaptureFailed);
      }
    } finally {
      if (mounted) {
        setState(() => _sharing = false);
      }
    }
  }

  Widget _buildBody(AppLocalizations l10n) {
    if (_loading && _data == null) {
      return PulseLoading(message: l10n.loading);
    }
    if (_error != null && _data == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(context.l10n.operationFailed('$_error')),
            TextButton(onPressed: _load, child: Text(context.l10n.retry)),
          ],
        ),
      );
    }
    final data = _data;
    if (data == null || data.templateId == null) {
      return EmptyView(
        message: l10n.emptyScheduleHint,
        icon: Icons.calendar_month_outlined,
      );
    }
    return Column(
      children: <Widget>[
        // 表格上方**不再有班级切换条**（用户规格：课表是一张表，
        // 课程不针对某个班级，表格上不该显示导入的班级）。
        // 只在"一个班级都没有"时给一条提示，告诉用户当前用的是默认作息。
        if (data.classes.isEmpty) _buildNoClassBanner(),
        if (_makeupToday != null) _buildMakeupBanner(_makeupToday!),
        Expanded(
          child: AnimatedSwitcher(
            duration: AppMotion.standard,
            switchInCurve: AppMotion.expressive,
            switchOutCurve: AppMotion.exit,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.985, end: 1).animate(animation),
                child: child,
              ),
            ),
            child: KeyedSubtree(
              key: ValueKey<_ViewMode>(_mode),
              child: _mode == _ViewMode.timeline
                  ? _buildTimeline(data)
                  : _buildGrid(data),
            ),
          ),
        ),
      ],
    );
  }

  /// 一个班级都没有时的提示条：表格在下面对应位置照常渲染。
  Widget _buildNoClassBanner() {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.spaceL,
        AppConstants.spaceS,
        AppConstants.spaceL,
        AppConstants.spaceXs,
      ),
      child: Material(
        color: scheme.secondaryContainer.withValues(alpha: 0.7),
        borderRadius: AppRadii.tileAll,
        child: InkWell(
          borderRadius: AppRadii.tileAll,
          onTap: () {
            AppMotion.tap();
            _openClassManagement();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppConstants.spaceM,
              vertical: AppConstants.spaceS,
            ),
            child: Row(
              children: <Widget>[
                Icon(
                  Icons.info_outline_rounded,
                  size: 17,
                  color: scheme.onSecondaryContainer,
                ),
                const SizedBox(width: AppConstants.spaceS),
                Expanded(
                  child: Text(
                    l10n.scheduleNoClassHint,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.onSecondaryContainer,
                    ),
                  ),
                ),
                Text(
                  l10n.addClass,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 17,
                  color: scheme.primary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 调休上班日的提醒条（用户规格第 13 轮）。
  ///
  /// 只在**今天确实是调休上班日**时出现，说清两件事：
  /// 补的是哪个节日的班、今天按星期几的课表上课。
  /// 老师还没确认过"上周几的课"时，文案会明确说"还没确认"并给一个设置入口 ——
  /// 这一条不能替老师猜：上周几的课是各校自己的通知（见 [HolidayService]）。
  Widget _buildMakeupBanner(HolidayDay day) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final shift = day.shiftOverridden
        ? l10n.holidayMakeupResolved(l10n.weekdayShort(day.labelWeekday))
        : l10n.holidayMakeupNotSet;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.spaceL,
        AppConstants.spaceS,
        AppConstants.spaceL,
        AppConstants.spaceXs,
      ),
      child: Material(
        color: scheme.tertiaryContainer.withValues(alpha: 0.85),
        borderRadius: AppRadii.tileAll,
        child: InkWell(
          borderRadius: AppRadii.tileAll,
          onTap: () {
            AppMotion.tap();
            // ignore: discarded_futures — 弹层自己处理错误
            _editMakeupShift(day);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppConstants.spaceM,
              vertical: AppConstants.spaceS,
            ),
            child: Row(
              children: <Widget>[
                Icon(
                  Icons.swap_horiz_rounded,
                  size: 17,
                  color: scheme.onTertiaryContainer,
                ),
                const SizedBox(width: AppConstants.spaceS),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        l10n.holidayMakeupTitle,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: scheme.onTertiaryContainer,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        shift,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onTertiaryContainer.withValues(
                            alpha: 0.85,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  day.shiftOverridden ? l10n.edit : l10n.holidayMakeupSet,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 17,
                  color: scheme.primary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 表头角标文案：本周的调休日补的是哪一天的课。
  ///
  /// 例：`{3: "10-10 调休上班，上本周三的课"}` → 角标画在「周三」那一列，
  /// 老师一扫就知道这周要多上一天、而且照着周三的课表上。
  Map<int, String> _makeupHeaderHints() {
    if (_makeupColumns.isEmpty) {
      return const <int, String>{};
    }
    final l10n = context.l10n;
    return <int, String>{
      for (final entry in _makeupColumns.entries)
        entry.key: l10n.gridMakeupHint(
          _monthDayLabel(entry.value.date),
          l10n.weekdayShort(entry.value.labelWeekday),
        ),
    };
  }

  /// 「10-10」这种短日期：表头提示里空间紧，不带年份。
  static String _monthDayLabel(DateTime date) =>
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  Future<void> _editMakeupShift(HolidayDay day) async {
    // 先把"上次选过的星期几"读出来再弹层：如果把它写进弹层参数里
    // （`suggestWeekday: await ...`），await 会和后面的 context 落在同一个表达式里，
    // 分析器直接判 `use_build_context_synchronously`。
    final suggest = await _holidays.lastShift();
    if (!mounted) {
      return;
    }
    final choice = await showHolidayShiftSheet(
      context,
      date: day.date,
      currentWeekday: day.shiftOverridden ? day.labelWeekday : null,
      suggestWeekday: suggest,
    );
    if (choice == null || !mounted) {
      return;
    }
    await _holidays.setShift(day.date, choice.weekday);
    if (!mounted) {
      return;
    }
    showAppSnackBar(
      context,
      choice.weekday == null
          ? context.l10n.holidayShiftCleared
          : context.l10n.holidayShiftSaved(
              context.l10n.weekdayShort(choice.weekday!),
            ),
    );
    // 结算口径变了，重新读一遍（_load 里会重新取 _makeupToday）
    await _load();
  }

  Widget _buildGrid(_ScheduleData data) {
    final templateId = data.templateId;
    if (templateId == null) {
      return EmptyView(message: context.l10n.emptyScheduleHint);
    }
    return ClassGridView(
      templateId: templateId,
      periodsByWeekday: data.periodsByWeekday,
      lessons: data.gridLessons,
      courseStudentCounts: data.courseCounts,
      events: _events,
      weekStart: app_dates.DateUtils.startOfWeek(DateTime.now()),
      // 「今天」按调休映射落列，并把本周的调休安排提前标在对应列上
      todayWeekday: _todayLabelWeekday,
      makeupHints: _makeupHeaderHints(),
      courseColors: data.courseColors,
      onEmptyCellTap: (weekday, periodIndex) =>
          _onEmptyCellTap(data, weekday, periodIndex),
      onLessonTap: (lesson) => _onLessonTap(data, lesson),
      onPeriodTap: (weekday, periodIndex) =>
          _editPeriodTime(data, weekday, periodIndex),
      onSwap: (source, target) => _onSwap(data, source, target),
    );
  }

  Widget _buildTimeline(_ScheduleData data) {
    final tokens = context.watch<ThemeController>().tokens;
    return TimelineView(
      lessons: data.lessons,
      breakPeriods: data.breakPeriods,
      weekStart: app_dates.DateUtils.startOfWeek(DateTime.now()),
      tokens: tokens,
      weekdays: _activeWeekdays(data),
      events: _events,
      // 曲线档也吃课程自选色 —— 否则改了课程色只有表格档跟着变
      courseColors: data.courseColors,
      onLessonTap: (lesson) =>
          showLessonActionsSheet(context, lesson).then((_) => _load()),
    );
  }

  /// 曲线档要画哪几天：**模板作息里配置了节次的星期** ∪ 有课的星期。
  ///
  /// 用户规格（第 8 轮）："错峰课表如果放七天，字太小，而且周六周日是
  /// 浪费宽度的。最好与用户一键设置作息那里一样，如果用户选择周几，
  /// 这里就对应选择周几。" —— 一键生成作息勾了周几，
  /// `template_period` 里就有那几天的节次，所以直接从作息里推。
  /// 有课但作息行缺失的日子一并画出来（理论不该发生，兜底别漏课）。
  List<int> _activeWeekdays(_ScheduleData data) {
    final days = <int>{
      for (final entry in data.periodsByWeekday.entries)
        if (entry.value.isNotEmpty) entry.key,
      for (final lesson in data.lessons) lesson.lesson.weekday,
    }.toList()..sort();
    return days.isEmpty ? TimelineView.defaultWeekdays : days;
  }

  /// 班级选择条已按用户规格**移除**：课表是一张表、课程不针对某个班级，
  /// 表格上方不需要再列出导入的班级。这里不再保留任何班级切换 UI。
}

/// 右上角「作息切换」：一句话说清当前用的是哪套作息，点开换另一套。
class _TemplateSwitcher extends StatelessWidget {
  const _TemplateSwitcher({
    required this.templates,
    required this.currentTemplateId,
    required this.onSelected,
  });

  final List<ScheduleTemplate> templates;
  final int? currentTemplateId;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final current = templates.where((item) => item.id == currentTemplateId);
    final name = current.isEmpty
        ? context.l10n.templateTitle
        : current.first.name;

    return PopupMenuButton<int>(
      tooltip: context.l10n.switchTemplate,
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(borderRadius: AppRadii.dialogAll),
      onSelected: onSelected,
      itemBuilder: (context) => <PopupMenuEntry<int>>[
        for (final template in templates)
          PopupMenuItem<int>(
            value: template.id!,
            child: Row(
              children: <Widget>[
                Icon(
                  template.id == currentTemplateId
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 18,
                  color: template.id == currentTemplateId
                      ? scheme.primary
                      : scheme.outline,
                ),
                const SizedBox(width: AppConstants.spaceS),
                Expanded(
                  child: Text(template.name, overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
      ],
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(
          horizontal: AppConstants.spaceM,
          vertical: 4,
        ),
        decoration: BoxDecoration(
          color: scheme.secondaryContainer.withValues(alpha: 0.75),
          borderRadius: AppRadii.stadiumAll,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.swap_horiz_rounded,
              size: 16,
              color: scheme.onSecondaryContainer,
            ),
            const SizedBox(width: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 96),
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.onSecondaryContainer,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScheduleData {
  const _ScheduleData({
    required this.classes,
    required this.templates,
    required this.selectedClass,
    required this.templateId,
    required this.lessons,
    required this.breakPeriods,
    required this.periodsByWeekday,
    required this.gridLessons,
    required this.courses,
    required this.courseCounts,
    required this.maxPeriodCount,
  });

  final List<ClassInfo> classes;
  final List<ScheduleTemplate> templates;

  /// 兜底班级（列表第一个）。课表不按班级切分，它只在"课程没挂班级"这种
  /// 理论上的极端情况下，给 `lesson.class_id` 一个落点。
  final ClassInfo? selectedClass;

  /// 表格视图展示的作息模板：**持久化的展示模板优先**，没有再退到班级绑定。
  /// 为 null 表示库里连一个作息模板都没有（理论上不会发生）。
  final int? templateId;
  final List<LessonWithTime> lessons;
  final List<TemplatePeriod> breakPeriods;
  final Map<int, List<TemplatePeriod>> periodsByWeekday;

  /// 表格视图要画的课表条目：**这张课表的全部课**（教师维度），与班级无关。
  final List<LessonWithTime> gridLessons;

  /// 可选的课程：**全量课程**，供「滑动选课」面板与格子配色使用。
  /// 空格子选课不再按班级过滤（用户规格），配色也依赖它拿到课程色。
  final List<CourseDetail> courses;

  /// 课程 id → 人数（合班课为所选班级人数之和），格子里显示这个数
  final Map<int, int> courseCounts;

  /// 一周内节次数最多的一天有几节，用于「一键生成作息」的默认节数。
  final int maxPeriodCount;

  /// 课程自己挑过的颜色优先（**与课程管理里锁定的是同一个来源**），没挑过才
  /// 回落成班级色（`LessonWithTime.classColor`）。两个视图共用这一份：表格档与
  /// 曲线档各构建一遍的话，"改了课程色只有一边跟着变"是迟早的事。
  ///
  /// 用全量课程构建，避免"课在别的班 → 取不到课程色 → 颜色对不上"。
  Map<int, String> get courseColors => <int, String>{
    for (final detail in courses)
      if (detail.id != null) detail.id!: detail.color,
  };

  CourseDetail? detailFor(int courseId) {
    for (final item in courses) {
      if (item.id == courseId) {
        return item;
      }
    }
    return null;
  }
}
