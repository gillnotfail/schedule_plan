# schedule_plan 长期约定

> **只记「改错会出事」的硬约束**。**注入上限约 10k 字符**，超出部分后续会话**看不到** → 只留**红线**；
> **细则/常量/文件清单在 `MEMORY-DETAIL.md`**；过程记录在 `YYYY-MM-DD.md`。
> **动这些子系统前先读 `MEMORY-DETAIL.md`**：课表格子与曲线布局、考勤名单与日历圆环、表单与名单、节假日与调休、
> 日程与统计、「每日一句」语录卡片、**专注模式**、全局动效与配色、机械表盘、拍照识别课表、**发布与差分升级**。
> 需求唯一来源 `docs/SPEC.md`；发布手册 `docs/RELEASE.md`。

## 平台 / 需求
- 唯一规格 `docs/SPEC.md`（原 README.md，第 15 轮改名让位给 GitHub README）。**别用「更好的设计」覆盖**。
- **Windows 上 `README.md`/`readme.md` 是同一文件**：别照抄 GitHub 的 `echo "# x" >> README.md`。
- 只做 Android APK；iOS 只留默认模板，不验证。**暂不加鸿蒙（ohos）代码**。

## 质量门槛与工具链（提交前必跑）
- `flutter analyze --no-pub` 零 issue（**含 test/**）；`flutter test` 全绿（当前 +479）。
- **跑前设 `NO_PROXY=localhost,127.0.0.1,::1`**，否则代理劫持 flutter_tester 的 WebSocket。
- 找文件用 Glob、找内容用 Grep；Bash 里 managed Python/Node 走绝对路径。
  （**第 25 轮实测 `ls`/`grep`/`tail`/`head`/`wc` 都可用** —— 早先「coreutils 全废」的记录已不成立。）
- **flutter 一律走 `C:\Users\jeo\AppData\Local\Temp\wb_run_flutter.py`**（直调 `flutter.BAT`，绕开 PowerShell 管道）：
  `<py> wb_run_flutter.py <项目绝对路径> analyze --no-pub`。末尾自打 `=== EXIT n ===`，**以日志最后一行结论为准**
  （PowerShell 承接 flutter 输出时退出码不可信；`*>` 重定向是 UTF-16LE，要用 `Out-File -Encoding utf8`）。
- **同一时刻只跑一个 flutter 命令**：并发让 native assets 拷贝撞车报 `PathExistsException ... sqlite3.dll`；
  真撞了删 `build/native_assets` 重跑。
- **长命令必须显式给 `timeout`**：默认 **120s 就掐，`run_in_background` 也不豁免**。症状 = `Status: failed` +
  `Duration: 2m 1s` + **日志停在中间某行**（输出先缓存、结束才落盘）。`build apk --release` 实测 ~1m56s。
- **Python 脚本里调 flutter 必须解析出 `.bat`**（`shutil.which`），否则 `[WinError 2]`。
- **`flutter`/`dart` 全线废（analyze/test/build/format 一起挂）** 时报错是
  `CreateFile failed 231`（`ERROR_PIPE_BUSY`，**不是权限问题**），别误判成代码错误。
  **根因是 WorkBuddy 的进程环境**：第 24 轮实测同一探针在**用户自己的 cmd 里
  `成功 20 个`**、在本机 Bash/PowerShell 里 **100% 失败**；环境变量/沙箱开关/Job/控制台/管道全都排除了。
  **重启电脑解决不了**（实测 uptime 1.3 分钟仍挂）——别让人再去重启。
  **判据只有一条：当场起一个 Dart 子进程**（`%TEMP%\wb_spawn_probe.dart`）——**「刚才能跑」不算证据**。
  处置：请用户在自家终端里跑（样板 `%TEMP%\release_v1.0.8.bat`），别杀进程、别改代码。
  两个带偏人的假象：① **Bash 照样能用**（长驻 shell 复用管道）；② **PowerShell 工具静默返回空输出**（exit 0）。
  全部排查记录见 `MEMORY-DETAIL.md`「工具链故障」。
- **写 .bat 包 flutter 时，禁止用 `if errorlevel 1` 当门禁**：`flutter.BAT` **成功也返回非 0**，
  于是一个"环境自检"会把**整个后续流程静默跳过**（第 24 轮实测：窗口只打出 `flutter --version`
  就退出，发布一步没跑，而看上去像"跑完了"）。自检只做展示，**别拿它的退出码决定走不走下一步**。
- **同一文件多处改动要一条条 Edit**（并行写会互相覆盖：日志 success 但没落盘），改完复核。
  **Edit 替换「注释+紧邻声明」后立刻 analyze**（曾连注释删掉 `enum _TipTone` → 9 个 undefined_identifier）。
- 批量改代码走**独立 .py 脚本**（shell 单行会吃掉中文+三引号+`$`）；每处 replace 前 `assert 旧串 in s`；
  注意 CRLF，用 `newline=''` 读。`bash` heredoc 被安全策略拦，长文本用 Write/Edit。
- widget 测试改窗口：`tester.view.devicePixelRatio = 1; tester.view.physicalSize = size; addTearDown(tester.view.reset);`，
  别给 `MaterialApp` 套 `SizedBox`。测试 `main()` 内局部函数**不加下划线前缀**。
- widget 测试 `find.text` 会撞时间轴刻度，断言浮层用 `find.descendant(of: 浮层)` 限定。
- widget 测试里**组件 `initState` 去读 sqlite** 时，`pumpAndSettle` 推的是假时钟 → 查询永远跑不完，内部锁超时 Timer
  挂到测试结束、被判 "A Timer is still pending"；用 `tester.runAsync(() => Future.delayed(...))` 放它们跑完。
- 单测要真实亮度/对比度用 `dart:math` 的 `math.pow(...).toDouble()`，别手写 Taylor 展开。
- 断言日期前想清楚：**假期里的周六不是 weekend**（2026-09-26 在中秋假期内 → `holiday`）。

## 数据模型
- `lesson.period_index` 相对 `class.template_id`；真实时间靠 `lesson JOIN class JOIN template_period`。
  **冲突检测按真实时间区间重叠，禁止比 period_index**（多模板聚合会误判）。
- 时间存 `"HH:mm"`、日期存 `"YYYY-MM-DD"`，不存时间戳。考勤唯一键 `(student_id, lesson_id, date)`。
- 外键显式 ON DELETE；迁移包事务 + 校验 `class.template_id` 无悬空。
- DB `version=9`，**16 张表**（`schema_test.dart` 断言数量/顺序，加表/删表必须同步改）。加表一律是**纯加表加列**、
  可重复执行、不重建表；**逐版明细见 `MEMORY-DETAIL.md`「数据库」**。**不动 `migrate()` 的 `rebuildingCourse` 段**
  （只服务 v1→v2，须临时关外键，否则 DROP course 级联清空 lesson）。
- **删一个功能模块前，按 import 路径全库 grep（下划线形式，如 `note_repository`），别只搜驼峰类名** ——
  本项目有**一文件多类**的仓库（`note_repository.dart` 同时还装着 `ScheduleEventRepository`）。只搜类名会漏掉
  import 语句，删完 analyze 才炸一片 undefined。
- 桌面 sqflite 必须先初始化 FFI：`AppDatabase._ensureDatabaseFactory()` 按平台调 `sqfliteFfiInit()` +
  `databaseFactoryFfi`。`sqflite_common_ffi` + `sqlite3_flutter_libs` 必须在 `dependencies`。ff 包 import 要
  `hide DatabaseException`，且别与 `sqflite` 同时 import（analyzer 判 unnecessary）。
- 课程配色唯一口径 `CourseDetail.color`：课程自选 > 挂载班级里第一个 > 主题兜底。只走 `parseHexColor`
  （`core/utils/color_utils.dart`），**禁止 `int.parse` 裸转**。**凡是"把课程色铺满一块"的地方都必须再过一个
  `solidFillColor`**（把过亮的色压到白字对比度 ≥ 3.2）。课表格子第 19 轮起是**整格铺满 + 白字**。
- 翻月走 `DateUtils.shiftMonth`（`DateTime(y,m±1,d)` 会进位：3/31 往前变 3/3）；加天用 `DateTime(y,m,d+n)`。

## i18n
- 禁止硬编码，全走 `lib/l10n/app_zh.arb`/`app_en.arb` + `context.l10n`，zh/en 严格对齐。
- **加键一律走 `.workbuddy/tools/add_l10n_keys.py`**（幂等）：`NEW_KEYS` 加键、`UPDATE_KEYS` 改已存在键口径（脚本内
  `assert key in data`）、`PLACEHOLDERS` 加 `@key`；末尾自带对齐断言。跑完 `flutter gen-l10n`（有 `l10n.yaml` 时
  命令行参数被忽略，属预期）再 analyze。当前 zh/en 各 **718** 键。
  **改这个脚本别拿 `"...元数据",\n}` 当尾部锚点**：`NEW_KEYS` / `PLACEHOLDERS` / `UPDATE_KEYS` 三个 dict 都以它结尾，
  会串到另一个 dict 里去。锚点要带上前一条**完整的键名**。

## 发布与更新链路（**细则见 `MEMORY-DETAIL.md` 同名章节；这一节只留红线**）
- **仓库必须公开**（私有 → 手机端永远看不到更新，raw 与 jsDelivr 都 404）。**别把 token 塞进 App**（APK 可反编译）。
- **`release.py` 顺序不能反**：先「提交 → 打标签 → 推送」→ 再建 Release（反过来 GitHub 会自造同名标签挂到旧提交）。
  要建 Release 就必须带 `--push`。仓库：`gillnotfail/schedule_plan`（GitHub）+ **`jeo-xie/schedule_plan`（Gitee，首选）**。
- `CHANGELOG.md` **必须写用户能看懂的话**（`release.py` 原样抽最新一节进 `updates/latest.json` 给应用内展示；
  条目可折行、缩进续行会接回同一条，**别用空行续写同一条**）。`updates/latest.json` **入库**，APK 与补丁**不入库**。
- `pubspec.yaml` 的 `version: x.y.z+N`，**`N`（versionCode）每次发版必须递增**，否则拒绝覆盖安装。
  **CHANGELOG 没有对应版本节时直接拒绝发布**（设计如此，不是 bug）。
- **双仓库分发**：每次发布往 Gitee 与 GitHub **各发一份**同一批 APK/补丁；清单 `assetsBases=[Gitee, GitHub]`，
  客户端取清单 **Gitee raw 第一**（带 `?t=` 破 60s 缓存）→ GitHub raw → jsDelivr → 用户自配镜像。
  **`schemaVersion` 绝不因加字段而 +1**（老客户端见更高版本会判"清单不可用"，等于把已装机用户锁死）。
  **单数 `assetsBase` 必须保留**且指向当场回验过能匿名下载的源（≤1.0.5 的旧客户端只读它）。
- **回验里「本机连不上」≠「源坏了」**：只有服务器明确回 4xx/5xx 才剔源；超时 / 连接重置 / `000`
  一律**保留为兜底**（发布机在国内时 `github.com` 时通时断，剔掉等于让用户没了退路）。
- **发布最后一步是清 jsDelivr 缓存**（`release.py` 自动做，别绕过；`@main` 对分支最长缓存 12h）。
  `status == "finished"` **不代表清成功**，要看 `paths[...].throttled`（连发两版必被限流，约 6 分钟）；
  这个端点**必须走 curl**（本机 urllib 必 `WinError 10054`）。
- **令牌只放 `~/.schedule_plan-release.env`**（`GITHUB_TOKEN` / `GITEE_TOKEN`），**绝不进仓库**；
  别让用户把 token 贴进对话（实测两次都被截到 31 字符）。
- **分差掩码必须取高 15 位（bits 17..31）**，放低位会退化。**三层安全网**：下载后按清单 SHA-256 校验 →
  分差合成后再与清单里整包的指纹交叉校验 → 生成端 `--verify`；任一步失败 → 换下一地址 → 最终回落整包。
- **安装走 `PackageInstaller`**（`androidx.core` 由 share_plus `compileOnly` 引入 → 自建 FileProvider 编不过）。
- **`RandomAccessFile.writeFrom(list, start, end)` 第三参是下标 `end` 不是长度**（只有多条命令才暴露）。

## 构建
- `flutter build apk --release`；签名走 `android/key.properties` → `android/keystore.jks`（不入库）。
  体积：arm64 ~24 MB / armeabi-v7a ~22 MB / universal ~69 MB。
- 改 proguard 别删 `-dontwarn com.google.android.play.core.**`，R8 会失败。

## 红线速查（**细则、常量、文件清单全在 `MEMORY-DETAIL.md`**）
- **课表骨架：表永远是满的**。出厂作息唯一来源 `DatabaseSchema.generatePeriodRows`，禁止第二份循环；三层兜底缺一不可
  （`TemplateRepository.ensureFactorySchedule` 补整份 / 无班级时用**默认作息模板**渲染不走 `EmptyView` /
  `ClassGridView._periods` 整份为空时用出厂骨架渲染且**不落库**）。「一键清空课表」**只清 `lesson`**，不动 `template_period`；
  「一键生成作息」`clearUnselected: true` 会把**没勾的星期一并清空**。「在看哪套作息」必须**冷存储**
  （`scheduleDisplayTemplateId` + `scheduleSelectedClassId`），**禁止按 `is_default`/第一个模板临时推导**。
  改节次时间时结束时间默认跟随=开始+**本节自己的课堂时长**（早读/晚自习不能用全局 40 分钟）。
- **课表页：不按班级切分**，表格上方永远没有班级切换条；**没有 FAB**（第 7 轮：遮挡内容）；空格子点击判定只有一条
  ——「全库有没有课程」（`listCourses()` 全量，**禁止再按班级过滤**，那正是「建好课程回来点还提示去添加课程」的根因）；
  **换课只改 `courseId` 不动 `classId`**（`updateLesson(copyWith(courseId:))`，不要 clearSlot 再 placeLesson）；
  点格子一律**对话框**（空格 `showCoursePickerDialog` / 有课 `lesson_detail_dialog.dart`），不退底部抽屉；
  「去点名」名单 = 这门课**全部班级的并集**，不是 `lesson.class_id` 那一个班。
- **表格与曲线档都必须一屏铺满**：禁止写死 `gridDayMinWidth × 天数` + 横向滚动；曲线档 `dayWidth = 可用宽 / 7`、
  像素密度走 `TimeAxis.fitted`，**不许有任何 `Scrollable`**（回归 `test/widget/timeline_view_test.dart`）。
- **考勤记录不随课表变动删除**（`lesson_id` 可空 + `ON DELETE SET NULL` + 冗余快照列，查询一律 LEFT JOIN + `COALESCE`）；
  状态是**平铺胶囊**，**不要退回「点击循环切换状态」**；**七态**（日常五态 + 休学/免修，后者是**课程级 180 天**长期状态，
  命中者自动沉底）。**休学 ≠ 免修**：**休学锁死日常五态**（唯一出口=再点休学胶囊→「复学」确认）；**免修只作角标、不锁**
  （免修学生仍会来上课，迟到早退照常标）。**考勤日历格子上只有四样标记，且全部由日历下方那行图例解释**
  （口径唯一来源 `features/attendance/calendar_marks.dart` 的 `CalendarMark` + `AttendanceCalendarLegend`）：
  **放假 = 红点**、**调休上班 = 紫点**、**有课未点名 = 淡圈**、**点过名 = 红弧**（弧长=出勤人次 ÷ 应点名人次）。
  **这四样之外禁止再加标记**（长按提示已被老师判为"命中率太低"去掉）。**改任何一种标记的颜色或可见条件，
  必须同步改图例的文案/符号**——否则"图例说的"和"格子画的"对不上，老师就回到"看不懂"。
- **跨 Tab 只能走 `AppNavigationState`**；`IndexedStack` 切回来**既不 `initState` 也不重读库**——凡可能在别的 Tab 被改掉的
  数据都要在切回本 Tab 时重载，**推子页面返回后也要 `_load()`**。
- **节假日两个正交维度绝不能合并**：`DateTime.weekday`（天然）vs `CalendarDayKind`（国家安排）；所有「这天休息吗」
  必须查 `CalendarDayKind`，**禁止只判 `weekday == 6 || 7`**（否则课时算少）。**「调休那天上周几的课」必须老师确认、
  不准猜**（存 `app_settings`，值 `'1'..'7'` 或空串，**没有任何默认猜测**）。课时结算**走日历而非 weekday**。
  **「这天该上哪一套课」只有一个入口：`HolidayService.dayOf(date).labelWeekday`** —— 考勤页取当日课程、圆环
  `dayStats` 的应点名、课表表头「今天」落列全都要走它，**禁止裸用 `date.weekday`/`DateUtils.isoWeekday`**
  （漏一处就是「调休日照常上课，界面却显示当天没课」）。
- **动效时长/曲线只有 `AppMotion` 一个来源**，禁止裸写 `Duration(milliseconds: ...)`；**过冲曲线只能用于位移/缩放**，
  喂给 `Interval.transform`/`lerpDouble` 的值必须 `.clamp(0.0, 1.0)`；**颜色/描边/阴影/透明度一律用单调的 `effects`**。
- **`FilledButton`/`ElevatedButton`/`OutlinedButton` 不能直接放进 `Row`**（全局 `minimumSize: Size.fromHeight(52)`
  → `BoxConstraints forces an infinite width`）。**所有 SnackBar 一律 2 秒**。
- **Android `INTERNET` 权限必须写在 `AndroidManifest.xml`**：debug/profile 由 Flutter 自动补，**release 不会**。
- **设置页第一页只有四块**（第 22 轮用户规格，`test/widget/settings_page_test.dart` 盯着）：课表与名单 /
  **系统设置（一条入口）** / 显示与语言 / 关于；**彩色标题卡在最底部**，不是顶部。原来平铺的
  「教学参数 / 权限 / 数据维护」三块整体搬进 `features/settings/system_settings_page.dart`，页内顺序 =
  未记录日期的默认状态 → 调休(3) → 通知权限(4) → 时间列级联更新 → 清空数据(2)。
  **「拍照生成课表」与「统计设置」不允许再回设置页**（前者与课表页重复，后者在工具箱「教学成果」标题右侧齿轮）。
- **专注模式只有专注态锁屏**，暂停与休息一律不锁；`isBreak` 必须进快照（否则恢复时会把休息当专注锁上）。
  **计时必须墙钟口径**（"每次 tick 减 1 秒"会让 25 分钟 5 分钟就跑完）；`started_at` = **开始**时刻；
  统计**只算 `completed`**；**休息段不写 `focus_session`**；`label` 落库存**稳定 id**、显示时查 l10n。
  增强档「屏幕固定」**先做后验**，失败如实提示，**绝不假装锁上**（普通 App 做不到绝对锁定）。
