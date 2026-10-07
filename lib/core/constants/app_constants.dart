import 'package:flutter/painting.dart';

/// 全局常量集中管理。
///
/// readme 第六章「风险规避」明确要求：所有阈值（缺勤次数、保留天数、pxPerMinute 等）
/// 必须统一放入常量文件或 app_settings 表，禁止在业务代码中出现魔法数字。
abstract final class AppConstants {
  // ---------------------------------------------------------------------------
  // 通用交互规范（模块八 / 第四章 UI 规范）
  // ---------------------------------------------------------------------------

  /// 全局统一圆角半径 16dp（规范 1：禁止局部使用不同圆角值）
  ///
  /// 保留为兼容基准值；实际渲染请使用 [AppRadii] 中的分级形状 Token。
  static const double radius = 16.0;

  /// 按钮按下缩放至 96%（规范 3）
  static const double pressScale = 0.96;
  // 松开弹回时长见 AppMotion.instant —— 全 App 的动效时长统一放在 AppMotion，
  // 这里不再另外维护一份，避免同一个 100ms 出现两个来源。

  /// SnackBar 统一展示 **2 秒**。
  ///
  /// 用户规格：所有黑框提醒最多停留 2 秒。早期默认 3 秒、带操作按钮的 6 秒，
  /// 反馈是「一句话提醒停太久，挡着看课表」。这里把长短两档都收到 2 秒，
  /// 需要用户做决定的内容一律走弹窗 / 常驻入口，不再依赖 SnackBar 承载。
  static const Duration snackBarDuration = Duration(seconds: 2);

  /// 保留为兼容入口：与 [snackBarDuration] 同为 2 秒。
  static const Duration snackBarLongDuration = Duration(seconds: 2);

  /// 间距 Design Token（规范 2）
  static const double spaceXs = 4.0;
  static const double spaceS = 8.0;
  static const double spaceM = 12.0;
  static const double spaceL = 16.0;
  static const double spaceXl = 24.0;

  /// 底部半屏弹层高度占比（模块一 1.5）
  static const double bottomSheetInitialFraction = 0.6;
  static const double bottomSheetExpandedFraction = 0.9;

  // ---------------------------------------------------------------------------
  // 默认作息（课表页「一键生成作息」的出厂参数）
  //
  // 出厂口径：上午 08:00 开始，一天 10 节，每节 40 分钟，课间 10 分钟。
  // 第 i 节开始时间 = 08:00 + (i - 1) × (40 + 10) 分钟，节次与真实时间解耦，
  // 这里只是生成初始 template_period 的算法参数，不参与任何冲突判定。
  // ---------------------------------------------------------------------------

  /// 默认第一节开始时间（本地 "HH:mm"）
  static const String defaultDayStartTime = '08:00';

  /// 默认每节课时长（分钟）
  static const int defaultLessonMinutes = 40;

  /// 默认课间间隔（分钟）
  static const int defaultBreakMinutes = 10;

  /// 默认一天节数
  static const int defaultDayPeriodCount = 10;

  // ---------------------------------------------------------------------------
  // 课表网格（模块一 1.4 模式 A）
  // ---------------------------------------------------------------------------

  /// 网格行高的**上限**（一屏放得下时用不到，行高会按可用高度自适应）。
  static const double gridRowHeight = 62.0;

  /// 网格行高的下限。超过这个压缩幅度就不再压，改为纵向滚动，
  /// 否则一天 10 节挤在小屏上会把文字压到看不清。
  static const double gridRowMinHeight = 46.0;

  /// 节数很少时的行高上限：允许行"长高"铺满一屏，但不至于变成三行大字。
  static const double gridRowStretchMaxHeight = 96.0;

  /// 网格左侧节次/时间列宽度（窄屏时按比例再收一点）
  static const double gridGutterWidth = 62.0;

  /// 网格左侧列宽占整表宽度比例上限，防止窄屏上时间列把课表挤没。
  static const double gridGutterMaxFraction = 0.18;

  /// 星期列宽不再固定：整表宽度减去左侧列后**按天均分**，
  /// 保证课表永远一屏显示、不需要横向滚动。此处仅保留一个参考下限，
  /// 用于判断「天数多到已经压不出可读宽度」时是否收紧内边距。
  static const double gridDayMinWidth = 40.0;

  /// 手风琴：被点开的那一列相对等宽时的放大倍数。
  static const double gridAccordionExpandFactor = 2.3;

  /// 手风琴：其余列最多收窄到等宽时的这个比例，再窄就不放大展开列了。
  static const double gridAccordionShrinkFactor = 0.56;

  /// 手风琴详情（人数 / 班级）在这段动画区间内淡入，形成"先展开、后出现内容"的层次。
  static const double gridAccordionDetailFadeBegin = 0.45;

  /// 网格表头高度
  static const double gridHeaderHeight = 52.0;

  /// 课表格子四周的缝。
  ///
  /// 格子铺满整格后，缝里透出来的就是"行底色"——这是整张表有"表格底"的关键，
  /// 缝太窄会糊成一片，太宽又浪费本就紧张的格子空间。
  static const double gridCellGap = 3.0;

  // ---------------------------------------------------------------------------
  // 考勤页（模块二 2.5 + 用户规格）
  // ---------------------------------------------------------------------------

  /// 可一键选中的考勤状态个数：
  /// 日常点名五种（出勤 / 迟到 / 早退 / 缺勤 / 请假）
  /// + 两种**长期状态**（休学 / 免修）。
  ///
  /// "未标记"不是可选项（它只是"还没有记录"的显示态），所以不占格子。
  static const int attendanceStatusChoiceCount = 7;

  /// 其中「长期状态」（休学 / 免修）的个数。
  ///
  /// 它们和日常点名状态不是一个量级的东西：点一次就管 180 天，
  /// 所以排在最右侧并留一道稍宽的缝，视觉上自成一组。
  static const int attendanceLongTermCount = 2;

  /// 单个状态胶囊的宽度。
  ///
  /// 用户规格要求把状态**平铺在每条学生信息后面**，一下点到目标状态，
  /// 而不是滑动 / 循环切换去挑。所以这里刻意做窄（一个字正好），
  /// 七个连成一排也必须放得下，不能把姓名挤没。
  static const double attendanceStatusChipWidth = 27.0;

  /// 相邻状态胶囊的间距。
  static const double attendanceStatusChipGap = 2.0;

  /// 日常状态与长期状态之间的分组缝（比普通间距宽一点）。
  static const double attendanceLongTermGroupGap = 6.0;

  /// 一排状态胶囊的总宽度（姓名 / 学号两列剩下的就是它的）。
  static const double attendanceStatusStripWidth =
      attendanceStatusChipWidth * attendanceStatusChoiceCount +
          attendanceStatusChipGap *
              (attendanceStatusChoiceCount - attendanceLongTermCount) +
          attendanceLongTermGroupGap;

  /// 「休学 / 免修」这类长期状态默认持续的天数。
  ///
  /// 用户规格：一次点了休学 / 免修，这门课上就不再需要每节重复标记，
  /// 时间跨度按 180 天算（与考勤记录的保留天数同一口径）。
  static const int longTermStatusDays = 180;

  /// 考勤页「班级分组横带」的高度。
  static const double rosterGroupBandHeight = 42.0;

  // ---------------------------------------------------------------------------
  // 时间轴视图（模块一 1.4 / 规范 10）
  // ---------------------------------------------------------------------------

  /// 默认每分钟映射像素高度，做成可配置常量而非硬编码
  static const double pxPerMinuteDefault = 1.2;

  /// 自适应缩放下限，避免极端跨度（早 6 点 ~ 晚 10 点）导致单屏过高
  static const double pxPerMinuteMin = 0.35;

  /// 单屏时间轴总高度上限
  static const double timeAxisMaxHeight = 2400.0;

  /// 上下界各预留至少 30 分钟余量
  static const int timeAxisMarginMinutes = 30;

  /// 上下界取整粒度（整点或半点 => 30 分钟）
  static const int timeAxisRoundingMinutes = 30;

  /// 左侧小时刻度栏宽度
  static const double timeAxisGutterWidth = 54.0;

  /// 时间轴左侧刻度栏占整宽的比例上限（窄屏上别把 7 天的列挤没）。
  static const double timeAxisGutterMaxFraction = 0.16;

  /// 时间轴单日列的参考宽度。
  ///
  /// 用户规格：时间轴也要**自适应铺满窗口**，所以真实列宽是
  /// `(可用宽 - 刻度栏) / 7`，这个值只用于文案缩放的下限判断。
  static const double timeAxisDayMinWidth = 104.0;

  /// 星期表头高度（时间轴顶部那一行）。
  static const double timeAxisHeaderHeight = 44.0;

  /// 像素密度下限：可用高度极小（横屏 / 分屏）时的兜底，避免除零。
  static const double pxPerMinuteFloor = 0.10;

  /// 像素密度上限：节次很少时不允许把一节拉成一整屏高。
  static const double pxPerMinuteCeiling = 6.0;

  // ---------------------------------------------------------------------------
  // 课表分享（第 8 轮）
  // ---------------------------------------------------------------------------

  /// 分享卡片底部信息带高度（app 名 + 二维码位那一行）。
  ///
  /// **给用户留的替换点之一**：二维码定了以后如果想要更高的底带，
  /// 只调这里；二维码本体尺寸见 [shareQrPlaceholderSize]。
  static const double shareFooterHeight = 76.0;

  /// 二维码占位框边长。
  ///
  /// **给用户留的替换点之二**：用户规格"后续可能还要加上二维码供分享……
  /// 你留个位置，做好标记"。这是给真实二维码留的位置，
  /// 印在截图里要扫得动，**别改小**；换上真实二维码时沿用这个尺寸即可。
  static const double shareQrPlaceholderSize = 60.0;

  // ---------------------------------------------------------------------------
  // 滚轮选择器（模块一 1.6 / 规范 6）
  // ---------------------------------------------------------------------------

  /// 停止时自动吸附到最近的 5 分钟刻度
  static const int wheelSnapMinutes = 5;

  /// 滚轮单行高度
  static const double wheelItemExtent = 44.0;

  // ---------------------------------------------------------------------------
  // 考勤（模块二 / 模块三）
  // ---------------------------------------------------------------------------

  /// 高风险学生缺勤次数阈值（默认 3 次，可在设置中调整）
  static const int riskAbsenceThreshold = 3;

  /// 出勤率警示阈值（默认 85%）
  static const double attendanceWarnRate = 85.0;

  /// 高风险加权计分：缺勤 ×3 + 迟到 ×1 + 早退 ×1（权重可在设置中调整）
  static const int riskWeightAbsent = 3;
  static const int riskWeightLate = 1;
  static const int riskWeightEarlyLeave = 1;

  /// 自动生成「检查缺勤」待办的周内缺勤次数阈值（模块四 4.1）
  static const int autoTodoAbsenceThreshold = 2;

  /// 随机点名老虎机动画总时长约 2.5 秒（模块二 2.8）
  static const Duration rollCallDuration = Duration(milliseconds: 2500);

  /// 老虎机滚动停止前的减速曲线为 easeOutCubic，此处为刻度滚动间隔
  static const Duration rollCallTick = Duration(milliseconds: 60);

  /// 工具箱「本周教学成果」最多展示多少名需关注学生
  static const int insightAttentionLimit = 3;

  /// 课前提醒提前量可调范围（分钟）
  static const int reminderMinutesMin = 5;
  static const int reminderMinutesMax = 60;

  /// 读取不到平台版本号时的兜底文案
  static const String fallbackVersionLabel = '1.0.0';

  // ---------------------------------------------------------------------------
  // 工具箱分页卡片（用户规格：2 列、每页 4 张、左右滑动切页）
  // ---------------------------------------------------------------------------

  /// 每行卡片数
  static const int toolCardsPerRow = 2;

  /// 每页卡片数
  static const int toolCardsPerPage = 4;

  /// 工具卡片宽高比（略高于正方形，给标题与描述留出呼吸感）
  static const double toolCardAspectRatio = 1.04;

  // ---------------------------------------------------------------------------
  // 拍照识别课表（第 11 轮）
  // ---------------------------------------------------------------------------

  /// 拍照 / 选图时长边缩放到多少像素再送去 OCR。
  ///
  /// 手机原图动辄 4000×3000，直接喂给识别引擎既慢又吃内存，
  /// 而课表只需要能看清字，1600 已经绰绰有余（桌面端不受此影响）。
  static const int ocrMaxImageSide = 1600;

  /// 识别框（框选课表表格区域）在屏幕上的最大边长占比。
  ///
  /// 框选控件按图片宽高等比放大到窗口内，别让它撑破布局。
  static const double ocrCropMaxViewFraction = 0.62;

  // ---------------------------------------------------------------------------
  // 教师工具箱（模块五）
  // ---------------------------------------------------------------------------

  /// 番茄钟默认 25 分钟专注 + 5 分钟休息（可调整）
  static const int focusDefaultMinutes = 25;
  static const int focusDefaultBreakMinutes = 5;

  /// 专注时长的可选下限 / 上限：1 分钟 ~ 3 小时。
  ///
  /// 下限 1 分钟是给"我就想坐一会儿"留的入口；上限 3 小时是因为再长
  /// 就不该叫专注了（那是没睡）。滚轮上「时」最多拨到 3，拨到 3 时
  /// 分 / 秒自动收成 0，所以这三条边界天然一致，不需要再做钳制。
  static const int focusMinSeconds = 60;
  static const int focusMaxSeconds = 3 * 60 * 60;

  /// 时长滚轮的小时上限（0~3）。见 [focusMaxSeconds] 的说明。
  static const int focusMaxHours = 3;

  /// 时长滚轮「秒」列的步长。
  ///
  /// 专注计时精确到秒没有意义，5 秒一格足够表达"再坐 20 秒"，
  /// 还能把 60 格的秒列缩到 12 格，少滚一半的圈。
  static const int focusSecondStep = 5;

  /// 曾经这里是 `focusTicker = 200ms`，配一个"每次 tick 减 1 秒"的回调，
  /// 于是 25 分钟的专注 5 分钟就跑完了。**根因不是间隔取错，而是"拿累加器
  /// 表示剩余时间"这条路本身就错**：定时器的抖动、掉帧、被系统延后都会
  /// 永久沉淀成误差。现在改成墙钟口径（见 `focus_clock.dart`），
  /// 只记每一段从什么时候开始、每次用 `DateTime.now()` 现算，
  /// 刷新频率就只是"画多细"，不再影响"准不准"。故这里不再需要 ticker 常量。
  static const Duration focusUiTick = Duration(milliseconds: 100);

  // ---------------------------------------------------------------------------
  // 存储与自动清理（模块七 7.6）
  // ---------------------------------------------------------------------------

  /// 考勤记录保留 180 天，超期自动清理（清理前先本地备份）
  static const int attendanceRetentionDays = 180;

  /// 导入日志保留 360 天
  static const int importLogRetentionDays = 360;

  // ---------------------------------------------------------------------------
  // 通知（模块七 7.1 / 7.2）
  // ---------------------------------------------------------------------------

  /// 课前提醒通知 ID 段（每日凌晨批量重算，不固化绝对时间戳）
  static const int lessonReminderIdBase = 100000;

  /// 日程提醒通知 ID 段
  static const int eventReminderIdBase = 500000;

  /// 每日重新计算提醒的调度任务 ID
  static const int dailyReminderJobId = 900001;

  /// 课前提醒提前量（分钟），可在设置中调整
  static const int reminderMinutesBefore = 10;

  // ---------------------------------------------------------------------------
  // 其他
  // ---------------------------------------------------------------------------

  /// 当前为单教师应用，教师 ID 退化为常量（readme 3.5 表注明预留字段）
  static const int currentTeacherId = 1;

  /// 一周天数上限（weekday 取值 1~7）
  static const int weekdayCount = 7;

  /// 默认排课工作日数：周一~周五（出厂作息只铺这 5 天，
  /// 周末留给用户按需自己加，避免一进来就是一张 7 列的大表）
  static const int defaultWorkdayCount = 5;

  /// 学生名单分页懒加载，ListView.builder 每次构建窗口外缓存条数
  static const int listCacheExtent = 200;

  /// 学生表现标签的预设数量（模块二 2.10）
  static const int presetTagCount = 7;

  /// 课程详情对话框里「标签」列的固定宽度。
  ///
  /// 用户规格：标题（标签）靠左、具体内容居中。标签必须等宽，
  /// 几行的内容列才会对齐、居中的中线才是同一条。
  static const double dialogLabelWidth = 52.0;

  /// 「选一门课放进这一格」对话框里课程列表的最大高度。
  ///
  /// 够一屏看到 4~5 门课（再多就滚动），同时保证整颗对话框不会顶到屏幕边缘。
  static const double pickCourseListMaxHeight = 300.0;

  /// 日历月视图固定 6 行 × 7 列 = 42 格。
  ///
  /// 固定 42 格（而不是按当月天数算）是为了**翻月时高度不跳**：
  /// 2 月只有 4 行、3 月要 6 行，按需渲染的话每次翻月整个页面都会上下抽动。
  static const int calendarGridDays = 42;

  /// 日历格子宽高比。略高于 1 是为了给"休 / 班"角标留出行高。
  static const double calendarCellAspectRatio = 1.02;
}

/// 分级形状 Token（Material 3 Expressive Shape System）。
///
/// M3E 要求用**形状对比**建立层级，而不是到处同一种圆角：
/// - [stadium] 全圆胶囊：按钮、主指示器、Chip（高重要性、可点击）
/// - [squircel] 高曲率圆角：卡片、容器（包裹内容）
/// - [sheet] 大圆角：底部弹层、对话框（从边缘长出来的东西）
/// - [tile] 中圆角：列表项、输入控件
abstract final class AppRadii {
  /// 全圆胶囊（Stadium），用于按钮与主要指示器。
  static const double stadium = 999.0;

  /// Squircel 高曲率圆角，用于卡片与承载区。
  static const double squircel = 22.0;

  /// 次一级容器圆角（卡片内部嵌套块）。
  static const double inner = 16.0;

  /// 列表项、输入控件。
  static const double tile = 14.0;

  /// 小圆角（徽标、图标底、进度条）。
  static const double small = 10.0;

  /// 底部弹层顶部圆角。
  static const double sheet = 30.0;

  /// 对话框圆角。
  static const double dialog = 28.0;

  /// 课表单元格（略小，密集排布时避免显得臃肿）。
  static const double cell = 12.0;

  static BorderRadius get stadiumAll => BorderRadius.circular(stadium);
  static BorderRadius get squircelAll => BorderRadius.circular(squircel);
  static BorderRadius get innerAll => BorderRadius.circular(inner);
  static BorderRadius get tileAll => BorderRadius.circular(tile);
  static BorderRadius get smallAll => BorderRadius.circular(small);
  static BorderRadius get sheetTop =>
      const BorderRadius.vertical(top: Radius.circular(sheet));
  static BorderRadius get dialogAll => BorderRadius.circular(dialog);
  static BorderRadius get cellAll => BorderRadius.circular(cell);
}
