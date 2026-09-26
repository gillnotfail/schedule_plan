#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""APK 分差补丁生成器（内容分块 CDC）。

为什么不是"按固定大小切块做去重"
--------------------------------
APK 里最大的一块是 `lib/<abi>/libapp.so`（Dart AOT 快照，通常 8~12 MB）。
只要改几行 Dart 代码，这个文件里若干函数的字节长度就会变化，
**后面所有内容的偏移随之整体平移**。定长切块在这种位移面前会全面失配——
第 1 块错位 3 个字节，后面几千块全部对不上，去重率直接归零。

所以这里用**内容分块（Content-Defined Chunking）**：块的边界由滚动哈希
（gear hash）在内容上"自然涌现"的位置决定，与它落在文件的第几个字节无关。
内容一旦位移，边界会跟着内容一起移动，未改动区域照样整块命中。

为什么设备端不需要实现这套算法
------------------------------
补丁里的命令直接记录「从源文件的第 X 字节起取 Y 字节」，也就是说
**分块只发生在生成端**。设备端要做的仅仅是：
    校验源文件指纹 → 按命令搬运字节 → 校验产物指纹
因此 Dart 侧只有解析与拷贝，没有哈希分块，正确性风险极低。

补丁文件格式（v1，整体 gzip）
-----------------------------
    0   4   magic  = b'SPDP'
    4   1   formatVersion = 1
    5   1   avgBits         分块平均位宽（15 → 平均 32 KiB）
    6   4   minChunk        最小块长（BE u32）
    10  4   maxChunk        最大块长（BE u32）
    14  8   baseSize        源文件字节数（BE u64）
    22  8   targetSize      目标文件字节数（BE u64）
    30  32  baseSha256      源文件 SHA-256
    62  32  targetSha256    目标文件 SHA-256（设备端合成后必须核对）
    94  4   commandCount    命令条数（BE u32）
    98  ..  命令表，逐条：
              op=1 COPY_BASE    : u64 baseOffset + u32 length   （共 13 字节）
              op=2 COPY_LITERAL : u32 length                    （共 5 字节）
    随后是字面量载荷：所有 COPY_LITERAL 的新内容按命令顺序首尾相接。

命令表与载荷一起被 gzip 压缩（gzip 头 10 字节由 GZipCodec 处理，
Dart 侧用 GZipCodec.decode 解整包）。
"""

from __future__ import annotations

import gzip
import hashlib
import json
import os
import struct
import sys
import time

# ---------------------------------------------------------------------------
# 分块参数
# ---------------------------------------------------------------------------

MAGIC = b"SPDP"
FORMAT_VERSION = 1

AVG_BITS = 15
MIN_CHUNK = 4 * 1024  # 4 KiB
# 最大块长取 64 KiB（= 2 × 平均块长）。
# 实测 128K / 64K / 32K 对真实 APK 的补丁大小几乎无差别
# （替换中间 1 MB：4.30% / 4.30% / 4.25%），但上限越小，最坏情况越轻：
# 可执行文件里夹着成片的零填充（对齐空洞），这类区间内容完全均匀，
# 切出来的中间块**无论落在哪个偏移内容都一样、永远能命中**，
# 只有改动所在的那一两个边界块会作废——上限越小，作废的字节就越少。
#
# 另外，撞到上限的块有个非显然的好处：它的长度与内容无关，
# 因此**内容改动不会让它后面的边界漂移**。这也是为什么"改 1 个字节"
# 在真实 APK 上能把边界位置整份保住、复用率到 99.9%。
MAX_CHUNK = 64 * 1024

# 边界判定掩码：取**高 15 位**（17..31），平均块长 2^15 = 32 KiB。
#
# 为什么不能把掩码放在低位（这是踩过的坑）
# ----------------------------------------
# gear 哈希是 h = (h << 1) + GEAR[b]，于是 bit0 恒等于 GEAR[最后一个字节]&1——
# **低位基本只由最后消费的那个字节决定**，最多只有约 256 种取值。
# 掩码里一旦含 bit0，边界出现的概率会远低于设计值；
# 实测把掩码放在 bits 1..29 时随机数据上均值还有 3.2 万（勉强能用），
# 但方差大得多，曾出现"整个 70 KB 目标文件一个边界都没切出来"的退化情形
# （固定样例的复用率因此掉到 0%）。高位由多个字节的加法进位混合而来，
# 分布稳得多——实测本机 22.89 MB 的 release APK：
#     随机数据 均值 36.5 KB / 中位 25.2 KB
#     真实 APK 均值 39.8 KB / 中位 30.0 KB
# 均值略高于 32 KB 是加法进位带来的相关性所致，对去重效果无影响，
# `selftest` 里有区间护栏，防止以后改动把它再次弄退化。
MASK = 0
for _b in range(17, 32):
    MASK |= 1 << _b

U32 = 0xFFFFFFFF


def _build_gear_table() -> list[int]:
    """生成 256 项 gear 表（xorshift32，种子固定）。

    Dart 侧必须生成**完全一致**的表，否则分块边界对不上。
    具体做法见 `lib/core/utils/delta_patch.dart` 里的同名常量注释。
    """
    table = []
    state = 0x1234567
    for _ in range(256):
        state ^= (state << 13) & U32
        state ^= state >> 17
        state ^= (state << 5) & U32
        state &= U32
        table.append(state)
    return table


GEAR = _build_gear_table()


def chunk_length(data, offset: int, length: int) -> int:
    """返回从 offset 起下一块的字节数（1 <= r <= min(length, MAX_CHUNK)）。

    与 Dart 侧逐字节等价：
      1. 先无条件消化 min(MIN_CHUNK, 可用长度) 个字节；
      2. 之后每消化一个字节前先测一次 (hash & MASK) == 0；
      3. 命中即在此处切断，否则一路上限 cut 掉。
    """
    n = length if length < MAX_CHUNK else MAX_CHUNK
    k = MIN_CHUNK if n > MIN_CHUNK else n

    h = 0
    for t in range(k):
        h = ((h << 1) + GEAR[data[offset + t]]) & U32

    i = k
    while i < n:
        if (h & MASK) == 0:
            return i
        h = ((h << 1) + GEAR[data[offset + i]]) & U32
        i += 1
    return n


def chunk_index(data) -> dict[bytes, list[tuple[int, int]]]:
    """把整份数据切成内容分块，返回 {块指纹: [(offset, length), ...]}。

    同一指纹保留**所有**出现位置，而不只第一个：文件里重复内容
    （比如大量零填充、重复的资源）能显著抬高命中率。
    """
    index: dict[bytes, list[tuple[int, int]]] = {}
    total = len(data)
    offset = 0
    while offset < total:
        size = chunk_length(data, offset, total - offset)
        # 末尾残块（长度可能不足 MIN_CHUNK）照样索引：整份文件最多只有
        # 一个这种块，收下它能让"目标文件的尾部与源文件尾部相同"这种情况也命中。
        key = hashlib.sha256(data[offset : offset + size]).digest()[:16]
        index.setdefault(key, []).append((offset, size))
        offset += size
    return index


def sha256_file(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as fp:
        for block in iter(lambda: fp.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


# ---------------------------------------------------------------------------
# 生成
# ---------------------------------------------------------------------------


def build_patch(base: bytes, target: bytes) -> tuple[bytes, dict]:
    """生成补丁，返回 (补丁字节, 统计信息)。"""
    started = time.time()
    index = chunk_index(base)
    chunked_at = time.time()

    commands: list[bytes] = []
    literals = bytearray()
    reused = 0
    literal_total = 0

    offset = 0
    total = len(target)
    while offset < total:
        size = chunk_length(target, offset, total - offset)
        blob = target[offset : offset + size]
        key = hashlib.sha256(blob).digest()[:16]
        hits = index.get(key)
        matched = None
        if hits:
            # 指纹取的是 SHA-256 前 16 字节，碰撞概率可以忽略，
            # 但"忽略"不等于"不存在"——这里仍然逐字节比对一次再复用。
            # 代价是每块一次切片比较（32 KB 量级，可以忽略），
            # 换来的是**补丁正确性不依赖概率**：比不中就当新内容发出去。
            for base_offset, base_size in hits:
                if base_size == size and base[base_offset : base_offset + base_size] == blob:
                    matched = (base_offset, base_size)
                    break
        if matched is not None:
            base_offset, base_size = matched
            commands.append(struct.pack(">BQI", 1, base_offset, base_size))
            reused += base_size
        else:
            commands.append(struct.pack(">BI", 2, size))
            literals += blob
            literal_total += size
        offset += size

    header = bytearray()
    header += MAGIC
    header += struct.pack(">B", FORMAT_VERSION)
    header += struct.pack(">B", AVG_BITS)
    header += struct.pack(">II", MIN_CHUNK, MAX_CHUNK)
    header += struct.pack(">QQ", len(base), len(target))
    header += hashlib.sha256(base).digest()
    header += hashlib.sha256(target).digest()
    header += struct.pack(">I", len(commands))

    raw = bytes(header) + b"".join(commands) + bytes(literals)
    packed = gzip.compress(raw, compresslevel=9, mtime=0)

    stats = {
        "baseSize": len(base),
        "targetSize": len(target),
        "patchSize": len(packed),
        "rawPatchSize": len(raw),
        "baseSha256": hashlib.sha256(base).hexdigest(),
        "targetSha256": hashlib.sha256(target).hexdigest(),
        "commandCount": len(commands),
        "literalBytes": literal_total,
        "reusedBytes": reused,
        "reuseRatio": round(reused / total, 4) if total else 0.0,
        # 相对"直接下载完整包"的下载量占比，越小越好
        "downloadRatio": round(len(packed) / len(target), 4) if target else 0.0,
        "chunkIndexMs": int((chunked_at - started) * 1000),
        "totalMs": int((time.time() - started) * 1000),
    }
    return packed, stats


# ---------------------------------------------------------------------------
# 应用（同时也是 Dart 侧实现的参考语义，两边必须表现一致）
# ---------------------------------------------------------------------------


def parse_patch(packed: bytes) -> dict:
    raw = gzip.decompress(packed)
    if len(raw) < 98 or raw[:4] != MAGIC:
        raise ValueError("不是合法的 SPDP 补丁")
    version = raw[4]
    if version != FORMAT_VERSION:
        raise ValueError(f"补丁格式版本不支持：{version}（本工具只认 {FORMAT_VERSION}）")

    avg_bits = raw[5]
    min_chunk, max_chunk = struct.unpack_from(">II", raw, 6)
    base_size, target_size = struct.unpack_from(">QQ", raw, 14)
    base_sha = raw[30:62].hex()
    target_sha = raw[62:94].hex()
    (count,) = struct.unpack_from(">I", raw, 94)

    commands = []
    cursor = 98
    literal_total = 0
    for _ in range(count):
        op = raw[cursor]
        if op == 1:
            base_offset, length = struct.unpack_from(">QI", raw, cursor + 1)
            cursor += 13
            commands.append(("base", base_offset, length))
        elif op == 2:
            (length,) = struct.unpack_from(">I", raw, cursor + 1)
            cursor += 5
            commands.append(("literal", length))
            literal_total += length
        else:
            raise ValueError(f"未知命令 op={op}")

    payload = raw[cursor:]
    if len(payload) != literal_total:
        raise ValueError(
            f"补丁载荷长度不符：声明 {literal_total}，实际 {len(payload)}"
        )

    return {
        "avgBits": avg_bits,
        "minChunk": min_chunk,
        "maxChunk": max_chunk,
        "baseSize": base_size,
        "targetSize": target_size,
        "baseSha256": base_sha,
        "targetSha256": target_sha,
        "commands": commands,
        "payload": payload,
    }


def apply_patch(base: bytes, packed: bytes) -> bytes:
    info = parse_patch(packed)
    if len(base) != info["baseSize"]:
        raise ValueError(
            f"源文件大小不符：期望 {info['baseSize']}，实际 {len(base)}"
        )
    if sha256_bytes(base) != info["baseSha256"]:
        raise ValueError("源文件指纹不符，补丁不适用")

    out = bytearray()
    cursor = 0
    payload = info["payload"]
    for cmd in info["commands"]:
        if cmd[0] == "base":
            _, base_offset, length = cmd
            out += base[base_offset : base_offset + length]
        else:
            _, length = cmd
            out += payload[cursor : cursor + length]
            cursor += length

    if len(out) != info["targetSize"]:
        raise ValueError(f"合成结果大小不符：{len(out)} != {info['targetSize']}")
    if sha256_bytes(bytes(out)) != info["targetSha256"]:
        raise ValueError("合成结果指纹校验失败")
    return bytes(out)


# ---------------------------------------------------------------------------
# 命令行
# ---------------------------------------------------------------------------


def _read(path: str) -> bytes:
    with open(path, "rb") as fp:
        return fp.read()


def _cmd_diff(args) -> int:
    base = _read(args.base)
    target = _read(args.target)
    packed, stats = build_patch(base, target)
    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    with open(args.out, "wb") as fp:
        fp.write(packed)

    if args.verify:
        rebuilt = apply_patch(base, packed)
        if rebuilt != target:
            print("!! 自校验失败：合成结果与目标不一致", file=sys.stderr)
            return 2
        stats["verified"] = True

    if args.json:
        print(json.dumps(stats, ensure_ascii=False))
    else:
        saving = 1 - stats["downloadRatio"]
        print(f"源包      {stats['baseSize'] / 1048576:.2f} MB")
        print(f"目标包    {stats['targetSize'] / 1048576:.2f} MB")
        print(f"补丁      {stats['patchSize'] / 1048576:.2f} MB"
              f"（压缩前 {stats['rawPatchSize'] / 1048576:.2f} MB）")
        print(f"复用率    {stats['reuseRatio'] * 100:.1f}%")
        print(f"下载量    {stats['downloadRatio'] * 100:.1f}%  "
              f"（比整包省 {saving * 100:.1f}%）")
        print(f"命令数    {stats['commandCount']}")
        print(f"耗时      {stats['totalMs']} ms")
        if args.verify:
            print("自校验    通过")
    return 0


def _cmd_apply(args) -> int:
    base = _read(args.base)
    packed = _read(args.patch)
    out = apply_patch(base, packed)
    with open(args.out, "wb") as fp:
        fp.write(out)
    print(f"已合成 {args.out}（{len(out)} 字节），指纹校验通过")
    return 0


def _cmd_stat(args) -> int:
    packed = _read(args.patch)
    info = parse_patch(packed)
    listed = dict(info)
    listed.pop("payload")
    listed.pop("commands")
    listed["commandCount"] = len(info["commands"])
    listed["payloadBytes"] = len(info["payload"])
    print(json.dumps(listed, ensure_ascii=False, indent=2))
    return 0


def _cmd_selftest(args) -> int:
    """自检：分块退化护栏 + 六类改动形态的往返校验。"""
    import random

    failures = 0

    # ---- 护栏一：分块不能退化 ----
    # 这条用例是补上来的：曾经因为把边界掩码放在低位，
    # 导致目标文件"一个边界都切不出来"，整份文件变成一个巨块，
    # 分差直接退化成全量。均值跑出设计区间就必须立刻失败。
    rng = random.Random(4242)
    probe = bytes(rng.getrandbits(8) for _ in range(4_000_000))
    sizes = []
    offset = 0
    while offset < len(probe):
        size = chunk_length(probe, offset, len(probe) - offset)
        sizes.append(size)
        offset += size
    mean = sum(sizes) / len(sizes)
    lo, hi = AVG_BITS and (1 << (AVG_BITS - 1)), (1 << (AVG_BITS + 1))
    ok = lo <= mean <= hi
    if not ok:
        failures += 1
    print(f"{'分块均值落在设计区间':<34}{mean:>10.0f} B"
          f"  期望 {lo}~{hi}   {'通过' if ok else '失败'}")
    if max(sizes) >= MAX_CHUNK:
        # 撞上限说明有大量长块，属于可接受但不健康的信号，只提示不判失败
        capped = sum(1 for s in sizes if s >= MAX_CHUNK)
        print(f"  提示：{capped}/{len(sizes)} 块撞到最大块长上限")

    # ---- 护栏二：各类改动形态都要能正确往返 ----
    rng = random.Random(20260926)
    cases = []

    base = bytes(rng.getrandbits(8) for _ in range(300_000))
    cases.append(("完全无关的两份数据（应几乎不复用）", base,
                  bytes(rng.getrandbits(8) for _ in range(300_000))))

    base = bytes(rng.getrandbits(8) for _ in range(300_000))
    tgt = bytearray(base)
    tgt[150_000] ^= 0xFF
    cases.append(("只改 1 个字节", base, bytes(tgt)))

    base = bytes(rng.getrandbits(8) for _ in range(300_000))
    tgt = bytearray(base)
    tgt[100_000:140_000] = bytes(rng.getrandbits(8) for _ in range(40_000))
    cases.append(("中间整段替换 40 KB", base, bytes(tgt)))

    base = bytes(rng.getrandbits(8) for _ in range(300_000))
    tgt = base[:120_000] + base[121_000:]  # 删掉 1000 字节 → 全局前移
    cases.append(("删掉 1000 字节（后面全部位移）", base, tgt))

    base = bytes(rng.getrandbits(8) for _ in range(300_000))
    tgt = base[:50_000] + bytes(rng.getrandbits(8) for _ in range(33_333)) + base[50_000:]
    cases.append(("中间插入 33 KB（后面全部位移）", base, tgt))

    base = bytes(rng.getrandbits(8) for _ in range(300_000))
    cases.append(("完全相同（应 100% 复用）", base, base))

    # 可执行文件的真实形态：数据块与零填充（段对齐空洞）交替出现。
    # 注意别用"整份都是零"当用例——纯常量串在 gear 哈希下是退化输入
    # （收敛到不动点后要么永不切、要么处处切），它既不像真实文件，
    # 也会因为文件太小、块数太少而得出没有意义的复用率。
    mixed = bytearray()
    for _ in range(20):
        mixed += bytes(rng.getrandbits(8) for _ in range(10_000))
        mixed += bytes(rng.choice([0, 1_000, 4_000, 8_000]))
    base = bytes(mixed)
    cases.append(("数据块与零填充交替（模拟可执行文件）",
                  base, base[:150_000] + b"\xAA" + base[150_000:]))

    print()
    print(f"{'用例':<34}{'补丁':>12}{'复用率':>10}{'下载占比':>10}   校验")
    print("-" * 78)
    for name, a, b in cases:
        packed, stats = build_patch(a, b)
        try:
            ok = apply_patch(a, packed) == b
        except Exception as error:  # noqa: BLE001
            ok = False
            print(f"  异常：{error}", file=sys.stderr)
        if not ok:
            failures += 1
        print(f"{name:<34}{stats['patchSize']:>10} B"
              f"{stats['reuseRatio'] * 100:>9.1f}%"
              f"{stats['downloadRatio'] * 100:>9.1f}%   "
              f"{'通过' if ok else '失败'}")

    # ---- 护栏三：不适用的补丁必须被拒绝 ----
    base = bytes(rng.getrandbits(8) for _ in range(300_000))
    target = bytes(rng.getrandbits(8) for _ in range(300_000))
    packed, _ = build_patch(base, target)
    wrong = bytes(rng.getrandbits(8) for _ in range(300_000))
    try:
        apply_patch(wrong, packed)
        print("!! 用错误的源文件应用补丁竟然成功了", file=sys.stderr)
        failures += 1
    except ValueError:
        print("错误源文件被正确拒绝（指纹不符）")

    if failures:
        print(f"\n{failures} 项失败", file=sys.stderr)
        return 1
    print("\n全部通过")
    return 0


def _cmd_fixture(args) -> int:
    """生成跨语言固定样例：Dart 侧单测会读这份补丁做真正的应用测试。

    规模刻意压小（源文件 88 KB 上下）：它是用来锁**格式兼容性**的，
    不是用来压性能的。压性能请用 selftest 或直接拿真实 APK 跑 diff。
    """
    import random

    out_dir = args.out
    os.makedirs(out_dir, exist_ok=True)
    rng = random.Random(20260927)

    # 采用"数据块 + 零填充"交替的布局，贴近真实可执行文件；
    # 并特意放入一段重复内容，让索引的"同指纹多位置"分支也被走到。
    # 规模压到 20 万字节上下（约 5 块）：足够走到多命令、多块、gzip 三条路径，
    # 又不会让仓库为一份测试样例多背上几百 KB。
    parts = []
    for _ in range(9):
        parts.append(bytes(rng.getrandbits(8) for _ in range(18_000)))
        parts.append(bytes(2_000))
    parts.append(parts[5])  # 重复片段
    base = b"".join(parts)

    # 改动刻意做得"占比很小"：样例要证明的是**格式能跨语言互通**，
    # 不是压缩比。曾经把改动铺得太满（1 字节翻转 + 12 KB 替换 + 尾部截断
    # 各毁掉一个块），复用率算出来只有 17.7%——那是正确结果，
    # 却容易被误读成算法退化。这里只做一处原地替换 + 一处小段删除。
    target = bytearray(base)
    target[60_000:64_000] = bytes(rng.getrandbits(8) for _ in range(4_000))
    target = bytes(target[:120_000]) + bytes(target[120_300:])

    packed, stats = build_patch(base, target)

    # 护栏的分工要说清楚：
    #   · "分块是否退化"由 selftest 里的均值区间守护（那才是合适的地方）；
    #   · 这里只确认样例**确实覆盖了两类命令**，否则它证明不了跨语言格式兼容。
    # 曾经在这里拿复用率当门槛（要求 > 0.7），结果样例里改动占比一高就报警，
    # 而 57% 之类的数字本身完全正常——用错指标守错了东西。
    ops = set()
    info = parse_patch(packed)
    for cmd in info["commands"]:
        ops.add(cmd[0])
    if ops != {"base", "literal"} or len(info["commands"]) < 3:
        print(f"!! 样例不完整：命令 {len(info['commands'])} 条，类型 {sorted(ops)}，"
              f"需要两类命令都出现", file=sys.stderr)
        return 1
    with open(os.path.join(out_dir, "base.bin"), "wb") as fp:
        fp.write(base)
    with open(os.path.join(out_dir, "patch.spdp"), "wb") as fp:
        fp.write(packed)
    with open(os.path.join(out_dir, "expected.json"), "w", encoding="utf-8") as fp:
        json.dump(
            {
                "baseSize": len(base),
                "targetSize": len(target),
                "baseSha256": sha256_bytes(base),
                "targetSha256": sha256_bytes(target),
                "patchSize": len(packed),
                "commandCount": stats["commandCount"],
                "literalBytes": stats["literalBytes"],
                "reusedBytes": stats["reusedBytes"],
            },
            fp,
            ensure_ascii=False,
            indent=2,
        )
    print(f"样例已写入 {out_dir}")
    print(f"  源文件   {len(base)} B  {sha256_bytes(base)}")
    print(f"  目标文件 {len(target)} B  {sha256_bytes(target)}")
    print(f"  补丁     {len(packed)} B（命令 {stats['commandCount']} 条，"
          f"复用率 {stats['reuseRatio'] * 100:.1f}%）")
    return 0


def main(argv: list[str]) -> int:
    import argparse

    parser = argparse.ArgumentParser(
        prog="delta_patch.py",
        description="APK 分差补丁工具（内容分块 CDC，离线、无第三方依赖）",
    )
    sub = parser.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("diff", help="由两个文件生成补丁")
    p.add_argument("--base", required=True)
    p.add_argument("--target", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--verify", action="store_true", help="生成后立刻自校验")
    p.add_argument("--json", action="store_true", help="以 JSON 输出统计（给发布脚本用）")
    p.set_defaults(func=_cmd_diff)

    p = sub.add_parser("apply", help="用补丁把源文件合成成目标文件")
    p.add_argument("--base", required=True)
    p.add_argument("--patch", required=True)
    p.add_argument("--out", required=True)
    p.set_defaults(func=_cmd_apply)

    p = sub.add_parser("stat", help="查看补丁元信息")
    p.add_argument("--patch", required=True)
    p.set_defaults(func=_cmd_stat)

    p = sub.add_parser("selftest", help="跑一组自检用例")
    p.set_defaults(func=_cmd_selftest)

    p = sub.add_parser("fixture", help="为 Dart 单测导出固定样例")
    p.add_argument("--out", required=True)
    p.set_defaults(func=_cmd_fixture)

    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
