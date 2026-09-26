# schedule_plan 长期约定

> 只记「改错会出事」的硬约束，电信式短语。**本文受注入上限（约 10k 字符）约束，必须精简**；
> 详细经过、理由、数据一律写 `.workbuddy/memory/YYYY-MM-DD.md`。需求规格在 `docs/SPEC.md`。

## 平台 / 需求
- 唯一规格 `docs/SPEC.md`（原 README.md，第 15 轮改名让位给 GitHub README）。别用「更好的设计」覆盖。
- **Windows 上 `README.md` 与 `readme.md` 是同一文件**：别照抄 GitHub 的 `echo "# x" >> README.md`。
- 只做 Android APK；iOS 只留默认模板，不验证。**暂不加鸿蒙（ohos）代码**。

## 数据模型
- `lesson.period_index` 相对 `class.template_id`；真实时间靠 `lesson JOIN class JOIN template_period`。
  **冲突检测按真实时间区间重叠，禁止比 period_index**（多模板聚合会误判）。
- 时间存 `"HH:mm"`、日期存 `"YYYY-MM-DD"`，不存时间戳。考勤唯一键 `(student_id, lesson_id, date)`。
- 外键显式 ON DELETE；迁移包事务 + 校验 `class.template_id` 无悬空。
- DB `version=7`，**18 张表**（`test/unit/schema_test.dart` 断言数量/顺序，加表必须同步改）：v3 `course.color`、
  v4 `attendance_record`、v5 `student_course_status`、v6 `schedule_event.recurrence`（默认 `'once'`）、
  v7 `holiday_day`。全是**纯加表加列**、可重复执行、不重建表。
  **不动 `migrate()` 里 `rebuildingCourse` 那段**（只服务 v1→v2，须临时关外键，否则 DROP course 级联清空 lesson）。
- 桌面 sqflite 必须先初始化 FFI：`AppDatabase._ensureDatabaseFactory()` 按 `Platform.isWindows/isLinux/isMacOS`
  调 `sqfliteFfiInit()` + `databaseFactoryFfi`，否则 not initialized。`sqflite_common_ffi` + `sqlite3_flutter_libs`
  必须在 `dependencies`。ff 包 import 要 `hide DatabaseException`，且别与 `sqflite` 同时 import（analyzer 判
  unnecessary）。
- 课程配色唯一口径 `CourseDetail.color`：课程自选 > 挂载班级里第一个 > 主题兜底。只走 `parseHexColor`
  （`core/utils/color_utils.dart`），**禁止 `int.parse` 裸转**；课表/课程卡/表单预览不许各写一套。
- 翻月走 `DateUtils.shiftMonth`（`DateTime(y,m±1,d)` 会进位：3/31 往前变 3/3）；加天用 `DateTime(y,m,d+n)`。

## 质量门槛与工具链（提交前必跑）
- `flutter analyze --no-pub` 零 issue（含 test/）；`flutter test` 全绿。
- **跑测试前设 `NO_PROXY=localhost,127.0.0.1,::1`**，否则代理劫持 flutter_tester 的 WebSocket。
- **本机 Git Bash 的 coreutils 全废**（`ls`/`grep`/`tail` not found）。flutter 一律 **PowerShell 工具**；找文件用
  Glob、找内容用 Grep，**不走 Bash**；Bash 里只有 managed Python/Node 绝对路径可用。
- PowerShell 重定向用 `& flutter ... 2>&1 | Out-File -Encoding utf8 <log>`，**不要 `*>`**（UTF-16LE）；读日志用
  Python `open(p, encoding='utf-8')`；看中文测试名先设 `[Console]::OutputEncoding` 为 UTF8。
- **PowerShell 承接 flutter 输出时退出码不可信**（stderr 的 `Flutter assets will be downloaded...` 被包成
  `NativeCommandError`）——**只信日志最后一行**（`No issues found!` / `All tests passed!`）。
- **同一时刻只跑一个 flutter 命令**：并发让 native assets 拷贝撞车报 `PathExistsException ... sqlite3.dll`；
  真撞了删 `build/native_assets` 重跑。改源码时不同时构建。
- **同一文件多处改动要一条条 Edit**（并行写会互相覆盖：日志 success 但没落盘），改完复核。
  **Edit 替换「注释+紧邻声明」后立刻 analyze**（曾连注释删掉 `enum _TipTone` → 9 个 undefined_identifier）。
- 批量改代码走**独立 .py 脚本**（`bash -c`/PowerShell 单行会被 shell 吃掉中文+三引号+`$`）；每处 replace 前
  `assert 旧串 in s`；**注意 CRLF**，用 `newline=''` 读。`bash` heredoc 会被安全策略拦，长文本用 Write/Edit。
- widget 测试改窗口：`tester.view.devicePixelRatio = 1; tester.view.physicalSize = size;
  addTearDown(tester.view.reset);`，别给 `MaterialApp` 套 `SizedBox`。
- **测试 `main()` 内局部函数不加下划线前缀**（`_no_leading_underscores_for_local_identifiers`）。
- widget 测试 `find.text` 会撞时间轴刻度，断言浮层用 `find.descendant(of: 浮层)` 限定。
- 单测要真实亮度/对比度用 `dart:math` 的 `math.pow(...).toDouble()`，别手写 Taylor 展开。
- 断言日期前想清楚：**假期里的周六不是 weekend**（2026-09-26 在中秋假期内 → `holiday`）。

## i18n
- 禁止硬编码，全走 `lib/l10n/app_zh.arb` / `app_en.arb` + `context.l10n`，zh/en 严格对齐。
- **加键一律走 `.workbuddy/tools/add_l10n_keys.py`**（幂等）：`NEW_KEYS` 加键、`UPDATE_KEYS` 改已存在键口径
  （脚本内 `assert key in data`，不许凭空 create）、`PLACEHOLDERS` 加 `@key`；末尾自带对齐断言。跑完
  `flutter gen-l10n`（有 `l10n.yaml` 时命令行参数被忽略，属预期）再 analyze。当前 zh/en 各 **679** 键。

## 发布与更新链路（第 15 轮）
- 仓库 `gillnotfail/schedule_plan`。`README.md` 面向 GitHub，规格 `docs/SPEC.md`，更新说明 `CHANGELOG.md`
  （**必须写用户能看懂的话**：`tool/release.py` 原样抽最新一节进 `updates/latest.json` 给应用内展示）。
  `updates/latest.json` **入库**；APK 与补丁挂 Releases **不入库**。`.gitignore` 覆盖 `*.jks`/`*.keystore`/
  `key.properties`/`*.apk`/`dist/`/`symbols/`。
- `pubspec.yaml` 的 `version: x.y.z+N`，**`N` 是 versionCode，每次发版必须递增**，否则拒绝覆盖安装。
- **分差**：`tool/delta_patch.py`（生成端）+ `lib/core/utils/delta_patch.dart`（设备端）。CDC 分块（32 位 gear
  哈希滚动找边界）+ SPDP v1 格式（整体 gzip，固定头 98 字节；命令只 `COPY_BASE(offset u64, length u32)` 13 字节
  与 `COPY_LITERAL(length u32)` 5 字节）。
  - **分块只在生成端**，设备端只「校验指纹 → 按命令搬字节 → 校验产物指纹」；故无「两端边界一致」的跨语言陷阱，
    只需格式解析一致（`test/fixtures/delta/` 固定样例锁住）。
  - **掩码必须取高 15 位（bits 17..31）**：`h = (h<<1) + GEAR[b]` 的 bit0 恒等于 `GEAR[末字节] & 1`，低位只有
    256 种取值，掩码放低位会退化（曾出现「整份文件切不出边界」）。`selftest` 有**分块均值必须落在
    `[1<<14, 1<<16]`** 护栏；**别拿复用率当格式兼容性门槛**（守错指标）。
  - 纯零串在 gear 哈希下收敛到不动点（`-GEAR[0] = 0xA7825A60`），长零填充稳定切 `MAX_CHUNK` 块；**撞上限的块
    长度与内容无关 → 边界不因内容改动漂移**（改 1 字节仍复用 99.9% 的原因）。用例用「数据块与零填充交替」，
    **别用整份都是零**。
  - `MAX_CHUNK = 64*1024`（128K/64K/32K 补丁大小几乎无差；上限越小，长常量串中间被改动时作废的字节越少）。
    `chunk_index` 必须**保留全部位置（含末尾残块）**；命中候选必须**逐字节复核**（防哈希碰撞）。
  - 实测 22.89 MB APK：改 1 字节 → 0.11%；删 4096 字节（后 10.9 MB 全位移）→ 0.10%；中间 500 KB 清零 → 0.17%；
    完全相同 → 0.02%；**arm64 → armeabi-v7a（最坏）→ 42.5%**。
- **三层安全网**：① 下载后按清单 SHA-256 校验；② 分差合成后再与**清单里整包指纹交叉校验**（两个独立来源）；
  ③ 生成端 `--verify` 自校验。任一步失败 → 删文件、换下一地址、**最终回落下载完整包**。
  `UpdateManifest.deltaWorthwhileRatio = 0.9`（补丁 ≥ 整包 90% 不生成）。
- **安装走 `PackageInstaller`，不用 `ACTION_VIEW` + FileProvider**：本项目 **`androidx.core` 由 share_plus 以
  `compileOnly` 引入 → 自建 FileProvider 子类编译不过**（决策性理由）。走「字节写进安装会话管道」，无需 content
  URI，还能拿 `installResult` 回执。需 `REQUEST_INSTALL_PACKAGES` 权限 + `canRequestPackageInstalls()` +
  「安装未知应用」授权页跳转。`InstallResultReceiver` 会被调用**一到两次**；系统装完重启进程致回执丢失 →
  故有 `UpdateService.markInstalledExternally()`（回前台比对版本号）。
- **清单地址**：raw.githubusercontent（第一）+ jsDelivr（第二、国内可达）+ 用户可配镜像前缀。自动检查一天一次
  （`updateLastCheckAt` 节流）。`UpdateService` 是独立 `ChangeNotifier`，在 `AppDependencies` 里
  `unawaited(autoCheckIfDue())`（不阻塞启动、不弹窗打断）。
- **`RandomAccessFile.writeFrom(list, start, end)` 第三个参数是下标 `end` 不是长度**；写错时第一条命令
  （cursor=0）恰好正确、第二条才抛 `RangeError`——**只有多条命令才暴露**。

## 构建
- `flutter build apk --release`；签名走 `android/key.properties` → `android/keystore.jks`（不入库）。
- 体积：arm64 ~24 MB / armeabi-v7a ~22 MB / universal ~69 MB。
- 改 proguard 别删 `-dontwarn com.google.android.play.core.**`，R8 会失败。

## 课表骨架（表永远是满的）
- **出厂作息唯一来源 `DatabaseSchema.generatePeriodRows`**：出厂种子、一键生成作息、新建模板预置作息、作息自愈
  全调它，禁止第二份循环。入参 `DatabaseExecutor`，事务内/库上都能调。默认周一~周五 × 08:00 起 × 每节 40 分钟 ×
  课间 10 分钟 × 一天 10 节，全 `normal`。
- **骨架永远不能空**（用户反复强调），三层兜底缺一不可：① `TemplateRepository.ensureFactorySchedule(templateId)`
  整份为空就补一份；② 无班级时用**默认作息模板**渲染（不走 `EmptyView`），只加「还没有班级」提示条；
  ③ `ClassGridView._periods` getter 整份为空时用出厂骨架渲染（不落库）。
- **「一键清空课表」只清 `lesson`**，不动 `template_period`（删了会得到连节次都没有的空表）。
- **「一键生成作息」权限最大**：`generatePeriods(clearUnselected: true)` 把**没勾的星期一并清空**，否则「先选 7 天
  再改回 5 天」永远停在 7 列。只清 `template_period` 不动 `lesson`；`clearUnselected` 默认 false 以保住
  `ensureDefaultWeekday` 这类「只补一天」语义。弹层初值必须**回显当前模板真实状态**（`SchedulePage._generateDefaults`
  + `showScheduleSettingsSheet(initialXxx:)`）。
- **「在看哪套作息」必须冷存储**：`SettingKeys.scheduleDisplayTemplateId` + `scheduleSelectedClassId`（默认 `'0'`）。
  禁止按 `is_default`/第一个模板临时推导（多模板重启会静默换表）。优先级：有班级 → 班级绑定；无班级 → 持久化展示
  模板；都拿不到才回落默认。`_load()` 末尾把真正展示的写回去。
- **改节次时间只调开始时间就够**：`_PeriodTimeSheet` 默认 `_endManual = false`，结束 = 开始 + **本节自己的课堂
  时长**（早读/晚自习不能用全局 40 分钟），封顶 23:55（`formatMinutes` 按 24h 取模，1440 绕回 `"00:00"`）。点过
  结束时间才 `_endManual = true`；「恢复自动」回到自动跟随。级联开关默认 **ON**，否则第 1 节后挪会和第 2 节默认
  时间重叠被校验拦下。

## 课表页交互（用户反复强调，别改回去）
- **不按班级切分**，表格上方永远没有班级切换条。一张表、课程不针对某个班级、不显示导入的班级。
- **空格子点击判定只有一条：全库有没有课程**——有就弹滑动选课（`listCourses()` 全量，**禁止再按班级过滤**，那
  正是「建好课程回来点还提示去添加课程」的根因）；一门课都没有才提示，且无班级时先去建班级（`createCourse` 要求
  至少挂一个班）。排新课 `lesson.class_id` 取 `CourseDetail.primaryClassIdOrNull`；**换课只改 `courseId`、不动
  `classId`**，用 `updateLesson(copyWith(courseId:))`，不要「clearSlot 再 placeLesson」。「移出课表」= 只
  `clearSlot`，课程必须留在课程管理里。
- **课表页没有 FAB**（第 7 轮：遮挡内容）。只有**空白课表**点空格子才给提醒。
- 点空格子 → **对话框** `showCoursePickerDialog`（课程色卡片上下滑动，底部左「取消」右「放进这一格」），不要退回
  底部抽屉/左右翻页。
- 点有课的格子 → **对话框** `lesson_detail_dialog.dart`：顶部课程色渐变带 + 居中课程名，信息行「图标 + 固定宽
  标签（左）+ 细线 + 内容居中」淡底卡片，底部左「取消」右「去点名」，次要动作收右上角溢出菜单。
- **「去点名」名单 = 这门课全部班级的并集**（`CourseRepository.classIdsOfCourse` +
  `StudentRepository.listByClasses`），不是 `lesson.class_id` 那一个班。日期取 `DateUtils.nearestWeekdayDate`。
- 周几文案只有一处来源 `AppLocalizations.weekdayShort` / `weekdayPeriodLabel`（`core/l10n/l10n_extensions.dart`）。
- **`showScheduleSettingsSheet` 是加课类入口集中地**：一键生成作息/作息模板管理/默认作息修改/一键新增课表/拍照导入
  课表/一键清空。弹层里要推页面时**必须先 `Navigator.pop(false)` 再 `await handler()`**——直接 push 会被外层
  `showModalBottomSheet` 吞掉。
- 班级列表点卡片 → `class_detail_page.dart`：抬头名称/年级/班主任/绑定作息，下面人数数字块，再下面学生名单（可
  增删改），另有「这个班的课程」「Excel 导入」。人数走 `ClassRosterStats.of()`。

### 表格骨架：一屏显示 + 自适应缩放 + 横向手风琴
- `class_grid_view.dart` 用 `LayoutBuilder` 量宽高，**禁止写死 `gridDayMinWidth × 天数` + 横向滚动**。列宽 =
  `(可用宽 - gutter) / 天数`，gutter = `min(62, 宽×0.18)`；行高 = `(可用高 - 表头 - spaceS) / 行数`，clamp 到
  `[gridRowMinHeight 46, gridRowStretchMaxHeight 96]`（末尾留白算进可用高，否则多 8px 让整表可滚动）。
- 手风琴：**一个 `AnimationController` 同时驱动列宽插值与详情淡入**，折叠态**只显示课程名**；第一次点展开该列并
  延迟淡入「人数 · 班级」，再点同一格才开详情弹层；点展开列的星期表头收回等宽。列宽两端之和恒等于 `dayArea`。
- `ClassGridView.onLessonTap` 必须是 `Future<void> Function(LessonWithTime)`（课表页要等对话框关掉才返回，grid 在
  它返回后 `_collapse()`）。三条收回路径（弹窗取消/点遮罩、点其它空格子、点展开列星期表头）都汇到 `_collapse()`。
  **不要改回 `void`**。
- 格子底色：课程色斜向渐变 + 左侧色脊 + 同色描边 + 展开时投影；空格子隔行深浅交替、今天那列泛主色、休息节次一条
  中性色带；`SizedBox.expand` 铺满。**交换模式下空格子不可点**（`_swapMode` 时 `onTap: null`）。

### 曲线档 `timeline_view.dart` 也必须一屏铺满
同一张表右上角「网格 ⇄ 曲线」切换。
- `LayoutBuilder` 量宽高：gutter 按 `timeAxisGutterMaxFraction` 收，`dayWidth = (maxWidth - gutter) / 7`，像素密度
  走 `TimeAxis.fitted(lessons, availableHeight)`（clamp 到 `[pxPerMinuteFloor, pxPerMinuteCeiling]`）。**整条无滚动**
  （不许有任何 `Scrollable`）。回归 `test/widget/timeline_view_test.dart`。
- 课程块 `FittedBox` 缩放、最小高 14.0；文本必须先按列宽换行再缩放（否则 7 列时字缩到 4px）。
- **日程**：`TimelineView.events` + `_EventMarker`。收起态只有玫红色块 + 标题；**点一下**在该块右上角浮出
  `_EventDetailPanel`（`FractionalTranslation(0, -0.95)`，宽 `_panelWidth = 118`），显示「14:30 - 15:10」+ 标题
  （有地点缀 ` · 地点`）。`endAt` 为空时**只显示开始时间**，不给空尾巴。状态 `_openEventId` + `_toggleEvent()`。
  **不要套 `IgnorePointer`**（要能点）。顶部 `_buildLegend()` 仅在有日程时出现。

## 考勤
- **记录必须长期保存，不随课表变动级联删除**（用户明确要求）。`attendance_record`（v4）的 `lesson_id` 可空 +
  `ON DELETE SET NULL`，冗余 `class_id / course_id / weekday / period_index / start_time / end_time /
  course_name / class_name` 快照列；`recorded_at` 是首次标记时间（重复点名只刷 `updated_at`）。写入走
  `AttendanceRecord.forLesson` + `AttendanceRepository.mark(...)`；查询一律 LEFT JOIN + `COALESCE`。
- 状态是**平铺胶囊** `AttendanceStatusStrip`（`attendance_status_strip.dart`），**不要退回「点击循环切换状态」**；
  点整行 = 记出勤。宽度常量 `AppConstants.attendanceStatusStripWidth`（表头「考勤」列也用它对齐）。
- **七态** = 日常五态 出/迟/早/缺/假 + 长期两态 **休学/免修**。`AttendanceStatus.dailyChoices` / `longTermChoices` /
  `choices`；`.next` 是「日常五态环 + 休学⇄免修小环」；`isAbnormal` 排除长期状态。`attendanceStatusChoiceCount = 7`、
  `attendanceLongTermCount = 2`、`attendanceStatusChipWidth = 27.0`、`attendanceLongTermGroupGap = 6.0`。颜色
  `AttendancePalette.suspended` / `.exempt`。
- **休学/免修是「课程级长期状态」**：`student_course_status` 表 + `CourseStudentStatus`（`[startDate, endDate]`
  闭区间，跨度 `longTermStatusDays = 180`）。一次点击生效 180 天；同状态再点弹确认取消。命中者在这门课里**自动
  沉底**（`compareRosterStudents` 里长期状态排最后）；已锁的日常胶囊置灰并给 `attendanceLongTermLocked` 提示。
  API：`activeCourseStatuses` / `courseStatusesForStudent` / `setCourseStatus` / `clearCourseStatus`。
- **名单按班级分组**：抬头是**班级横带** `ClassGroupBand`（`features/attendance/class_group_band.dart`，**公开**
  组件 + 独立测试，高 `rosterGroupBandHeight = 42.0`）。**不要**搬回页面当私有 `_ClassGroupBand`——私有类测不到，
  而横带是全页最挤的一行。名单是 `_RosterRow` / `_RosterGroup` 扁平序列 + `ListView.builder` 懒构建。班内排序纯函数
  `compareRosterStudents(a, b, {mode, direction, isLongTerm, statusIndexOf})`（单测
  `test/unit/attendance_roster_sort_test.dart`）。排序状态**所有班共用一份**。有效状态 `_effectiveStatus`：长期状态 >
  当天记录 > 默认。
- 日历标记是**进度圆环**（`day_attendance_ring.dart`）：无课不画；有课没记录 = 透明描边圈；有记录 = 红色圆弧按
  `AttendanceDayStat.rate`（**出勤率 = 出勤人次 ÷ 应点名人次**，应点名含合班课全部班级的人）填充。数据源
  `dayStats({from, to, teacherId})`，考勤页用 `_statsFrom/_statsTo` 缓存 + `_refreshRingStatsQuietly()`（**统计失败
  只记日志**，不能把成功保存报成失败）。**不要退回一个小红点**。
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
- **`IndexedStack` 里页面切回来不会重建**：既不走 `initState` 也不重新读库。凡「可能在别的 Tab 被改掉」的数据，都要
  订阅 `AppNavigationState` 并在**切回本 Tab 时重新加载**（见 `SchedulePage._onNavigationChanged`）。典型踩坑：设置页
  建好课程，回课表点空格子仍提示「还没有添加课程」；空格外另一层兜底是 `courses` 为空时先 `_load()` 再判定。
  **推子页面返回后也要 `_load()`**。

## 节假日与调休
- **两个正交维度绝不能合并**：`DateTime.weekday`（天然星期几，永不变）vs `CalendarDayKind { workday, weekend,
  holiday, makeupWorkday }`（国家安排的放假/上班属性）。周六调休上班正是「两维不一致」的产物——**所有「这天休息吗」
  必须查 `CalendarDayKind`，禁止只判 `weekday == 6 || 7`**（否则课时算少）。
- **数据源两层：远程优先、内置兜底**：① `data/services/china_holiday_calendar.dart` 内置常量表（国办年度通知逐条
  抄录：私有 `_Range`/`_Makeup` + `_ranges`/`_makeup` + `_expand()` 铺成 `Map<String, ChinaHoliday>`），
  `builtinYears = {2025, 2026}` 是**出厂兜底**；② **联网取回的年度缓存**（`holiday_day` 表）补内置表没有的年份。
  `infoOf(date)` = `_remote[key] ?? _builtin[key]`（**远程优先**）。`overrideWith(table)` / `resetOverride()`（**单测
  setUp+tearDown 必须调**，静态状态会串）。`coveredYears` 现为 **getter**（并集），**不再是 `const`**。两边都查不到
  回落「周六日休息」，表外年份 UI 走 `holidayOutsideCoverage` 提示。
  **不做「读手机自带日历」**：国产 ROM 调休数据不一定进 CalendarProvider；事件标题无标准只能猜；iOS 的 Apple
  「中国大陆节假日」**只标放假、不标补班**；还要多要权限。
- **「调休那天上周几的课」必须由老师确认，不能猜**：国务院只规定哪天上班，**没说补班那天上星期几的课**。故
  `holiday_shift_YYYY-MM-DD` 存 `app_settings`，值 `'1'..'7'` 或空串（=不调整），**没有任何默认猜测**；
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
- **Android `INTERNET` 权限必须写在 `android/app/src/main/AndroidManifest.xml`**：debug / profile 清单由 Flutter
  自动补，**release 不会**——少了它正式版就是永远连不上网的哑巴，而 debug 跑得好好的，最容易漏到发版才发现。

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

## 全局 UI / 动效硬约束
- **动效时长/曲线只有 `AppMotion` 一个来源**，禁止裸写 `Duration(milliseconds: ...)`。按下缩放 = `instant`(100ms) +
  `softSpring`；位移用 `expressive`，颜色/透明度用 `effects`。可用时长：`instant 100 / quick 180 / wheelSnap 200 /
  scrollSettle 120 / standard 300 / springMedium 500 / springSlow 700 / pageTransition 420 / listStaggerStep 45 /
  listStaggerCap 600 / dialPointer 620 / pulse 1400`（**没有 `fast`**）。形状走 `AppRadii`（stadium / squircel 22 /
  sheet 30 / dialog 28 / tile 14 / small 10 / inner 16），禁止硬编码圆角。
- **过冲曲线只能用于位移/缩放**：`expressive`(0.34,1.56,0.64,1) / `softSpring`(0.2,1.25,0.4,1) 会越过 1。**喂给
  `Interval.transform` 或 `lerpDouble` 的值必须 `.clamp(0.0, 1.0)`**；一旦动画 lerp `boxShadow`/`border.width`，
  `BoxShadow.lerp` 会把 `blurRadius` 算成负数 → debug 崩。**颜色、描边、阴影、透明度一律用单调的 `effects`**。
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
