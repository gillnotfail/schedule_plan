# schedule_plan 长期约定

> **只记「改错会出事」的硬约束**（注入上限约 10k 字节，超了后续会话看不到 → 只留红线）。
> **细则/常量/文件清单在 `MEMORY-DETAIL.md`**（工具链故障、发布链路、课表格子与曲线、考勤、统计、专注模式等章节）。
> 过程记录在 `YYYY-MM-DD.md`；需求唯一来源 `docs/SPEC.md`；发布手册 `docs/RELEASE.md`。

## 平台 / 需求
- 唯一规格 `docs/SPEC.md`，**别用「更好的设计」覆盖**。
- 只做 Android APK（iOS 不验证、不加鸿蒙）；**Windows 上 `README.md`/`readme.md` 是同一文件**。

## 工具链
- 提交前 `flutter analyze --no-pub` 零 issue（含 `test/`）+ `flutter test` 全绿（当前 **517**）；
  **跑前设 `NO_PROXY=localhost,127.0.0.1,::1`**（代理会劫持 flutter_tester 的 WebSocket）。
- flutter 一律走 `C:\Users\jeo\AppData\Local\Temp\wb_run_flutter.py`（直调 `flutter.BAT`）；
  **以日志最后一行 `=== EXIT n ===` 为准**（PowerShell 承接输出时退出码不可信）。
- **同一时刻只跑一个 flutter 命令**（并发撞 `sqlite3.dll`，删 `build/native_assets` 重跑）；
  **长命令必须显式给 `timeout`**（默认 120s 就掐，`run_in_background` 不豁免）。
- **`CreateFile failed 231`（管道耗尽）是 WorkBuddy 进程环境问题，重启电脑无效**：判据只有
  「当场起一个 Dart 子进程」；处置是请用户在自家终端跑 .bat。假象：Bash 看似正常、PowerShell 静默返回空。
- **.bat 里禁止用 `if errorlevel 1` 当门禁**（`flutter.BAT` 成功也返回非 0，会静默跳过后续全部流程）。
- 批量改代码走独立 .py（每处 `assert 旧串 in s`；CRLF 用 `newline=''` 读）；**同一文件多处改动一条条 Edit**。
- widget 测试：改窗口用 `tester.view.devicePixelRatio/physicalSize` + `addTearDown(tester.view.reset)`；
  `find.text` 撞刻度用 `find.descendant` 限定；`initState` 读 sqlite 要用 `tester.runAsync` 放它跑完；
  **统计页有常驻动画 → 不能 `pumpAndSettle`**，改 `tester.pump(400ms)`。

## 数据模型
- `lesson.period_index` 相对 `class.template_id`；**冲突检测按真实时间重叠，禁止比 period_index**。
- 时间存 `"HH:mm"`、日期存 `"YYYY-MM-DD"`；考勤唯一键 `(student_id, lesson_id, date)`。
- DB `version=9`、**16 张表**（`schema_test.dart` 断言数量/顺序，加删表同步改）；加表一律**纯加表加列**；
  **不动 `migrate()` 的 `rebuildingCourse` 段**（否则 DROP course 级联清空 lesson）。
- **删模块前按 import 路径全库 grep（下划线形式）**，别只搜驼峰类名（有一文件多类的仓库）。
- 桌面 sqflite 先 `AppDatabase._ensureDatabaseFactory()`；ff 包 import 要 `hide DatabaseException`，别与 `sqflite` 同时 import。
- 课程配色唯一口径 `CourseDetail.color`，只走 `parseHexColor`；**铺满一块的地方都要再过 `solidFillColor`**（白字对比度 ≥ 3.2）。
- 翻月走 `DateUtils.shiftMonth`（`DateTime(y,m±1,d)` 会进位）；加天用 `DateTime(y,m,d+n)`。

## i18n
- 禁止硬编码，全走 `app_zh/en.arb` + `context.l10n`，zh/en 严格对齐（当前各 **754** 键）。
- **加键一律走 `.workbuddy/tools/add_l10n_keys.py`**（幂等）：`NEW_KEYS` 加、`UPDATE_KEYS` 改（内含 assert）、
  `PLACEHOLDERS` 加 `@key`；跑完 `gen-l10n` 再 analyze。**别拿 `"...元数据",\n}` 当锚点**（三个 dict 都以它结尾）。

## 发布（细则见 DETAIL）
- **仓库必须公开**；**token 只放 `~/.schedule_plan-release.env`**，不进仓库、不进对话。
- **`release.py` 顺序不能反**：提交 → 打标签 → 推送 → 再建 Release（要建 Release 必须带 `--push`）。
- `version: x.y.z+N`，**N 必须递增**；**CHANGELOG 没对应版本节直接拒绝发布**（设计如此）；条目写用户看得懂的话。
- **双仓库**（Gitee 首选 + GitHub，各发一份）；清单必须保留单数 `assetsBase`；
  **`schemaVersion` 绝不因加字段 +1**（老客户端会判清单不可用 = 锁死已装机用户）。
- 回验「本机连不上」≠「源坏了」（只有明确 4xx/5xx 才剔源）；发布最后清 jsDelivr 缓存（必须走 curl，
  `status==finished` 不代表清成功，看 `throttled`）。
- 分差掩码取高 15 位（bits 17..31）；三层安全网：清单 SHA-256 → 合成后交叉校验 → 生成端 `--verify`。
- 安装走 `PackageInstaller`；`RandomAccessFile.writeFrom(list,start,end)` 第三参是**下标 end** 不是长度。
- 构建 `flutter build apk --release`（签名 `android/key.properties` + `keystore.jks`，不入库）；
  改 proguard 别删 `-dontwarn com.google.android.play.core.**`。

## 红线速查（常量与文件清单在 DETAIL）
- **课表骨架：表永远是满的**。出厂作息唯一来源 `DatabaseSchema.generatePeriodRows`（禁止第二份循环），三层兜底缺一不可。
  「一键清空课表」**只清 `lesson`**；「在看哪套作息」必须**冷存储**，禁止按 `is_default`/第一个模板推导；
  改节次时间时结束时间 = **本节自己的课堂时长**。
- **课表页不按班级切分、没有 FAB**；空格子点击判定只有一条「全库有没有课程」；**换课只改 `courseId` 不动 `classId`**；
  点格子一律**对话框**；「去点名」名单 = 该课**全部班级的并集**。
- **表格与曲线档都必须一屏铺满**：禁止 `gridDayMinWidth × 天数` + 横向滚动；曲线档 `dayWidth = 可用宽 / 7`、
  走 `TimeAxis.fitted`，**不许有任何 `Scrollable`**。
- **考勤记录不随课表变动删除**（`lesson_id` 可空 + `ON DELETE SET NULL` + 快照列，查询 LEFT JOIN + `COALESCE`）。
  状态是**平铺胶囊**，**不要退回「点击循环切换」**；**七枚胶囊 / 八种状态**：出 迟 早 缺 假 ｜ 休 免，
  「迟到+早退」= **迟、早两枚同时亮**（用户明确否掉加第八枚）→ 一个枚举 `lateAndEarly`（库内 `late_early`）、
  一条记录；单迟到再点「迟」**不写库**；统计**只算一次异常**但 `isLate`/`isEarlyLeave` 都认它（SQL 用 `IN (...)`）；
  摘要按**枚举声明顺序**输出（`choices` 没有组合态，照它遍历会漏人）。
  **休学 ≠ 免修**：休学**锁死日常状态**（出口=再点休学→「复学」确认）；免修只作角标、**不锁**。
  **考勤日历格子只有四样标记**（唯一来源 `calendar_marks.dart`）：放假红点、调休上班紫点、未点名淡圈、
  点过名红弧；**不许再加**，改任一标记必须同步改图例，否则"图例说的"和"格子画的"对不上。
- **跨 Tab 只能走 `AppNavigationState`**；`IndexedStack` 切回来既不 `initState` 也不重读库，凡可能被别处改的
  数据都要在切回时重载，**推子页面返回后也要 `_load()`**。
- **节假日两个维度绝不能合并**：`weekday`（天然）vs `CalendarDayKind`（国家安排），「这天休息吗」必须查后者，
  **禁止只判 `weekday == 6 || 7`**。「调休那天上周几的课」**必须老师确认、不准猜**（存 `app_settings`）。
  **「这天该上哪一套课」唯一入口 `HolidayService.dayOf(date).labelWeekday`**，禁止裸用 `date.weekday`。
- **动效只有 `AppMotion` 一个来源**，禁止裸写 `Duration(milliseconds:)`；过冲只用于位移/缩放，
  喂给 `Interval.transform`/`lerpDouble` 必须 `.clamp(0,1)`；颜色/描边/透明度用单调的 `effects`。
- **`FilledButton`/`ElevatedButton`/`OutlinedButton` 不能直接放进 `Row`**（全局 `minimumSize` 撑成无限宽）；
  **所有 SnackBar 一律 2 秒**；**Android `INTERNET` 权限必须写在 `AndroidManifest.xml`**（release 不自动补）。
- **设置页第一页只有四块**：课表与名单 / 系统设置（一条入口）/ 显示与语言 / 关于，**彩色标题卡在最底部**；
  「拍照生成课表」与「统计设置」不许回设置页（后者在工具箱「教学成果」齿轮）。
- **统计 = 两本台账**（SPEC 3.8~3.11）：干预台账（`riskRanking` 加权分）迟到/早退**各计一次**；评价台账
  （出勤率排行 + 学生档案）五个状态数**互斥**、组合态单列 —— **口径不同是刻意的，不许统一**。
  出勤率 = **1 − 缺勤 ÷ 应上**（迟到/早退/请假不进分子）；应上由 `countScheduledSessions` 按课表推算
  （放假日不算、调休走 `labelWeekdayOf`、休学跳过、**未点名按全勤**）；改课表会追溯重算、必须写在界面上；
  **不许把"没点名"伪造成 present 行**。口径文案只在 `attendance_formula_sheet.dart` 一处。
- **专注模式只有专注态锁屏**（暂停/休息不锁），`isBreak` 必须进快照；**计时必须墙钟口径**；统计只算 `completed`；
  休息段不写 `focus_session`；`label` 落库稳定 id。**释放锁定必须无条件**（靠"我记得锁过"判断会漏掉
  `stopLockTask()`，用户被钉在 App 里 —— 第 28 轮真事故）。准备态一屏与滚轮细则见 DETAIL。
