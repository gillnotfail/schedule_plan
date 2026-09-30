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

### 1. 仓库必须是**公开**的（否则应用内升级整条链路不通）

这一条排在第一位，因为**仓库设为私有（Private）时，发布流程会全部成功，而手机端
永远看不到更新** —— 没有任何一步会报错，最难查。

原因：应用里没有、也不该有凭据，它只能匿名取清单和安装包。

| 地址 | 私有仓库 | 公开仓库 |
| --- | --- | --- |
| `raw.githubusercontent.com/.../updates/latest.json` | 404 | 200 |
| `cdn.jsdelivr.net/gh/.../updates/latest.json` | **404**（jsDelivr 完全不服务私有仓库） | 200 |
| `github.com/<repo>/releases/download/...`（安装包） | 404 | 200 |
| `api.github.com/repos/<repo>` | 404 | 200 |

判断方法（匿名探测，就是手机的视角）：

```bash
curl -s -o /dev/null -w '%{http_code}\n' https://api.github.com/repos/<owner>/<repo>
# 404 = 私有（带 token 再试会是 200），200 = 公开
```

**不要**试图把 token 塞进 App 里换取私有仓库 —— APK 可以被反编译，等于把仓库
读写权限公开送人。要公开就公开仓库，要保密就别用应用内升级。

公开前先确认历史里没有密钥：

```bash
git log --all --name-only --pretty=format: | sort -u \
  | grep -Ei '\.(jks|keystore|apk|aab|p12|pem)$|key\.properties$|\.env$'
# 期望：无输出
```

### 2. SSH 密钥（推送代码用）

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

### 3. `GITHUB_TOKEN`（建 Release 与上传附件用）

GitHub → Settings → Developer settings → **Personal access tokens**。

推荐建**细粒度 token**，Repository access 只选 `schedule_plan`，
权限给 **Contents: Read and write**（其余全不用给）。

**复制时务必整条复制**：

| 类型 | 形态 | 长度 |
| --- | --- | --- |
| 细粒度 `github_pat_` | `github_pat_<22 位>_<59 位>`，**中间还有一个下划线** | 93 |
| 经典 `ghp_` | `ghp_<36 位>` | 40 |

两种放法，任选：

```bash
# 放法 A：写进家目录的文件（推荐，发版要反复用）
#   ~/.schedule_plan-release.env 内容就一行：
#   GITHUB_TOKEN=github_pat_xxx
```
```bash
# 放法 B：只放在当前终端里
export GITHUB_TOKEN=github_pat_xxx
```

家目录那个文件**故意放在仓库之外** —— 仓库里的任何文件都有被 `git add -A`
顺手带上去的风险，PAT 泄露不可逆。建议 `chmod 600`。

> **别把 token 贴进任何对话 / issue / 聊天窗口。** token 都是长随机串，
> 在聊天链路里被截断是常见事故（症状是服务端只回一句 `401 Bad credentials`，
> 极容易被误判成"权限不够"而反复重新生成）。用编辑器直接写进上面那个文件，
> 不经过剪贴板以外的任何环节。实测过的两种截断形态：
>
> - `github_pat_` 只跟了 20 个字符就断（共 31 字符，连第二个下划线都没有）
> - 长度看着够、但服务端拒绝
>
> 脚本对前者会在**联网之前**拦下来并说明长度不对；对后者会明确提示是"令牌被拒绝"，
> 而不是让你去猜权限。

脚本的行为：

- **在打包之前**先验一次 token（`GET /user` + `GET /repos/...`）。token 无效或
  被截断时立刻退出并说明原因，不会白等一轮几分钟的构建、也不会留下改了一半的
  工作区。截断是最常见的错——症状却是服务端一句 `401 Bad credentials`。
- 两者都没有时**跳过上传**，只生成本地产物，并在日志里给出补上 token 后重跑的
  命令（产物已就绪，可加 `--no-build` 免重新构建）。所以发现"Release 建好了但
  没有附件"时，先检查 token。
- 跳过上传时会明确说明**为什么**取不到 token：文件不存在 / 文件里没有那一行 /
  等号右边是空的 / 有值但读不出来。这四种情况的处置完全不同，混成一句
  "没有可用的 GITHUB_TOKEN" 会让人对着一个明明存在的文件反复怀疑路径。

### 4. 下载地址要不要配镜像

`updates/latest.json` 里的下载地址默认为
`https://github.com/<repo>/releases/download/<tag>/<file>`。
**部分网络会封掉 `github.com` 解析到的那组 IP**（表现为 TCP 直接连不上，
而 `api.github.com`、`uploads.github.com`、`objects.githubusercontent.com`
却是通的）。遇到这种情况：

- 发布侧不受影响 —— 建 Release 和上传附件走的是 `api.github.com` /
  `uploads.github.com`，与 `github.com` 不是同一组地址。
- 手机侧会下不动包，需要在 设置 → 检查更新 → 下载镜像 里填一个前缀
  （如 `https://ghproxy.net/https://github.com`），应用会自动把它套在直连地址前面试。

### 5. 签名文件

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
8. 建 GitHub Release 并上传 APK 与补丁附件；
9. **清掉 jsDelivr 上清单文件的 CDN 缓存**（见下面「清单的 12 小时缓存」）。

> **第 9 步不能省**：jsDelivr 对 `@main` 这种分支引用最长缓存 12 小时，
> 而国内 `raw.githubusercontent.com` 经常直接不通 —— 客户端是 raw 优先、
> jsDelivr 兜底，raw 走不通时老师手机上就只剩旧清单，「检查更新」看不到新版本。
> `release.py` 用 jsDelivr 的公开端点（`https://purge.jsdelivr.net/<路径>`，
> 不需要凭据）主动清一次；失败只告警、不中止发布（缓存自己会过期）。

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

### 清单的 12 小时缓存（第 2 个地址特有）

jsDelivr 对**分支引用**（`@main`）的缓存最长 **12 小时**；同一个 commit 换成
`@<sha>` 取则是**实时**的。于是会出现这种怪事：GitHub 上的 `latest.json` 明明是新的，
手机端却看不到新版本 —— 因为国内 raw 经常不通，客户端只能落到第 2 个地址。

- 正常发布不用管：`release.py` 推送之后会自动 purge（流程第 9 步）；
- 手工补清（公开端点，不需要凭据）：

  ```bash
  curl -s "https://purge.jsdelivr.net/gh/gillnotfail/schedule_plan@main/updates/latest.json"
  # {"status":"finished","paths":{"/gh/.../latest.json":{"throttled":false}}}
  #   → 已清；随后 @main 立刻返回最新内容
  ```

- 判断"是不是缓存在作怪"：同一个文件用两种引用各取一次，对比 `generatedAt`
  与首个版本号 —— `@main` 旧、`@<sha>` 新就一定是缓存。

> **看 `throttled`，不要只看 `status`。** 被限流时返回的也是
> `{"status":"finished", "paths": {…: {"throttled": true, "throttlingReset": 406}}}` ——
> 状态是"完成"，但**这个路径根本没清**。连续发两个版本必然中招（限流窗口实测
> 约 6 分钟），所以 `release.py` 会等到点自动重试一轮（最多 10 分钟），超时才告警。
> 手工执行时看到 `throttled: true`，就按 `throttlingReset` 的秒数等一下再清。

> **清完要回读验证**：`curl @main` 拿到的内容与本地 `updates/latest.json` 做 sha256
> 对比，一致才算真的生效（只看 purge 的返回会被上面的限流骗过去）。

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
| `git push` 提示 Permission denied | 公钥没加到 GitHub，或没走 443（见 §2.2） |
| Release 建好了但没有附件 | 没设 `GITHUB_TOKEN`，脚本跳过上传（日志里会说明具体是哪种情况） |
| 日志说"没有可用的 GITHUB_TOKEN"但文件明明在 | 看紧跟的「原因」一行：多半是等号右边是空的（编辑器没保存/粘贴没落盘） |
| `401 Bad credentials` | 先用日志里的字符数判断：细粒度 PAT 只有 93 字符才是完整的，不够就是复制时被截断了 |
| 应用内看不到新版本 | ①**仓库是私有的**（最常见，见 §2.1）；②`updates/latest.json` 没推到 `main` 分支；③**jsDelivr 上的清单缓存还没过期**（raw 不通时客户端只能读它，最长 12 小时）——手工 purge 一次即可，见 §4「清单的 12 小时缓存」；purge 返回里 `throttled` 为 `true` 表示被限流（要按 `throttlingReset` 秒数再等），**`status` 是 `finished` 也照样没清** |
| 应用内看到新版但走整包 | 本机 APK 指纹和 `deltas[].baseSha256` 对不上（装过第三方渠道包）；或补丁没省到九折以下 |
| 安装失败 `INSTALL_FAILED_VERSION_DOWNGRADE` | `pubspec.yaml` 的 `+N` 没递增 |
| 安装被拦下 | 缺「安装未知应用」授权，或 Manifest 少了 `REQUEST_INSTALL_PACKAGES` |
| 装完没收到结果回执 | 系统安装会重启进程，回执可能送不到 → 回前台时靠比对版本号兜底（`markInstalledExternally()`） |
| 正式版永远连不上网 | Manifest 少了 `INTERNET` 权限（debug 包由 Flutter 自动补，release 不会） |
| 补丁自校验失败 | 生成时就会中止发布，不会发出去；查 `delta_patch.py selftest` |
| 上传成功了，但 `git push` 标签报 `already exists` | Release 建在了打标签之前 → GitHub 自造了一个同名标签。脚本现在会拦住这种参数组合；已踩到的按下面修 |
| Release 挂在不含本次发布的提交上 | 同上。修：`git push origin +refs/tags/v1.0.0:refs/tags/v1.0.0` 把标签硬挪到发布提交 |

---

## 八、发布前检查清单

- [ ] **仓库是公开的**（`curl -s -o /dev/null -w '%{http_code}' https://api.github.com/repos/<owner>/<repo>` → 200）
- [ ] `CHANGELOG.md` 写好了吗（**用老师能看懂的话**，会原样显示在手机上）
- [ ] `flutter analyze --no-pub` → `No issues found!`
- [ ] `flutter test` → `All tests passed!`
- [ ] `python tool/delta_patch.py selftest` 通过
- [ ] `keystore.jks` 有备份
- [ ] `git status` 干净，没有误提交 `*.jks` / `key.properties` / APK
- [ ] 命令里带了 `--push`（否则脚本会拒绝建 Release，因为标签没进远端）
