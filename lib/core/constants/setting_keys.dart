/// app_settings 表的键名常量（readme 3.15 节）。
///
/// 所有「可在设置中调整」的阈值都落库到这张 KV 表，
/// 避免魔法数字散落在业务代码里。
abstract final class SettingKeys {
  /// 界面语言：zh / en（模块七 7.4）
  static const String language = 'language';

  /// 主题：mint / minimal_gray / night_care（模块七 7.5）
  static const String theme = 'theme';

  /// 高风险学生缺勤次数阈值
  static const String riskAbsenceThreshold = 'risk_absence_threshold';

  /// 出勤率警示阈值（百分比）
  static const String attendanceWarnRate = 'attendance_warn_rate';

  /// 高风险计分权重：缺勤
  static const String riskWeightAbsent = 'risk_weight_absent';

  /// 高风险计分权重：迟到
  static const String riskWeightLate = 'risk_weight_late';

  /// 高风险计分权重：早退
  static const String riskWeightEarlyLeave = 'risk_weight_early_leave';

  /// 考勤记录保留天数
  static const String attendanceRetentionDays = 'attendance_retention_days';

  /// 导入日志保留天数
  static const String importLogRetentionDays = 'import_log_retention_days';

  /// 时间列级联更新开关（模块一 1.7，默认开启）
  static const String cascadeUpdateEnabled = 'cascade_update_enabled';

  /// 未记录日期的默认考勤状态：present（出勤）/ unmarked（未标记）
  static const String defaultAttendanceStatus = 'default_attendance_status';

  /// 课前提醒提前量（分钟）
  static const String reminderMinutesBefore = 'reminder_minutes_before';

  /// 课前提醒总开关
  static const String lessonReminderEnabled = 'lesson_reminder_enabled';

  /// 番茄钟专注时长（分钟）
  static const String focusMinutes = 'focus_minutes';

  /// 番茄钟休息时长（分钟）
  static const String focusBreakMinutes = 'focus_break_minutes';

  /// 学生列表排序方式（模块二 2.4，排序方式记忆在本地）
  static const String studentSortMode = 'student_sort_mode';

  /// 学生列表排序方向：0 = 升序，1 = 降序（与表头双三角指示器联动）
  static const String studentSortDescending = 'student_sort_descending';

  /// 上次导出考勤统计时选中的班级（模块三 3.1 切换粒度时保留筛选条件）
  static const String statisticsClassFilter = 'statistics_class_filter';

  /// 上次使用的考勤统计粒度：day / week / month
  static const String statisticsGranularity = 'statistics_granularity';

  /// 课表页当前展示的作息模板 id。
  ///
  /// 必须持久化：课表第一列的「第 N 节 + 起止时间」完全由这套作息决定。
  /// 早期版本每次进入都按「选中班级的模板 -> 默认模板」临时推导，
  /// 只要库里多出一套被设为默认的模板，重启后就会静默换成另一套作息，
  /// 用户看到的现象就是"我改的时间又变回默认了"。
  static const String scheduleDisplayTemplateId = 'schedule_display_template_id';

  /// 课表页上次查看的班级 id（0 表示当前没有任何班级）。
  ///
  /// 同样需要持久化，否则重启后固定回落到班级列表第一个，
  /// 选中的班级一变，展示的作息也就跟着变了。
  static const String scheduleSelectedClassId = 'schedule_selected_class_id';

  /// 节假日 / 调休总开关（默认开启）。
  ///
  /// 关掉之后一律按"周六周日休息"处理，节假日与调休都不再影响课表与结算——
  /// 给那些"学校不按国家安排走"的老师留的逃生口。
  static const String holidayAwareEnabled = 'holiday_aware_enabled';

  /// 某个调休上班日"上周几的课"的前缀，完整键 = 前缀 + "YYYY-MM-DD"。
  ///
  /// 值 = ISO 星期几（1~7），空字符串表示"不调整"。
  /// 必须按**日期**存而不是全局存一个值：不同调休日学校给的安排可能不同
  /// （国庆前那次上周三、国庆后那次上周四是很常见的组合）。
  static const String holidayShiftPrefix = 'holiday_shift_';

  /// 上次为某个调休日确认过的"上周几的课"，用于给新的调休日做预选。
  static const String holidayLastShift = 'holiday_last_shift';

  /// 自动联网获取节假日数据（默认开启）。
  ///
  /// 内置表只抄到发布过的年份，跨年后就会过期——这个开关决定要不要
  /// 每年自动去把新一年的安排取回来。关掉也不会坏：只是继续用内置表。
  static const String holidayRemoteEnabled = 'holiday_remote_enabled';

  /// 上次**检查**节假日数据的时间（毫秒时间戳）。
  ///
  /// 成败都记：节流窗口要从"上次尝试"起算，否则失败之后会一直重试。
  static const String holidayLastSyncAt = 'holiday_last_sync_at';

  /// 上次检查是否全部成功（1/0）——决定下次重试是走 6 小时还是 3 天。
  static const String holidayLastSyncOk = 'holiday_last_sync_ok';

  /// 各键的默认值，读取时若库中不存在则返回此处的值。
  static const Map<String, String> defaults = <String, String>{
    language: 'zh',
    theme: 'mint',
    riskAbsenceThreshold: '3',
    attendanceWarnRate: '85',
    riskWeightAbsent: '3',
    riskWeightLate: '1',
    riskWeightEarlyLeave: '1',
    attendanceRetentionDays: '180',
    importLogRetentionDays: '360',
    cascadeUpdateEnabled: '1',
    defaultAttendanceStatus: 'present',
    reminderMinutesBefore: '10',
    lessonReminderEnabled: '1',
    focusMinutes: '25',
    focusBreakMinutes: '5',
    studentSortMode: 'name',
    studentSortDescending: '0',
    statisticsClassFilter: '0',
    statisticsGranularity: 'week',
    scheduleDisplayTemplateId: '0',
    scheduleSelectedClassId: '0',
    holidayAwareEnabled: '1',
    holidayLastShift: '',
    holidayRemoteEnabled: '1',
    holidayLastSyncAt: '0',
    holidayLastSyncOk: '0',
  };
}
