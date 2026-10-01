# 全面课表计划 (schedule_plan)

> 面向一线教师 / 辅导员的**离线优先**个人效率工具。把「看课表 → 记考勤 → 出统计 → 做待办」串成一条线，数据全部存在手机本地，不需要账号、不依赖服务端。

---

## 它解决什么问题

学校的排课系统面向教务处，老师真正需要的是另一套东西：**我这周什么时候有课、哪几个班还没点名、这个月出勤率怎么样、下节课讲什么**。

而这个 App 要处理几个现实中很别扭的情况：

| 现实情况 | 本项目的处理方式 |
|---|---|
| 高一 11:20 午休、高二高三 12:00 才午休，同一个老师的「第 4 节」是两个时间 | **作息模板**：节次编号与真实时间解耦，班级绑定模板，真实时间联查解析；个人课表一律用**时间轴**渲染，不显示裸的「第 4 节」 |
| 中国有调休，周六要上班上课，还要补星期几的课 | 内置国务院放假安排 + 每年联网保鲜；调休当天**由老师确认**上周几的课，课时按日历结算 |
| 课表经常被临时调整 | 课表格子一键换课 / 移出，空白格点开就是选课对话框 |
| 学生休学、免修要一直记着 | 课程级长期状态，点一次管 180 天，名单里自动沉底 |
| 手机里没有云，怕数据丢 | 名单 Excel 导入导出、课表截图分享、日程提醒 |

---

## 功能概览

**课表**
- 周视图网格（一屏铺满、自适应缩放、横向手风琴展开）与**曲线视图**（按真实时间轴渲染，错峰课表一屏装下一天）一键切换
- 作息模板：周一~周日独立节次表、一键生成作息、从其他工作日复制、绑定/迁移班级
- 调休感知：放假不计课时、调休上班日按老师指定的星期结算，当天顶部出提醒条
- 课表分享成图片、拍照/相册导入课表（本机离线识别）

**考勤**
- 七态：出勤 / 迟到 / 早退 / 缺勤 / 请假 + 课程级长期状态 休学 / 免修
- 按班级分组的滚动名单、点整行即记出勤、班内排序（含长期状态沉底）
- 日历上的**出勤率进度圆环**（出勤人次 ÷ 应点名人次，合班课按全部班级人数算）

**管理**
- 班级 / 学生 / 课程三套单一实现表单，班主任随班级联动
- Excel 导入名单：选文件即入库，同班同名自动去重，兼容 WPS / 老版 Excel 的非法数字格式

**工具箱**
- 日历与日程（支持单次 / 每周 / 隔周 / 每月重复）、专注计时、快速笔记（可接自配 LLM 拓写）
- **教学成果**：数据概览 + 今日回顾 + 四段可展开明细（课时分布、出勤情况与最好/最差班级、专注投入、额外事务）

**设置**
- 主题（亮 / 暗 / 跟随系统）、中英文、默认考勤状态、级联开关、节假日开关与数据更新、数据清理

---

## 技术栈

| 层 | 选型 |
|---|---|
| UI | Flutter（Material 3 Expressive），provider 状态管理 |
| 持久化 | sqflite（Android 走系统 SQLite，Windows/macOS/Linux 走 FFI），**无云端数据库** |
| 国际化 | flutter_localizations + ARB（`zh` / `en` 严格对齐） |
| 通知 | flutter_local_notifications（本地定时，无云推送） |
| 表格 | excel + archive + xml（含 xlsx 修复） |
| 识别 | 本机离线 OCR 后端可插拔，**不接任何 AI 服务商** |
| 联网 | `http`。只用于两件事：节假日数据保鲜、用户自配的 LLM 接口 |

当前最低支持 **Android 8.0（API 26）**，目标 API 跟随 Flutter 默认。

---

## 快速开始

```bash
flutter pub get
flutter gen-l10n          # 生成 lib/l10n/generated/
flutter analyze --no-pub
flutter test
flutter run -d <device>
```

> Windows 上用 `flutter run` 起桌面端调试时，`sqflite` 需要 `sqflite_common_ffi` 初始化（代码里已按平台自动处理）。

### 打包

```bash
# 分 ABI 打包 + 通用包（android/app/build.gradle.kts 已开启 splits）
flutter build apk --release
```

产物在 `build/app/outputs/flutter-apk/`：

| 文件 | 体积量级 | 说明 |
|---|---|---|
| `app-arm64-v8a-release.apk` | ~24 MB | **推荐**，现代手机装这个 |
| `app-armeabi-v7a-release.apk` | ~22 MB | 老旧 32 位机型 |
| `app-release.apk` | ~69 MB | 通用包，包含全部 ABI，体积是单包的三倍 |

> 如果你一直在传通用包，那 69 MB 的下载时间就解释得通了——绝大多数手机只需要 arm64 单包。

---

## 发布与应用内分差升级

这个仓库同时充当**分发云**：APK 与分差补丁挂在 Release 附件，版本清单 `updates/latest.json` 跟着 `main` 分支走。

同一份内容会**发布到两个平台**，因为老师在教室里连不上 GitHub：

| 平台 | 仓库 | 用途 |
| --- | --- | --- |
| Gitee | [jeo-xie/schedule_plan](https://gitee.com/jeo-xie/schedule_plan) | **首选**：国内直连，通常不需要代理 |
| GitHub | [gillnotfail/schedule_plan](https://github.com/gillnotfail/schedule_plan) | 主仓库；Gitee 不通时自动回落 |

应用内的「检查更新」按 **Gitee → GitHub → jsDelivr → 自配镜像** 的顺序取清单，安装包与补丁也走同一套顺序，任何一步失败就换下一条路。清单里的 `assetsBases` 就是这份顺序。

> **前提：两个仓库都必须公开。** 应用里没有也不该有凭据，它只能匿名取清单和安装包。
> 仓库设为私有（Private）时，**发布流程会全部成功，而手机端永远看不到更新**——
> 见 [`docs/RELEASE.md` §2.1](docs/RELEASE.md)。发布脚本会在上传后**逐个源回验能否匿名下载**，
> 下不动的源会被自动从清单里剔除。

### 为什么需要分差

APK 里最大的一块是 `lib/libapp.so`（Dart AOT 快照，约 10 MB）。改几行 Dart 代码，这个文件的字节会整体平移——**定长分块去重在这种场景下会直接失效**（一块错位，后面全错位）。

所以补丁格式采用**内容分块（CDC）**：用滚动哈希找内容边界，边界只取决于内容本身，与偏移无关。位移再多，未改动区域照样能整块命中。

```
分块参数：min 4 KiB / avg 32 KiB / max 128 KiB（32 位 gear hash）
补丁结构：magic "SPDP" + 分块参数 + baseSize/targetSize/targetSha256
          + 命令表（COPY_BASE 取本地旧包 / COPY_LITERAL 取补丁内新内容）
          + 字面量载荷，整体 gzip
```

生成端是 Python（`tool/delta_patch.py`），应用端是纯 Dart（`lib/core/utils/delta_patch.dart`）。两端的 gear 表由同一 LCG 生成，保证**分块边界逐字节一致**，并且有跨语言的固定样例单测锁住。

安装时读取**手机里已装的 APK 本身**作为基础包，因此补丁必须与本地基础包哈希完全匹配；任何一步对不上（哈希不符、合成后校验失败、磁盘空间不足）都**自动回落下载完整包**，不会卡在中间态。

### 一键发布

```bash
# 1) 先写更新说明（应用内会原样展示给用户）
#    编辑 CHANGELOG.md，在最上面加一条 ## [1.0.1] - 2026-10-01

# 2) 一条命令搞定：自增版本号 → 打包 → 生成补丁 → 写清单 → 提交打标签
#    → 推 gitee 与 origin → 两边各建一份 Release 并上传附件 → 回验附件能匿名下载
python tool/release.py --bump patch --push
```

细节见 [`docs/RELEASE.md`](docs/RELEASE.md)。

---

## 签名与数据

- 发布签名使用 `android/key.properties` + `android/keystore.jks`，**两者都已加入 `.gitignore`，不会入库**。
- ⚠️ **请自行备份 keystore**：Android 只允许同签名的包覆盖安装，密钥丢失就意味着所有用户（包括你自己）必须卸载重装，应用内升级链路也会断掉。
- 密钥文件缺失时 Gradle 会自动回落到 debug 签名，`flutter build apk --release` 仍可跑通——但那只是为了让构建不失败，**不要用它发包**。

---

## 目录结构

```
lib/
├── app/                    # 依赖装配、根 Widget
├── core/                   # 常量、主题、日期与颜色工具、日志、通用组件
├── data/
│   ├── db/                 # 建表与迁移（当前 version = 7）
│   ├── models/             # 领域模型
│   ├── repositories/       # SQL 访问层
│   └── services/           # 节假日、OCR、Excel、通知、LLM、更新等
├── features/               # 按模块划分的页面
│   ├── schedule/ attendance/ management/ statistics/ todo/
│   ├── toolbox/ templates/ settings/ shell/
└── l10n/                   # ARB 文案与生成产物
tool/                       # 发布与差分工具（Python，不参与 App 构建）
updates/                    # 应用内更新清单
docs/                       # 需求规格、发布流程
test/                       # 单元测试与 Widget 测试
```

---

## 文档

| 文档 | 内容 |
|---|---|
| [`docs/SPEC.md`](docs/SPEC.md) | **需求规格书**。UI 风格、交互模式、数据模型、边界处理全部在此定死，新增功能前先读它 |
| [`docs/RELEASE.md`](docs/RELEASE.md) | 发布流程、版本号规则、分差补丁生成与排障 |
| [`CHANGELOG.md`](CHANGELOG.md) | 更新说明，同时作为应用内「更新内容」的数据源 |

---

## 开发约定（摘要）

- **`docs/SPEC.md` 是唯一需求来源**，不要用「我觉得更好的设计」覆盖规格。
- 时间统一存 `"HH:mm"` / 日期存 `"YYYY-MM-DD"` 字符串，不存绝对时间戳。
- 冲突检测必须基于**真实时间区间重叠**，禁止直接比较 `period_index`（多模板聚合会误判）。
- 数据库迁移一律**纯加表 / 加列**、可重复执行；迁移整段包事务。
- 文案全部走 ARB，中英严格对齐；页面里不写死中文串。
- 提交前跑 `flutter analyze --no-pub` 与 `flutter test`，两者都必须干净。
