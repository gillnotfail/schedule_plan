import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// APK 分差补丁的**应用端**实现（生成端在 `tool/delta_patch.py`）。
///
/// 为什么这里没有分块算法
/// ----------------------
/// 分块只发生在生成端：补丁命令直接记录「从源文件第 X 字节起取 Y 字节」，
/// 设备端要做的只有三件事——
///   1. 校验源文件（手机里已装的 APK）的**大小与 SHA-256**；
///   2. 按命令搬运字节：要么从源文件抠一段，要么从补丁载荷里取一段；
///   3. 校验产物的**大小与 SHA-256**。
/// 因此设备端不需要实现 gear 哈希，也就没有"两端分块边界必须一致"这类
/// 跨语言陷阱——唯一需要保证一致的是**格式解析**，而它有固定样例单测锁住。
///
/// 补丁格式（整体 gzip 压缩，详细字段见生成端注释）
/// ------------------------------------------------
/// ```
/// magic "SPDP" | 版本 u8 | avgBits u8 | minChunk u32 | maxChunk u32
/// baseSize u64 | targetSize u64 | baseSha256(32) | targetSha256(32)
/// commandCount u32 | 命令表 | 字面量载荷
/// ```
/// 命令只有两种：`COPY_BASE(offset u64, length u32)` 与 `COPY_LITERAL(length u32)`，
/// 后者按出现顺序从载荷区依次取字节。

/// 补丁解析或应用失败。UI 不应该直接展示 [message]（它是给排查用的），
/// 而应该按 [DeltaPatchErrorKind] 映射到本地化文案。
class DeltaPatchException implements Exception {
  const DeltaPatchException(this.kind, this.message);

  final DeltaPatchErrorKind kind;
  final String message;

  @override
  String toString() => 'DeltaPatchException(${kind.name}): $message';
}

enum DeltaPatchErrorKind {
  /// 不是 SPDP 补丁、gzip 解不开、或字段自相矛盾。
  malformed,

  /// 补丁格式版本高于本 App 认识的范围。
  unsupportedVersion,

  /// 本地基础包大小或指纹对不上——补丁不适用，应该回落下载完整包。
  baseMismatch,

  /// 合成结果校验失败——写出来的文件不是它该有的样子。
  targetMismatch,

  /// 磁盘读写失败。
  io,
}

/// 一条搬运命令。
sealed class DeltaCommand {
  const DeltaCommand();
}

/// 从基础包复制。[offset] 是源文件内的绝对偏移。
final class DeltaCopyBase extends DeltaCommand {
  const DeltaCopyBase({required this.offset, required this.length});

  final int offset;
  final int length;
}

/// 从补丁载荷复制，按命令顺序消费载荷区。
final class DeltaCopyLiteral extends DeltaCommand {
  const DeltaCopyLiteral({required this.length});

  final int length;
}

/// 合成结果，供 UI 展示与问题排查。
class DeltaApplyReport {
  const DeltaApplyReport({
    required this.baseBytes,
    required this.targetBytes,
    required this.targetSha256,
    required this.commandCount,
    required this.literalBytes,
    required this.reusedBytes,
    required this.elapsed,
  });

  final int baseBytes;
  final int targetBytes;
  final String targetSha256;
  final int commandCount;
  final int literalBytes;
  final int reusedBytes;
  final Duration elapsed;

  /// 复用率 = 从本地旧包直接搬运的字节占新包的比例。
  double get reuseRatio => targetBytes == 0 ? 0 : reusedBytes / targetBytes;
}

/// 解析后的补丁。构造是纯计算，不碰文件系统，因此可以放心单测。
class DeltaPatch {
  const DeltaPatch._({
    required this.formatVersion,
    required this.avgBits,
    required this.minChunk,
    required this.maxChunk,
    required this.baseSize,
    required this.targetSize,
    required this.baseSha256,
    required this.targetSha256,
    required this.commands,
    required Uint8List payload,
  }) : _payload = payload;

  static const List<int> magic = <int>[0x53, 0x50, 0x44, 0x50]; // 'SPDP'

  /// 本 App 能解析的最高补丁格式版本。
  static const int formatVersionSupported = 1;

  static const int _headerFixedSize = 98;

  final int formatVersion;
  final int avgBits;
  final int minChunk;
  final int maxChunk;
  final int baseSize;
  final int targetSize;
  final String baseSha256;
  final String targetSha256;
  final List<DeltaCommand> commands;
  final Uint8List _payload;

  int get commandCount => commands.length;

  /// 字面量载荷的字节数（等于所有 COPY_LITERAL 长度之和）。
  int get literalBytes => _payload.length;

  /// 从本地旧包搬运的字节数。
  int get reusedBytes =>
      commands.whereType<DeltaCopyBase>().fold(0, (sum, c) => sum + c.length);

  /// 解析一份**已解压**的补丁字节。
  factory DeltaPatch.parse(Uint8List raw) {
    if (raw.length < _headerFixedSize) {
      throw DeltaPatchException(
        DeltaPatchErrorKind.malformed,
        '补丁长度 ${raw.length} 不足一个包头（$_headerFixedSize）',
      );
    }
    for (var i = 0; i < magic.length; i++) {
      if (raw[i] != magic[i]) {
        throw const DeltaPatchException(
          DeltaPatchErrorKind.malformed,
          '魔数不匹配，不是 SPDP 补丁',
        );
      }
    }

    final view = ByteData.view(raw.buffer, raw.offsetInBytes, raw.length);
    final version = view.getUint8(4);
    if (version > formatVersionSupported) {
      throw DeltaPatchException(
        DeltaPatchErrorKind.unsupportedVersion,
        '补丁格式版本 $version 高于本 App 支持的 $formatVersionSupported',
      );
    }

    final baseSize = view.getUint64(14);
    final targetSize = view.getUint64(22);
    final baseSha = _hex(raw, 30, 32);
    final targetSha = _hex(raw, 62, 32);
    final commandCount = view.getUint32(94);

    final commands = <DeltaCommand>[];
    var cursor = _headerFixedSize;
    var literalTotal = 0;
    for (var i = 0; i < commandCount; i++) {
      if (cursor >= raw.length) {
        throw const DeltaPatchException(
          DeltaPatchErrorKind.malformed,
          '命令表越界，补丁被截断',
        );
      }
      final op = raw[cursor];
      if (op == 1) {
        if (cursor + 13 > raw.length) {
          throw const DeltaPatchException(
            DeltaPatchErrorKind.malformed,
            'COPY_BASE 命令被截断',
          );
        }
        final offset = view.getUint64(cursor + 1);
        final length = view.getUint32(cursor + 9);
        cursor += 13;
        if (offset + length > baseSize) {
          throw DeltaPatchException(
            DeltaPatchErrorKind.malformed,
            'COPY_BASE 超出源文件范围：$offset + $length > $baseSize',
          );
        }
        commands.add(DeltaCopyBase(offset: offset, length: length));
      } else if (op == 2) {
        if (cursor + 5 > raw.length) {
          throw const DeltaPatchException(
            DeltaPatchErrorKind.malformed,
            'COPY_LITERAL 命令被截断',
          );
        }
        final length = view.getUint32(cursor + 1);
        cursor += 5;
        commands.add(DeltaCopyLiteral(length: length));
        literalTotal += length;
      } else {
        throw DeltaPatchException(
          DeltaPatchErrorKind.malformed,
          '未知命令 op=$op',
        );
      }
    }

    // 载荷用视图（不拷贝）：大补丁能到几兆，没必要再复制一份。
    final payload = Uint8List.sublistView(raw, cursor);
    if (payload.length != literalTotal) {
      throw DeltaPatchException(
        DeltaPatchErrorKind.malformed,
        '载荷长度不符：命令声明 $literalTotal，实际 ${payload.length}',
      );
    }

    return DeltaPatch._(
      formatVersion: version,
      avgBits: view.getUint8(5),
      minChunk: view.getUint32(6),
      maxChunk: view.getUint32(10),
      baseSize: baseSize,
      targetSize: targetSize,
      baseSha256: baseSha,
      targetSha256: targetSha,
      commands: commands,
      payload: payload,
    );
  }

  /// 解析一份 gzip 压缩的补丁文件内容。
  factory DeltaPatch.parseGzipped(Uint8List packed) {
    try {
      return DeltaPatch.parse(Uint8List.fromList(gzip.decode(packed)));
    } on DeltaPatchException {
      rethrow;
    } catch (error) {
      throw DeltaPatchException(
        DeltaPatchErrorKind.malformed,
        '补丁解压失败：$error',
      );
    }
  }

  /// 用 [basePath] 指向的本地包合成新包，写到 [outputPath]。
  ///
  /// 全程流式读写：基础包按需 `setPosition` 读取，产物顺序写出，
  /// 内存里只留补丁载荷本身（生成端会保证它不超过目标的 60%）。
  Future<DeltaApplyReport> apply({
    required String basePath,
    required String outputPath,
  }) async {
    final started = DateTime.now();
    final baseFile = File(basePath);
    if (!baseFile.existsSync()) {
      throw DeltaPatchException(
        DeltaPatchErrorKind.baseMismatch,
        '找不到本地基础包：$basePath',
      );
    }
    final baseBytes = baseFile.lengthSync();
    if (baseBytes != baseSize) {
      throw DeltaPatchException(
        DeltaPatchErrorKind.baseMismatch,
        '基础包大小不符：期望 $baseSize，实际 $baseBytes',
      );
    }
    final actualBaseSha = await sha256OfFile(basePath);
    if (actualBaseSha != baseSha256) {
      throw DeltaPatchException(
        DeltaPatchErrorKind.baseMismatch,
        '基础包指纹不符：期望 $baseSha256，实际 $actualBaseSha',
      );
    }

    final output = File(outputPath);
    await output.parent.create(recursive: true);
    RandomAccessFile? source;
    RandomAccessFile? sink;
    try {
      source = await baseFile.open();
      sink = await output.open(mode: FileMode.write);
      var payloadCursor = 0;
      // 64 KiB 的搬运缓冲区：既够大而减少系统调用，又不至于占内存。
      final buffer = Uint8List(64 * 1024);

      for (final command in commands) {
        switch (command) {
          case DeltaCopyBase(:final offset, :final length):
            var remaining = length;
            var position = offset;
            while (remaining > 0) {
              final want = remaining < buffer.length ? remaining : buffer.length;
              await source.setPosition(position);
              final got = await source.readInto(buffer, 0, want);
              if (got != want) {
                throw DeltaPatchException(
                  DeltaPatchErrorKind.baseMismatch,
                  '读取基础包失败：期望 $want 字节，实际 $got',
                );
              }
              await sink.writeFrom(buffer, 0, got);
              position += got;
              remaining -= got;
            }
          case DeltaCopyLiteral(:final length):
            if (payloadCursor + length > _payload.length) {
              throw const DeltaPatchException(
                DeltaPatchErrorKind.malformed,
                '读取载荷越界',
              );
            }
            // 注意 `writeFrom(list, start, end)` 的第三个参数是**下标 end**，
            // 不是长度。写成 `writeFrom(_payload, payloadCursor, length)` 时
            // 第一条命令（cursor=0）恰好正确，第二条就会变成
            // start 大于 end 而抛 RangeError——这类"只有多条命令才暴露"的
            // 错误最容易漏，补丁里同时含多段新内容时才会现形。
            await sink.writeFrom(_payload, payloadCursor, payloadCursor + length);
            payloadCursor += length;
        }
      }
      await sink.flush();
      await sink.close();
      sink = null;
    } on DeltaPatchException {
      rethrow;
    } catch (error) {
      throw DeltaPatchException(
        DeltaPatchErrorKind.io,
        '合成过程中读写失败：$error',
      );
    } finally {
      await source?.close();
      await sink?.close();
    }

    final produced = output.lengthSync();
    if (produced != targetSize) {
      throw DeltaPatchException(
        DeltaPatchErrorKind.targetMismatch,
        '合成结果大小不符：期望 $targetSize，实际 $produced',
      );
    }
    final producedSha = await sha256OfFile(outputPath);
    if (producedSha != targetSha256) {
      // 走到这里说明补丁或基础包有一方不可信。绝不能把这份文件拿去安装——
      // 装上去的会是个签名对不上的包，系统会直接拒绝。
      throw DeltaPatchException(
        DeltaPatchErrorKind.targetMismatch,
        '合成结果指纹校验失败：期望 $targetSha256，实际 $producedSha',
      );
    }

    return DeltaApplyReport(
      baseBytes: baseBytes,
      targetBytes: produced,
      targetSha256: producedSha,
      commandCount: commands.length,
      literalBytes: literalBytes,
      reusedBytes: reusedBytes,
      elapsed: DateTime.now().difference(started),
    );
  }

  static String _hex(Uint8List bytes, int start, int length) {
    final buffer = StringBuffer();
    for (var i = start; i < start + length; i++) {
      buffer.write(bytes[i].toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }
}

/// 流式计算文件 SHA-256（小写十六进制）。
///
/// 用 `bind` 而不是把整个文件读进内存：APK 有二十多兆，
/// 在低端机上一次性读进来是有可能被系统杀掉的。
Future<String> sha256OfFile(String path) async {
  final digest = await sha256.bind(File(path).openRead()).first;
  return digest.toString();
}
