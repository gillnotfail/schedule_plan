# schedule_plan 细则（`MEMORY.md` 的延展）

> `MEMORY.md` **受注入上限（≈10.9k 字符）约束**，只放「改错就出事」的红线；**常量、文件名、实现细节全在本文件**。
> **动下列子系统之前先读对应小节**。过程与理由见 `.workbuddy/memory/YYYY-MM-DD.md`。
> 红线（不许违反的那句话）在 `MEMORY.md` 的「红线速查」，本文件负责「怎么才对」。

## 课表骨架（表永远是满的）
- **出厂作息唯一来源 `DatabaseSchema.generatePeriodRows`**：出厂种子、一键生成作息、新建模板预置作息、作息自愈全调它，
  禁止第二份循环。入参 `DatabaseExecutor`，事务内/库上都能调。默认周一~周五 × 08:00 起 × 每节 40 分钟 × 课间 10 分钟
  × 一天 10 节，全 `normal`。
- 「一键生成作息」只清 `template_period` 不动 `lesson`；`clearUnselected` 默认 false 以保住 `ensureDefaultWeekday`
  这类「只补一天」语义。弹层初值必须**回显当前模板真实状态**（`SchedulePage._generateDefaults` +
  `showScheduleSettingsSheet(initialXxx:)`）。
- 「在看哪套作息」优先级：有班级 → 班级绑定；无班级 → 持久化展示模板；都拿不到才回落默认。`_load()` 末尾把真正展示的写回去。
- **改节次时间只调开始时间就够**：`_PeriodTimeSheet` 默认 `_endManual = false`，结束 = 开始 + **本节自己的课堂时长**，
  封顶 23:55（`formatMinutes` 按 24h 取模，1440 绕回 `"00:00"`）。点过结束时间才 `_endManual = true`；「恢复自动」回到
  自动跟随。**级联开关默认 ON**，否则第 1 节后挪会和第 2 节默认时间重叠被校验拦下。

## 课表页交互（用户反复强调，别改回去）
- **不按班级切分**，表格上方永远没有班级切换条。一张表、课程不针对某个班级、不显示导入的班级。
- 空格子点击：有课程就弹滑动选课（`listCourses()` 全量）；一门课都没有才提示，且**无班级时先去建班级**
  （`createCourse` 要求至少挂一个班）。排新课 `lesson.class_id` 取 `CourseDetail.primaryClassIdOrNull`。
  「移出课表」= 只 `clearSlot`，**课程必须留在课程管理里**。
- **课表页没有 FAB**（第 7 轮：遮挡内容）。只有**空白课表**点空格子才给提醒。
- 点空格子 → **对话框** `showCoursePickerDialog`（课程色卡片上下滑动，底部左「取消」右「放进这一格」），不要退回底部抽屉/左右翻页。
- 点有课的格子 → **对话框** `lesson_detail_dialog.dart`：顶部课程色渐变带 + 居中课程名，信息行「图标 + 固定宽标签（左）+
  细线 + 内容居中」淡底卡片，底部左「取消」右「去点名」，次要动作收右上角溢出菜单。
- **「去点名」名单 = 这门课全部班级的并集**（`CourseRepository.classIdsOfCourse` + `StudentRepository.listByClasses`）。
  日期取 `DateUtils.nearestWeekdayDate`。
- 周几文案只有一处来源 `AppLocalizations.weekdayShort` / `weekdayPeriodLabel`（`core/l10n/l10n_extensions.dart`）。
- **`showScheduleSettingsSheet` 是加课类入口集中地**：一键生成作息/作息模板管理/默认作息修改/一键新增课表/拍照导入课表/
  一键清空。弹层里要推页面时**必须先 `Navigator.pop(false)` 再 `await handler()`**——直接 push 会被外层
  `showModalBottomSheet` 吞掉。
- 班级列表点卡片 → `class_detail_page.dart`：抬头名称/年级/班主任/绑定作息，下面人数数字块，再下面学生名单（可增删改），
  另有「这个班的课程」「Excel 导入」。人数走 `ClassRosterStats.of()`。

### 表格骨架：一屏显示 + 自适应缩放 + 横向手风琴
- `class_grid_view.dart` 用 `LayoutBuilder` 量宽高，**禁止写死 `gridDayMinWidth × 天数` + 横向滚动**。列宽 =
  `(可用宽 - gutter) / 天数`，gutter = `min(62, 宽×0.18)`；行高 = `(可用高 - 表头 - spaceS) / 行数`，clamp 到
  `[gridRowMinHeight 46, gridRowStretchMaxHeight 96]`（末尾留白算进可用高，否则多 8px 让整表可滚动）。
- 手风琴：**一个 `AnimationController` 同时驱动列宽插值与详情淡入**，折叠态**只显示课程名**；第一次点展开该列并延迟淡入
  「人数 · 班级」，再点同一格才开详情弹层；点展开列的星期表头收回等宽。列宽两端之和恒等于 `dayArea`。
- `ClassGridView.onLessonTap` 必须是 `Future<void> Function(LessonWithTime)`（课表页要等对话框关掉才返回，grid 在它返回后
  `_collapse()`）。三条收回路径（弹窗取消/点遮罩、点其它空格子、点展开列星期表头）都汇到 `_collapse()`。**不要改回 `void`**。
- 格子底色：课程色斜向渐变 + 左侧色脊 + 同色描边 + 展开时投影；空格子隔行深浅交替、今天那列泛主色、休息节次一条中性色带；
  `SizedBox.expand` 铺满。**交换模式下空格子不可点**（`_swapMode` 时 `onTap: null`）。

### 曲线档 `timeline_view.dart` 也必须一屏铺满
同一张表右上角「网格 ⇄ 曲线」切换。
- `LayoutBuilder` 量宽高：gutter 按 `timeAxisGutterMaxFraction` 收，`dayWidth = (maxWidth - gutter) / 7`，像素密度走
  `TimeAxis.fitted(lessons, availableHeight)`（clamp 到 `[pxPerMinuteFloor, pxPerMinuteCeiling]`）。**整条无滚动**。
  回归 `test/widget/timeline_view_test.dart`。
- 课程块 `FittedBox` 缩放、最小高 14.0；文本必须先按列宽换行再缩放（否则 7 列时字缩到 4px）。
- **日程**：`TimelineView.events` + `_EventMarker`。收起态只有玫红色块 + 标题；**点一下**在该块右上角浮出
  `_EventDetailPanel`（`FractionalTranslation(0, -0.95)`，宽 `_panelWidth = 118`），显示「14:30 - 15:10」+ 标题
  （有地点缀 ` · 地点`）。`endAt` 为空时**只显示开始时间**，不给空尾巴。状态 `_openEventId` + `_toggleEvent()`。
  **不要套 `IgnorePointer`**（要能点）。顶部 `_buildLegend()` 仅在有日程时出现。

## 考勤
- **记录必须长期保存，不随课表变动级联删除**（用户明确要求）。`attendance_record`（v4）的 `lesson_id` 可空 +
  `ON DELETE SET NULL`，冗余 `class_id / course_id / weekday / period_index / start_time / end_time / course_name /
  class_name` 快照列；`recorded_at` 是首次标记时间（重复点名只刷 `updated_at`）。写入走
  `AttendanceRecord.forLesson` + `AttendanceRepository.mark(...)`；查询一律 LEFT JOIN + `COALESCE`。
- 状态是**平铺胶囊** `AttendanceStatusStrip`（`attendance_status_strip.dart`），**不要退回「点击循环切换状态」**；
  点整行 = 记出勤。宽度常量 `AppConstants.attendanceStatusStripWidth`（表头「考勤」列也用它对齐）。
- **七态** = 日常五态 出/迟/早/缺/假 + 长期两态 **休学/免修**。`AttendanceStatus.dailyChoices` / `longTermChoices` /
  `choices`；`.next` 是「日常五态环 + 休学⇄免修小环」；`isAbnormal` 排除长期状态。`attendanceStatusChoiceCount = 7`、
  `attendanceLongTermCount = 2`、`attendanceStatusChipWidth = 27.0`、`attendanceLongTermGroupGap = 6.0`。颜色
  `AttendancePalette.suspended` / `.exempt`。
- **休学/免修是「课程级长期状态」**：`student_course_status` 表 + `CourseStudentStatus`（`[startDate, endDate]`
  闭区间，跨度 `longTermStatusDays = 180`）。一次点击生效 180 天。命中者在这门课里**自动
  沉底**（`compareRosterStudents` 里长期状态排最后）。API：`activeCourseStatuses` / `courseStatusesForStudent` /
  `setCourseStatus` / `clearCourseStatus`。
- **休学 ≠ 免修（第 16 轮改）**：休学 = 完全不来，**锁死日常五态与免修胶囊**，唯一出口是再点休学胶囊 → 「复学」确认
  （`attendanceResume*` 键）；免修 = 免修这门课但仍会来上课，**只作角标、不锁日常五态**（迟到早退照常标）。
  实现：strip 新增 `activeLongTerm`（与 `status` 并列，分别高亮长期/日常胶囊）；`locked` 只在「休学」时为真；
  `_effectiveStatus` 只对休学返回长期状态；高风险/异常摘要也只把休学当「不在点名范围」、免修照常累计。
- **名单按班级分组**：抬头是**班级横带** `ClassGroupBand`（`features/attendance/class_group_band.dart`，**公开**
  组件 + 独立测试，高 `rosterGroupBandHeight = 42.0`）。**不要**搬回页面当私有 `_ClassGroupBand`——私有类测不到，
  而横带是全页最挤的一行。名单是 `_RosterRow` / `_RosterGroup` 扁平序列 + `ListView.builder` 懒构建。班内排序纯函数
  `compareRosterStudents(a, b, {mode, direction, isLongTerm, statusIndexOf})`（单测
  `test/unit/attendance_roster_sort_test.dart`）。排序状态**所有班共用一份**。有效状态 `_effectiveStatus`：长期状态 >
  当天记录 > 默认。
- 日历标记是**进度圆环**（`day_attendance_ring.dart`）：无课不画；有课没记录 = 透明描边圈；有记录 = 红色圆弧按
  `AttendanceDayStat.rate`（**出勤率 = 出勤人次 ÷ 应点名人次**，应点名含合班课全部班级的人）填充。数据源
  `dayStats({from, to, teacherId})`，考勤页用 `_statsFrom/_statsTo` 缓存 + `_refreshRingStatsQuietly()`（**统计失败
  只记日志**，不能把成功保存报成失败）。
- 设置页「课表与名单」分组顺序 = **实际使用顺序**：Excel 导入名单 → 学生名单 → 班级管理 → 课程管理 → 级联开关。
  「作息模板」入口在课表页 `showScheduleSettingsSheet` 的 `onManageTemplates`（保留是为还能建「错峰课表」第二套
  作息，别让 `TemplateListPage` 变死代码）。设置页默认状态下拉只用**日常五态 + 未标记**。

## 表单与名单（单一实现）
- 班主任一律取「所属班级」，**不往 `student` 加列**；表单里只读展示、随班级联动。班级删除按 `info.studentCount` 选
  文案（>0 用 `classDeleteConfirmWithStudents(count)`）。
- 课程表单「上课班级」走**弹层多选**（`_ClassPickSheet`，带各班人数与班主任），不要平铺成 FilterChip。
- **Excel 导入名单不做二次确认**（用户规格）：选文件 → 解析 → 直接入库 → `pushReplacement` 到 `StudentListPage`；
  只有「全是错误行」或「一行都没读到」才停在本页。导入口必须自带防线 `StudentRepository.existingRosterKeys()`
  （键 `rosterKey(class_id, name)`，**同班同名视为同一人**）拦重复行、状态记 `skip` 并报出来——否则误选同一文件两次
  名单整份翻倍。改这块连带跑 `test/unit/schedule_authority_test.dart` 的导入去重用例。明细预览默认折叠
  （`importDetailToggle`），主按钮固定在**顶部**。
- 学生/班级表单各只有一份：`showStudentFormSheet` / `showClassFormSheet`。名单页、班级详情页、班级列表页全部复用，
  禁止复制私有 `_StudentForm` / `_ClassForm`。`StudentAvatar` 也在前者里。
- xlsx 兼容：`lib/data/services/xlsx_repair.dart` 修 `<numFmts>` 里的非法内置 id（WPS/老 Excel 把 41/42/43/44 再
  声明一遍 → `custom numFmtId starts at 164 but found ...`）。解析统一走 `ExcelService.decodeWorkbook`。

## 跨 Tab 与导航
- **跨 Tab 只能走 `AppNavigationState`**：四 Tab 是 `MainShell` 的 `IndexedStack` 平级子页，无 Navigator push 关系。
  `openAttendance(AttendanceRequest)` 同时切 Tab 并投递意图，考勤页 `consumeAttendance()` 后自行定位（同一请求只生效
  一次）。定位日期用 `DateUtils.nearestWeekdayDate`。
- 典型踩坑：设置页建好课程，回课表点空格子仍提示「还没有添加课程」；另有一层兜底是 `courses` 为空时先 `_load()` 再判定。
  见 `SchedulePage._onNavigationChanged`。

## 节假日与调休
- **两个正交维度绝不能合并**：`DateTime.weekday`（天然星期几，永不变）vs `CalendarDayKind { workday, weekend,
  holiday, makeupWorkday }`（国家安排的放假/上班属性）。周六调休上班正是「两维不一致」的产物。
- **数据源两层：远程优先、内置兜底**：① `data/services/china_holiday_calendar.dart` 内置常量表（国办年度通知逐条
  抄录：私有 `_Range`/`_Makeup` + `_ranges`/`_makeup` + `_expand()` 铺成 `Map<String, ChinaHoliday>`），
  `builtinYears = {2025, 2026}` 是**出厂兜底**；② **联网取回的年度缓存**（`holiday_day` 表）补内置表没有的年份。
  `infoOf(date)` = `_remote[key] ?? _builtin[key]`。`overrideWith(table)` / `resetOverride()`（**单测
  setUp+tearDown 必须调**，静态状态会串）。`coveredYears` 现为 **getter**（并集），**不再是 `const`**。两边都查不到
  回落「周六日休息」，表外年份 UI 走 `holidayOutsideCoverage` 提示。
  **不做「读手机自带日历」**：国产 ROM 调休数据不一定进 CalendarProvider；事件标题无标准只能猜；iOS 的 Apple
  「中国大陆节假日」**只标放假、不标补班**；还要多要权限。
- **「调休那天上周几的课」必须由老师确认，不能猜**：国务院只规定哪天上班，**没说补班那天上星期几的课**。故
  `holiday_shift_YYYY-MM-DD` 存 `app_settings`，值 `'1'..'7'` 或空串（=不调整）。
  `HolidayService.labelWeekdayOf(date, overrideWeekday)` 里**只有 `makeupWorkday` 才允许被覆盖值改**，其余一律返回
  天然 weekday（并 `clamp(1,7)`）。`holidayLastShift` 记住上次选择做弹层预选。`todayMakeupWorkday()` **先查开关、
  再看 dayOf 结论**，否则开关关掉还弹假提醒。
- **课时结算走日历而非 weekday**：`TeachingInsightService.load()` 先取 `HolidayService.weekOf(weekStart)`，再按
  `lesson.weekday` 分桶，然后 `for (day in holidayWeek.days) { if (!day.hasClasses) continue;
  total += byWeekday[day.labelWeekday].length; }`——**放假不计、调休上班日按 `labelWeekday` 取那天课表**。
  `HolidayWeek.hasAdjustment` 只认 `holiday` / `makeupWorkday`（否则每周末都显示调休条）。
- 总开关 `SettingKeys.holidayAwareEnabled`（默认 `'1'`，设置页「级联开关」下面一条）。关掉后调休提示与日历着色退场，
  但**老师已确认的映射不清空**。
- 落地：`schedule_page.dart` 提醒条 `_buildMakeupBanner`（`scheme.tertiaryContainer` + `Icons.swap_horiz_rounded`，
  副文案按 `shiftOverridden` 分支，右侧「设置/编辑」）；`toolbox/holiday_shift_sheet.dart` 的
  `showHolidayShiftSheet(...)`（七 chip +「不调整」chip，`HolidayShiftChoice{final int? weekday;}` 包装以区分「取消」
  与「不调整」）；`toolbox/calendar_page.dart`（`holiday` → `scheme.error` +「休」角标，`makeup` → `scheme.tertiary`
  +「班」角标，配 `holidayLegend` 图例）。日历格固定 **42 天（6×7）**：`AppConstants.calendarGridDays` +
  `calendarCellAspectRatio`，避免翻月高度抖动。
- **`await` 不能写在弹层参数里**（`suggestWeekday: await _holidays.lastShift()`）→ `use_build_context_synchronously`。
  先 `final x = await ...; if (!mounted) return;` 再弹层。
- **`holiday_day` 表（v7，纯加表 `_migrateV6ToV7`）**：`date` 主键 / `kind` / `name` / `year` / `source` /
  `fetched_at`，无外键，索引 `idx_holiday_year`。**只存有「国家安排」含义的日子**（`holiday` + `makeupWorkday`）——
  普通工作日/周末看 `weekday` 就能推，存进去只会跟内置表抢解释权。`HolidayRepository`：`loadAll()` 全读、
  `cachedYears()`、`replaceYear()`（先删后插同事务）、`clear()`；**空数据不写库**，免得「拉到空表」清掉已有缓存。
- **远程源可插拔**：`data/services/holiday_remote_source.dart` 的 `HolidayRemoteSource` + `TimorHolidaySource`
  （主源，`timor.tech/api/holiday/year/{年}?type=Y&week=Y`，`type` 段一次给全四态 0 工作日/1 周末/2 节日/3 调休）+
  `HolidayCnSource`（备源，jsDelivr 上 `holiday-cn` 静态 JSON，只有 `isOffDay` 两态）+
  `ChainedHolidaySource.standard()` 串联。**「这一年还没公布」必须返回空结果、不要抛异常**——上层靠这个决定 3 天
  还是 30 天后再试。
- **解析器必须是纯函数**（`parseTimorYear` / `parseHolidayCnYear`），单测喂 JSON fixture。两个坑：① `type` 段必须
  **先**吃（它认得调休），`holiday` 段用 `putIfAbsent` 只做兜底——反过来会把调休上班日整个丢掉，而那正是最要紧的
  一天；② 响应含中文节日名，**必须 `utf8.decode(response.bodyBytes)`**。
- **节流全靠纯函数 `HolidaySyncService.shouldFetch`**（单测覆盖）：从没试过 → 试；`missingYears` 空 → 只按 90 天
  复查；上次失败 → 6 小时；上次成功但仍缺年份 → **缺「今年或更早」就不管几月都按 3 天追**，只缺「明年」才看
  `inPublishWindow`（10 月起）→ 窗口内 3 天 / 窗口外 30 天。负间隔（系统时间往回调）一律放行，否则被永久卡住。
  口径：**国务院一般每年 10 月下旬~11 月中旬发布次年安排**，**不是「每年 1 月 1 日就有」**。
- **启动时序**（`app_dependencies.dart`）：`await holidaySync.bootstrap()`（纯本地读库注入，必须等）→
  `unawaited(holidaySync.refreshQuietly())`（**故意不 await**，别卡启动；绝大多数启动 `missingYears` 为空，
  `shouldFetch` 直接 false，压根不发请求）。`refreshQuietly()` 绝不外抛。
- **`HolidaySyncService` 是 `ChangeNotifier`**：后台拉到数据后 `notifyListeners()`；日历页 `context.watch` 即可，
  课表页必须走 listener（`_bindHolidaySync` → `_load()`）——那里要**重算** `_makeupToday`。非订不可的场景：**首次
  安装又正好跨年**（2027-01 装 App，内置表只到 2026）。
- **第 17 轮：调休映射要「看得见」，而且用的地方必须是同一个口径。** 上层统一按
  `map[date] ?? date.weekday` 解析，`HolidayService.shiftMap({from, to})` 一次 `LIKE` 把区间内**所有**已确认的调休日
  读回来（`map` = `"YYYY-MM-DD" → 实际执行 weekday`，**只收 `makeupWorkday` + 老师选过的**；总开关关掉直接返回空表）。
  它存在只为性能：考勤页圆环一次算 42 天，逐天 `shiftOf` 就是 42 次 query。底层
  `SettingsRepository.readByPrefix(prefix)` 的 SQL 是 `key LIKE ? ESCAPE '\'` 且参数经 `_escapeLike` 转义 ——
  **`holiday_shift_` 里的 `_` 在 LIKE 中是「任意单字符」通配符，不转义会误命中 `holidayXshiftY...`**。
- **三处必须吃这个映射，漏一处就是「界面显示当天没课」**：① 考勤页取当日课程（`_loadDayLessons`，原来裸用
  `DateUtils.isoWeekday(_selectedDate)`）；② 圆环的应点名（`AttendanceRepository.dayStats(weekdayOverrides:)`，
  原来按 `day.weekday` 查 `expectedByWeekday`，调休日会查到一个空圈）；③ 课表页表头「今天」落列
  （`ClassGridView.todayWeekday`，缺省才回落 `DateTime.now().weekday`）。**新增第四处前先回来读这一条。**
- **考勤日历的调休标记**：`_buildDayTile` 顶部一个 5px 小圆点（`holiday → scheme.error`、`makeupWorkday →
  scheme.tertiary`，与工具箱日历同一套配色）。周视图并进「周X」那一行（不占高度），月视图在顶部留 **6px 固定**
  标记带（固定高度是为了有/无标记的格子一样高，网格不参差）。总开关关掉时不标。长按 Tooltip 走 `_dayHint(day, stat)`
  ——**先日历安排后点名情况**（原来的 `_ringHint` 已被它取代，别再退回单段文案）。
- **考勤页回切要刷新**（`IndexedStack` 切回来既不 `initState` 也不重读库）：`_lastTabIndex` + `_reloadIfReturned()`
  照抄课表页的做法，只 `setState` 重算「开关 + 圆环 + 当日课程」（`_refreshHolidayContext`），**不置整页 `_loading`**。
  `_consumePendingAttendance()` 改成**同步返回 bool**（是否消费了「去点名」请求），有请求时跳过回切刷新，免得
  `_locateTo` 与本方法各加载一遍、`_selectedDate` 交错。
- **课表表头的两个角标**（都在星期文字**右边**一个 5px 圆点，不占列宽）：今天 → `scheme.primary` 点 +
  `primaryContainer` 胶囊底；本周调休落在这一列 → `scheme.tertiary` 点 + 淡 `tertiaryContainer` 底 + 长按 Tooltip。
  优先级 `今天 > 调休 > 展开列`。数据由 `schedule_page` 在 `_load()` 里算好（`_todayLabelWeekday` +
  `_makeupColumns`，后者只收 `shiftOverridden` 的调休日，落点写成 `labelWeekday: HolidayDay`），文案在 build 里用
  `gridMakeupHint(date, weekday)` 拼（`date` 用 `_monthDayLabel` 的 `MM-DD` 短格式）。
- **`HolidayName` → 文案只有一份**：`core/l10n/l10n_extensions.dart` 的 `AppLocalizations.holidayName(name)` 扩展
  （原 toolbox_page / calendar_page 各抄了一份 switch，已删）。同类先例是 `weekdayShort`，**新增枚举文案一律加到这里**，
  不要在页面里再写 switch。`core/` import `data/models/china_holiday.dart` 是既有分层惯例（`theme_controller` 也 import
  `data/repositories`），不算越界。

## 日程与统计
- **日程重复周期只有一个判定入口**：`ScheduleEvent.occursOnWeek(weekStart)`（纯函数）：单次只在自己那周、每周都
  发生、隔周隔着发生、每月看「这一周有没有开始日的天号」。课表页、错峰课表、日历页都调它。`EventRecurrence` 的
  storageKey 就是枚举名。
- **统计页筛选按课程、不按班级**：下拉是「全部 + 课程」；出勤率折线是多课程曲线（`attendanceRateSeriesByCourse`
  一条课程一条线，`_linePalette` 轮转色 + 图例）。`riskRanking`/`exportSummary`/`abnormalDetails`/
  `attendanceRateByCourse` 都带 `courseId` 可选参。
- **考勤「复制」只复制异常**（非出勤），复制前弹 `_SummaryDialog` 展示内容再复制；日历圆环用 `_applyRingDelta` 同步
  增量更新（**别退回整月重算**，那是「ring 延迟」的根因）。
- 工具箱是 `DefaultTabController` 两页（工具/成果）；卡片按压缩放用 `SquishyTap`（原点 = 手指点 + elastic 过冲回弹），
  成果页包 `HeartBurst`（点哪儿爆心）。

## 全局 UI / 动效
- **动效时长/曲线只有 `AppMotion` 一个来源**。按下缩放 = `instant`(100ms) + `softSpring`；位移用 `expressive`，
  颜色/透明度用 `effects`。可用时长：`instant 100 / quick 180 / wheelSnap 200 / scrollSettle 120 / standard 300 /
  springMedium 500 / springSlow 700 / pageTransition 420 / listStaggerStep 45 / listStaggerCap 600 / dialPointer 620 /
  pulse 1400`（**没有 `fast`**）。形状走 `AppRadii`（stadium / squircel 22 / sheet 30 / dialog 28 / tile 14 /
  small 10 / inner 16），禁止硬编码圆角。
- **过冲曲线只能用于位移/缩放**：`expressive`(0.34,1.56,0.64,1) / `softSpring`(0.2,1.25,0.4,1) 会越过 1。一旦动画
  lerp `boxShadow`/`border.width`，`BoxShadow.lerp` 会把 `blurRadius` 算成负数 → debug 崩。
- **`FilledButton`/`ElevatedButton`/`OutlinedButton` 不能直接放进 `Row`**（尤其和 `Spacer` 并排）：`app_theme.dart`
  给它们设了 `minimumSize: Size.fromHeight(52)`（宽度 infinity），`Row` 给非 flex 子节点无界宽度约束 →
  `BoxConstraints forces an infinite width`。需贴边自适应时就地覆盖
  `style: FilledButton.styleFrom(minimumSize: const Size(0, 48))`。
- **所有 SnackBar 一律 2 秒**（`snackBarDuration` 与 `snackBarLongDuration` 同为 2s）。用户明确否掉「长提醒」：需要
  用户做决定的内容走弹窗或常驻入口。「黑框」来自全局 `snackBarTheme`，别在调用处改样式。
- **底色只用 token 显式赋过值的两档**（`surface` / `surfaceContainer`）：`surfaceContainerLow/Lowest` 是 Flutter 默认
  基线色（带紫灰），在「樱花粉」「晨曦暖橙」里会脏。
- **工具箱彩色卡** `ToolCardTone`（`core/theme/app_colors.dart`，`@immutable`，字段 `key`/`light`/`deep`，
  `gradientFor(Brightness)` 暗色下 `Color.lerp(..., Colors.white, 0.10/0.06)` 提亮）。六色定稿：`blue #446DC6/#34569F`、
  `violet #7E60BB/#61459C`、`rose #C04A74/#9E355C`、`amber #A5691A/#8A5410`、`green #377E61/#29674D`、
  `teal #2E7B96/#21607A`。色板规则（有单测压着）：六色相**相对亮度 0.162~0.182（spread < 0.04）**、**白字对比度
  > 4.4:1**、key 唯一且两端色不同、色相均匀铺开且一行「一冷一暖」。卡片是 `DecoratedBox` + `LinearGradient` 实色
  渐变（**不再用 AppCard 浅底**），图标块 `Colors.white.withValues(alpha: 0.22)`。**改色必须重算明度与对比度**。

## 机械表盘（只有一套实现）
`core/widgets/dial_time_picker.dart`：内圈 12 个小时数字（1~12，12 点正上方），外圈 12 个分钟刻度（00/05/…/55），
**禁止再加回「时/分」分段模式**。点内圈即定小时并自动把焦点交给外圈；`DialTimeMath` 负责 12/24 换算（可单测，别内联
算）。12 小时表盘必须配 上午/下午。点击判定在 `_DialFace._handleTapUp`：按到圆心距离分内外环，**两圈都能整环点**，
不是只有数字小圆点可点。指针：短针指内圈、长针指外圈，各自 spring 旋转。

## 拍照识别课表（本机离线 OCR，不接 AI/LLM 服务商）
- **用户明确要求「不需要 ai 或者 llm 提供商」**，硬约束。路线：`相机/相册（image_picker）→ 本机 OCR 出「文字 +
  归一化包围盒」→ 本地几何规则还原表格 → SQLite`。依据是**课表是结构化表格**，不需要语言模型。
- **分层不可合并**：`schedule_ocr_types.dart`（纯类型，**不 import 插件**）→ `schedule_ocr_parser.dart`（**纯 Dart
  解析层，核心资产**，17 个单测压着）→ `schedule_ocr_service.dart`（引擎层，可插拔 `OcrRecognizer`，默认
  `UnavailableOcrRecognizer` 抛 `OcrEngineUnavailable`，**不许静默返回空列表**——那会让用户以为「照片拍得太差」）→
  `schedule_ocr_import_service.dart`（草稿 → 课程 + lesson 落库）→ `features/management/course_ocr_page.dart`。
- **引擎当前未接入**：`pubspec.yaml` 只有 `image_picker`。启用时加 `google_mlkit_text_recognition`（Android 完全
  离线）/ 系统 Vision（iOS），实现 `OcrRecognizer` 后 `setupRecognizer(...)` 注入，**解析规则一行都不用改**。
- **机型三档**（`_DeviceSupportCard` + l10n `ocrDevice*`）：**Android（小米/OPPO/vivo）**可用——**有 GMS 走 ML Kit，
  无 GMS 必须回落系统识别**（国行机 GMS 常缺失）；**华为鸿蒙 HarmonyOS 暂未适配**（当前明确提示走 Excel / 手动
  排课）；**iOS** 预留在 `VNRecognizeTextRequest`。
- 解析算法四条硬规则：① **周几必须按最长别名判定**（`indexOf` 式首命中会让「周日」被「周一」抢走）；② **节次识别
  前先 `replaceAll(_timeRangePattern, ' ')`**，否则 `08:50-09:30` 里的 50/09/30 会被裸数字规则吃成节次；裸数字只认
  「整行就是一个数字」；③ **行归属用中点分界**（对不均匀行高宽容），且**首尾锚点外留「半行」容差**；④
  **`_noiseWords` 绝不能放「早读/自习/晚自习/升旗」**——它们在国内课表里是真占一节的条目。
- **`buckets` 嵌套 Map 的键序必须写进注释**：`putIfAbsent(row).putIfAbsent(column)` 的键序是 **[节次][周几]**，组装
  时反着读会把「第 2 节」写成「第 1 节」（踩过）。
- `CropSelector`（**公开组件，有 widget 测试**）：图片按 `contain` 铺进可用空间，屏幕像素与图片比例之间差一个缩放
  系数，**所有指针事件必须先过这个变换**，否则手指与框错位。对外只吐归一化 `Rect`（0~1），解析层因此与分辨率无关。
  `imageSizeProvider` 可注入（`decodeImageFromList` 在 `flutter test` 的 fake-async 里永不 resolve）。
- 导入策略：**课程按名字复用**（同名不重复建，保留已有配色）、**默认只补空格子**（`overwrite: false`，照片识别必有
  错，宁可少排也不能悄悄改掉老师手工排的课）。
- **语音助手（结论：能做但暂不做）**：「平台集成」而非「app 内开发」。唤起 app：Android 加 `intent-filter` +
  `MainActivity.kt` 读 `intent.action/extras` & MethodChannel 递给 Dart；iOS 走 SiriKit / App Intents。端内 ASR 要用
  系统 `SpeechRecognizer` / `SFSpeechRecognizer`（离线看机型）或云端 ASR（**违背「不接服务商」**）。**要做先做
  「唤起 + 预填」，不要一上来做端内 ASR。**

## 发布与更新链路（细则）
- **客户端清单地址**：raw.githubusercontent（第一）+ jsDelivr（第二、国内可达）+ 用户可配镜像前缀。自动检查一天一次
  （`updateLastCheckAt` 节流）。`UpdateService` 是独立 `ChangeNotifier`，`AppDependencies` 里
  `unawaited(autoCheckIfDue())`（不阻塞启动、不弹窗打断）。清单默认下载地址指向 `github.com`。
- **本机网络（实测，别信旧结论）**：**按 IP 封，不是按域名**——DNS 解析正常但 TCP 连不上。
  - **2026-09-30 复测**：`github.com`（`20.205.243.166`）**000 不通**；`raw.githubusercontent.com`
    （`185.199.108/109/110/111.133`）**也 000 不通**（连测 4 次；**上一条「raw 都通」的结论已失效**）；
    `api.github.com`（`20.205.243.168`）**200 通**；`cdn.jsdelivr.net`（`151.101.x.229`）**200 通**。
  - 结论：**发布链路不受影响**（走 api.github.com + uploads）。客户端清单 `manifestUrls()` 是 **raw 第一、jsDelivr
    第二**（raw 永远最新，jsDelivr 对分支有最长 12h 缓存，故意排第二），raw 不通时**自动落到 jsDelivr**——本机正好
    是这个状态。手机侧若同样封这组 IP，必须配镜像前缀；且**这台机器验证不了真实下载地址**，只验证得了 jsDelivr。
  - 系统代理配了 `127.0.0.1:7890` 但 **`ProxyEnable=0` 且端口没监听**（所以 curl 是直连，才有上面的现象）。
- **`tool/release.py`**：`--bump` 自增版本号并写回 pubspec；**推送必须显式 `--push`**（标签一次性，试探性的本地跑
  不该造出不可回收的标签）；`--no-commit` 真空跑；`--skip-upload` 只产本地产物。分差基准取**严格小于当前
  versionCode 里最大的那个**，不能取「清单里第一个不是自己的」（清单降序，补发旧版本时会拿更新的版本当基准，方向反了）。
  **基准包缓存 `dist/releases/<code>/` 是分差的地基**——动过里面的 APK 就必须删掉整个 `dist/` 重跑。
  **CHANGELOG 里没有对应版本节时直接拒绝发布**（设计如此，不是 bug）。
- **`GITHUB_TOKEN` 探测**：环境变量优先，其次 `~/.schedule_plan-release.env`（dotenv）。`verify_token()` 在**打包之前**
  先验（`GET /user` + `GET /repos/...` 的 `permissions.push`）。`token_looks_truncated()` 专拦「复制了一半」：
  **细粒度 PAT 共 93 字符、中间还有一个下划线**，截断后服务端只回一句 `401 Bad credentials`。`commit_and_tag` **幂等**
  （标签已存在且 `rev-parse <tag>^{}` == HEAD 就跳过）。`token_file_status()` 会区分「文件不存在 / 没有那一行 /
  等号右边为空 / 有值读不出」——**别把四种合成一句**「没有可用的 GITHUB_TOKEN」。
- **按行改 dotenv/ini 必须逐行比键名**：`re.sub(r"GITHUB_TOKEN=.*")` 会把注释行里同名的文字一起吃掉。
- **`.gitignore` 覆盖** `*.jks`/`*.keystore`/`key.properties`/`*.apk`/`dist/`/`symbols/`。
- **分差细节**：CDC（32 位 gear 哈希滚动找边界）+ SPDP v1（整体 gzip，固定头 98 字节）。**分块只在生成端**，设备端只
  「校验指纹 → 按命令搬字节 → 校验产物指纹」；故无「两端边界一致」的跨语言陷阱，只需格式解析一致
  （`test/fixtures/delta/` 固定样例锁住）。命令只有 `COPY_BASE(offset u64, length u32)` 13 字节与
  `COPY_LITERAL(length u32)` 5 字节。`MAX_CHUNK = 64*1024`；`chunk_index` 必须**保留全部位置（含末尾残块）**；
  命中候选必须**逐字节复核**（防碰撞）。纯零串在 gear 哈希下收敛到不动点（`-GEAR[0]=0xA7825A60`），长零填充稳定切
  `MAX_CHUNK`；**撞上限的块长度与内容无关 → 边界不因内容改动漂移**（改 1 字节仍复用 99.9% 的原因）。用例用「数据块与
  零填充交替」，**别整份都是零**。`UpdateManifest.deltaWorthwhileRatio = 0.9`（补丁 ≥ 整包 90% 不生成）。
  - 实测 22.89 MB APK：改 1 字节 → 0.11%；删 4096 字节（后 10.9 MB 全位移）→ 0.10%；中间 500 KB 清零 → 0.17%；
    完全相同 → 0.02%；**arm64 → armeabi-v7a（最坏）→ 42.5%**。
- **客户端骨架**：`lib/data/models/app_release.dart`（`UpdateManifest.supportedSchemaVersion = 1`、`tryParse`、`plan`）、
  `lib/data/services/apk_installer.dart`、`lib/data/services/update_service.dart`、`lib/features/settings/update_page.dart`、
  `android/.../ApkInstallerChannel.kt` + `InstallResultReceiver.kt`；需 `REQUEST_INSTALL_PACKAGES` +
  `canRequestPackageInstalls()` + 「安装未知应用」授权页。
- **已发生的事故（供查）**：仓库曾为 private → 应用内检查更新必然失败且**无任何报错**（2026-09-30 转 public 修复）。
  历史提交 `8b20383`~`2ffe4c2` 的 `.workbuddy/memory/*.md` 里残留两个**截断到 31 字符的 PAT 字面量**（从未生效，别当
  有效凭据）；当前 HEAD 已清除，要彻底清需重写历史 + force push。
- **`tool/release.py` 已修的两个缺陷（v1.0.1 首发才暴露）**：
  ① `run(["flutter", ...])` 在 Windows 报 `FileNotFoundError [WinError 2]`——`CreateProcess` 只自动补 `.exe`
  （`PATHEXT` 是 cmd.exe 的规则），新增 `flutter_command()` 走 `shutil.which` 拿到 `flutter.BAT`；
  ② `write_version` 的 `\s*$` 正则里 **`\s` 会吃掉行尾换行** → **每次发版都悄悄删掉 `version:` 与 `environment:`
  之间的空行**，产生无意义的 pubspec diff；已改用 `[ \t]*$`（`read_version` 同步改）。
- **跑 release.py 必须给足超时**：`run()` 是 `capture_output=True`，**构建期间日志一个字都不输出**，外层工具
  120s 一掐，日志就永远停在 `$ ... flutter.BAT build apk --release` 那一行（看起来像卡住，其实是超时被杀）。
  实测 `flutter build apk --release` ~1m56s。三个选项：显式 `timeout: 600000`；或拆两步——
  先 `flutter build apk --release`，再 `release.py --no-bump --no-build --push`（`--no-build` 复用
  `build/app/outputs/flutter-apk/`，但**版本号必须先用 `release.write_version` 改好**，否则 APK 里是旧 versionCode）。
- **别拿 APK 体积判断有没有重建**：v1.0.1 的两个包与 v1.0.0 **逐字节同大小**（`libapp.so` 刚好对齐），
  但 sha256 不同。要比就比 **zip 内部条目的 CRC**：`AndroidManifest.xml` 与 `lib/<abi>/libapp.so` 都应变。
- **真实发版的复用率远低于合成用例**：v1.0.0 → v1.0.1（改 2 个 widget + 3 个 l10n 键）实测 arm64 复用 **59.3%**
  → 补丁 3.81 MB = 整包 **16.5%**；armeabi-v7a 复用 **50.7%** → 补丁 4.22 MB = **20.0%**。
  即「真实功能更新下，手机端只需下 1/6~1/5」。（合成用例「改 1 字节」的 99.9% 只说明算法正确，不代表真实场景。）
