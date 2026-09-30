#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""一键发布：自增版本号 → 打包 → 生成分差补丁 → 写更新清单 → 提交打标签 → 建 GitHub Release。

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

典型用法
--------
    # 1) 先写更新说明（会原样出现在老师手机上，用大白话写）
    #    编辑 CHANGELOG.md，最上面加一节 ## [1.0.1] - 2026-10-01

    # 2) 发布（要建 Release 就必须带 --push，理由见下方"顺序"一节）
    python tool/release.py --bump patch --push

    # 空跑：只生成产物与清单，不碰网络、不提交、不打标签
    python tool/release.py --bump patch --skip-upload --no-commit

    # 首次发布（版本号已经是最终的，不想再动）：
    python tool/release.py --no-bump --push

顺序（踩过的坑）
----------------
    必须是 **先提交打标签推送 → 再建 Release**。

    反过来做的话：GitHub 收到创建 Release 的请求时，如果远端还没有这个标签，
    它会照着 target_commitish 的 HEAD **自己造一个同名标签**。结果是 Release
    挂在一个不含本次发布的旧提交上，而随后真正 `git push` 标签又被
    `already exists` 拒绝——两处都错，却都在"上传成功"之后才暴露，
    很容易被误判成权限问题。脚本现在会主动拦住这种组合。

环境变量
--------
    GITHUB_TOKEN  建 Release 与上传附件所需的令牌。
                  优先读环境变量，其次读 ~/.schedule_plan-release.env
                  （里面写 `GITHUB_TOKEN=github_pat_xxx`，权限请置 600）。
                  两者都没有就跳过上传，只生成本地产物。
                  脚本会在**打包之前**先验一次 token，避免白等一轮构建。
                  别把 token 贴进对话／聊天窗口：细粒度 PAT 有 93 个字符，
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
    log("  $ %s" % " ".join(command))
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
            % (process.returncode, " ".join(command),
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


def save_manifest(manifest: dict) -> None:
    os.makedirs(os.path.dirname(MANIFEST), exist_ok=True)
    manifest["generatedAt"] = time.strftime("%Y-%m-%dT%H:%M:%S+08:00")
    manifest["assetsBase"] = ASSETS_BASE
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


def purge_cdn_cache() -> None:
    """清掉 jsDelivr 上清单文件的边缘缓存。

    **这条不能省。** jsDelivr 对分支引用（`@main`）的缓存最长 12 小时，而
    `raw.githubusercontent.com` 在国内经常直接不通 —— 客户端的地址列表是
    raw 优先、jsDelivr 兜底（见 `UpdateService.manifestUrls`），raw 走不通时
    就只剩这份旧清单：老师手机上「检查更新」要么看不到新版本，要么晚半天才看到。

    实测（2026-09-30，发 v1.0.2 时）：`@main` 仍返回 v1.0.0 的清单（generatedAt
    停在 09-27），purge 之后立刻变成 v1.0.2。同一个 commit 用 `@<sha>` 取是实时的，
    但我们没法在客户端拼 sha，所以只能在发布侧主动清。

    失败**不中止发布**——缓存自己会过期，顶多晚 12 小时看到更新。
    """
    request = urllib.request.Request(
        MANIFEST_PURGE_URL,
        headers={"User-Agent": "schedule_plan-release"},
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            payload = json.loads(response.read().decode("utf-8") or "{}")
    except Exception as error:  # 网络问题一律只告警
        log("  ! 清理 jsDelivr 缓存失败（不影响发布，最长 12 小时后自动过期）：%s"
            % error)
        return
    entry = (payload.get("paths") or {}).get("/" + MANIFEST_CDN_PATH) or {}
    if str(payload.get("status")) == "finished" and not entry.get("throttled"):
        log("  jsDelivr 清单缓存已清理")
    else:
        # 有响应但状态不是 finished（偶发限流）：同样不阻断
        log("  ! jsDelivr 返回异常：%s"
            % json.dumps(payload, ensure_ascii=False)[:160])


def commit_and_tag(version_name: str, tag: str, push: bool) -> str:
    """提交、打标签、（可选）推送，返回本次发布对应的提交 SHA。"""
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
        git("push", "origin", "HEAD")
        git("push", "origin", tag)
        # 推送之后再确认一次远端标签真的落在 HEAD 上。`git push` 成功但标签
        # 指向别处的情况（比如上一轮 Release 让 GitHub 自造了一个同名标签）
        # 会让 Release 挂在错误的提交上，而日志里一切正常——必须自己验。
        remote = git("ls-remote", "--tags", "origin", tag).stdout.strip()
        remote_sha = remote.split()[0] if remote else ""
        if not remote_sha:
            die("推送后仍没在远端看到标签 %s，请检查网络或权限。" % tag)
        log("  已推送到 origin")
    else:
        log("  已提交并打标签（未推送，加 --push 才推）")
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


def upload_release(tag: str, version_name: str, notes: list[str],
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


def read_token() -> str | None:
    """取 GitHub token：环境变量优先，其次 TOKEN_FILE。

    文件格式就是最朴素的 dotenv：

        GITHUB_TOKEN=github_pat_xxx

    `#` 开头的行和空行忽略；值两边的引号会被剥掉（从网页复制时常常会带上）。
    """
    from_env = os.environ.get("GITHUB_TOKEN")
    if from_env and from_env.strip():
        return from_env.strip()
    try:
        with open(TOKEN_FILE, "r", encoding="utf-8") as handle:
            for line in handle:
                line = line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                key, _, value = line.partition("=")
                if key.strip() != "GITHUB_TOKEN":
                    continue
                return value.strip().strip('"').strip("'") or None
    except FileNotFoundError:
        return None
    return None


def token_file_status() -> str:
    """说明 TOKEN_FILE 当前为什么取不到值。

    「文件不存在」和「文件在、但等号右边是空的」处置完全不同：前者要新建，
    后者是粘贴没落盘。原来的日志两种情况都只说"没有可用的 GITHUB_TOKEN"，
    用户明明看到文件就躺在那儿，只会以为是脚本读错了路径。
    """
    if not os.path.exists(TOKEN_FILE):
        return "%s 不存在" % TOKEN_FILE
    try:
        with open(TOKEN_FILE, "r", encoding="utf-8") as handle:
            content = handle.read()
    except OSError as error:
        return "%s 读取失败：%s" % (TOKEN_FILE, error)
    if "GITHUB_TOKEN" not in content:
        return "%s 里没有 GITHUB_TOKEN= 这一行" % TOKEN_FILE
    for line in content.splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        if key.strip() == "GITHUB_TOKEN" and value.strip().strip('"').strip("'"):
            return "%s 里有值但没能取出来（检查是否混入了不可见字符）" % TOKEN_FILE
    return "%s 里的 GITHUB_TOKEN= 后面是空的" % TOKEN_FILE


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


def verify_token(token: str) -> str:
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
# 主流程
# ---------------------------------------------------------------------------


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(
        prog="release.py",
        description="一键发布：打包 → 分差补丁 → 更新清单 → 标签 → GitHub Release",
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
                        help="不建 GitHub Release，只生成本地产物与清单")
    parser.add_argument("--push", action="store_true",
                        help="提交并打标签后推送到 origin（默认只在本地提交打标签）")
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
    args = parser.parse_args(argv)

    if args.bump and args.no_bump:
        die("--bump 与 --no-bump 不能同时给")

    token = None if args.skip_upload else read_token()
    if token:
        verify_token(token)
    else:
        log("没有可用的 GITHUB_TOKEN，本次只生成本地产物（不会建 Release）。")
        log("    原因：%s" % token_file_status())
        log("    写进一行 `GITHUB_TOKEN=github_pat_xxx` 后重跑即可上传"
            "（产物已就绪，加 --no-build 免重新构建）")

    # 「创建 Release」与「提交并推送标签」必须成对。GitHub 在收到创建 Release
    # 的请求时，如果远端还没有这个标签，会照着 target_commitish 的 HEAD
    # **自己造一个**；随后真正推送标签就会被 `already exists` 拒绝，而 Release
    # 已经挂在一个不含本次发布的提交上了。两条路都得堵住，所以在这里先拦。
    if token:
        if args.no_commit:
            die(
                "要创建 Release 就不能加 --no-commit：\n"
                "    GitHub 会按远端 HEAD 自己造一个同名标签，指向不含本次发布的提交，\n"
                "    而随后真正的推送又会被 `already exists` 拒绝。\n"
                "    只想空跑请改用 --skip-upload；要正式发布请去掉 --no-commit 并加 --push。"
            )
        if not (args.push and not args.no_push):
            die(
                "要创建 Release 就必须加 --push：\n"
                "    标签不进远端，GitHub 会按远端 HEAD 自造一个同名标签，\n"
                "    Release 于是挂在不含本次发布的提交上。\n"
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
    save_manifest(manifest)

    log("更新清单已写入 updates/latest.json：")
    log("  版本 %s+%d，整包 %d 个，分差 %d 个"
        % (name, code, len(entry["assets"]), len(entry["deltas"])))

    cache_current_apks(code, abis)

    # 顺序是有讲究的：**先提交、打标签、推送，再建 Release**。
    # 反过来的话，GitHub 收到创建请求时发现远端还没有这个标签，会照着
    # target_commitish（默认远端默认分支的 HEAD）**自己造一个同名标签**——
    # 于是 Release 挂在不含本次发布的提交上，随后真正的 `git push` 标签
    # 又被 `already exists` 拒绝。两个症状都在"上传完成"之后才出现，
    # 排查时很容易被误判成权限问题。
    if args.no_commit:
        log("跳过 git 提交与打标签（--no-commit）。")
        head_sha = git("rev-parse", "HEAD").stdout.strip()
    else:
        head_sha = commit_and_tag(name, tag, push=args.push and not args.no_push)

    if args.skip_upload:
        log("跳过 GitHub Release（--skip-upload）。")
    elif not token:
        log("没有可用的 token，跳过上传（产物与清单都已就绪）。")
    else:
        upload_release(tag, name, entry["notes"], uploads, token, head_sha)

    # 清单刚推上 GitHub，顺手清掉 CDN 缓存：否则手机端最长要等 12 小时才看得到
    # 新版本（国内 raw 不通时 jsDelivr 是唯一来路）。
    if not args.no_commit and args.push and not args.no_push:
        log("清理 jsDelivr 上的清单缓存…")
        purge_cdn_cache()

    if args.skip_upload or not token:
        log("\n完成（未上传）。产物与清单都在本地，补上 token 后重跑即可上传。")
    else:
        log("\n完成。接下来：确认 Release 附件已上传，"
            "应用内的「检查更新」就能看到 v%s。" % name)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
