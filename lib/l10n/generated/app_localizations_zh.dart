// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => '全面课表计划';

  @override
  String get ok => '确定';

  @override
  String get cancel => '取消';

  @override
  String get save => '保存';

  @override
  String get delete => '删除';

  @override
  String get edit => '编辑';

  @override
  String get add => '新增';

  @override
  String get back => '返回';

  @override
  String get close => '关闭';

  @override
  String get confirm => '确认';

  @override
  String get retry => '重试';

  @override
  String get loading => '加载中...';

  @override
  String get noData => '暂无数据';

  @override
  String get all => '全部';

  @override
  String get searchHint => '搜索';

  @override
  String get today => '今天';

  @override
  String get mon => '周一';

  @override
  String get tue => '周二';

  @override
  String get wed => '周三';

  @override
  String get thu => '周四';

  @override
  String get fri => '周五';

  @override
  String get sat => '周六';

  @override
  String get sun => '周日';

  @override
  String get tabSchedule => '课表';

  @override
  String get tabAttendance => '考勤';

  @override
  String get tabStatistics => '统计';

  @override
  String get tabTodo => '待办';

  @override
  String get tabToolbox => '工具箱';

  @override
  String get scheduleTitle => '我的课表';

  @override
  String get scheduleAggregateView => '时间轴';

  @override
  String get scheduleClassView => '班级网格';

  @override
  String get selectClass => '选择班级';

  @override
  String get emptyScheduleHint => '本周还没有排课，点击右下角 + 新增一节';

  @override
  String get addLesson => '新增课表';

  @override
  String get editLesson => '编辑课表';

  @override
  String get deleteLesson => '删除课表';

  @override
  String get deleteLessonConfirmBody => '该课表条目及其关联的考勤记录将被一并删除，且无法撤销。';

  @override
  String get lessonSaved => '课表已保存';

  @override
  String get lessonDeleted => '课表已删除';

  @override
  String get conflictMessage => '该时间段已存在其他课程，存在时间冲突';

  @override
  String get slotOccupied => '该班级本节的课表格子已被占用';

  @override
  String get noTemplatePeriod => '该班级绑定的作息模板中没有对应的节次';

  @override
  String get quickAddLessonHint => '按 班级 → 课程 → 周几/节次 三步把课排进课表';

  @override
  String get swapModeHint => '交换模式：拖拽一个格子到另一个格子上即可互换';

  @override
  String get swapForbidden => '跨班级或跨模板不支持直接交换';

  @override
  String get swapDone => '课表格子已交换';

  @override
  String get editLessonTime => '修改时间';

  @override
  String get cascadeTitle => '修改范围';

  @override
  String get cascadeOnlyThis => '仅修改本节';

  @override
  String get cascadeAllFollowing => '同步修改后续所有节次';

  @override
  String periodIndexLabel(int index) {
    return '第 $index 节';
  }

  @override
  String get templateTitle => '作息模板';

  @override
  String get templateNew => '新建模板';

  @override
  String get templateName => '模板名称';

  @override
  String get templateNameRequired => '模板名称不能为空';

  @override
  String get templateSetDefault => '设为默认';

  @override
  String get templateSetDefaultConfirm => '新建班级时将默认使用此模板，已绑定其他模板的班级不受影响。';

  @override
  String get templateIsDefault => '默认';

  @override
  String templateBoundClasses(int count) {
    return '$count 个班级';
  }

  @override
  String get templateDelete => '删除模板';

  @override
  String get templateDeleteBlocked => '无法删除该模板';

  @override
  String templateDeleteBlockedBody(String names) {
    return '以下班级仍绑定该模板，请先迁移：$names';
  }

  @override
  String templateEditAffectClasses(int count) {
    return '此操作会影响 $count 个班级的课表显示时间，不会修改具体上课内容安排。';
  }

  @override
  String get copyFromOtherDay => '从其他工作日复制';

  @override
  String get copyToTargets => '复制到';

  @override
  String get copyDone => '已复制';

  @override
  String get addPeriod => '新增节次';

  @override
  String get removePeriod => '删除节次';

  @override
  String get periodType => '类型';

  @override
  String get periodStart => '开始时间';

  @override
  String get periodEnd => '结束时间';

  @override
  String get periodLabel => '备注';

  @override
  String get periodTypeNormal => '普通课节';

  @override
  String get periodTypeLunch => '午休';

  @override
  String get periodTypeRecess => '课间大休';

  @override
  String get periodTypeSelfStudy => '自习';

  @override
  String get periodTypeOther => '其他';

  @override
  String get periodErrorInvalidFormat => '时间格式必须为 HH:mm';

  @override
  String get periodErrorEndBeforeStart => '结束时间必须晚于起始时间';

  @override
  String get periodErrorOverlap => '与其他时段重叠';

  @override
  String get periodErrorNotAscending => '起始时间需随节次序号递增';

  @override
  String get templateSaved => '模板已保存';

  @override
  String get attendanceTitle => '考勤';

  @override
  String get calendarMonth => '月视图';

  @override
  String get calendarWeek => '周视图';

  @override
  String get courseChipToday => '今日有课';

  @override
  String get courseChipOther => '其他课程';

  @override
  String get studentList => '学生名单';

  @override
  String get sortByName => '按姓名拼音';

  @override
  String get sortByNo => '按学号';

  @override
  String get sortByStatus => '按考勤状态';

  @override
  String get statusPresent => '出勤';

  @override
  String get statusLate => '迟到';

  @override
  String get statusEarlyLeave => '早退';

  @override
  String get statusAbsent => '缺勤';

  @override
  String get statusLeave => '请假';

  @override
  String get statusUnmarked => '未标记';

  @override
  String get rollCall => '随机点名';

  @override
  String get rollCallTitle => '点名中...';

  @override
  String get copySummary => '复制出勤摘要';

  @override
  String get copiedToClipboard => '出勤摘要已复制到剪贴板';

  @override
  String get highRisk => '高风险';

  @override
  String riskScoreLabel(int score) {
    return '风险分 $score';
  }

  @override
  String get tagTitle => '表现标签';

  @override
  String get starRating => '星级';

  @override
  String get remark => '文字备注';

  @override
  String get noStudentsHint => '该班级还没有学生';

  @override
  String get attendanceSaved => '考勤已保存';

  @override
  String get tagActiveSpeaking => '积极发言';

  @override
  String get tagHomeworkOnTime => '按时完成作业';

  @override
  String get tagFocusedListening => '专注听讲';

  @override
  String get tagHelpingOthers => '乐于助人';

  @override
  String get tagGoodQuestion => '善于提问';

  @override
  String get tagNeatHandwriting => '书写工整';

  @override
  String get tagTeamLeader => '小组带头';

  @override
  String get statisticsTitle => '统计与导出';

  @override
  String get granularityDay => '按日';

  @override
  String get granularityWeek => '按周';

  @override
  String get granularityMonth => '按月';

  @override
  String get attendanceRateChart => '出勤率折线图';

  @override
  String get courseRateChart => '课程出勤率';

  @override
  String get abnormalList => '异常出勤明细';

  @override
  String get riskRanking => '高风险学生排名';

  @override
  String get emotionCard => '情绪价值卡片';

  @override
  String get exportExcel => '导出 Excel';

  @override
  String get exportSuccess => 'Excel 已生成';

  @override
  String get filterByStatus => '按状态筛选';

  @override
  String get attendanceRateLabel => '出勤率';

  @override
  String get emotionExcellent => '这个班级的孩子们真给力！';

  @override
  String get emotionGood => '出勤稳稳的，继续保持！';

  @override
  String get emotionNormal => '每一点进步都值得被看见。';

  @override
  String get emotionEncourage => '新的一周，新的闪光点。';

  @override
  String get todoTitle => '待办';

  @override
  String get todoSmart => '智能待办';

  @override
  String get todoGeneral => '通用清单';

  @override
  String get todoAdd => '新增待办';

  @override
  String get todoTitleRequired => '待办标题不能为空';

  @override
  String get todoDescription => '描述（可选）';

  @override
  String get todoPriority => '优先级';

  @override
  String get priorityHigh => '高';

  @override
  String get priorityMedium => '中';

  @override
  String get priorityLow => '低';

  @override
  String get todoDueDate => '截止日期（可选）';

  @override
  String get todoAutoCompleted => '系统自动完成';

  @override
  String get todoDeleteConfirmBody => '该待办将被永久删除，无法恢复。';

  @override
  String get emptyTodo => '暂时没有待办事项';

  @override
  String todoCompletedSection(int count) {
    return '已完成（$count）';
  }

  @override
  String get toolboxTitle => '教师工具箱';

  @override
  String get focusTimer => '专注模式';

  @override
  String get focusStart => '开始';

  @override
  String get focusPause => '暂停';

  @override
  String get focusResume => '继续';

  @override
  String get focusReset => '重置';

  @override
  String get focusBreak => '休息';

  @override
  String get focusDone => '专注完成';

  @override
  String get scheduleCalendar => '日程安排';

  @override
  String get eventAdd => '新增日程';

  @override
  String get eventTitle => '标题';

  @override
  String get eventLocation => '地点（可选）';

  @override
  String get eventReminder => '提醒';

  @override
  String get eventReminderBefore => '提前分钟数';

  @override
  String get manageTitle => '管理';

  @override
  String get manageClasses => '班级管理';

  @override
  String get manageCourses => '课程管理';

  @override
  String get manageStudents => '学生管理';

  @override
  String get className => '班级名称';

  @override
  String get gradeName => '年级';

  @override
  String get headTeacher => '班主任';

  @override
  String studentCountLabel(int count) {
    return '$count 名学生';
  }

  @override
  String get classColor => '标记颜色';

  @override
  String get templateBinding => '作息模板';

  @override
  String get studentName => '姓名';

  @override
  String get studentNo => '学号';

  @override
  String get importExcel => 'Excel 批量导入';

  @override
  String get importPreview => '导入预览';

  @override
  String importResult(int success, int fail, int skip) {
    return '成功 $success 行，失败 $fail 行，跳过 $skip 行';
  }

  @override
  String get importReasonMissingName => '姓名为空';

  @override
  String get importReasonClassNotFound => '未匹配到班级';

  @override
  String get importReasonDuplicate => '已存在';

  @override
  String get importDone => '导入完成';

  @override
  String get dragToReorderHint => '长按拖拽调整顺序';

  @override
  String get batchUpdateTemplate => '批量修改作息模板';

  @override
  String batchUpdateTemplateConfirm(String names) {
    return '以下班级将被更新：$names';
  }

  @override
  String get classDeleteConfirmBody => '删除班级会同时删除其课程、课表、学生与全部考勤记录，且无法恢复。';

  @override
  String get settingsTitle => '设置';

  @override
  String get language => '语言';

  @override
  String get languageZh => '简体中文';

  @override
  String get languageEn => 'English';

  @override
  String get theme => '主题';

  @override
  String get themeMint => '清新薄荷';

  @override
  String get themeMinimalGray => '极简灰白';

  @override
  String get themeNightCare => '深夜护眼';

  @override
  String get riskThreshold => '高风险缺勤次数阈值';

  @override
  String get attendanceWarnThreshold => '出勤率警示阈值（%）';

  @override
  String get retentionDays => '考勤保留天数';

  @override
  String get retentionImportLogDays => '导入日志保留天数';

  @override
  String get cascadeSwitch => '时间列级联更新';

  @override
  String get defaultAttendanceStatus => '未记录日期的默认状态';

  @override
  String get notificationPermission => '通知权限';

  @override
  String get notificationCheck => '检查权限状态';

  @override
  String get notificationOpenSettings => '前往系统设置开启';

  @override
  String get notificationGranted => '通知权限已开启';

  @override
  String get notificationDenied => '通知权限未开启';

  @override
  String get lessonReminder => '课前提醒';

  @override
  String get reminderMinutesBefore => '提前提醒分钟数';

  @override
  String get reminderRegenerate => '立即重算提醒';

  @override
  String reminderRegenerated(int count) {
    return '已按当前作息模板重新生成 $count 条提醒';
  }

  @override
  String get cleanupNow => '清理过期数据';

  @override
  String cleanupResult(int attendance, int logs) {
    return '已清理考勤 $attendance 条、导入日志 $logs 条';
  }

  @override
  String get cleanupAborted => '备份失败，已取消本次清理';

  @override
  String get dangerZone => '危险操作';

  @override
  String get clearAllData => '清空全部数据';

  @override
  String get clearAllDataConfirm => '所有班级、课程、课表、学生、考勤与待办将被永久清除，无法恢复。';

  @override
  String get aboutTitle => '关于';

  @override
  String versionLabel(String version) {
    return '版本 $version';
  }

  @override
  String autoTodoTitle(String className) {
    return '检查 $className 本周缺勤学生情况';
  }

  @override
  String get colRow => '行号';

  @override
  String get colName => '姓名';

  @override
  String get colNo => '学号';

  @override
  String get colClass => '班级';

  @override
  String get colStatus => '状态';

  @override
  String get classFormTitle => '班级';

  @override
  String get courseFormTitle => '课程';

  @override
  String get studentFormTitle => '学生';

  @override
  String get eventFormTitle => '日程';

  @override
  String get addClass => '新增班级';

  @override
  String get addCourse => '新增课程';

  @override
  String get addStudent => '新增学生';

  @override
  String get addEvent => '新增日程';

  @override
  String get addNote => '新增笔记';

  @override
  String get deleteNote => '删除笔记';

  @override
  String get deleteEvent => '删除日程';

  @override
  String get deleteStudent => '删除学生';

  @override
  String get deleteCourse => '删除课程';

  @override
  String get deleteClass => '删除班级';

  @override
  String get pickColor => '选择颜色';

  @override
  String get importChooseFile => '选择 Excel 文件';

  @override
  String get classSaved => '班级已保存';

  @override
  String get courseSaved => '课程已保存';

  @override
  String get studentSaved => '学生已保存';

  @override
  String get eventSaved => '日程已保存';

  @override
  String get dismiss => '忽略';

  @override
  String get timePickerTitle => '选择时间';

  @override
  String get hour => '时';

  @override
  String get minute => '分';

  @override
  String get requiredField => '该项为必填';

  @override
  String operationFailed(String message) {
    return '操作失败：$message';
  }

  @override
  String get unexpectedError => '发生未知错误，请重试';

  @override
  String get tabSettings => '设置';

  @override
  String get scheduleModeTraditional => '传统课表';

  @override
  String get scheduleModeStaggered => '错峰课表';

  @override
  String get scheduleModeSwitch => '切换课表视图';

  @override
  String get scheduleSettings => '课表设置';

  @override
  String get gridPeriodHeader => '节次';

  @override
  String get gridTimeHeader => '时间';

  @override
  String get todayLabel => '今天';

  @override
  String get quickGenerateTitle => '一键生成作息';

  @override
  String get quickGenerateDesc => '按开始时间、每节时长、课间间隔与节数批量生成';

  @override
  String get generateStartTime => '开始时间';

  @override
  String get generateLessonMinutes => '每节课时长（分钟）';

  @override
  String get generateBreakMinutes => '课间间隔（分钟）';

  @override
  String get generatePeriodCount => '一天节数';

  @override
  String get generateWeekdays => '应用到';

  @override
  String get generatePreview => '生成预览';

  @override
  String generateDone(int count) {
    return '已生成 $count 节';
  }

  @override
  String generatePreviewRow(int index, String start, String end) {
    return '第 $index 节　$start-$end';
  }

  @override
  String get generateInvalidRange => '时间超出一天范围，请减少节数或缩短时长';

  @override
  String get generateEmptyWeekdays => '请至少选择一个星期';

  @override
  String get editPeriodTime => '修改本节时间';

  @override
  String get editPeriodTimeDesc => '仅修改该节次，可选择是否顺延后续节次';

  @override
  String get cascadeFollowing => '后续节次自动顺延';

  @override
  String get periodTimeUpdated => '本节时间已更新';

  @override
  String cascadeApplied(int count) {
    return '已顺延 $count 节';
  }

  @override
  String get defaultTemplateEdit => '默认作息修改';

  @override
  String get defaultTemplateHint => '新建班级默认使用该作息';

  @override
  String get clearSchedule => '一键清空课表';

  @override
  String get clearScheduleConfirm => '将清除当前作息模板下所有班级的课表内容，作息时间保留，且不可撤销。';

  @override
  String get clearScheduleDone => '课表已清空';

  @override
  String get importPhotoSchedule => '拍照导入课表';

  @override
  String get importPhotoScheduleHint => '拍照或从相册选一张课表，本机识别后自动排进课表';

  @override
  String get comingSoon => '敬请期待';

  @override
  String get toolboxAllTools => '全部工具';

  @override
  String get toolStatistics => '统计';

  @override
  String get toolTodo => '待办';

  @override
  String get toolFocus => '专注模式';

  @override
  String get toolCalendar => '日程安排';

  @override
  String get toolboxInsight => '本周教学成果';

  @override
  String get insightDoneLessons => '已上课时';

  @override
  String get insightLeftLessons => '剩余课时';

  @override
  String get insightAttention => '需关注';

  @override
  String get insightNoAttention => '暂无异常，继续保持';

  @override
  String get insightAttendanceRate => '本周出勤率';

  @override
  String insightCheer(int done) {
    return '本周已完成 $done 节课，辛苦了';
  }

  @override
  String insightStudentRisk(String name, int count) {
    return '$name 本周缺勤 $count 次';
  }

  @override
  String pageIndicator(int current, int total) {
    return '第 $current / $total 页';
  }

  @override
  String weekRange(String start, String end) {
    return '$start ~ $end';
  }

  @override
  String get groupScheduleData => '课表与名单';

  @override
  String get groupPermission => '通知权限';

  @override
  String get groupDisplay => '显示与语言';

  @override
  String get groupAbout => '关于';

  @override
  String get studentRoster => '学生名单';

  @override
  String get studentRosterDesc => '添加、修改、删除学生，或从 Excel 批量导入';

  @override
  String get classManagement => '班级管理';

  @override
  String get classManagementDesc => '导入名单后自动生成班级与人数';

  @override
  String get courseManagement => '课程管理';

  @override
  String get courseManagementDesc => '新增课程、维护教室与上课班级（课表页点空格子即可排进这一格）';

  @override
  String get statisticsSettings => '统计设置';

  @override
  String get statisticsSettingsDesc => '高风险判定与出勤预警线';

  @override
  String get studentGender => '性别';

  @override
  String get genderMale => '男';

  @override
  String get genderFemale => '女';

  @override
  String get genderUnset => '未填';

  @override
  String get studentNoOptional => '学号（选填）';

  @override
  String get studentNameRequired => '姓名（必填）';

  @override
  String get studentClassRequired => '班级（必填）';

  @override
  String get studentFormDesc => '姓名与班级为必填，性别与学号可选';

  @override
  String get courseNameLabel => '课程名称';

  @override
  String get courseRoomLabel => '上课教室';

  @override
  String get courseClassLabel => '上课班级';

  @override
  String get courseCountLabel => '人数';

  @override
  String get courseRemarkLabel => '备注';

  @override
  String get courseMultiClassHint => '可选择多个班级（合班 / 大课）';

  @override
  String get courseClassRequired => '请至少选择一个班级';

  @override
  String get courseAutoCountHint => '根据所选班级自动统计';

  @override
  String get courseClearAll => '清空全部课程';

  @override
  String get courseClearAllConfirm => '将删除全部课程及其课表条目，且不可撤销。';

  @override
  String get courseCleared => '课程已清空';

  @override
  String get importStudents => 'Excel 批量导入学生名单';

  @override
  String get importFormatTitle => '文件格式说明';

  @override
  String get importFormatLine1 => '仅支持 .xlsx 文件';

  @override
  String get importFormatLine2 => '必须包含「姓名」「班级」两列';

  @override
  String get importFormatLine3 => '「学号」「性别」为可选列';

  @override
  String get importFormatLine4 => '未匹配到的班级会自动创建';

  @override
  String get importFormatExample => '示例';

  @override
  String importAutoCreated(int count) {
    return '自动创建班级 $count 个';
  }

  @override
  String importRowsTotal(int count) {
    return '共解析 $count 行';
  }

  @override
  String get importNeedNameOrClass => '「姓名」「班级」两列都必须填写';

  @override
  String get importOverall => '导入总览';

  @override
  String get importClassColumn => '班级';

  @override
  String get aboutVersion => '版本';

  @override
  String get aboutChangelog => '更新说明';

  @override
  String get aboutChangelogBody =>
      '1.0.0 首个正式版本：课表 / 考勤 / 统计 / 待办 / 工具箱全面上线，支持六套主题与中英文。';

  @override
  String get aboutDeveloper => '开发者';

  @override
  String get aboutDeveloperName => '教学助手团队';

  @override
  String get aboutAppName => '全面课表计划';

  @override
  String get sortAscending => '升序';

  @override
  String get sortDescending => '降序';

  @override
  String get attendanceWeekDefault => '按周查看';

  @override
  String get attendanceMonthView => '按月查看';

  @override
  String get attendanceNoLesson => '当天没有课';

  @override
  String attendanceCountSummary(int total, int present) {
    return '共 $total 人 · 出勤 $present 人';
  }

  @override
  String get markAll => '全部标记';

  @override
  String get statsRiskThresholdDesc => '一周内缺勤达到该次数即标记为高风险';

  @override
  String get statsWarnThresholdDesc => '低于该出勤率时在图表中高亮预警';

  @override
  String get statsColumnName => '姓名';

  @override
  String get statsColumnNo => '学号';

  @override
  String get statsColumnStatus => '考勤';

  @override
  String get toolStatisticsDesc => '出勤率趋势与排名';

  @override
  String get toolTodoDesc => '智能待办与通用清单';

  @override
  String get toolFocusDesc => '番茄钟专注计时';

  @override
  String get toolCalendarDesc => '日程与课前提醒';

  @override
  String get importReasonMissingClass => '缺少班级';

  @override
  String get noStudentNo => '未填学号';

  @override
  String get unitTimes => '次';

  @override
  String get unitDays => '天';

  @override
  String get unitMinutes => '分钟';

  @override
  String get unitPercent => '%';

  @override
  String get settingsSubtitle => '课表、名单、权限与显示';

  @override
  String get themeSunrise => '晨曦暖橙';

  @override
  String get themeOceanBlue => '静谧深蓝';

  @override
  String get themeSakura => '樱花粉';

  @override
  String get scheduleCleared => '课表已清空';

  @override
  String get periodTimeSaved => '节次时间已更新';

  @override
  String get switchTemplate => '切换作息';

  @override
  String scheduleGenerated(int count) {
    return '已生成 $count 节课的作息';
  }

  @override
  String get studentNameShort => '姓名';

  @override
  String get studentNoShort => '学号';

  @override
  String get attendanceColumn => '考勤';

  @override
  String calendarMonthTitle(int year, int month) {
    return '$year年$month月';
  }

  @override
  String calendarWeekTitle(String start, String end) {
    return '$start ~ $end';
  }

  @override
  String get importFileUnreadable =>
      '这份表格读不出来。请确认是未加密的 .xlsx 文件，或用 Excel/WPS 打开后另存为 .xlsx 再试。';

  @override
  String get scheduleNoClassHint => '还没有班级，当前显示默认作息';

  @override
  String get cellNoCourseTitle => '这一格还没有课程';

  @override
  String get cellNoCourseBody => '先在课程管理里建好课程，回来点这一格就能左右滑动挑选并排进课表。';

  @override
  String get cellNeedsClassBody => '还没有班级，先建一个班级并导入学生名单，才能往格子里排课。';

  @override
  String get goAddCourse => '去添加课程';

  @override
  String get goCreateClass => '去建班级';

  @override
  String get pickCourseTitle => '选一门课放进这一格';

  @override
  String get pickCourseHint => '上下滑动浏览，点一下选中，再放进这一格';

  @override
  String get placeHere => '放进这一格';

  @override
  String get noCourseYet => '还没有课程';

  @override
  String get lessonDetailTitle => '课程信息';

  @override
  String get goRollCall => '去点名';

  @override
  String get changeLessonCourse => '换个课程';

  @override
  String get removeFromSchedule => '移出课表';

  @override
  String get removedFromSchedule => '已移出课表';

  @override
  String get placedToSchedule => '已排进课表';

  @override
  String cellStudentCount(int count) {
    return '$count 人';
  }

  @override
  String get classHeadTeacherFromClass => '班主任（取自所属班级）';

  @override
  String classDeleteConfirmWithStudents(int count) {
    return '该班级下还有 $count 名学生，删除后学生、课程、课表与全部考勤记录都会一并删除，且无法恢复。';
  }

  @override
  String get classCreatedNextStep => '班级已创建，去添加这个班的学生名单';

  @override
  String get goAddStudents => '去加名单';

  @override
  String attendanceLocatedTo(String date) {
    return '已定位到 $date';
  }

  @override
  String get dialAmLabel => '上午';

  @override
  String get dialPmLabel => '下午';

  @override
  String get dialTwoRingHint => '内圈点小时，外圈点分钟';

  @override
  String periodDurationMinutes(int count) {
    return '本节时长 $count 分钟';
  }

  @override
  String get periodAutoEndHint => '结束时间按本节时长自动计算';

  @override
  String get periodCustomEnd => '自定义结束时间';

  @override
  String get periodAutoEndBadge => '自动';

  @override
  String get classInfoTitle => '班级信息';

  @override
  String get classStatStudents => '学生总数';

  @override
  String get classStatMale => '男生';

  @override
  String get classStatFemale => '女生';

  @override
  String get classStatUnset => '未填性别';

  @override
  String get classDetailStudents => '本班学生';

  @override
  String get classDetailStudentsDesc => '点学生即可修改，右侧图标可删除';

  @override
  String get classDetailNoStudents => '这个班还没有学生，点右下角添加';

  @override
  String get classDetailCourses => '这个班的课程';

  @override
  String get classDetailCoursesDesc => '维护课程名称、教室与上课班级';

  @override
  String get classDetailTapHint => '点击进入班级详情';

  @override
  String get deleteStudentConfirmBody => '删除后该学生的考勤记录也会一并删除，且无法恢复。';

  @override
  String rosterSummary(int students, int classes) {
    return '共 $students 名学生 · $classes 个班级';
  }

  @override
  String get rosterEmptyGuide => '还没有学生，先从 Excel 导入名单';

  @override
  String get goImportRoster => '去导入名单';

  @override
  String get coursePickClassTitle => '选择上课班级';

  @override
  String get coursePickClassHint => '可多选（合班 / 大课），人数自动汇总';

  @override
  String get pickClass => '选择班级';

  @override
  String get teacherUnset => '未设置';

  @override
  String get periodRestoreAuto => '恢复自动';

  @override
  String get classDetailTitle => '班级详情';

  @override
  String get importAutoHint => '已自动导入，无需再次确认';

  @override
  String get importGoRoster => '去学生名单';

  @override
  String importDetailToggle(int count) {
    return '查看导入明细（共 $count 行）';
  }

  @override
  String get importDetailHide => '收起导入明细';

  @override
  String get courseColorLabel => '课程颜色';

  @override
  String get courseColorAuto => '跟随班级色';

  @override
  String get courseColorHint => '选一个颜色，课表格子会用这个颜色标记这门课';

  @override
  String get generateReplacesHint => '以本次选择为准，未选中的星期会被清空';

  @override
  String get importEmptyFile => '表格里没读到学生行，请确认「姓名」「班级」两列有内容';

  @override
  String get moreActions => '更多操作';

  @override
  String get statusShortPresent => '出';

  @override
  String get statusShortLate => '迟';

  @override
  String get statusShortEarlyLeave => '早';

  @override
  String get statusShortAbsent => '缺';

  @override
  String get statusShortLeave => '假';

  @override
  String get statusShortUnmarked => '—';

  @override
  String get statusSuspended => '休学';

  @override
  String get statusExempt => '免修';

  @override
  String get statusShortSuspended => '休';

  @override
  String get statusShortExempt => '免';

  @override
  String attendanceLongTermUntil(String status, String date) {
    return '$status · 至 $date';
  }

  @override
  String attendanceLongTermSet(String name, String status, String date) {
    return '$name 已标记为$status，至 $date';
  }

  @override
  String attendanceLongTermCleared(String name) {
    return '$name 已恢复正常点名';
  }

  @override
  String attendanceLongTermClearTitle(String status) {
    return '取消$status？';
  }

  @override
  String attendanceLongTermClearBody(String name) {
    return '$name 将恢复正常点名，之后每节课都要单独标记。';
  }

  @override
  String attendanceLongTermLocked(String name, String status, String date) {
    return '$name · $status（至 $date），无需逐节点名';
  }

  @override
  String rosterGroupCount(int count) {
    return '$count 人';
  }

  @override
  String get shareSchedule => '分享课表';

  @override
  String get shareSavedToGallery => '已保存到相册';

  @override
  String get shareGalleryPermissionDenied => '需要「照片和视频」权限才能保存到相册';

  @override
  String get shareOpenSettings => '去设置';

  @override
  String get shareCaptureFailed => '截图失败，请重试';

  @override
  String get shareQrPlaceholder => '二维码位';

  @override
  String get copyAction => '复制';

  @override
  String get summaryNoAbnormal => '全员出勤，无异常';

  @override
  String get courseFilterLabel => '按课程筛选';

  @override
  String get eventRecurrence => '重复周期';

  @override
  String get eventRecurrenceOnce => '单次';

  @override
  String get eventRecurrenceWeekly => '每周';

  @override
  String get eventRecurrenceBiweekly => '隔周';

  @override
  String get eventRecurrenceMonthly => '每月';

  @override
  String get insightBenefitedStudents => '受益学生';

  @override
  String get toolboxSwipeHint => '左右滑动 · 共 2 页';

  @override
  String get ocrTitle => '拍照识别课表';

  @override
  String get ocrEntryTitle => '拍照生成课表';

  @override
  String get ocrEntryDesc => '拍一张课表照片，本机识别后自动排进课表';

  @override
  String get ocrPickPhoto => '选择课表照片';

  @override
  String get ocrPickPhotoHint => '把整张课表拍平、拍正，字要清楚；表头有「周一…周五」和「第 N 节」最容易识别';

  @override
  String get ocrFromCamera => '拍照';

  @override
  String get ocrFromGallery => '从相册选';

  @override
  String get ocrRecognizing => '正在识别…';

  @override
  String get ocrRecognizingHint => '全部在本机完成，照片不会上传到任何服务器';

  @override
  String get ocrCropTitle => '框选课表区域';

  @override
  String get ocrCropHint => '只框住表格本身，去掉标题和空白，识别更准';

  @override
  String get ocrCropReset => '重新框选';

  @override
  String get ocrCropConfirm => '识别这块区域';

  @override
  String get ocrResultTitle => '识别结果';

  @override
  String ocrResultSummary(Object courses, Object days, Object lessons) {
    return '$lessons 节课 · $courses 门课 · 覆盖 $days 天';
  }

  @override
  String get ocrConfidenceHigh => '识别效果不错，确认无误后导入';

  @override
  String get ocrConfidenceMedium => '识别结果一般，请逐条核对后再导入';

  @override
  String get ocrConfidenceLow => '这张照片不太清楚，建议重拍或手动修正';

  @override
  String get ocrImport => '导入课表';

  @override
  String ocrImportDone(Object courses, Object lessons) {
    return '已导入 $lessons 节课，新增 $courses 门课程';
  }

  @override
  String get ocrRecapture => '重拍一张';

  @override
  String get ocrEditRow => '点击可修改课程名';

  @override
  String get ocrRowEditTitle => '修改课程名';

  @override
  String get ocrNoPhoto => '没有选择照片';

  @override
  String get ocrNoPhotoPermission => '需要「照片」权限才能读取课表图片';

  @override
  String get ocrEngineUnavailable => '本机没有可用的文字识别引擎，请改用 Excel 导入';

  @override
  String get ocrEngineUnavailableTitle => '无法调用识别引擎';

  @override
  String get ocrEngineUnavailableBody =>
      '文字识别完全跑在手机本机（Google ML Kit 离线模型），不需要联网、也不会上传照片。当前设备取不到这个能力，通常是系统版本过低或缺少 Google 服务。你可以先用「Excel 导入名单」那条路，或者手动在课表里排课。';

  @override
  String get ocrWarnNoWeekday => '没认到「周几」表头，请确认照片拍全了整张表';

  @override
  String get ocrWarnPartialWeekday => '只认到部分星期列，可能有几天没识别出来';

  @override
  String get ocrWarnNoPeriod => '没认到「第几节」表头，建议重拍或手动修正';

  @override
  String get ocrWarnNoLesson => '没有识别出任何课程，换个角度或拍清楚一点再试';

  @override
  String get ocrManualAdd => '手动补一节';

  @override
  String get ocrAllWeekdays => '全部';

  @override
  String get ocrNoGoogleServices => '未安装 Google 服务，识别功能不可用';

  @override
  String get ocrSettingsHint => '拍张课表照片，本机识别后自动排进这一格';

  @override
  String get ocrDeviceTitle => '机型适配';

  @override
  String get ocrDeviceAndroid =>
      '安卓（小米 / OPPO / vivo 等国产手机）：可直接使用。识别用系统自带的离线文字识别，有 Google 服务走 ML Kit，没有则自动回落到系统自带识别，全程不联网。';

  @override
  String get ocrDeviceHarmony =>
      '华为（鸿蒙 HarmonyOS）：本功能暂未适配，鸿蒙缺少上述两个识别接口。后续会按鸿蒙的 AI 能力单独接一版，当前请先用 Excel 导入或手动排课。';

  @override
  String get ocrDeviceIos => '苹果 iOS：能力已预留在 Apple Vision 上，等 iOS 版本开发时一并启用。';

  @override
  String get timelineEventLegend => '日程';

  @override
  String timelineEventTime(String start, String end) {
    return '$start - $end';
  }

  @override
  String get timelineEventTapHint => '点一下看时间';

  @override
  String get holidayKindHoliday => '休';

  @override
  String get holidayKindMakeup => '班';

  @override
  String get holidayLegend => '红底=放假 · 橙底=调休上班';

  @override
  String get holidayNameNewYear => '元旦';

  @override
  String get holidayNameSpringFestival => '春节';

  @override
  String get holidayNameQingming => '清明节';

  @override
  String get holidayNameLabourDay => '劳动节';

  @override
  String get holidayNameDragonBoat => '端午节';

  @override
  String get holidayNameMidAutumn => '中秋节';

  @override
  String get holidayNameNationalDay => '国庆节';

  @override
  String get holidayNameNationalDayMidAutumn => '国庆节、中秋节';

  @override
  String get holidayMakeupTitle => '今天调休上班';

  @override
  String holidayMakeupAsk(String name) {
    return '补$name的班。学校通知上星期几的课？';
  }

  @override
  String holidayMakeupResolved(String weekday) {
    return '按$weekday的课表上课';
  }

  @override
  String get holidayMakeupNotSet => '还没确认上周几的课，课时结算先按当天算';

  @override
  String get holidayMakeupSet => '设置';

  @override
  String get holidayShiftTitle => '这天上周几的课？';

  @override
  String get holidayShiftBody => '以学校通知为准。选完之后，这一天的课时会按它来结算。';

  @override
  String get holidayShiftNone => '不调整（按当天）';

  @override
  String holidayShiftSaved(String weekday) {
    return '已按$weekday的课表结算';
  }

  @override
  String get holidayShiftCleared => '已恢复为不调整';

  @override
  String holidayOutsideCoverage(int year) {
    return '$year 年的放假安排尚未收录，先按周末休息处理';
  }

  @override
  String holidayFreeCount(int count) {
    return '本周放假 $count 天';
  }

  @override
  String holidayMakeupCount(int count) {
    return '本周调休上班 $count 天';
  }

  @override
  String get toolboxOverviewTitle => '数据概览';

  @override
  String get toolboxTodayTitle => '今日回顾';

  @override
  String get insightWeekLessons => '本周上课';

  @override
  String get insightTotalLessons => '总课节数';

  @override
  String get insightFocusCount => '专注次数';

  @override
  String get insightTodayLessons => '今天课节';

  @override
  String get insightTodayNoLesson => '今天没有课';

  @override
  String insightUnitDays(int count) {
    return '$count 天';
  }

  @override
  String insightUnitLessons(int count) {
    return '$count 节课';
  }

  @override
  String insightUnitPeriods(int count) {
    return '$count 节';
  }

  @override
  String insightUnitTimes(int count) {
    return '$count 次';
  }

  @override
  String insightUnitCourses(int count) {
    return '$count 门课程';
  }

  @override
  String insightFocusMinutes(int minutes) {
    return '累计专注 $minutes 分钟';
  }

  @override
  String get insightFocusNoRecord => '本周还没专注过';

  @override
  String get insightSectionLessons => '课时分布';

  @override
  String get insightSectionAttendance => '出勤情况';

  @override
  String get insightSectionFocus => '专注投入';

  @override
  String get insightSectionEvents => '额外事务';

  @override
  String get insightSectionLessonsDesc => '每天、每门课各多少节';

  @override
  String get insightSectionAttendanceDesc => '出勤率与最需要关注的班';

  @override
  String get insightSectionEventsDesc => '日程里安排的活动';

  @override
  String insightDoneOfTotal(int done, int total) {
    return '已上 $done / 共 $total 节';
  }

  @override
  String get insightPerDayTitle => '每天课节';

  @override
  String get insightPerCourseTitle => '按课程';

  @override
  String get insightBestClass => '出勤最好';

  @override
  String get insightWorstClass => '最需要关注';

  @override
  String insightClassRate(int rate, int total) {
    return '$rate% · $total 人次';
  }

  @override
  String get insightNoClassData => '本周还没有点名记录';

  @override
  String get insightSingleClass => '本周只点了一个班的名，暂无可比对象';

  @override
  String get insightEventsEmpty => '本周没有额外事务';

  @override
  String insightEventWithLocation(String title, String location) {
    return '$title · $location';
  }

  @override
  String get insightNoLessonThisWeek => '本周还没有排课';

  @override
  String insightUnitMinutes(int count) {
    return '$count 分钟';
  }

  @override
  String insightUnitStudents(int count) {
    return '$count 位学生';
  }

  @override
  String get insightFocusTotal => '累计专注';

  @override
  String get insightFocusAverage => '平均一次';

  @override
  String insightTodayEventsCount(int count) {
    return '今日事务 $count 项';
  }

  @override
  String get previousMonth => '上一月';

  @override
  String get nextMonth => '下一月';

  @override
  String yearMonth(int year, int month) {
    return '$year 年 $month 月';
  }

  @override
  String get eventDayTitle => '当天日程';

  @override
  String get holidayAwareSwitch => '节假日与调休';

  @override
  String get holidayAwareDesc => '放假不计课时、调休上班日照常结算，并在调休当天提醒上周几的课';

  @override
  String insightUnitItems(int count) {
    return '$count 项';
  }

  @override
  String get holidayRemoteSwitch => '自动获取节假日安排';

  @override
  String get holidayRemoteDesc => '每年自动取回新一年的放假安排；关掉也能用内置数据';

  @override
  String get holidayDataTitle => '节假日数据';

  @override
  String get holidayDataUnknown => '暂无数据';

  @override
  String holidayDataSummary(String years) {
    return '已覆盖 $years 年';
  }

  @override
  String holidayDataSummaryChecked(String years, String date) {
    return '已覆盖 $years 年 · 上次检查 $date';
  }

  @override
  String get holidaySyncNow => '立即更新';

  @override
  String holidaySyncUpdated(String years) {
    return '已更新 $years 年的放假安排';
  }

  @override
  String holidaySyncNotPublished(String years) {
    return '$years 年的安排还没公布，发布后会自动补齐';
  }

  @override
  String get holidaySyncFailed => '获取失败，请检查网络后重试';

  @override
  String get holidaySyncUpToDate => '已经是最新的了';

  @override
  String get holidaySyncDisabled => '已关闭自动获取，请先打开上面的开关';

  @override
  String get updateTitle => '检查更新';

  @override
  String get updateCurrentVersionLabel => '当前版本';

  @override
  String updateVersionWithBuild(String version, int code) {
    return '$version（build $code）';
  }

  @override
  String get updateVersionUnknown => '无法读取版本号';

  @override
  String get updateInstallBlockedTitle => '需要「安装未知应用」权限';

  @override
  String get updateInstallBlockedDesc => '系统要求先允许本应用安装应用，否则点安装会被直接拒绝';

  @override
  String get updateGrantInstall => '去授权';

  @override
  String get updateRecheck => '我已授权';

  @override
  String get updateUnsupported => '当前平台不支持应用内更新';

  @override
  String get updateChecking => '正在检查更新…';

  @override
  String updateDownloadingPercent(int percent) {
    return '正在下载… $percent%';
  }

  @override
  String get updateFellBackToFull => '分差升级没成功，已自动改用完整包';

  @override
  String get updateAssembling => '正在用本机旧包合成新版本…';

  @override
  String get updateAssemblingHint => '不需要重新下载整包，这一步在本机完成';

  @override
  String get updateInstallingHint => '请在系统弹窗里确认安装';

  @override
  String get updateInstalledHint => '安装完成，重启应用后生效';

  @override
  String get updateUpToDate => '已是最新版本';

  @override
  String get updateCheckAgain => '再检查一次';

  @override
  String updateAvailableTitle(String version) {
    return '有新版 $version';
  }

  @override
  String get updateDeltaBadge => '分差升级';

  @override
  String get updateFullBadge => '完整包';

  @override
  String updateSizeWithDelta(String download, String full) {
    return '只需下载 $download（完整包 $full）';
  }

  @override
  String updateSizeFull(String full) {
    return '需要下载 $full';
  }

  @override
  String updateSavedHint(String saved, int percent) {
    return '比整包少下 $saved，省下约 $percent%';
  }

  @override
  String get updateChangesTitle => '更新内容';

  @override
  String get updateNoChanges => '这一版没有额外说明';

  @override
  String get updateDownloadDelta => '分差升级';

  @override
  String get updateDownloadFull => '下载并安装';

  @override
  String get updateSkipVersion => '跳过这个版本';

  @override
  String updateSkipConfirmBody(String version) {
    return '跳过 $version 之后不会再提醒这一版；出了更新的版本会重新提示';
  }

  @override
  String get updateSkippedHint => '已跳过，出了更新的版本会再提醒';

  @override
  String get updateReadyTitle => '新版本已就绪';

  @override
  String get updateReadyDeltaHint => '已在本机合成完成，点下面的按钮交给系统安装';

  @override
  String get updateReadyFullHint => '完整包已下载并校验通过，点下面的按钮安装';

  @override
  String get updateInstallNow => '立即安装';

  @override
  String get updateRetry => '重试';

  @override
  String get updateFailureNetwork => '没连上服务器，检查网络后重试';

  @override
  String get updateFailureManifest => '版本信息暂时取不到';

  @override
  String get updateFailureAssetMissing => '这个版本没有适配你手机架构的安装包';

  @override
  String get updateFailureHash => '下载内容校验没通过，已放弃安装';

  @override
  String get updateFailureDelta => '分差合成结果校验没通过';

  @override
  String get updateFailureNoSpace => '存储空间不足';

  @override
  String get updateFailureInstallBlocked => '还没允许本应用安装应用';

  @override
  String get updateFailureInstallRejected => '系统拒绝了这次安装';

  @override
  String get updateFailureUnknown => '出了点问题';

  @override
  String get updateMirrorTitle => '下载加速地址';

  @override
  String get updateMirrorDesc =>
      'GitHub 的下载地址在部分网络下很慢。可以填代理前缀（每行一个），直连失败后会依次尝试';

  @override
  String get updateMirrorHint => 'https://你的代理/';

  @override
  String get updateMirrorSaved => '已保存，请重新检查更新';

  @override
  String updateSettingsSubtitle(String version) {
    return '当前版本 $version';
  }

  @override
  String updateSettingsSubtitleAvailable(String version) {
    return '有新版本 $version';
  }

  @override
  String get attendanceResumeTitle => '是否复学？';

  @override
  String attendanceResumeBody(String name) {
    return '$name 当前已休学。复学后将恢复正常点名。';
  }

  @override
  String get attendanceResumeConfirm => '复学';

  @override
  String gridMakeupHint(String date, String weekday) {
    return '$date 调休上班，上$weekday的课';
  }

  @override
  String get attendanceLegendMakeup => '调休上班';

  @override
  String get attendanceLegendHoliday => '放假';

  @override
  String get attendanceLegendNoRecord => '有课未点名';

  @override
  String get attendanceLegendRate => '出勤率';

  @override
  String get quoteCardTapHint => '轻触换一句';

  @override
  String get quoteCardSourceTitle => '语录来源';

  @override
  String quoteCardSourceBuiltIn(int count) {
    return '内置 $count 条';
  }

  @override
  String quoteCardSourceCustom(String path) {
    return '自定义文件：$path';
  }

  @override
  String quoteCardSourceCustomMissing(String path) {
    return '自定义文件（尚未创建，可按同样格式新建）：$path';
  }

  @override
  String get quoteCardSourceFormat =>
      '每条写 text（句子）与 from（出处，可省略）两个字段；想加句子就往文件里追加，打开 App 时自动读取。';

  @override
  String get groupSystem => '系统设置';

  @override
  String get systemSettingsDesc => '考勤默认状态、调休、通知与数据清理';

  @override
  String get groupHoliday => '调休';

  @override
  String get groupClearData => '清空数据';
}
