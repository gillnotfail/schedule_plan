#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""一键发布：自增版本号 → 打包 → 生成分差补丁 → 写更新清单 → 提交打标签 →
推送 Gitee/GitHub → 建两个 Release 并上传附件 → 回验附件真的能匿名下载。

为什么要有这个脚本
------------------
应用内升级链路的每一个环节都依赖"发布时把哪些数字写对了"：
  · `pubspec.yaml` 的 `+N` 是 Android 的 versionCode，**每次必须递增**，
    否则设备会拒绝覆盖安装（INSTALL_FAILED_VERSION_DOWNGRADE / 同版本不升级）；
  · `updates/latest.json` 里的 `size` 与 `sha256` 必须和被上传的那份 APK
    逐字节一致，否则设备端校验会失败并回落整包；
  · 分差补丁必须拿**上一个已发布版本**的 APK 当基准，且它自己的指纹、
    基准包指纹、目标包指纹三个都要写对。
这些靠手工维护必然出错，而且错在发布之后才被发现。所以全部交给脚本。

双仓库（Gitee 必需）
------------------
老师的手机大多在国内，GitHub 的 raw 与附件经常连不通，Gitee 才是能用的来路。
所以每次发布都**同时**往 Gitee 与 GitHub 各传一份同样的 APK 和补丁，清单里
`assetsBases` 按 `[Gitee, GitHub]` 排列，客户端从上往下试第一个能下的。
Gitee 侧需要两样东西（见 README 的"发布"一节）：
  · 仓库里配好 SSH 公钥（否则 `git push gitee` 会被拒）；
  · 一个私人令牌 `GITEE_TOKEN`，用于建发行版和上传附件。

典型用法
--------
    # 1) 先写更新说明（会原样出现在老师手机上，用大白话写）
    #    编辑 CHANGELOG.md，最上面加一节 ## [1.0.1] - 2026-10-01

    # 2) 发布（要建 Release 就必须带 --push，理由见下方"顺序"一节）
    python tool/release.py --bump patch --push

    # 空跑：只生成产物与清单，不碰网络、不提交、不打标签
    python tool/release.py --bump patch --skip-upload --no-commit

    # 只发 Gitee（GitHub 连不上时用；清单里也只写 Gitee）
    python tool/release.py --bump patch --push --gitee-only

    # 首次发布（版本号已经是最终的，不想再动）：
    python tool/release.py --no-bump --push

顺序（踩过的坑）
----------------
    必须是 **先提交打标签推送 → 再建 Release**。

    反过来做的话：远端收到创建 Release 的请求时，如果远端还没有这个标签，
    GitHub 会照着 target_commitish 的 HEAD **自己造一个同名标签**。结果是
    Release 挂在一个不含本次发布的旧提交上，而随后真正 `git push` 标签又被
    `already exists` 拒绝——两处都错，却都在"上传成功"之后才暴露，
    很容易被误判成权限问题。脚本现在会主动拦住这种组合。

环境变量
--------
    GITHUB_TOKEN  建 GitHub Release 与上传附件所需的令牌。
    GITEE_TOKEN   建 Gitee 发行版与上传附件所需的私人令牌。
                  两者都优先读环境变量，其次读 ~/.schedule_plan-release.env
                  （dotenv 风格，权限请置 600）。缺哪一个就只跳过那一侧的
                  上传，本地产物照常生成。
                  脚本会在**打包之前**先验一遍令牌，避免白等一轮构建。
                  别把令牌贴进对话／聊天窗口：细粒度 PAT 有 93 个字符，
                  在聊天链路里被截断是常见事故，症状却只是服务端一句
                  `401 Bad credentials`。用编辑器直接写进上面那个文件。
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import delta_patch  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PUBSPEC = os.path.join(ROOT, "pubspec.yaml")
CHANGELOG = os.path.join(ROOT, "CHANGELOG.md")
MANIFEST = os.path.join(ROOT, "updates", "latest.json")

REPOSITORY = "gillnotfail/schedule_plan"
ASSETS_BASE = "https://github.com/%s/releases/download" % REPOSITORY
API_BASE = "https://api.github.com/repos/%s" % REPOSITORY

# Gitee 镜像仓库。发布时两边各传一份同样的附件，清单里 Gitee 排在 GitHub
# 前面——国内手机连 gitee.com 通常不用代理，连 github.com 常常要。
GITEE_REPOSITORY = "jeo-xie/schedule_plan"
# 附件地址与 GitHub **完全同构**（`/releases/download/<tag>/<file>`），
# 所以客户端拼地址那套逻辑一套就够，不必为 Gitee 单独开分支。
GITEE_ASSETS_BASE = "https://gitee.com/%s/releases/download" % GITEE_REPOSITORY
GITEE_API_BASE = "https://gitee.com/api/v5/repos/%s" % GITEE_REPOSITORY
# 推送用的远端名，由 `git remote add gitee <地址>` 建好（见 README 的"发布"）。
GITEE_REMOTE = "gitee"

# 清单在 jsDelivr 上的路径。这是客户端地址列表里的**第二顺位**
# （见 `UpdateService.manifestUrls`：raw 优先、jsDelivr 兜底）。
MANIFEST_CDN_PATH = "gh/%s@main/updates/latest.json" % REPOSITORY
# jsDelivr 的公开清缓存端点，不需要凭据。
MANIFEST_PURGE_URL = "https://purge.jsdelivr.net/%s" % MANIFEST_CDN_PATH

# 发布凭据的落地位置。故意放在**家目录**而不是仓库里：仓库里的任何文件都有
# 被 `git add -A` 顺手带上去的风险，PAT 泄露是不可逆的。发版要反复执行，
# 每次把 PAT 明文写进命令行会落进 shell 历史，所以留一个 dotenv 风格的文件。
TOKEN_FILE = os.path.join(os.path.expanduser("~"), ".schedule_plan-release.env")

APK_DIR = os.path.join(ROOT, "build", "app", "outputs", "flutter-apk")

# 需要发布的 ABI。x86_64 只对模拟器有意义，通用包体积是单包的三倍，
# 都不适合手机端下载——默认不发，需要时用 --include-emulator 打开。
PHONE_ABIS = ("arm64-v8a", "armeabi-v7a")
EMULATOR_ABIS = ("x86_64",)

# 上一次发布时留下的 APK 会缓存在这里，供下次生成补丁时当基准。
# 它是本地缓存、不入库：APK 进 git 会让仓库体积永久膨胀且无法回收。
RELEASE_CACHE = os.path.join(ROOT, "dist", "releases")

# 清单里保留多少个历史版本。应用内只需展示"比当前新"的那些，
# 留太多既没意义又会让清单越来越大。
MANIFEST_HISTORY = 20

# 分差补丁最多比整包小到这个比例才值得发。省得少就不值当多担一条合成链路。
DELTA_WORTHWHILE_RATIO = 0.9


# ---------------------------------------------------------------------------
# 基础工具
# ---------------------------------------------------------------------------


# 打印命令时，这些键名等号右边的值一律打成星号。
_SECRET_PATTERN = re.compile(
    r"(?i)\b(access_token|private_token|gitee_token|github_token|token)"
    r"=([^\s&\"']+)"
)
# `https://user:token@host/...` 这种把凭据塞进 URL 的写法（走 HTTPS 远端时）。
_URL_CREDENTIAL_PATTERN = re.compile(
    r"(?i)\b([a-z][a-z0-9+.\-]*://)[^/\s:@]+:[^/\s@]+@"
)


def mask_secrets(text: str) -> str:
    """把命令与日志里的凭据打成星号。

    发布日志是**经常被整段贴出来排障**的东西（报错、奇怪的状态码、问"这行为什么
    这样"）。而 `curl_request` 走的是命令行，一次 `verify_gitee_token` 就足以把
    32 位令牌写进终端回滚缓冲、CI 日志、聊天窗口——泄露不可逆，且当事人往往
    意识不到。所以三个打印命令的出口（`run` 的正常日志与失败分支、`curl_request`
    的超时分支）全部过一遍这里。

    注意是"过一遍文本"而不是"在拼参数时跳过"：令牌还可能藏在 URL query
    （`?access_token=`）、`--form-string access_token=`、以及远端地址里的
    `user:pass@` 三种形态，逐处判断迟早会漏。
    """
    text = _URL_CREDENTIAL_PATTERN.sub(lambda m: "%s***:***@" % m.group(1), text)
    return _SECRET_PATTERN.sub(lambda m: "%s=***" % m.group(1), text)


def log(message: str) -> None:
    print(message, flush=True)


def die(message: str) -> None:
    print("错误：%s" % message, file=sys.stderr)
    sys.exit(1)


def sha256_of(path: str) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for block in iter(lambda: handle.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def read_file_bytes(path: str) -> bytes:
    """读整份文件。显式开闭句柄——APK 有二十多兆，靠引用计数回收太随意，
    在 Windows 上未关闭的句柄会让后续覆盖/删除失败。"""
    with open(path, "rb") as handle:
        return handle.read()


def flutter_command(*args: str) -> list[str]:
    """组装 flutter 命令，并解决 Windows 上的可执行文件解析问题。

    Flutter 在 Windows 上装的是 `flutter.bat`，而 `subprocess` 走的是
    `CreateProcess`：它在找不到文件时只会自动补 **`.exe`**（`PATHEXT` 是
    cmd.exe 的规则，`CreateProcess` 不认）。所以直接传 `"flutter"` 会报
    `FileNotFoundError: [WinError 2] 系统找不到指定的文件`。

    `shutil.which` 按完整 `PATHEXT` 解析，能拿到 `flutter.bat` 的真实路径。
    解析不到时原样返回，交给 PATH 处理（Linux/macOS 上本来就是 `flutter`）。
    """
    executable = (
        os.environ.get("FLUTTER_BIN")
        or shutil.which("flutter")
        or "flutter"
    )
    return [executable, *args]


def run(command: list[str], *, cwd: str = ROOT, env: dict | None = None,
        check: bool = True) -> subprocess.CompletedProcess:
    log("  $ %s" % mask_secrets(" ".join(command)))
    process = subprocess.run(
        command,
        cwd=cwd,
        env=env,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    if check and process.returncode != 0:
        die(
            "命令失败（退出码 %d）：%s\n--- stdout ---\n%s\n--- stderr ---\n%s"
            % (process.returncode, mask_secrets(" ".join(command)),
               process.stdout[-4000:], process.stderr[-4000:])
        )
    return process


# ---------------------------------------------------------------------------
# 版本号
# ---------------------------------------------------------------------------


def read_version() -> tuple[str, int]:
    with open(PUBSPEC, encoding="utf-8") as handle:
        content = handle.read()
    match = re.search(r"^version:[ \t]*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)[ \t]*$",
                      content, re.MULTILINE)
    if not match:
        die("pubspec.yaml 里的 version 不是 `x.y.z+N` 形式，无法解析")
    return match.group(1), int(match.group(2))


def write_version(name: str, code: int) -> None:
    with open(PUBSPEC, encoding="utf-8") as handle:
        content = handle.read()
    # 注意用 `[ \t]*$` 而不是 `\s*$`：`$` 在 MULTILINE 下匹配行尾，
    # 但 `\s` 能吃掉换行，`\s*$` 会把版本行末尾的 `\n` 一起吞掉，
    # 于是 `version:` 与下一行之间的空行会被悄悄删掉（每次发版都产生一条
    # 无意义的 pubspec diff）。
    content = re.sub(
        r"^version:[ \t]*[0-9]+\.[0-9]+\.[0-9]+\+[0-9]+[ \t]*$",
        "version: %s+%d" % (name, code),
        content,
        count=1,
        flags=re.MULTILINE,
    )
    with open(PUBSPEC, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(content)


def bump(name: str, kind: str) -> str:
    major, minor, patch = (int(part) for part in name.split("."))
    if kind == "major":
        return "%d.0.0" % (major + 1)
    if kind == "minor":
        return "%d.%d.0" % (major, minor + 1)
    return "%d.%d.%d" % (major, minor, patch + 1)


# ---------------------------------------------------------------------------
# 更新说明
# ---------------------------------------------------------------------------


def notes_from_changelog(version_name: str) -> list[str]:
    """从 CHANGELOG.md 里抽出某个版本那一节的条目。

    写进清单后会原样显示在老师手机上，所以这里只做搬运，不做任何加工。
    """
    if not os.path.exists(CHANGELOG):
        die("找不到 CHANGELOG.md，请先写更新说明")
    with open(CHANGELOG, encoding="utf-8") as handle:
        lines = handle.read().splitlines()

    header = re.compile(r"^##\s*\[?%s\]?" % re.escape(version_name))
    collected: list[str] = []
    inside = False
    for line in lines:
        if line.startswith("## "):
            if inside:
                break
            inside = bool(header.match(line))
            continue
        if not inside:
            continue
        stripped = line.strip()
        # 只收二级标题下的 `-` 条目；### 小标题本身略过（它只是分类）
        if stripped.startswith("- "):
            collected.append(stripped[2:].strip())
    return collected


# ---------------------------------------------------------------------------
# 构建
# ---------------------------------------------------------------------------


def build_apks() -> None:
    log("构建 release 包（分 ABI）…")
    env = dict(os.environ)
    # 本机挂了 HTTP 代理，flutter 连 localhost 的观测端口会被代理拦掉。
    env.setdefault("NO_PROXY", "localhost,127.0.0.1,::1")
    run(flutter_command("build", "apk", "--release"), env=env)


def apk_path(abi: str) -> str:
    return os.path.join(APK_DIR, "app-%s-release.apk" % abi)


def previous_apk(abi: str, previous_version_code: int | None,
                 override_dir: str | None) -> str | None:
    """找上一个已发布版本的 APK，用作分差基准。找不到就只发整包。"""
    if override_dir:
        candidate = os.path.join(override_dir, "app-%s-release.apk" % abi)
        return candidate if os.path.exists(candidate) else None
    if previous_version_code is None:
        return None
    candidate = os.path.join(
        RELEASE_CACHE, str(previous_version_code), "app-%s-release.apk" % abi
    )
    return candidate if os.path.exists(candidate) else None


def cache_current_apks(version_code: int, abis: tuple[str, ...]) -> None:
    target_dir = os.path.join(RELEASE_CACHE, str(version_code))
    os.makedirs(target_dir, exist_ok=True)
    for abi in abis:
        source = apk_path(abi)
        if os.path.exists(source):
            shutil.copy2(source, os.path.join(
                target_dir, "app-%s-release.apk" % abi))
    log("  已缓存本次产物到 dist/releases/%d（下次生成补丁要用）" % version_code)


# ---------------------------------------------------------------------------
# 清单
# ---------------------------------------------------------------------------


def load_manifest() -> dict:
    if not os.path.exists(MANIFEST):
        return {"schemaVersion": 1, "assetsBase": ASSETS_BASE, "releases": []}
    with open(MANIFEST, encoding="utf-8") as handle:
        return json.load(handle)


def save_manifest(manifest: dict, assets_bases: list[str]) -> None:
    """写清单。[assets_bases] 按优先级排列，第一个会同时写进单数的 `assetsBase`。

    单数字段是留给**已经装在老师手机上的旧版本**的（它们只读这一个），
    所以它必须是"当场验证过能下载"的那一个，不能凭想当然把 Gitee 写上去。
    """
    if not assets_bases:
        die("清单至少要有一个附件根地址，否则客户端没有可下载的来源")
    os.makedirs(os.path.dirname(MANIFEST), exist_ok=True)
    manifest["generatedAt"] = time.strftime("%Y-%m-%dT%H:%M:%S+08:00")
    manifest["assetsBase"] = assets_bases[0]
    manifest["assetsBases"] = assets_bases
    manifest["releases"] = manifest["releases"][:MANIFEST_HISTORY]
    with open(MANIFEST, "w", encoding="utf-8", newline="\n") as handle:
        json.dump(manifest, handle, ensure_ascii=False, indent=2)
        handle.write("\n")


def build_release_entry(
    *,
    version_name: str,
    version_code: int,
    tag: str,
    notes: list[str],
    abis: tuple[str, ...],
    previous_version_code: int | None,
    previous_dir: str | None,
    patch_dir: str,
) -> tuple[dict, list[str]]:
    """为一个版本生成清单条目，并把要上传的文件路径一并返回。"""
    assets = []
    deltas = []
    uploads = []

    for abi in abis:
        path = apk_path(abi)
        if not os.path.exists(path):
            die("缺少构建产物：%s\n请确认 android/app/build.gradle.kts 的 splits 配置"
                % path)
        size = os.path.getsize(path)
        digest = sha256_of(path)
        assets.append({
            "abi": abi,
            "file": os.path.basename(path),
            "size": size,
            "sha256": digest,
        })
        uploads.append(path)
        log("  %-14s %8.2f MB  %s" % (abi, size / 1048576, digest[:16]))

        # ---- 分差补丁 ----
        base = previous_apk(abi, previous_version_code, previous_dir)
        if base is None:
            log("  %-14s 没有上一版基准包，跳过分差" % abi)
            continue
        if previous_version_code is None:
            continue

        log("  生成分差补丁：%s → %s" % (
            os.path.basename(os.path.dirname(base)), abi))
        base_bytes = read_file_bytes(base)
        target_bytes = read_file_bytes(path)
        packed, stats = delta_patch.build_patch(base_bytes, target_bytes)

        # 生成后立刻自校验一次：宁可这里多花几秒，也不要把一份合不出来的
        # 补丁发出去——用户侧拿到只会合成失败再回落整包，白下载一趟。
        if delta_patch.apply_patch(base_bytes, packed) != target_bytes:
            die("分差补丁自校验失败（%s），已中止发布" % abi)

        if stats["downloadRatio"] >= DELTA_WORTHWHILE_RATIO:
            log("  补丁只省下 %.1f%%，不值得发，跳过"
                % ((1 - stats["downloadRatio"]) * 100))
            continue

        patch_name = "patch-%d-%d-%s.spdp" % (
            previous_version_code, version_code, abi)
        patch_path = os.path.join(patch_dir, patch_name)
        with open(patch_path, "wb") as handle:
            handle.write(packed)

        deltas.append({
            "fromVersionCode": previous_version_code,
            "abi": abi,
            "file": patch_name,
            "size": len(packed),
            "targetSize": size,
            "sha256": sha256_of(patch_path),
            "baseSha256": sha256_of(base),
        })
        uploads.append(patch_path)
        log("  补丁 %-14s %8.2f KB  复用 %.1f%%  下载量仅为整包的 %.2f%%"
            % (abi, len(packed) / 1024, stats["reuseRatio"] * 100,
               stats["downloadRatio"] * 100))

    entry = {
        "versionCode": version_code,
        "versionName": version_name,
        "tag": tag,
        "publishedAt": time.strftime("%Y-%m-%dT%H:%M:%S+08:00"),
        "notes": notes,
        "assets": assets,
        "deltas": deltas,
    }
    return entry, uploads


def previous_release(manifest: dict, current_code: int) -> dict | None:
    """找分差基准版本：versionCode **严格小于** current_code 里最大的那个。

    不能只取"清单里第一个不是自己的"——清单是按 versionCode 降序排的，
    补发一个旧版本时列表头可能就是比当前更新的版本，拿它当基准会生成一份
    方向反了的补丁（用户端拿旧包根本合不出来）。
    """
    candidates = [
        release for release in manifest.get("releases", [])
        if isinstance(release.get("versionCode"), int)
        and release["versionCode"] < current_code
    ]
    if not candidates:
        return None
    return max(candidates, key=lambda release: release["versionCode"])


# ---------------------------------------------------------------------------
# Git 与 GitHub
# ---------------------------------------------------------------------------


def git(*args: str, check: bool = True) -> subprocess.CompletedProcess:
    return run(["git", *args], check=check)


def purge_cdn_cache(max_wait_seconds: int = 600) -> None:
    """清掉 jsDelivr 上清单文件的边缘缓存。

    **这条不能省。** jsDelivr 对分支引用（`@main`）的缓存最长 12 小时，而
    `raw.githubusercontent.com` 在国内经常直接不通 —— 客户端的地址列表是
    raw 优先、jsDelivr 兜底（见 `UpdateService.manifestUrls`），raw 走不通时
    就只剩这份旧清单：老师手机上「检查更新」要么看不到新版本，要么晚半天才看到。

    实测（2026-09-30，发 v1.0.2 时）：`@main` 仍返回 v1.0.0 的清单（generatedAt
    停在 09-27），purge 之后立刻变成 v1.0.2。同一个 commit 用 `@<sha>` 取是实时的，
    但我们没法在客户端拼 sha，所以只能在发布侧主动清。

    失败**不中止发布**——缓存自己会过期，顶多晚 12 小时看到更新。

    **被限流会等着重试一轮**：jsDelivr 按路径限流，`throttlingReset` 实测 6~7 分钟
    （2026-10-01 连发 v1.0.3 / v1.0.4 时第二次必然被打回）。既然"发布后立刻清"正是
    最需要成功的时刻（老师下一秒就要在手机上点「检查更新」），就等这一轮再试；
    剩余时间超过 [max_wait_seconds] 才放弃。**注意限流时返回的 `status` 仍是
    `finished`** —— 只看 `status` 会把"没清掉"误判成"已清理"。
    """
    deadline = time.monotonic() + max_wait_seconds
    while True:
        payload = _request_purge()
        if payload is None:
            return
        entry = (payload.get("paths") or {}).get("/" + MANIFEST_CDN_PATH) or {}
        finished = str(payload.get("status")) == "finished"
        if finished and not entry.get("throttled"):
            log("  jsDelivr 清单缓存已清理")
            return
        reset = entry.get("throttlingReset")
        if (
            finished
            and isinstance(reset, (int, float))
            and 0 < reset <= deadline - time.monotonic()
        ):
            log("  jsDelivr 限流中，等 %.0f 秒后重试…" % reset)
            time.sleep(reset + 2)
            continue
        log("  ! jsDelivr 清单缓存没清掉：%s"
            % json.dumps(payload, ensure_ascii=False)[:160])
        if isinstance(reset, (int, float)) and reset > 0:
            log("    %.0f 秒后可手工补清：%s" % (reset, MANIFEST_PURGE_URL))
        else:
            log("    最长 12 小时后自动过期；必要时手工补清：%s" % MANIFEST_PURGE_URL)
        return


def _request_purge() -> dict | None:
    """请求一次 purge 端点，拿回解析后的 JSON；网络层失败返回 None（告警已在此打过）。

    **优先走 curl。** 本机的 Python `urllib` 访问 `purge.jsdelivr.net` 会被远程
    直接重置（`WinError 10054`，直连与走系统代理都一样），而同一个地址换成 curl
    就能正常拿到 JSON —— 是这台机器的环境差异，不是端点的问题（`api.github.com`
    的 urllib 请求是好的，所以发布本身没受影响，只有这一条会挂）。
    找不到 curl 才回落 urllib。
    """
    curl = shutil.which("curl")
    if curl:
        result = subprocess.run(
            [curl, "-s", "--max-time", "30", "-A", "schedule_plan-release",
             MANIFEST_PURGE_URL],
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
        )
        body = (result.stdout or "").strip()
        if result.returncode == 0 and body:
            try:
                return json.loads(body)
            except json.JSONDecodeError as error:
                log("  ! 清理 jsDelivr 缓存失败（返回不是 JSON）：%s" % error)
                return None
        log("  ! 清理 jsDelivr 缓存失败（curl 退出码 %s）：%s"
            % (result.returncode, (result.stderr or "").strip()[:120]))
        return None
    request = urllib.request.Request(
        MANIFEST_PURGE_URL,
        headers={"User-Agent": "schedule_plan-release"},
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return json.loads(response.read().decode("utf-8") or "{}")
    except Exception as error:  # 网络问题一律只告警
        log("  ! 清理 jsDelivr 缓存失败（不影响发布，最长 12 小时后自动过期）：%s"
            % error)
        return None


def commit_and_tag(version_name: str, tag: str, push: bool,
                   remotes: tuple[str, ...] = ("origin",)) -> str:
    """提交、打标签、（可选）推送到每个远端，返回本次发布对应的提交 SHA。"""
    log("提交并打标签…")
    git("add", "-A")
    message = "release: v%s" % version_name
    # 允许"没有可提交内容"（比如只重跑了一次清单生成）
    status = git("status", "--porcelain")
    if status.stdout.strip():
        git("commit", "-m", message)
    else:
        log("  没有需要提交的改动")
    # 标签是"一次性"的，但**同一次发布重跑**必须允许：上传成功、推送失败
    # 这类半途而废的场面很常见，如果这时死磕"标签已存在"，就只能手动删标签。
    # 所以只在"标签指向别的提交"时才拒绝——那才是真的想复用版本号。
    existing = git("tag", "--list", tag).stdout.strip()
    if existing:
        head = git("rev-parse", "HEAD").stdout.strip()
        tagged = git("rev-parse", "%s^{}" % tag).stdout.strip()
        if tagged != head:
            die("标签 %s 已存在，且指向 %s（当前 HEAD 是 %s）。\n"
                "    要么递增版本号，要么确认后手动删掉旧标签再重试。"
                % (tag, tagged[:8], head[:8]))
        log("  标签 %s 已存在且就指向当前提交，跳过创建" % tag)
    else:
        git("tag", "-a", tag, "-m", message)
    head = git("rev-parse", "HEAD").stdout.strip()
    if push:
        for remote in remotes:
            git("push", remote, "HEAD")
            git("push", remote, tag)
            # 推送之后再确认一次远端标签真的存在。`git push` 成功但标签
            # 指向别处的情况（比如上一轮 Release 让远端自造了一个同名标签）
            # 会让 Release 挂在错误的提交上，而日志里一切正常——必须自己验。
            remote_tags = git("ls-remote", "--tags", remote, tag).stdout.strip()
            if not remote_tags:
                die("推送后仍没在 %s 看到标签 %s，请检查网络或权限。" % (remote, tag))
            log("  已推送到 %s" % remote)
    else:
        log("  已提交并打标签（未推送，加 --push 才推）")
    return head


def amend_release_commit(version_name: str, tag: str,
                         remotes: tuple[str, ...]) -> str:
    """清单被修正后补一次提交，并把标签挪到新提交上再推一次。

    只在一种场面用到：发布已经跑完，但回验发现某个下载源其实不通，于是清单
    得改。此时**必须移动标签**——远端刚建好的发行版指的是标签，标签若留在
    旧提交上，清单里的更正就不在标签里，以后 checkout v1.0.6 拿到的还是那份
    写着坏源的清单。这是整个脚本里唯一允许强推标签的地方。
    """
    git("add", "-A")
    if git("status", "--porcelain").stdout.strip():
        git("commit", "-m", "release: v%s（修正可用下载源）" % version_name)
    git("tag", "-f", "-a", tag, "-m", "release: v%s" % version_name)
    head = git("rev-parse", "HEAD").stdout.strip()
    for remote in remotes:
        git("push", remote, "HEAD")
        git("push", "--force", remote, tag)
    log("  清单更正已提交并强推标签 %s → %s" % (tag, head[:8]))
    return head


def github_api(method: str, url: str, token: str, payload: dict | None = None,
               *, raw_body: bytes | None = None,
               content_type: str = "application/json") -> dict:
    headers = {
        "Authorization": "Bearer %s" % token,
        "Accept": "application/vnd.github+json",
        "User-Agent": "schedule_plan-release",
        "Content-Type": content_type,
    }
    data = raw_body
    if payload is not None:
        data = json.dumps(payload).encode("utf-8")
    request = urllib.request.Request(url, data=data, headers=headers,
                                     method=method)
    try:
        with urllib.request.urlopen(request, timeout=120) as response:
            body = response.read().decode("utf-8")
            return json.loads(body) if body.strip() else {}
    except urllib.error.HTTPError as error:
        detail = error.read().decode("utf-8", "replace")
        hint = ""
        if error.code in (401, 403):
            hint = ("\n    → 令牌被拒绝了：确认 GITHUB_TOKEN 没有过期，"
                    "细粒度 token 的 Contents 权限是 Read and write。")
        die("GitHub API %s %s 失败：%s %s%s"
            % (method, url, error.code, detail, hint))
    except urllib.error.URLError as error:
        die("连不上 GitHub：%s（必要时给 git/命令行配代理）" % error)


def upload_release_github(tag: str, version_name: str, notes: list[str],
                   uploads: list[str], token: str, target_sha: str) -> None:
    log("创建 GitHub Release 并上传附件…")
    # target_commitish 必须显式给成本次发布的提交。
    # 不给的话 GitHub 会用仓库默认分支的 HEAD——如果标签当时还不存在于远端，
    # 它就会**照着那个 HEAD 自己造一个同名标签**，Release 于是挂在一个不含本次
    # 发布的提交上，而随后真正的 `git push` 标签又会被 already exists 拒绝。
    # 两种症状都出现在"上传成功"之后，排查时很容易怪到权限头上。
    release = github_api("POST", "%s/releases" % API_BASE, token, {
        "tag_name": tag,
        "target_commitish": target_sha,
        "name": "v%s" % version_name,
        "body": "\n".join("- %s" % note for note in notes)
                or "本次发布没有额外说明。",
        "draft": False,
        "prerelease": False,
    })
    upload_url = release["upload_url"].split("{")[0]
    for path in uploads:
        name = os.path.basename(path)
        log("  上传 %s（%.2f MB）" % (name, os.path.getsize(path) / 1048576))
        github_api(
            "POST",
            "%s?name=%s" % (upload_url, name),
            token,
            raw_body=read_file_bytes(path),
            content_type="application/octet-stream",
        )
    log("  Release 地址：%s" % release["html_url"])


def read_secret(name: str) -> str | None:
    """取一个凭据：环境变量优先，其次 TOKEN_FILE。

    [name] 是变量名（`GITHUB_TOKEN` / `GITEE_TOKEN`）。文件格式就是最朴素的
    dotenv，两个令牌可以写在同一个文件里：

        GITHUB_TOKEN=github_pat_xxx
        GITEE_TOKEN=xxxxxxxxxxxxxxxx

    `#` 开头的行和空行忽略；值两边的引号会被剥掉（从网页复制时常常会带上）。
    """
    from_env = os.environ.get(name)
    if from_env and from_env.strip():
        return from_env.strip()
    try:
        with open(TOKEN_FILE, "r", encoding="utf-8") as handle:
            for line in handle:
                line = line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                key, _, value = line.partition("=")
                if key.strip() != name:
                    continue
                return value.strip().strip('"').strip("'") or None
    except FileNotFoundError:
        return None
    return None


def secret_file_status(name: str) -> str:
    """说明 TOKEN_FILE 当前为什么取不到 [name] 的值。

    「文件不存在」和「文件在、但等号右边是空的」处置完全不同：前者要新建，
    后者是粘贴没落盘。原来的日志两种情况都只说一句"没有可用的令牌"，
    用户明明看到文件就躺在那儿，只会以为是脚本读错了路径。
    """
    if not os.path.exists(TOKEN_FILE):
        return "%s 不存在" % TOKEN_FILE
    try:
        with open(TOKEN_FILE, "r", encoding="utf-8") as handle:
            content = handle.read()
    except OSError as error:
        return "%s 读取失败：%s" % (TOKEN_FILE, error)
    if name not in content:
        return "%s 里没有 %s= 这一行" % (TOKEN_FILE, name)
    for line in content.splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        if key.strip() == name and value.strip().strip('"').strip("'"):
            return "%s 里有值但没能取出来（检查是否混入了不可见字符）" % TOKEN_FILE
    return "%s 里的 %s= 后面是空的" % (TOKEN_FILE, name)


def token_looks_truncated(token: str) -> bool:
    """粗判 PAT 是不是被复制截断了。

    细粒度 PAT（`github_pat_`）有 93 个字符、中间还有一个下划线，从网页上
    复制时截断一半是很容易犯的错——症状却是服务端一句没头没脑的
    `401 Bad credentials`。在发请求之前拦一下，把 401 变成一句能看懂的话。
    """
    if token.startswith("github_pat_"):
        return len(token) < 80
    if token.startswith(("ghp_", "gho_", "ghu_", "ghs_")):
        return len(token) < 36
    return len(token) < 20


def verify_github_token(token: str) -> str:
    """打包**之前**确认 token 可用，返回 token 对应的登录名。

    这件事必须提前做。原先是在构建完、清单写完、产物缓存完才用 token，
    结果是：token 坏了要白白等一轮几分钟的构建，而且工作区里已经躺着被
    改过的 pubspec.yaml 和 updates/latest.json，还得手动还原。
    """
    if token_looks_truncated(token):
        die(
            "GITHUB_TOKEN 看起来被截断了（当前只有 %d 个字符）。\n"
            "    细粒度 PAT 形如 github_pat_<22位>_<59位>，共 93 个字符；\n"
            "    经典 PAT 形如 ghp_<36位>。请到 GitHub 的\n"
            "    Settings → Developer settings → Personal access tokens 重新复制。\n"
            "    注意：token 只在创建的那一瞬间完整显示一次，离开页面就再也看不到了，\n"
            "    所以大概率需要重新生成一个。" % len(token)
        )
    account = github_api("GET", "https://api.github.com/user", token)
    repository = github_api("GET", API_BASE, token)
    login = account.get("login")
    if not (repository.get("permissions") or {}).get("push"):
        die(
            "token 属于 %s，但对 %s 没有写权限，无法创建 Release。\n"
            "    细粒度 token 请在该仓库的权限里把 Contents 设为 Read and write。"
            % (login, REPOSITORY)
        )
    log("GitHub 身份：%s（对 %s 有写权限）" % (login, REPOSITORY))
    return login


# ---------------------------------------------------------------------------
# Gitee
# ---------------------------------------------------------------------------

# curl 把状态码写在响应体后面，用这个标记切出来（标志串本身不可能出现在
# JSON 响应里）。
CURL_STATUS_MARKER = "\n__HTTP_STATUS__"


def curl_request(method: str, url: str, *, fields: dict | None = None,
                 attachment: tuple[str, str] | None = None,
                 timeout: int = 300) -> tuple[int, str]:
    """用 curl 发一次请求，返回 `(状态码, 响应体)`。

    为什么 Gitee 这边走 curl 而不是 urllib：
      · 这台机器上 Python 的 TLS 栈对部分域名会被中途重置（jsDelivr 那次是
        `WinError 10054`，同一个地址 curl 一直正常），少一类"只在某台机器上
        才复现"的失败；
      · `attach_files` 是 multipart 上传，手工拼 body 在边界、CRLF、编码上
        各有一堆坑，curl 的 `-F` 直接给出正确答案。
    文本字段一律用 `--form-string` 而不是 `-F`：`-F` 会把值里的开头的 `@`
    当文件名、`;type=` 当元数据，而发行说明是用户写的中文文案，不该受这套
    规则约束。
    """
    command = [
        "curl", "-sS", "-X", method,
        "--max-time", str(timeout),
        "-w", CURL_STATUS_MARKER + "%{http_code}",
    ]
    for key, value in (fields or {}).items():
        command += ["--form-string", "%s=%s" % (key, value)]
    if attachment is not None:
        name, path = attachment
        command += ["-F", "%s=@%s" % (name, path)]
    command.append(url)
    result = run(command, check=False)
    output = result.stdout or ""
    index = output.rfind(CURL_STATUS_MARKER)
    if index < 0:
        die("curl 没有返回状态码（%s）：\n%s\n%s"
            % (mask_secrets(" ".join(command)), output[-600:],
               (result.stderr or "")[-600:]))
    return int(output[index + len(CURL_STATUS_MARKER):].strip()), output[:index]


def gitee_api(method: str, url: str, *, token: str,
              fields: dict | None = None,
              attachment: tuple[str, str] | None = None) -> dict:
    """调一次 Gitee OpenAPI v5，返回解析后的 JSON。非 2xx 直接中止发布。"""
    payload = dict(fields or {})
    payload["access_token"] = token
    status, body = curl_request(method, url, fields=payload,
                                attachment=attachment)
    if status not in (200, 201):
        hint = ""
        if status in (401, 403):
            hint = ("\n    → 令牌被拒绝了：确认 GITEE_TOKEN 没有过期，"
                    "且勾了 projects 权限。")
        elif status == 404:
            hint = ("\n    → 404 通常是仓库路径不对；也可能是令牌没有这个"
                    "仓库的权限。")
        die("Gitee API %s %s 失败：%s %s%s"
            % (method, url, status, body.strip()[:600], hint))
    try:
        return json.loads(body) if body.strip() else {}
    except json.JSONDecodeError as error:
        die("Gitee 返回的不是 JSON（%s）：%s" % (error, body.strip()[:600]))


def verify_gitee_token(token: str) -> str:
    """打包**之前**确认 Gitee 令牌可用，返回令牌对应的登录名。

    与 GitHub 那边同理：令牌坏了要白等一轮几分钟的构建，而且工作区里已经躺着
    被改过的 `pubspec.yaml` 与 `updates/latest.json`，还得手动还原。
    """
    if len(token) < 20:
        die(
            "GITEE_TOKEN 太短了（当前 %d 个字符）。\n"
            "    Gitee 私人令牌一般是 32 位十六进制串；请到\n"
            "    https://gitee.com/profile/personal_access_tokens 重新生成，\n"
            "    勾选 projects 权限（这一项管仓库与发行版）。" % len(token)
        )
    user = gitee_api("GET", "https://gitee.com/api/v5/user", token=token)
    repository = gitee_api("GET", GITEE_API_BASE, token=token)
    login = user.get("login")
    # 仓库接口只在**已认证**时返回 permission；匿名看自己的公开仓库拿不到。
    permission = repository.get("permission") or {}
    if permission and not (permission.get("push") or permission.get("admin")):
        die("Gitee 令牌属于 %s，但对 %s 没有写权限，无法建发行版。"
            % (login, GITEE_REPOSITORY))
    log("Gitee 身份：%s（仓库 %s）" % (login, GITEE_REPOSITORY))
    return login


def ensure_gitee_default_branch(token: str) -> None:
    """尽力把 Gitee 仓库的默认分支改成 main。

    我们的分支叫 `main`（与 GitHub 一致），而 Gitee 建仓库时给的是 `master`。
    不改的话：客户端读 raw 不受影响（地址里写死了 `main`），但网页端一进去会
    显示"master 分支不存在"，很容易让人误以为代码根本没推上去。
    **失败只记一行日志**——它和"能不能发版"无关，不该拦住发布。
    """
    status, body = curl_request(
        "GET", GITEE_API_BASE, fields={"access_token": token})
    if status != 200:
        return
    try:
        repository = json.loads(body)
    except json.JSONDecodeError:
        return
    if repository.get("default_branch") == "main":
        return
    status, _ = curl_request("PATCH", GITEE_API_BASE,
                             fields={"access_token": token,
                                     "default_branch": "main"})
    if status in (200, 201):
        log("  已把 Gitee 的默认分支设为 main")
    else:
        log("  （没能设置 Gitee 默认分支，返回 %s；不影响发布，"
            "可到 仓库设置 → 基本信息 手工改）" % status)


def gitee_existing_release(tag: str, token: str) -> dict | None:
    """找同一个 tag 上已有的发行版。

    发布跑到一半失败（上传中断、网络断了）是常态，重跑时必须**接着用**那个
    发行版，而不是再建一个同名的——Gitee 不会拦你，于是仓库里会凭空多出
    两个 v1.0.6，手机上看到的更新说明也会开始飘。
    """
    status, body = curl_request(
        "GET", "%s/releases/tags/%s" % (GITEE_API_BASE, tag),
        fields={"access_token": token})
    if status == 200 and body.strip():
        try:
            found = json.loads(body)
        except json.JSONDecodeError:
            found = None
        # 注意：这个接口在 tag 不存在时**也返回 200**，响应体是光秃秃一个
        # `null`——只看状态码会把"没有"当成"有"。
        if isinstance(found, dict) and found.get("id") is not None:
            return found
    status, body = curl_request(
        "GET", "%s/releases" % GITEE_API_BASE,
        fields={"access_token": token, "per_page": "30"})
    if status != 200:
        return None
    try:
        releases = json.loads(body)
    except json.JSONDecodeError:
        return None
    for release in releases if isinstance(releases, list) else []:
        if release.get("tag_name") == tag:
            return release
    return None


def upload_release_gitee(tag: str, version_name: str, notes: list[str],
                         uploads: list[str], token: str, target_sha: str) -> None:
    """在 Gitee 建发行版并上传附件；已存在同名发行版时接着用。"""
    log("创建 Gitee 发行版并上传附件…")
    release = gitee_existing_release(tag, token)
    if release is None:
        # target_commitish 与 GitHub 那边同理：显式指成本次发布的提交，
        # 不让远端按"默认分支的 HEAD"去猜。
        release = gitee_api("POST", "%s/releases" % GITEE_API_BASE, token=token,
                            fields={
                                "tag_name": tag,
                                "target_commitish": target_sha,
                                "name": "v%s" % version_name,
                                "body": "\n".join("- %s" % note for note in notes)
                                        or "本次发布没有额外说明。",
                                "prerelease": "false",
                            })
    else:
        log("  已有 tag %s 的发行版（id %s），沿用它"
            % (tag, release.get("id")))

    release_id = release.get("id")
    if release_id is None:
        die("Gitee 没有返回发行版 id：%s" % release)

    uploaded = {asset.get("name") for asset in (release.get("assets") or [])}
    for path in uploads:
        name = os.path.basename(path)
        if name in uploaded:
            log("  附件 %s 已存在，跳过" % name)
            continue
        log("  上传 %s（%.2f MB）" % (name, os.path.getsize(path) / 1048576))
        gitee_api(
            "POST",
            "%s/releases/%s/attach_files" % (GITEE_API_BASE, release_id),
            token=token,
            fields={"owner": GITEE_REPOSITORY.split("/")[0],
                    "repo": GITEE_REPOSITORY.split("/")[1],
                    "release_id": str(release_id)},
            attachment=("file", path),
        )
    log("  发行版地址：https://gitee.com/%s/releases/tag/%s"
        % (GITEE_REPOSITORY, tag))


def url_is_downloadable(url: str) -> bool:
    """这个地址**不登录、不带头**能不能下到东西。

    这是整条链路里最值钱的一次检查：仓库一旦转成私有、附件权限被收紧、
    或者文件名拼错了，脚本这边一切"成功"，而老师手机上永远看不到更新——
    症状要等用户报上来才发现。用 Range 只取前 1 KB，二十多兆的包也只是
    一次很轻的请求。
    """
    result = run(["curl", "-sSL", "--max-time", "60", "--range", "0-1023",
                  "-o", os.devnull, "-w", "%{http_code} %{size_download}", url],
                 check=False)
    parts = (result.stdout or "").split()
    if len(parts) != 2:
        return False
    code, size = parts
    return code in ("200", "206") and int(size) > 0


def verify_asset_urls(bases: list[str], entry: dict) -> list[str]:
    """逐个下载源挑一个文件试下，返回**验证通过**的源（保持原顺序）。

    每个源只抽一个文件（优先补丁，它最小），够判断"这条路通不通"了。
    """
    probe = (entry.get("deltas") or [{}])[0].get("file") \
        or entry["assets"][0]["file"]
    ok: list[str] = []
    for base in bases:
        url = "%s/%s/%s" % (base, entry["tag"], probe)
        if url_is_downloadable(url):
            log("  %s 可匿名下载 ✓（抽查 %s）" % (base, probe))
            ok.append(base)
        else:
            log("  %s **下不动** ✗（抽查 %s）" % (base, probe))
    return ok


# ---------------------------------------------------------------------------
# 主流程
# ---------------------------------------------------------------------------


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(
        prog="release.py",
        description="一键发布：打包 → 分差补丁 → 更新清单 → 标签 → "
                    "Gitee/GitHub 双份发行版",
    )
    parser.add_argument("--bump", choices=["patch", "minor", "major"],
                        help="自增版本号。不给就沿用 pubspec 里现有的版本。")
    parser.add_argument("--no-bump", action="store_true",
                        help="明确表示不改版本号（首次发布用）")
    parser.add_argument("--notes", help="直接用这段文字当更新说明，分号分隔；"
                                        "不给就从 CHANGELOG.md 里抽")
    parser.add_argument("--no-build", action="store_true",
                        help="跳过 flutter build（复用已有产物）")
    parser.add_argument("--skip-upload", action="store_true",
                        help="不建任何发行版，只生成本地产物与清单")
    parser.add_argument("--push", action="store_true",
                        help="提交并打标签后推送到每个远端（默认只在本地提交打标签）")
    parser.add_argument("--no-push", action="store_true",
                        help="显式不推送（等价于不加 --push，保留给习惯写法）")
    parser.add_argument("--no-commit", action="store_true",
                        help="只生成产物与清单，不提交也不打标签（空跑用）")
    parser.add_argument("--previous-apk-dir",
                        help="手动指定上一版 APK 所在目录（默认读 dist/releases/<版本号>/）")
    parser.add_argument("--patch-dir", default=os.path.join(ROOT, "dist", "patches"),
                        help="补丁输出目录")
    parser.add_argument("--include-emulator", action="store_true",
                        help="同时发布 x86_64（仅模拟器需要）")
    parser.add_argument("--no-gitee", action="store_true",
                        help="完全不碰 Gitee：不推 gitee 远端、不建 Gitee 发行版，"
                             "清单里也只写 GitHub（老行为）")
    parser.add_argument("--gitee-only", action="store_true",
                        help="只发 Gitee（GitHub 连不上时用；清单里只写 Gitee）")
    args = parser.parse_args(argv)

    if args.bump and args.no_bump:
        die("--bump 与 --no-bump 不能同时给")
    if args.no_gitee and args.gitee_only:
        die("--no-gitee 与 --gitee-only 不能同时给")

    # 附件源与要推送的远端，都由上面两个开关决定。顺序就是客户端尝试的顺序。
    if args.no_gitee:
        asset_bases = [ASSETS_BASE]
        remotes = ("origin",)
    elif args.gitee_only:
        asset_bases = [GITEE_ASSETS_BASE]
        remotes = (GITEE_REMOTE,)
    else:
        asset_bases = [GITEE_ASSETS_BASE, ASSETS_BASE]
        remotes = (GITEE_REMOTE, "origin")

    github_token = None
    gitee_token = None
    if args.skip_upload:
        log("跳过上传（--skip-upload），不校验令牌。")
    else:
        if not args.no_gitee:
            gitee_token = read_secret("GITEE_TOKEN")
            if gitee_token:
                verify_gitee_token(gitee_token)
            else:
                log("没有可用的 GITEE_TOKEN，本次不往 Gitee 发。")
                log("    原因：%s" % secret_file_status("GITEE_TOKEN"))
                log("    在 %s 里补一行 `GITEE_TOKEN=…` 后重跑即可"
                    "（产物已就绪，加 --no-build 免重新构建）。" % TOKEN_FILE)
        if not args.gitee_only:
            github_token = read_secret("GITHUB_TOKEN")
            if github_token:
                verify_github_token(github_token)
            else:
                log("没有可用的 GITHUB_TOKEN，本次不往 GitHub 发。")
                log("    原因：%s" % secret_file_status("GITHUB_TOKEN"))
                log("    写进一行 `GITHUB_TOKEN=github_pat_xxx` 后重跑即可"
                    "（产物已就绪，加 --no-build 免重新构建）")

    # 一个源都没成，清单就会指不到任何安装包。不如当场停下说清楚。
    if not args.skip_upload and not gitee_token and not github_token:
        die("两个令牌都取不到，清单无论怎么写都指不到安装包。\n"
            "    要么把令牌补齐，要么用 --skip-upload 只生成本地产物。")

    # 「创建 Release」与「提交并推送标签」必须成对。GitHub 在收到创建 Release
    # 的请求时，如果远端还没有这个标签，会照着 target_commitish 的 HEAD
    # **自己造一个**；随后真正推送标签就会被 `already exists` 拒绝，而 Release
    # 已经挂在一个不含本次发布的提交上了。两条路都得堵住，所以在这里先拦。
    if gitee_token or github_token:
        if args.no_commit:
            die(
                "要创建发行版就不能加 --no-commit：\n"
                "    远端会按默认分支 HEAD 自己造一个同名标签，指向不含本次发布的提交，\n"
                "    而随后真正的推送又会被 `already exists` 拒绝。\n"
                "    只想空跑请改用 --skip-upload；要正式发布请去掉 --no-commit 并加 --push。"
            )
        if not (args.push and not args.no_push):
            die(
                "要创建发行版就必须加 --push：\n"
                "    标签不进远端，远端会按 HEAD 自造一个同名标签，\n"
                "    发行版于是挂在不含本次发布的提交上。\n"
                "    只想在本地提交打标签请改用 --skip-upload。"
            )

    name, code = read_version()
    log("当前版本：%s+%d" % (name, code))

    manifest = load_manifest()
    known_codes = {r.get("versionCode") for r in manifest.get("releases", [])}
    already_released = code in known_codes

    if args.bump:
        name = bump(name, args.bump)
        code += 1
        write_version(name, code)
        log("新版本：  %s+%d" % (name, code))
    elif already_released:
        log("提示：版本 %d 已在清单里，将覆盖它的条目（不新增历史）" % code)
    else:
        log("不改版本号，直接发布 %s+%d" % (name, code))

    tag = "v%s" % name

    if not args.no_build:
        build_apks()
    else:
        log("跳过构建（--no-build）")

    abis = PHONE_ABIS + (EMULATOR_ABIS if args.include_emulator else ())
    os.makedirs(args.patch_dir, exist_ok=True)

    log("计算指纹与分差…")
    previous = previous_release(manifest, current_code=code)
    previous_code = previous.get("versionCode") if previous else None
    if previous_code is not None:
        log("  上一版：%s（versionCode %d）"
            % (previous.get("versionName"), previous_code))

    entry, uploads = build_release_entry(
        version_name=name,
        version_code=code,
        tag=tag,
        notes=(args.notes.split(";") if args.notes
               else notes_from_changelog(name)),
        abis=abis,
        previous_version_code=previous_code,
        previous_dir=args.previous_apk_dir,
        patch_dir=args.patch_dir,
    )

    if not entry["notes"]:
        die(
            "没有拿到更新说明。请在 CHANGELOG.md 里加一节\n"
            "    ## [%s] - %s\n"
            "然后按 `- 一句话` 的格式写上本次改了什么；\n"
            "也可以用 --notes \"说明一;说明二\" 直接指定。" % (
                name, time.strftime("%Y-%m-%d"))
        )

    # 覆盖同版本条目，其余按 versionCode 从新到旧排列
    releases = [r for r in manifest.get("releases", [])
                if r.get("versionCode") != code]
    releases.insert(0, entry)
    releases.sort(key=lambda r: r.get("versionCode", 0), reverse=True)
    manifest["releases"] = releases
    manifest["schemaVersion"] = 1
    # 这里先用"计划里的源"写清单：必须赶在推送到远端之前把清单定下来，
    # 否则远端建发行版时还没有标签（见下面的顺序说明）。上传完成后会再回验
    # 一次附件地址，发现哪个源其实下不动就立刻把它改掉、补一次提交推送。
    save_manifest(manifest, asset_bases)

    log("更新清单已写入 updates/latest.json：")
    log("  版本 %s+%d，整包 %d 个，分差 %d 个，下载源 %s"
        % (name, code, len(entry["assets"]), len(entry["deltas"]),
           " → ".join(asset_bases)))

    cache_current_apks(code, abis)

    # 顺序是有讲究的：**先提交、打标签、推送，再建发行版**。
    # 反过来的话，远端收到创建请求时发现还没有这个标签，会照着
    # target_commitish（默认远端默认分支的 HEAD）**自己造一个同名标签**——
    # 于是发行版挂在不含本次发布的提交上，随后真正的 `git push` 标签
    # 又被 `already exists` 拒绝。两个症状都在"上传完成"之后才出现，
    # 排查时很容易被误判成权限问题。
    if args.no_commit:
        log("跳过 git 提交与打标签（--no-commit）。")
        head_sha = git("rev-parse", "HEAD").stdout.strip()
    else:
        head_sha = commit_and_tag(name, tag, push=args.push and not args.no_push,
                                  remotes=remotes)

    if args.skip_upload:
        log("跳过建发行版（--skip-upload）。")
    else:
        if gitee_token:
            ensure_gitee_default_branch(gitee_token)
            upload_release_gitee(tag, name, entry["notes"], uploads,
                                 gitee_token, head_sha)
        if github_token:
            upload_release_github(tag, name, entry["notes"], uploads,
                                 github_token,
                           head_sha)

        # 回验 + 必要时修正清单。清单已经推上去了，所以这一轮如果发现某个源
        # 下不动，得**再提交推送一次**把源去掉——宁可多一个提交，也不能让
        # 清单指着一个下不动的地址。
        log("回验附件地址能否匿名下载…")
        verified = verify_asset_urls(asset_bases, entry)
        if not verified:
            die(
                "两个源都验证失败，清单可能已指向不可用的地址。\n"
                "    请确认 Gitee 仓库是**公开**的（私有仓库匿名取不到 raw 与附件），\n"
                "    以及 GitHub 上的附件确实上传完成。\n"
                "    修好后用 --no-build --no-bump 重跑一次即可。"
            )
        if verified != asset_bases:
            log("  有源不可用，清单改为只写：%s" % " → ".join(verified))
            save_manifest(manifest, verified)
            if not args.no_commit:
                amend_release_commit(name, tag, remotes)
            asset_bases = verified

    # 清单刚推上 GitHub，顺手清掉 CDN 缓存：否则手机端最长要等 12 小时才看得到
    # 新版本（国内 raw 不通时 jsDelivr 是唯一来路）。Gitee 那边靠客户端地址里
    # 的 `?t=` 时间戳绕开缓存，没有对应的清缓存端点。
    if (not args.no_commit and args.push and not args.no_push
            and not args.gitee_only):
        log("清理 jsDelivr 上的清单缓存…")
        purge_cdn_cache()

    if args.skip_upload:
        log("\n完成（未上传）。产物与清单都在本地，补上令牌后重跑即可上传。")
    else:
        log("\n完成。下载源：%s" % " → ".join(asset_bases))
        log("接下来：确认两边的发行版附件都在，应用内的「检查更新」"
            "就能看到 v%s。" % name)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
