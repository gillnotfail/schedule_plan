# 全面课表计划 Flutter 项目 · 全功能重构 Prompt

> 使用说明:本文档是唯一需要参考的需求规格,已经把 UI 风格、交互模式、数据模型、边界处理全部定好,不需要自行决策"用什么样式""用什么模型""怎么设计交互"。请严格按本文档的表格、字段、流程实现,遇到本文档未覆盖的细节,优先参照本文档已有模块的同类实现方式保持一致,而不是自行发挥。

---

## 一、项目概述

- **项目名称**:全面课表计划(工作代号,面向一线教师/辅导员的个人效率工具)
- **项目定位**:面向单个教师日常使用的移动端应用,核心场景是"查看自己的课表→按课表记考勤→根据考勤和课表生成待办→统计导出"。不是学校级排课系统,不需要多角色权限、不需要服务端排课引擎。
- **目标用户**:中学/大学一线教师、辅导员(班主任),可能同时承担多个年级/班级的教学任务。
- **技术栈**:
  - Flutter(跨平台 UI 框架),Dart 语言
  - 本地持久化:SQLite(通过 sqflite 或等价包),不使用云端数据库,不要求账号登录
  - AI 拓写功能(教师工具箱-快速笔记)：通过 HTTP 调用外部 LLM API,需支持配置多个提供商(如 OpenAI 兼容接口、Anthropic 接口等),API Key 由用户自行在设置中填写并加密存储在本地
  - 推送通知:使用 flutter_local_notifications 或等价包实现本地定时通知,不依赖云推送
- **运行平台**:优先 Android,暂不要求 iOS/Web/桌面适配
- **交付形态**:单一 Flutter 工程,可直接 `flutter build apk` 打包

---

## 二、功能模块详细需求

### 模块一:课表管理(含多作息模板系统)

#### 1.1 设计前提:为什么需要"作息模板"而不是全局统一作息

传统做法是全局配置一套"上课日、每日节数、起止时间、课时时长、课间时长",所有班级共用。但现实中同一所学校可能有多个年级错峰安排(例如高一 11:20 午休,高二高三 12:00 才午休),一个教师可能同时教多个年级,这些年级的"第4节"对应的真实时钟时间是不同的。

因此本项目采用"作息模板"机制:节次编号与真实时间解耦,每个班级/年级绑定一个模板,课表条目只记录"第几节",真实时间通过联查模板动态解析。**这是整个课表模块的基础设计,后面所有功能点都建立在这套机制之上。**

#### 1.2 作息模板管理(新增独立设置页)

**入口**:设置 → 作息模板管理,列表页展示所有模板卡片,每张卡片标注:模板名称、绑定的班级数量、是否为默认模板。

**交互流程**:
1. 点击"新建模板"→ 弹出全屏编辑页,先填写模板名称(必填,建议加输入校验防止空字符串)
2. 编辑页以"周一~周日"横向 Tab 切换,每个 Tab 内是可增删行的节次列表,每行包含:
   - 节次序号(自动编号,不可手动改,增删行后自动重排)
   - 类型下拉:普通课节(normal)/午休(lunch_break)/课间大休(recess)/自习(self_study)/其他(other)
   - 起止时间选择器(滚轮式,复用 1.5 节所述的滚轮组件)
3. 支持"从其他工作日复制"按钮:选中某一天的完整配置,一键复制到多个目标日期,减少重复录入
4. 保存前校验(校验失败必须在对应行内联提示具体原因,不允许静默失败或直接崩溃):
   - 同一天内所有时间段(含非 normal 类型)不得互相重叠
   - 按节次序号升序排列时,起始时间必须严格递增
   - 结束时间必须晚于起始时间,且同属一个自然日(本期不支持跨天时段,如遇 end_time ≤ start_time 直接拒绝保存)
5. 模板列表页支持"设为默认"操作,二次确认弹窗文案:"新建班级时将默认使用此模板,已绑定其他模板的班级不受影响"

**编辑已被使用的模板**:
- 修改一个已被至少一个班级绑定的模板的节次时间时,弹出提示:"此操作会影响 N 个班级的课表显示时间,不会修改具体上课内容安排"
- 删除模板前必须校验:若仍有班级绑定该模板,禁止删除,提示文案列出具体受影响的班级名单,引导用户先迁移

#### 1.3 班级绑定作息模板

- 班级创建/编辑表单中新增"作息模板"下拉选择器,默认预选当前的默认模板
- 年级管理页支持"批量修改本年级所有班级的作息模板",操作前必须展示将被影响的班级清单并二次确认

#### 1.4 周视图课表(周一~周日可配置)

- **单班级/单年级查看模式**(如班主任查看本班课表):沿用传统"节次网格"——横轴周一到周日,纵轴按该班级绑定模板的节次编号从第1节到第N节,固定行高。由于该视图内所有课来自同一模板,不存在跨模板时间对齐问题。
- **教师个人聚合视图**(教师首页/我的课表,可能跨多个年级/模板)——**必须使用时间轴网格渲染,不能用固定节次行的网格**,具体渲染算法:
  1. 联查该教师本周所有课表条目,通过 `class.template_id → template_period` 解析出每节课的真实起止时间
  2. 确定时间轴上下界:取本周所有课程真实时间的最小起始值与最大结束值,分别向下/向上取整到最近的整点或半点,并各预留至少30分钟余量
  3. 纵轴按分钟数线性映射像素高度,`pxPerMinute` 做成可配置常量而非硬编码,且当总时间跨度过大时自适应缩小该值,保证单屏总高度不超过设定上限(避免早6点到晚10点这种极端跨度导致滚动卡顿)
  4. 每节课渲染为绝对定位色块:`top = (course.start_minutes - axisStart_minutes) * pxPerMinute`,`height = (course.end_minutes - course.start_minutes) * pxPerMinute`
  5. 色块内文案展示课程名、班级/年级名、真实起止时间(如"高一(3)班 11:20-12:00"),**不展示裸的"第4节"编号**,因为跨年级场景下编号本身没有可比较的意义
  6. 非 normal 类型的时段(午休/大课间)在背景以浅色条带标注,帮助教师直观看到"这段时间其他年级在上课/休息",但该条带不可点击
  7. 时间轴上叠加一条随实际时间自动下移的"现在时间线"(红色细线),非上课时段该线仍显示,可降低透明度

#### 1.5 一键新增课表

- 底部半屏弹层(Bottom Sheet,占屏幕高度约60%,可上滑展开至90%)
- 弹层内以"Depth Stack 候选卡片"形式展示:第一张卡片选班级,选中后滑出第二张卡片选课程,再滑出第三张选周几和节次,层层递进,每层都可返回上一层重新选择
- 保存时执行 3.4 节所述的冲突检测逻辑

#### 1.6 一键修改课表时间

- 滚轮选择器(iOS风格分段滚轮:时、分两列独立滚动)
- 手势带速度衰减(快速滑动后有惯性滚动,逐渐减速)
- 停止时自动吸附到最近的5分钟刻度(吸附动画时长建议200ms)

#### 1.7 时间列级联更新

- 修改某一节课的时间后,弹出选项:"仅修改本节"/"同步修改后续所有节次"(后者会按原有节次间隔顺延调整)
- 该级联开关可在作息模板编辑页统一开启/关闭,默认开启

#### 1.8 课程格子交换模式

- 长按课程格子进入"交换模式"(格子边框高亮并有轻微放大动效),此时拖拽到另一个格子上释放即完成两节课的位置互换
- 交换仅允许在同一班级同一模板内进行,跨班级/跨模板的格子不支持直接拖拽交换(因为节次编号语义不同),尝试跨模板拖拽时格子显示"禁止"图标并震动反馈

---

### 模块二:考勤管理

#### 2.1 日历选日期

- 月视图/周视图可切换(顶部一个 Toggle 按钮)
- 有课的日期在日历格子上显示小圆点标记

#### 2.2 根据课表自动加载当日课程

- 选中日期后,自动查询该教师当天(按 weekday)的所有课表条目,联查所属班级的模板解析出真实时间,按真实时间排序展示

#### 2.3 课程 Chip 横滑条

- 横向可滑动的 Chip 列表,区分"今日有课"(实心高亮)与"其他课程"(描边低亮度,用于教师临时给非当天课表班级补录考勤的场景)

#### 2.4 学生列表

- 支持按姓名拼音、学号、当前考勤状态三种方式排序,排序方式记忆在本地(下次进入沿用上次选择)

#### 2.5 五种考勤状态

- 出勤 / 迟到 / 早退 / 缺勤 / 请假,每种状态对应固定色值和图标,点击学生条目快速切换,支持长按弹出更细粒度备注

#### 2.6 考勤记录按日期保存

- 切换日历日期后自动加载/切换对应日期的考勤数据,未记录过的日期默认全部学生状态为"出勤"(可在设置中改为"未标记"作为默认值)

#### 2.7 同天同课程不同节次考勤独立记录

- 考勤记录的唯一键是 `(student_id, lesson_id, date)` 而不是 `(student_id, course_id, date)`,确保同一天同一门课如果排了两节,两次考勤互不覆盖

#### 2.8 随机点名

- "老虎机滚动"动画:姓名列表快速滚动后逐渐减速,最终定格在随机选中的学生上(减速曲线建议 easeOutCubic,总时长约2.5秒)
- 已点过名的学生本次点名会话内不重复抽取,直到全部点完一轮后重置

#### 2.9 高风险学生自动检测

- 缺勤次数达到阈值(默认3次,可在设置中调整)的学生自动打上"高风险"标记,在学生列表和统计页突出显示

#### 2.10 表现标签系统

- 7种预设标签(如"积极发言""按时完成作业"等,具体文案可参照教育场景常见表述)+ 星级评分(1-5星)+ 文字备注,均可在记录考勤时一并快速打上

#### 2.11 一键复制出勤摘要到剪贴板

- 生成格式化文本摘要(班级、日期、出勤/缺勤/请假人数及具体名单),点击后复制到系统剪贴板并弹出 SnackBar 确认

---

### 模块三:考勤统计与导出

#### 3.1 出勤率折线图

- 支持按日/周/月三种粒度切换,切换时保留当前选中的班级筛选条件

#### 3.2 课程出勤率柱状图

- 横轴为课程/班级,纵轴为出勤率百分比,低于设定阈值(默认85%)的柱子变色警示

#### 3.3 异常出勤明细列表

- 列出所有非"出勤"状态的记录,支持按状态类型筛选

#### 3.4 高风险学生排名

- 按缺勤/迟到加权计分降序排列,分数计算规则:缺勤×3 + 迟到×1 + 早退×1(权重可在设置中调整)

#### 3.5 情绪价值卡片

- 根据整体出勤率自动生成鼓励性文案(如出勤率高于95%显示"这个班级的孩子们真给力"等语气正向的短句),避免生成任何负面或指责性表述

#### 3.6 Excel 多 Sheet 导出

- 生成的 Excel 文件包含三个 Sheet:考勤汇总、异常明细、学生排名,导出后调用系统分享面板供用户发送到微信/邮箱等

---

### 模块四:智能待办

#### 4.1 课程待办自动生成

- 根据课表和考勤联动自动生成待办(如"检查XX班本周缺勤学生情况"),生成规则:某班级本周累计出现2次以上缺勤记录时自动生成一条待办

#### 4.2 手动添加待办

- 字段:标题(必填)、描述(可选)、优先级(高/中/低)、截止日期(可选)

#### 4.3 待办完成状态管理

- 勾选完成后有删除线动效,已完成项自动下沉到列表底部并可折叠隐藏

#### 4.4 拖拽排序

- 长按拖拽调整待办顺序,排序结果本地持久化

#### 4.5 考勤联动自动完成

- 当自动生成的"检查缺勤"类待办对应的班级本周不再有新增缺勤时,自动标记为已完成,并在待办条目上标注"系统自动完成"

---

### 模块五:教师工具箱

#### 5.1 专注模式(番茄钟)

- 标准番茄钟计时(默认25分钟专注+5分钟休息,可调整),配合水波纹进度动画(圆形进度条内部有水波纹随进度上涨的视觉效果)

#### 5.2 快速笔记(支持 AI 拓写)

- 简单文本编辑器,支持选中一段文字后调用已配置的 LLM API 进行"扩写/润色/总结"操作,结果以 Diff 对比形式展示,用户确认后才替换原文
- 设置页支持配置多个 LLM 提供商(填写 API Base URL、API Key、模型名称),可切换默认使用哪一个

#### 5.3 日程安排

- 独立的日历视图 + 事件管理,字段包含标题、时间、地点(可选)、提醒开关

#** 5.4 待办列表**

- 独立于模块四"智能待办"的通用清单,不与课表/考勤联动,供教师记录私人事务

---

### 模块六:课程与学生管理

#### 6.1 课程 CRUD

- 字段:名称、教师、班级、班主任姓名、学生数、描述、颜色标记(用于课表格子配色)、教室

#### 6.2 学生手动逐个添加

- 表单字段:姓名、学号、班级归属,提交后立即出现在对应班级学生列表

#### 6.3 Excel 批量导入

- 支持上传 Excel 文件,自动识别列名(姓名/学号等常见表头关键词模糊匹配),导入前展示预览表格供用户核对班级匹配关系,导入过程展示每一行的同步状态(成功/失败/跳过),失败行给出具体失败原因而非笼统报错

#### 6.4 多班级管理

- 支持教师同时管理多个班级,班级列表页可拖拽调整展示顺序

---

### 模块七:系统级功能

#### 7.1 Android 课前提醒推送通知

- 提醒触发时间**不得**在排课时固化为绝对时间戳,必须在每日凌晨批量生成当天提醒任务时,重新联查当前生效的作息模板计算触发时刻(避免学校中途调整作息后提醒时间过时)

#### 7.2 日程提醒推送

- 与模块五 5.3 的日程事件联动,按事件设置的提醒开关和提前量生成本地通知

#### 7.3 通知权限管理

- 首次需要发送通知前主动请求系统权限;设置页提供"检查权限状态"入口;若权限被拒绝,引导用户跳转系统设置页手动开启,而不是仅提示"请开启通知权限"却没有跳转能力

#### 7.4 中英文国际化切换

- 全部界面文案通过 i18n 资源文件管理,设置页提供语言切换,切换后无需重启应用立即生效

#### 7.5 三套主题切换

- 清新薄荷 / 极简灰白 / 深夜护眼,通过统一的主题色 Token 管理,不允许在具体页面组件中硬编码颜色值

#### 7.6 SQLite 本地存储与自动清理

- 考勤记录保留180天,超期自动清理(清理前先做本地备份文件,防止误删无法恢复)
- 导入日志保留360天,超期自动清理

---

### 模块八:通用交互规范

- 底部导航栏(Material 3 风格)
- 圆角卡片弹窗(统一圆角半径,建议16dp)
- 按钮点击缩放反馈(按下缩小至96%,松开弹回,时长约100ms)
- SnackBar 提示统一样式与展示时长(默认3秒,重要操作可延长)
- 危险操作(删除班级/删除模板/清空数据)必须二次确认弹窗,弹窗文案需具体说明后果,不能只写"确定删除吗?"
- Hero 动画页面转场(列表项点击进入详情页时共享元素过渡)
- 脉冲环/交错动画(用于加载状态或引导用户注意某个新功能入口)

---

## 三、数据库设计(完整 Schema)

> 说明:以下为 SQLite 表结构,字段类型用 SQLite 亲和类型(INTEGER / TEXT / REAL),时间统一存毫秒级时间戳(INTEGER)或 "HH:mm" 格式字符串(仅作息模板节次时间使用字符串,原因见下方说明)。所有外键需显式声明 `ON DELETE` 行为,禁止裸外键不写级联策略。

### 3.1 schedule_template(作息模板)

| 字段 | 类型 | 约束 | 说明 |
|---|---|---|---|
| id | INTEGER | PRIMARY KEY AUTOINCREMENT | |
| name | TEXT | NOT NULL, UNIQUE | 模板名称 |
| is_default | INTEGER | NOT NULL DEFAULT 0 | 全库仅一条为1,写入时需在事务内先清除其他记录 |
| created_at | INTEGER | NOT NULL | |
| updated_at | INTEGER | NOT NULL | |

### 3.2 template_period(模板节次时间)

| 字段 | 类型 | 约束 | 说明 |
|---|---|---|---|
| id | INTEGER | PRIMARY KEY AUTOINCREMENT | |
| template_id | INTEGER | NOT NULL, FK → schedule_template(id) ON DELETE CASCADE | |
| weekday | INTEGER | NOT NULL, CHECK(weekday BETWEEN 1 AND 7) | |
| period_index | INTEGER | NOT NULL | 模板内部节次编号 |
| period_type | TEXT | NOT NULL DEFAULT 'normal' | normal/lunch_break/recess/self_study/other |
| start_time | TEXT | NOT NULL | "HH:mm",存本地时间字符串而非绝对时间戳,避免时区/夏令时问题 |
| end_time | TEXT | NOT NULL | 应用层校验 > start_time |
| label | TEXT | NULL | |

复合唯一索引:`UNIQUE(template_id, weekday, period_index)`

### 3.3 class(班级)

| 字段 | 类型 | 约束 | 说明 |
|---|---|---|---|
| id | INTEGER | PRIMARY KEY AUTOINCREMENT | |
| name | TEXT | NOT NULL | 如"高一(3)班" |
| grade | TEXT | NOT NULL | 年级标识,用于批量按年级操作 |
| head_teacher | TEXT | NULL | 班主任姓名 |
| student_count | INTEGER | NOT NULL DEFAULT 0 | 冗余字段,便于列表展示,增删学生时同步更新 |
| color | TEXT | NOT NULL | 十六进制色值,用于课表格子配色 |
| template_id | INTEGER | NOT NULL, FK → schedule_template(id) | 绑定的作息模板 |
| sort_order | INTEGER | NOT NULL DEFAULT 0 | 班级列表拖拽排序用 |

### 3.4 course(课程)

| 字段 | 类型 | 约束 | 说明 |
|---|---|---|---|
| id | INTEGER | PRIMARY KEY AUTOINCREMENT | |
| name | TEXT | NOT NULL | |
| teacher_name | TEXT | NOT NULL | |
| class_id | INTEGER | NOT NULL, FK → class(id) ON DELETE CASCADE | |
| description | TEXT | NULL | |
| room | TEXT | NULL | 教室 |

### 3.5 lesson(课表条目)

| 字段 | 类型 | 约束 | 说明 |
|---|---|---|---|
| id | INTEGER | PRIMARY KEY AUTOINCREMENT | |
| course_id | INTEGER | NOT NULL, FK → course(id) ON DELETE CASCADE | |
| class_id | INTEGER | NOT NULL, FK → class(id) ON DELETE CASCADE | 冗余存储便于查询,须与 course.class_id 保持一致 |
| teacher_id | INTEGER | NOT NULL | 教师标识(若应用为单教师使用可退化为常量,预留字段便于未来多教师扩展) |
| weekday | INTEGER | NOT NULL, CHECK(weekday BETWEEN 1 AND 7) | |
| period_index | INTEGER | NOT NULL | **相对于 class.template_id 所指模板的节次编号**,不是全局节次,不存绝对时间 |

索引:`(teacher_id, weekday)`、`(class_id, weekday, period_index)` 加速常用查询。

真实时间解析标准查询模式:

```sql
SELECT l.*, tp.start_time, tp.end_time, tp.period_type
FROM lesson l
JOIN class c ON l.class_id = c.id
JOIN template_period tp
  ON tp.template_id = c.template_id
 AND tp.weekday = l.weekday
 AND tp.period_index = l.period_index
WHERE l.teacher_id = :teacherId AND l.weekday = :weekday
```

### 3.6 student(学生)

| 字段 | 类型 | 约束 | 说明 |
|---|---|---|---|
| id | INTEGER | PRIMARY KEY AUTOINCREMENT | |
| name | TEXT | NOT NULL | |
| student_no | TEXT | NULL | 学号 |
| class_id | INTEGER | NOT NULL, FK → class(id) ON DELETE CASCADE | |

### 3.7 attendance_record(考勤记录)

| 字段 | 类型 | 约束 | 说明 |
|---|---|---|---|
| id | INTEGER | PRIMARY KEY AUTOINCREMENT | |
| student_id | INTEGER | NOT NULL, FK → student(id) ON DELETE CASCADE | |
| lesson_id | INTEGER | NOT NULL, FK → lesson(id) ON DELETE CASCADE | |
| date | TEXT | NOT NULL | "YYYY-MM-DD" |
| status | TEXT | NOT NULL | present/late/early_leave/absent/leave |
| note | TEXT | NULL | |

复合唯一索引:`UNIQUE(student_id, lesson_id, date)`,确保同天同课程不同节次独立记录不互相覆盖。

### 3.8 student_tag_record(表现标签记录)

| 字段 | 类型 | 约束 | 说明 |
|---|---|---|---|
| id | INTEGER | PRIMARY KEY AUTOINCREMENT | |
| student_id | INTEGER | NOT NULL, FK → student(id) ON DELETE CASCADE | |
| date | TEXT | NOT NULL | |
| tag | TEXT | NOT NULL | 7种预设标签之一 |
| star_rating | INTEGER | NOT NULL DEFAULT 0, CHECK(star_rating BETWEEN 0 AND 5) | |
| remark | TEXT | NULL | |

### 3.9 todo(智能待办 + 通用待办)

| 字段 | 类型 | 约束 | 说明 |
|---|---|---|---|
| id | INTEGER | PRIMARY KEY AUTOINCREMENT | |
| title | TEXT | NOT NULL | |
| description | TEXT | NULL | |
| priority | TEXT | NOT NULL DEFAULT 'medium' | high/medium/low |
| due_date | INTEGER | NULL | |
| is_done | INTEGER | NOT NULL DEFAULT 0 | |
| is_auto_generated | INTEGER | NOT NULL DEFAULT 0 | 区分模块四自动生成 vs 模块五手动添加 |
| related_class_id | INTEGER | NULL, FK → class(id) ON DELETE SET NULL | 自动生成待办关联的班级 |
| sort_order | INTEGER | NOT NULL DEFAULT 0 | |

### 3.10 note(快速笔记)

| 字段 | 类型 | 约束 | 说明 |
|---|---|---|---|
| id | INTEGER | PRIMARY KEY AUTOINCREMENT | |
| content | TEXT | NOT NULL | |
| created_at | INTEGER | NOT NULL | |
| updated_at | INTEGER | NOT NULL | |

### 3.11 schedule_event(日程安排事件)

| 字段 | 类型 | 约束 | 说明 |
|---|---|---|---|
| id | INTEGER | PRIMARY KEY AUTOINCREMENT | |
| title | TEXT | NOT NULL | |
| start_at | INTEGER | NOT NULL | |
| end_at | INTEGER | NULL | |
| location | TEXT | NULL | |
| reminder_enabled | INTEGER | NOT NULL DEFAULT 0 | |
| reminder_minutes_before | INTEGER | NULL | |

### 3.12 focus_session(专注模式记录)

| 字段 | 类型 | 约束 | 说明 |
|---|---|---|---|
| id | INTEGER | PRIMARY KEY AUTOINCREMENT | |
| started_at | INTEGER | NOT NULL | |
| duration_minutes | INTEGER | NOT NULL | |
| completed | INTEGER | NOT NULL DEFAULT 0 | |

### 3.13 import_log(批量导入日志)

| 字段 | 类型 | 约束 | 说明 |
|---|---|---|---|
| id | INTEGER | PRIMARY KEY AUTOINCREMENT | |
| file_name | TEXT | NOT NULL | |
| imported_at | INTEGER | NOT NULL | |
| success_count | INTEGER | NOT NULL | |
| fail_count | INTEGER | NOT NULL | |
| detail_json | TEXT | NULL | 每行导入结果的详细 JSON,便于回溯排查 |

### 3.14 llm_provider_config(LLM 提供商配置)

| 字段 | 类型 | 约束 | 说明 |
|---|---|---|---|
| id | INTEGER | PRIMARY KEY AUTOINCREMENT | |
| name | TEXT | NOT NULL | |
| base_url | TEXT | NOT NULL | |
| api_key_encrypted | TEXT | NOT NULL | 本地加密存储,不明文落盘 |
| model_name | TEXT | NOT NULL | |
| is_default | INTEGER | NOT NULL DEFAULT 0 | |

### 3.15 app_settings(应用设置,单行 KV 或单例表均可)

| 字段 | 类型 | 约束 | 说明 |
|---|---|---|---|
| key | TEXT | PRIMARY KEY | |
| value | TEXT | NOT NULL | |

存储:语言、主题、高风险学生阈值、考勤保留天数、导入日志保留天数、级联更新开关等键值对。

---

## 四、UI/UX 交互规范(12条核心规范)

1. 全局圆角统一使用16dp,禁止局部使用不同圆角值
2. 主题色、间距、字号全部通过 Design Token 集中管理,组件内禁止硬编码
3. 按钮按下缩放至96%,松开时长100ms内弹回
4. 危险操作二次确认弹窗必须具体描述后果,禁止使用模糊文案
5. 列表项点击进入详情页使用 Hero 共享元素动画
6. 滚轮选择器统一带速度衰减与吸附效果
7. 拖拽排序统一使用长按触发 + 触觉反馈(震动)
8. SnackBar 统一样式,默认展示3秒,可覆盖为更长
9. 加载状态统一使用脉冲环动画,禁止使用无说明的裸 Loading 圈
10. 时间轴视图(模块一 1.4 节)统一 pxPerMinute 常量管理,支持自适应缩放
11. 表单校验错误统一内联提示在对应字段下方,禁止用弹窗打断填写流程来报校验错误
12. 国际化文案严禁在组件代码中拼接字符串,统一走 i18n key 引用

---

## 五、技术约束与开发规范

- **依赖清单**:sqflite(本地数据库)、flutter_local_notifications(本地通知)、excel 或等价包(Excel 导入导出)、http 或 dio(调用 LLM API)、intl(国际化)
- **代码风格**:遵循 Dart 官方 lint 规则(effective_dart),提交前跑 `flutter analyze` 保证零警告
- **错误处理**:严禁空 catch 块吞异常,任何 catch 块必须至少记录日志;涉及数据库写操作的方法必须包裹在事务中,失败时完整回滚并向上层抛出可读的错误信息
- **性能优化**:长列表(学生名单、考勤历史)使用 ListView.builder 懒加载,禁止一次性构建全部 Widget;时间轴视图对超长时间跨度做渲染优化(见模块一 1.4 节)
- **国际化**:所有面向用户的文案必须走 i18n 资源文件,不允许硬编码中文/英文字符串
- **测试要求**:数据库层(Repository/DAO)编写单元测试,尤其覆盖 3.2 节模板节次校验逻辑、3.4 节冲突检测逻辑;关键交互流程(新增课表、记考勤)编写 Widget 测试

---

## 六、已知风险与规避策略

| 风险类别 | 规避策略 |
|---|---|
| SQL 注入 | 一律使用参数化查询,禁止字符串拼接 SQL |
| 空 catch 块吞异常 | 强制要求 catch 块内至少记录日志,禁止空实现 |
| Timer/StreamSubscription 泄漏 | 所有 Timer、订阅在对应 State 的 dispose 方法中显式取消 |
| 魔法数字硬编码 | 所有阈值(缺勤次数、保留天数、pxPerMinute 等)统一放入常量文件或 app_settings 表 |
| 数据库迁移丢失数据 | 迁移脚本必须包在事务中,失败整体回滚,并跑迁移后一致性校验 |
| 日期时区偏移 | 作息模板时间存本地 "HH:mm" 字符串而非绝对时间戳;日期统一存 "YYYY-MM-DD" 字符串,避免时区换算误差 |
| 大列表滚动卡顿 | 使用懒加载 ListView.builder;时间轴视图自适应缩放像素密度 |
| 通知权限拒绝后无引导 | 权限被拒绝时提供跳转系统设置页的入口,而非仅文字提示 |
| 模板节次时间跨天 | 本期不支持跨天时段,校验时直接拒绝 end_time ≤ start_time 的输入 |
| 多模板聚合视图冲突检测误判 | 冲突判定必须基于真实时间区间重叠,禁止直接比较 period_index |
| 模板变更影响历史统计口径 | 明确产品语义:模板变更只影响未来时间显示与提醒计算,不回溯修改已保存的历史考勤记录 |
| 迁移脚本中途失败导致外键悬空 | 迁移严格包事务;迁移完成后校验所有 class.template_id 均能在 schedule_template 中查到对应记录 |
| 同模板不同 weekday 节次数不一致导致渲染越界 | 所有涉及节次数量的逻辑必须按 (template_id, weekday) 单独取列表,不假设一周内节次数固定 |

---

## 七、建议实现顺序

1. 搭建 SQLite 数据库及全部表结构(第三章),编写迁移与建表脚本
2. 实现 schedule_template / template_period 的 CRUD 与校验逻辑(模块一 1.2 节),配单元测试
3. 实现班级、课程、学生的基础 CRUD(模块六)
4. 实现单班级课表网格视图(模块一 1.4 节模式A)
5. 实现教师聚合时间轴视图(模块一 1.4 节模式B),这是复杂度最高的部分,建议独立分支开发
6. 实现一键新增/修改课表、级联更新、格子交换(模块一 1.5-1.8 节)
7. 实现考勤记录与统计导出(模块二、模块三)
8. 实现智能待办与教师工具箱(模块四、模块五)
9. 实现系统级功能:通知、国际化、主题、自动清理(模块七)
10. 统一走查模块八通用交互规范与第六章风险表,逐条自查验收
