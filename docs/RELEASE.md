# 发布与更新

本项目分两件事：**把新版本发出去**（本文）和**让老师手机上的旧版本用最小流量升上来**
（分差升级）。两者由同一套脚本串起来，避免手工维护版本号、指纹和补丁基准。

---

## 一、版本号规则

`pubspec.yaml` 里是 `version: x.y.z+N`：

| 部分 | 含义 | 谁在用 |
| --- | --- | --- |
| `x.y.z` | 版本名（versionName） | 显示给老师看，也用于 git 标签 `vX.Y.Z` |
| `+N` | 版本代码（versionCode） | **Android 只认这个**，每次发版必须严格递增 |

> ⚠️ `N` 不递增，设备会拒绝覆盖安装。应用内的「检查更新」也靠它比对，
> 只改 `x.y.z` 而忘了 `N`，用户会看到"有新版本"但装不上。

`tool/release.py --bump patch` 会同时把两者改好，不要手改。

---

## 二、首次配置（只需做一次）

### 1. SSH 密钥（推送代码用）

```bash
ssh-keygen -t ed25519 -C "gillnotfail@github" -f ~/.ssh/id_ed25519 -N ""
cat ~/.ssh/id_ed25519.pub
```

把输出的公钥填到 GitHub → Settings → **SSH and GPG keys** → New SSH key。

本机 `~/.ssh/config` 已经让 github.com 走 `ssh.github.com:443`
（部分网络封禁 22 端口，443 通常可用）：

```
Host github.com
  HostName ssh.github.com
  Port 443
  User git
```

验证：

```bash
ssh -T git@github.com      # 期望：Hi gillnotfail! You've successfully authenticated...
```

### 2. `GITHUB_TOKEN`（建 Release 与上传附件用）

GitHub → Settings → Developer settings → **Personal access tokens** → 勾 `repo` 权限。

```bash
export GITHUB_TOKEN=ghp_xxx     # 只放在当前终端里，不要写进仓库
```

脚本读不到这个变量时会**跳过上传**，只生成本地产物 —— 不会报错，所以
发现"Release 里没有附件"时先检查它。

### 3. 签名文件

- `android/key.properties` → 指向 `android/keystore.jks`（两者都在 `.gitignore` 里）。
- **`keystore.jks` 必须另存备份**。丢了就再也无法给已安装的 App 发升级包，
  只能让所有人卸载重装。

---

## 三、日常发布流程

```bash
# 1) 先写更新说明 —— 这段文字会原样显示在老师手机上，用大白话写
#    编辑 CHANGELOG.md，在最上面加一节：
#    ## [1.0.1] - 2026-10-01
#    ### 修复
#    - 修好了课表里换课之后人数不更新的问题

# 2) 打个草稿看看（不联网、不提交、不推送）
python tool/release.py --bump patch --skip-upload
#    这一步会改 pubspec.yaml 的版本号，并在 dist/ 下生成补丁

# 3) 确认无误后正式发
python tool/release.py --bump patch --push
```

第 3 步依次做了：

1. 自增 `versionName` / `versionCode` 并写回 `pubspec.yaml`；
2. `flutter build apk --release`（分 ABI，见 `android/app/build.gradle.kts` 的 `splits`）；
3. 对每个 ABI 算 `size` 与 `sha256`；
4. 用上一版 APK 当基准生成分差补丁，并**当场自校验**（合不出来就中止发布）；
5. 写 `updates/latest.json`；
6. 把本次 APK 缓存到 `dist/releases/<versionCode>/`（下次当基准用）；
7. `git commit` + `git tag vX.Y.Z`，再 `git push`（只有加 `--push` 才推）；
8. 建 GitHub Release 并上传 APK 与补丁附件。

### 参数

| 参数 | 作用 |
| --- | --- |
| `--bump patch\|minor\|major` | 自增版本号 |
| `--no-bump` | 版本号已经是最终值，不再动（首次发布用） |
| `--notes "一;二"` | 直接用这段文字当更新说明，跳过 CHANGELOG |
| `--no-build` | 复用已有 APK（补传附件时用，省几分钟） |
| `--skip-upload` | 不建 Release，只产本地文件与清单 |
| `--push` | 提交后推送到 origin |
| `--previous-apk-dir <目录>` | 手动指定基准 APK 目录 |
| `--include-emulator` | 同时发布 x86_64（只有模拟器需要） |

> **推送是显式的**：不加 `--push` 就只做本地提交和打标签。标签是一次性的
> （同名标签已存在就必须改版本号），所以不能让一次试探性的本地跑顺手把它推上去。

---

## 四、更新清单 `updates/latest.json`

**这个文件要入库**——它是应用内更新能力的唯一数据源。APK 和补丁挂 Release
附件，**不入库**（二进制会让仓库体积永久膨胀且无法回收）。

```json
{
  "schemaVersion": 1,
  "generatedAt": "2026-10-01T10:00:00+08:00",
  "minSupportedVersionCode": 1,
  "assetsBase": "https://github.com/gillnotfail/schedule_plan/releases/download",
  "releases": [
    {
      "versionCode": 2,
      "versionName": "1.0.1",
      "tag": "v1.0.1",
      "publishedAt": "2026-10-01T10:00:00+08:00",
      "notes": ["修好了课表里换课之后人数不更新的问题"],
      "assets": [
        {
          "abi": "arm64-v8a",
          "file": "app-arm64-v8a-release.apk",
          "size": 24003104,
          "sha256": "…"
        }
      ],
      "deltas": [
        {
          "fromVersionCode": 1,
          "abi": "arm64-v8a",
          "file": "patch-1-2-arm64-v8a.spdp",
          "size": 1234567,
          "targetSize": 24003104,
          "sha256": "…",
          "baseSha256": "…"
        }
      ]
    }
  ]
}
```

- `releases` 按 `versionCode` **从新到旧**排列；脚本只保留最近 20 个版本。
- `deltas[].baseSha256` 是**基准包**（上一版整包）的指纹。设备端拿本机 APK 算指纹，
  对不上就说明补丁不适用（比如装的是第三方渠道包）→ 直接走整包。
- `assets[].sha256` 是**目标整包**的指纹。设备端合成完补丁后会拿它**交叉校验**
  ——这是与补丁自身指纹相互独立的一次验证。

### 设备端从哪读清单

`UpdateService.manifestUrls` 依次尝试：

1. `https://raw.githubusercontent.com/gillnotfail/schedule_plan/main/updates/latest.json`
2. `https://cdn.jsdelivr.net/gh/gillnotfail/schedule_plan@main/updates/latest.json`（国内通常更快）
3. 用户自己配的镜像前缀（设置 → 检查更新 → 下载镜像）套在前两个前面

因此**清单推送到 `main` 分支是发布生效的最后一步**。只建了 Release 而没推
`latest.json`，应用内是看不到新版本的。

---

## 五、分差升级

### 原理

APK 里有一个 8~12 MB 的 `lib/libapp.so`（Dart AOT 快照）。**改几行代码，这个文件
就会整体位移**——里面的函数顺序、常量池偏移全变了。所以定长分块（每 4 KB 一刀）去重
会全面失配，补丁几乎等于整包。

本项目用 **CDC（内容定义分块）**：用一个 32 位 **gear 哈希**在字节流上滚动，
`h = (h << 1) + GEAR[b]`，当 `h & MASK == 0` 时切一刀。因为边界只取决于**内容**、
与偏移无关，所以插入/删除一段字节只会影响附近少数几块，后面全部照旧复用。

实测一份 22.89 MB 的 release APK：

| 改动 | 补丁大小 | 占整包 |
| --- | --- | --- |
| 改 1 个字节 | 0.025 MB | 0.11% |
| 删 4096 字节（其后 10.9 MB 全部位移） | 0.022 MB | 0.10% |
| 中间 500 KB 清零 | 0.038 MB | 0.17% |
| 完全相同 | 0.005 MB | 0.02% |
| arm64 包 → armeabi-v7a 包（最坏情况） | 8.91 MB | 42.5% |

> 最坏情况是"换 ABI"，但正常发版不会遇到——每个 ABI 各自和自己上一版比。

### 两个关键实现细节

**掩码必须取高位（bits 17..31）。** gear 哈希的 `bit0` 恒等于 `GEAR[最后一个字节] & 1`，
所以低位最多 256 种取值，把掩码放低位会退化（曾出现"整份文件切不出一刀"）。
`delta_patch.py selftest` 里有一条护栏：**分块均值必须落在 `[1<<14, 1<<16]`**。

**长零填充会稳定切成 `MAX_CHUNK` 块。** 纯常量串在 gear 哈希下会收敛到不动点
（零串是 `-GEAR[0] = 0xA7825A60`），永远不命中边界，于是每块都撞上限。
这反而是好事：**撞上限的块长度与内容无关**，所以边界不因内容改动而漂移。

### 格式 SPDP v1

整份 gzip 压缩，解压后是：固定头 **98 字节**（魔数 `SPDP`、格式版本、分块参数、
基准/目标大小与指纹、命令数）+ 命令表 + 字面量载荷。命令只有两种：

| 命令 | 编码 | 含义 |
| --- | --- | --- |
| `COPY_BASE` | `0x01` + offset(u64) + length(u32) = 13 字节 | 从旧包某处搬 length 字节 |
| `COPY_LITERAL` | `0x02` + length(u32) = 5 字节 | 从载荷里取 length 字节 |

**分块只发生在生成端（Python）**，设备端只做"校验指纹 → 按命令搬字节 → 校验产物指纹"。
所以不存在"两端分块边界必须逐字节一致"的跨语言陷阱，只需格式解析一致——
这一点由 `test/fixtures/delta/` 的固定样例锁住（Python 生成、Dart 复现）。

### 手动使用

```bash
python tool/delta_patch.py selftest                      # 全链路自检（含护栏）
python tool/delta_patch.py diff old.apk new.apk --verify  # 生成补丁并自校验
python tool/delta_patch.py stat patch.spdp                # 看补丁元信息
python tool/delta_patch.py apply old.apk patch.spdp out.apk
```

---

## 六、设备端升级流程

1. 启动时 `autoCheckIfDue()`（一天一次节流），或用户在设置页点「检查更新」；
2. 取清单 → 比对 `versionCode` → 本 ABI 有包吗 → 用户跳过过这一版吗；
3. 只有到这一步才去**哈希本机 APK**（要读 24 MB，所以放在最后）；
4. 有匹配且够小的补丁 → 走分差；否则走整包；
5. 下载 → 校验 `sha256`；
6. 分差路径：合成 → 校验产物指纹 → 再与**清单里整包的指纹**交叉校验；
7. 交给 `PackageInstaller` 安装（需要「安装未知应用」授权）。

**三层安全网**，任何一步失败都会：删掉临时文件 → 换下一个地址 → 最终回落下载完整包。

> 为什么用 `PackageInstaller` 而不是 `Intent.ACTION_VIEW` + FileProvider：
> 本项目 `androidx.core` 是由 `share_plus` 以 `compileOnly` 引进来的，
> 自建一个 FileProvider 子类会因为类不在本模块 classpath 上而编译不过。
> `PackageInstaller` 把字节直接写进安装会话管道，不需要 content URI，
> 还能拿到安装结果回执。

---

## 七、排障

| 现象 | 原因 |
| --- | --- |
| `git push` 提示 Permission denied | 公钥没加到 GitHub，或没走 443（见 §2.1） |
| Release 建好了但没有附件 | 没设 `GITHUB_TOKEN`，脚本静默跳过上传 |
| 应用内看不到新版本 | `updates/latest.json` 没推到 `main` 分支 |
| 应用内看到新版但走整包 | 本机 APK 指纹和 `deltas[].baseSha256` 对不上（装过第三方渠道包）；或补丁没省到九折以下 |
| 安装失败 `INSTALL_FAILED_VERSION_DOWNGRADE` | `pubspec.yaml` 的 `+N` 没递增 |
| 安装被拦下 | 缺「安装未知应用」授权，或 Manifest 少了 `REQUEST_INSTALL_PACKAGES` |
| 装完没收到结果回执 | 系统安装会重启进程，回执可能送不到 → 回前台时靠比对版本号兜底（`markInstalledExternally()`） |
| 正式版永远连不上网 | Manifest 少了 `INTERNET` 权限（debug 包由 Flutter 自动补，release 不会） |
| 补丁自校验失败 | 生成时就会中止发布，不会发出去；查 `delta_patch.py selftest` |

---

## 八、发布前检查清单

- [ ] `CHANGELOG.md` 写好了吗（**用老师能看懂的话**，会原样显示在手机上）
- [ ] `flutter analyze --no-pub` → `No issues found!`
- [ ] `flutter test` → `All tests passed!`
- [ ] `python tool/delta_patch.py selftest` 通过
- [ ] `keystore.jks` 有备份
- [ ] `git status` 干净，没有误提交 `*.jks` / `key.properties` / APK
