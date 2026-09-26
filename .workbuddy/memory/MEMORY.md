# schedule_plan 长期约定

> **只记「改错会出事」的硬约束**。**注入上限实测 ≈10.9k 字符**（截断点在此文件 offset 10877），超出的部分后续会话
> **看不到** → 本文件只留**红线**；**细则、常量、文件清单在 `MEMORY-DETAIL.md`**；过程记录在 `YYYY-MM-DD.md`。
> **动这些子系统之前必须先读 `MEMORY-DETAIL.md`**：课表格子与曲线布局、考勤名单与日历圆环、表单与名单、节假日与调休、
> 日程与统计、全局动效与配色、机械表盘、拍照识别课表。
> 需求唯一来源 `docs/SPEC.md`；发布细节 `docs/RELEASE.md`。

## 平台 / 需求
- 唯一规格 `docs/SPEC.md`（原 README.md，第 15 轮改名让位给 GitHub README）。**别用「更好的设计」覆盖**。
- **Windows 上 `README.md`/`readme.md` 是同一文件**：别照抄 GitHub 的 `echo "# x" >> README.md`。
- 只做 Android APK；iOS 只留默认模板，不验证。**暂不加鸿蒙（ohos）代码**。

## 质量门槛与工具链（提交前必跑）
- `flutter analyze --no-pub` 零 issue（**含 test/**）；`flutter test` 全绿。
- **跑前设 `NO_PROXY=localhost,127.0.0.1,::1`**，否则代理劫持 flutter_tester 的 WebSocket。
- **本机 Git Bash 的 coreutils 全废**（`ls`/`grep`/`tail` not found）。flutter 一律走 **PowerShell**；找文件用 Glob、
  找内容用 Grep，**不走 Bash**；Bash 里只有 managed Python/Node 的绝对路径可用。
- PowerShell 重定向用 `& flutter ... 2>&1 | Out-File -Encoding utf8 <log>`，**不要 `*>`**（UTF-16LE）；读日志用
  Python `open(p, encoding='utf-8')`；看中文测试名先设 `[Console]::OutputEncoding` 为 UTF8。
- **PowerShell 承接 flutter 输出时退出码不可信**（stderr 的 `Flutter assets will be downloaded...` 被包成
  `NativeCommandError`）——**只信日志最后一行**（`No issues found!` / `All tests passed!`）。
- **同一时刻只跑一个 flutter 命令**：并发让 native assets 拷贝撞车报 `PathExistsException ... sqlite3.dll`；
  真撞了删 `build/native_assets` 重跑。改源码时不同时构建。
- **同一文件多处改动要一条条 Edit**（并行写会互相覆盖：日志 success 但没落盘），改完复核。
  **Edit 替换「注释+紧邻声明」后立刻 analyze**（曾连注释删掉 `enum _TipTone` → 9 个 undefined_identifier）。
- 批量改代码走**独立 .py 脚本**（`bash -c`/PowerShell 单行会被 shell 吃掉中文+三引号+`$`）；每处 replace 前
  `assert 旧串 in s`；注意 CRLF，用 `newline=''` 读。`bash` heredoc 被安全策略拦，长文本用 Write/Edit。
- widget 测试改窗口：`tester.view.devicePixelRatio = 1; tester.view.physicalSize = size; addTearDown(tester.view.reset);`，
  别给 `MaterialApp` 套 `SizedBox`。测试 `main()` 内局部函数**不加下划线前缀**。
- widget 测试 `find.text` 会撞时间轴刻度，断言浮层用 `find.descendant(of: 浮层)` 限定。
- 单测要真实亮度/对比度用 `dart:math` 的 `math.pow(...).toDouble()`，别手写 Taylor 展开。
- 断言日期前想清楚：**假期里的周六不是 weekend**（2026-09-26 在中秋假期内 → `holiday`）。

## 数据模型
- `lesson.period_index` 相对 `class.template_id`；真实时间靠 `lesson JOIN class JOIN template_period`。
  **冲突检测按真实时间区间重叠，禁止比 period_index**（多模板聚合会误判）。
- 时间存 `"HH:mm"`、日期存 `"YYYY-MM-DD"`，不存时间戳。考勤唯一键 `(student_id, lesson_id, date)`。
- 外键显式 ON DELETE；迁移包事务 + 校验 `class.template_id` 无悬空。
- DB `version=7`，**18 张表**（`test/unit/schema_test.dart` 断言数量/顺序，加表必须同步改）：v3 `course.color`、
  v4 `attendance_record`、v5 `student_course_status`、v6 `schedule_event.recurrence`（默认 `'once'`）、v7 `holiday_day`。
  全是**纯加表加列**、可重复执行、不重建表。**不动 `migrate()` 里 `rebuildingCourse` 那段**（只服务 v1→v2，
  须临时关外键，否则 DROP course 级联清空 lesson）。
- 桌面 sqflite 必须先初始化 FFI：`AppDatabase._ensureDatabaseFactory()` 按平台调 `sqfliteFfiInit()` + `databaseFactoryFfi`，
  否则 not initialized。`sqflite_common_ffi` + `sqlite3_flutter_libs` 必须在 `dependencies`。ff 包 import 要
  `hide DatabaseException`，且别与 `sqflite` 同时 import（analyzer 判 unnecessary）。
- 课程配色唯一口径 `CourseDetail.color`：课程自选 > 挂载班级里第一个 > 主题兜底。只走 `parseHexColor`
  （`core/utils/color_utils.dart`），**禁止 `int.parse` 裸转**；课表/课程卡/表单预览不许各写一套。
- 翻月走 `DateUtils.shiftMonth`（`DateTime(y,m±1,d)` 会进位：3/31 往前变 3/3）；加天用 `DateTime(y,m,d+n)`。

## i18n
- 禁止硬编码，全走 `lib/l10n/app_zh.arb`/`app_en.arb` + `context.l10n`，zh/en 严格对齐。
- **加键一律走 `.workbuddy/tools/add_l10n_keys.py`**（幂等）：`NEW_KEYS` 加键、`UPDATE_KEYS` 改已存在键口径（脚本内
  `assert key in data`，不许凭空 create）、`PLACEHOLDERS` 加 `@key`；末尾自带对齐断言。跑完 `flutter gen-l10n`
  （有 `l10n.yaml` 时命令行参数被忽略，属预期）再 analyze。当前 zh/en 各 **679** 键。

## 发布与更新链路
- **仓库必须公开**：应用里没有也不该有凭据，只能匿名取清单与安装包。私有仓库下**发布全绿、手机端永远看不到
  更新**（raw 与 jsDelivr 都 404，jsDelivr 根本不服务私有仓库）。判断：匿名 `GET api.github.com/repos/<o>/<r>`
  → 404 即私有。**别把 token 塞进 App 换私有**（APK 可反编译）。转公开前先审历史有无 `*.jks`/`key.properties`/APK。
- **`release.py` 顺序不能反**：**先提交打标签推送 → 再建 Release**。反过来的话 GitHub 会按 `target_commitish`
  （默认远端默认分支 HEAD）**自造同名标签** → Release 挂在旧提交上、随后 `git push` 标签被 `already exists`
  拒绝；两个症状都出现在上传成功之后。故 `upload_release` 必须显式传本次提交 SHA，推送后再 `ls-remote` 复核。
  **要建 Release 就必须去掉 `--no-commit` 且带 `--push`**（脚本会拦）。已发错的修法：
  `git push origin +refs/tags/vX:refs/tags/vX`。
- 仓库 `gillnotfail/schedule_plan`。`README.md` 面向 GitHub，规格 `docs/SPEC.md`，更新说明 `CHANGELOG.md`
  （**必须写用户能看懂的话**：`tool/release.py` 原样抽最新一节进 `updates/latest.json` 给应用内展示）。
  `updates/latest.json` **入库**；APK 与补丁挂 Releases **不入库**。`.gitignore` 覆盖 `*.jks`/`*.keystore`/
  `key.properties`/`*.apk`/`dist/`/`symbols/`。
- `pubspec.yaml` 的 `version: x.y.z+N`，**`N` 是 versionCode，每次发版必须递增**，否则拒绝覆盖安装。
- **`tool/release.py`**：`--bump` 自增版本号并写回 pubspec；**推送必须显式 `--push`**（标签一次性，试探性的本地跑
  不该造出不可回收的标签）；`--no-commit` 真空跑；`--skip-upload` 只产本地产物。分差基准取**严格小于当前
  versionCode 里最大的那个**，不能取「清单里第一个不是自己的」（清单降序，补发旧版本时会拿更新的版本当基准，方向反了）。
  **基准包缓存 `dist/releases/<code>/` 是分差的地基**——动过里面的 APK 就必须删掉整个 `dist/` 重跑。
  **CHANGELOG 里没有对应版本节时直接拒绝发布**（设计如此，不是 bug）。
- **`GITHUB_TOKEN`**：环境变量优先，其次 **`~/.schedule_plan-release.env`**（dotenv）。**故意放家目录不放仓库**
  （仓库里任何文件都可能被 `git add -A` 带上去，PAT 泄露不可逆）。`verify_token()` 在**打包之前**先验（`GET /user` +
  `GET /repos/...` 的 `permissions.push`）。`token_looks_truncated()` 专拦「复制了一半」：**细粒度 PAT 共 93 字符、
  中间还有一个下划线**，截断后服务端只回一句 `401 Bad credentials`。`commit_and_tag` **幂等**（标签已存在且
  `rev-parse <tag>^{}` == HEAD 就跳过）。
- **别让用户把 token 贴进对话**（实测两次都被截到 31 字符，形态 `github_pat_`+20 位、连第二个下划线都没有）；
  让用户用编辑器直接写 `~/.schedule_plan-release.env`。`token_file_status()` 会区分「文件不存在 / 没有那一行 /
  等号右边为空 / 有值读不出」——别把四种合成一句「没有可用的 GITHUB_TOKEN」。
- 按行改 dotenv/ini **必须逐行比键名**：`re.sub(r"GITHUB_TOKEN=.*")` 会把注释行里同名的文字一起吃掉。
- **本机网络（实测）**：`github.com` 解析出的 IP **TCP 直连不通**（DNS 给 `20.205.243.166`，而 `140.82.112.4:443`
  是通的 → **特定 IP 被封，不是域名**）；`api.github.com`/`uploads.github.com`/`objects.githubusercontent.com`/
  `raw.githubusercontent.com`/jsDelivr **都通**。→ 发布不受影响；清单默认下载地址指向 `github.com`，手机侧若同样封
  这组 IP 必须配镜像前缀，且**这台机器验证不了下载地址**。系统代理配了 `127.0.0.1:7890` 但 **`ProxyEnable=0` 且端口没监听**。
- **分差**：`tool/delta_patch.py`（生成端）+ `lib/core/utils/delta_patch.dart`（设备端）。CDC（32 位 gear 哈希滚动找
  边界）+ SPDP v1（整体 gzip，固定头 98 字节；命令只 `COPY_BASE(offset u64, length u32)` 13 字节与
  `COPY_LITERAL(length u32)` 5 字节）。
  - **分块只在生成端**，设备端只「校验指纹 → 按命令搬字节 → 校验产物指纹」；故无「两端边界一致」的跨语言陷阱，
    只需格式解析一致（`test/fixtures/delta/` 固定样例锁住）。
  - **掩码必须取高 15 位（bits 17..31）**：`h=(h<<1)+GEAR[b]` 的 bit0 恒等于 `GEAR[末字节]&1`，低位只有 256 种取值，
    放低位会退化（曾出现「整份文件切不出边界」）。`selftest` 有**分块均值必须落在 `[1<<14,1<<16]`** 护栏；
    **别拿复用率当格式兼容性门槛**（守错指标）。
  - 纯零串在 gear 哈希下收敛到不动点（`-GEAR[0]=0xA7825A60`），长零填充稳定切 `MAX_CHUNK`；**撞上限的块长度与内容
    无关 → 边界不因内容改动漂移**（改 1 字节仍复用 99.9% 的原因）。用例用「数据块与零填充交替」，**别整份都是零**。
    `MAX_CHUNK = 64*1024`；`chunk_index` 必须**保留全部位置（含末尾残块）**；命中候选必须**逐字节复核**（防碰撞）。
  - 实测 22.89 MB APK：改 1 字节 → 0.11%；删 4096 字节（后 10.9 MB 全位移）→ 0.10%；中间 500 KB 清零 → 0.17%；
    完全相同 → 0.02%；**arm64 → armeabi-v7a（最坏）→ 42.5%**。
- **三层安全网**：① 下载后按清单 SHA-256 校验；② 分差合成后再与**清单里整包的指纹交叉校验**（两个独立来源）；
  ③ 生成端 `--verify`。任一步失败 → 删文件、换下一地址、**最终回落下载完整包**。
  `UpdateManifest.deltaWorthwhileRatio = 0.9`（补丁 ≥ 整包 90% 不生成）。
- **安装走 `PackageInstaller`，不用 `ACTION_VIEW` + FileProvider**：本项目 `androidx.core` 由 share_plus 以
  `compileOnly` 引入 → **自建 FileProvider 子类编译不过**（决策性理由）。走「字节写进安装会话管道」，无需 content URI，
  还能拿 `installResult` 回执。需 `REQUEST_INSTALL_PACKAGES` + `canRequestPackageInstalls()` + 「安装未知应用」授权页。
  `InstallResultReceiver` 会被调用**一到两次**；系统装完重启进程致回执丢失 → 故有
  `UpdateService.markInstalledExternally()`（回前台比对版本号）。
- **清单地址**：raw.githubusercontent（第一）+ jsDelivr（第二、国内可达）+ 用户可配镜像前缀。自动检查一天一次
  （`updateLastCheckAt` 节流）。`UpdateService` 是独立 `ChangeNotifier`，`AppDependencies` 里
  `unawaited(autoCheckIfDue())`（不阻塞启动、不弹窗打断）。
- **`RandomAccessFile.writeFrom(list, start, end)` 第三个参数是下标 `end` 不是长度**；写错时第一条命令（cursor=0）
  恰好正确、第二条才抛 `RangeError`——**只有多条命令才暴露**。

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
  命中者自动沉底）；日历标记是**进度圆环**（出勤人次 ÷ 应点名人次），**不要退回一个小红点**。
- **跨 Tab 只能走 `AppNavigationState`**；`IndexedStack` 切回来**既不 `initState` 也不重读库**——凡可能在别的 Tab 被改掉的
  数据都要在切回本 Tab 时重载，**推子页面返回后也要 `_load()`**。
- **节假日两个正交维度绝不能合并**：`DateTime.weekday`（天然）vs `CalendarDayKind`（国家安排）；所有「这天休息吗」
  必须查 `CalendarDayKind`，**禁止只判 `weekday == 6 || 7`**（否则课时算少）。**「调休那天上周几的课」必须老师确认、
  不准猜**（存 `app_settings`，值 `'1'..'7'` 或空串，**没有任何默认猜测**）。课时结算**走日历而非 weekday**。
- **动效时长/曲线只有 `AppMotion` 一个来源**，禁止裸写 `Duration(milliseconds: ...)`；**过冲曲线只能用于位移/缩放**，
  喂给 `Interval.transform`/`lerpDouble` 的值必须 `.clamp(0.0, 1.0)`；**颜色/描边/阴影/透明度一律用单调的 `effects`**。
- **`FilledButton`/`ElevatedButton`/`OutlinedButton` 不能直接放进 `Row`**（全局 `minimumSize: Size.fromHeight(52)`
  → `BoxConstraints forces an infinite width`）。**所有 SnackBar 一律 2 秒**。
- **Android `INTERNET` 权限必须写在 `AndroidManifest.xml`**：debug/profile 由 Flutter 自动补，**release 不会**。
