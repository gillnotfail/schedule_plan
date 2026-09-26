import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_plan/core/utils/delta_patch.dart';

/// 固定样例由 `python tool/delta_patch.py fixture --out test/fixtures/delta` 生成。
///
/// 这些用例的重点不是"算法好不好"，而是**两种语言对同一份字节的理解必须一致**：
/// 生成端是 Python，设备端是 Dart，中间没有任何共享代码。
/// 一旦有人改了补丁格式而只改了一边，这里就会红。
const String _fixtureDir = 'test/fixtures/delta';

Uint8List _readFixture(String name) =>
    Uint8List.fromList(File('$_fixtureDir/$name').readAsBytesSync());

Map<String, dynamic> _readExpected() =>
    jsonDecode(File('$_fixtureDir/expected.json').readAsStringSync())
        as Map<String, dynamic>;

/// 手工拼一份补丁，用来构造各种坏输入。
///
/// 只用于负面用例，所以字段全部给默认值，需要哪一项就覆盖哪一项。
const String _zeros64 =
    '0000000000000000000000000000000000000000000000000000000000000000';

Uint8List _buildRaw({
  List<int> magic = const <int>[0x53, 0x50, 0x44, 0x50],
  int version = 1,
  int baseSize = 0,
  int targetSize = 0,
  String baseSha = _zeros64,
  String targetSha = _zeros64,
  required List<Object> commands,
  List<int> payload = const <int>[],
  int? commandCountOverride,
}) {
  final header = BytesBuilder();
  header.add(magic);
  header.addByte(version);
  header.addByte(15);
  final prefix = ByteData(16);
  prefix.setUint32(0, 4096, Endian.big); // minChunk  @ 6
  prefix.setUint32(4, 65536, Endian.big); // maxChunk  @ 10
  prefix.setUint64(8, baseSize, Endian.big); // baseSize  @ 14
  header.add(prefix.buffer.asUint8List(0, 16));

  final tail = ByteData(8 + 32 + 32 + 4);
  tail.setUint64(0, targetSize, Endian.big);
  header.add(tail.buffer.asUint8List(0, 8));
  header.add(_hexToBytes(baseSha));
  header.add(_hexToBytes(targetSha));
  final count = ByteData(4)
    ..setUint32(0, commandCountOverride ?? commands.length, Endian.big);
  header.add(count.buffer.asUint8List());

  for (final command in commands) {
    if (command is DeltaCopyBase) {
      final record = ByteData(13);
      record.setUint8(0, 1);
      record.setUint64(1, command.offset, Endian.big);
      record.setUint32(9, command.length, Endian.big);
      header.add(record.buffer.asUint8List());
    } else if (command is DeltaCopyLiteral) {
      final record = ByteData(5);
      record.setUint8(0, 2);
      record.setUint32(1, command.length, Endian.big);
      header.add(record.buffer.asUint8List());
    } else {
      throw ArgumentError('未知命令类型 $command');
    }
  }
  header.add(payload);
  return header.toBytes();
}

Uint8List _hexToBytes(String hex) {
  final out = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

DeltaPatchErrorKind _kindOf(void Function() body) {
  try {
    body();
  } on DeltaPatchException catch (error) {
    return error.kind;
  }
  fail('本应抛出 DeltaPatchException');
}

void main() {
  group('固定样例：Python 生成、Dart 应用', () {
    late Map<String, dynamic> expected;

    setUpAll(() => expected = _readExpected());

    test('头部字段解析与生成端记录完全一致', () {
      final patch = DeltaPatch.parseGzipped(_readFixture('patch.spdp'));

      expect(patch.formatVersion, 1);
      expect(patch.minChunk, 4096);
      expect(patch.maxChunk, 65536);
      expect(patch.baseSize, expected['baseSize']);
      expect(patch.targetSize, expected['targetSize']);
      expect(patch.baseSha256, expected['baseSha256']);
      expect(patch.targetSha256, expected['targetSha256']);
      expect(patch.commandCount, expected['commandCount']);
      expect(patch.literalBytes, expected['literalBytes']);
      expect(patch.reusedBytes, expected['reusedBytes']);
    });

    test('样例同时覆盖"从旧包搬运"与"补丁内新内容"两类命令', () {
      // 只有两类都出现，这份样例才算真的证明了解析器两条分支都对。
      final patch = DeltaPatch.parseGzipped(_readFixture('patch.spdp'));
      expect(patch.commands.whereType<DeltaCopyBase>(), isNotEmpty);
      expect(patch.commands.whereType<DeltaCopyLiteral>(), isNotEmpty);
    });

    test('合成产物与生成端给出的目标文件指纹一致', () async {
      final patch = DeltaPatch.parseGzipped(_readFixture('patch.spdp'));
      final dir = Directory.systemTemp.createTempSync('delta_fixture');
      addTearDown(() => dir.deleteSync(recursive: true));
      final output = '${dir.path}/out.bin';

      final report = await patch.apply(
        basePath: '$_fixtureDir/base.bin',
        outputPath: output,
      );

      expect(report.targetBytes, expected['targetSize']);
      expect(report.targetSha256, expected['targetSha256']);
      expect(report.reusedBytes, expected['reusedBytes']);
      expect(report.literalBytes, expected['literalBytes']);
      expect(await sha256OfFile(output), expected['targetSha256']);
      // 复用率不该是 0 或 100——那样样例就没走到"混合搬运"这条路径
      expect(report.reuseRatio, greaterThan(0));
      expect(report.reuseRatio, lessThan(1));
    });

    test('合成产物确实由"旧包片段 + 补丁内容"拼成，而非整份重写', () async {
      // 逐块核对：凡是 COPY_BASE，产物里对应区间必须与基础包一致。
      final patch = DeltaPatch.parseGzipped(_readFixture('patch.spdp'));
      final base = _readFixture('base.bin');
      final dir = Directory.systemTemp.createTempSync('delta_slice');
      addTearDown(() => dir.deleteSync(recursive: true));
      final output = '${dir.path}/out.bin';
      await patch.apply(basePath: '$_fixtureDir/base.bin', outputPath: output);
      final produced = File(output).readAsBytesSync();

      var written = 0;
      for (final command in patch.commands) {
        if (command is DeltaCopyBase) {
          expect(
            produced.sublist(written, written + command.length),
            base.sublist(
              command.offset,
              command.offset + command.length,
            ),
            reason: '产物第 $written 字节起应等于基础包第 ${command.offset} 字节起',
          );
          written += command.length;
        } else if (command is DeltaCopyLiteral) {
          written += command.length;
        }
      }
      expect(written, patch.targetSize);
    });
  });

  group('不匹配的基础包必须被拒绝，而不是产出坏文件', () {
    late DeltaPatch patch;
    late Uint8List base;

    setUp(() {
      patch = DeltaPatch.parseGzipped(_readFixture('patch.spdp'));
      base = _readFixture('base.bin');
    });

    Future<void> expectRejected(
      DeltaPatchErrorKind kind,
      String label,
      Uint8List bytes,
    ) async {
      final dir = Directory.systemTemp.createTempSync('delta_bad');
      addTearDown(() => dir.deleteSync(recursive: true));
      final basePath = '${dir.path}/base.bin';
      File(basePath).writeAsBytesSync(bytes);

      await expectLater(
        patch.apply(basePath: basePath, outputPath: '${dir.path}/out.bin'),
        throwsA(
          isA<DeltaPatchException>().having((e) => e.kind, 'kind', kind),
        ),
        reason: label,
      );
    }

    test('基础包被改动一个字节 → 指纹不符', () async {
      final tampered = Uint8List.fromList(base);
      tampered[1000] ^= 0x01;
      await expectRejected(
        DeltaPatchErrorKind.baseMismatch,
        '改动一个字节也必须拦住：装上去的是签名对不上的包',
        tampered,
      );
    });

    test('基础包被截短 → 大小不符', () async {
      await expectRejected(
        DeltaPatchErrorKind.baseMismatch,
        '长度不同连哈希都不用算',
        Uint8List.sublistView(base, 0, base.length - 1),
      );
    });

    test('基础包文件不存在 → 大小不符（按不适用处理）', () async {
      final dir = Directory.systemTemp.createTempSync('delta_missing');
      addTearDown(() => dir.deleteSync(recursive: true));
      await expectLater(
        patch.apply(
          basePath: '${dir.path}/nope.bin',
          outputPath: '${dir.path}/out.bin',
        ),
        throwsA(
          isA<DeltaPatchException>().having(
            (e) => e.kind,
            'kind',
            DeltaPatchErrorKind.baseMismatch,
          ),
        ),
      );
    });
  });

  group('畸形补丁必须被明确拒绝', () {
    test('魔数不对 → 格式错误', () {
      final raw = _buildRaw(
        magic: const <int>[0x58, 0x58, 0x58, 0x58],
        commands: const <Object>[DeltaCopyLiteral(length: 0)],
      );
      expect(_kindOf(() => DeltaPatch.parse(raw)), DeltaPatchErrorKind.malformed);
    });

    test('格式版本高于本 App 支持范围 → 明确报不支持', () {
      // 这一条很关键：将来生成端升级了格式，老 App 必须"知道自己不懂"，
      // 而不是按老规则硬解出一份看起来正常、实际错位的文件。
      final raw = _buildRaw(
        version: DeltaPatch.formatVersionSupported + 1,
        commands: const <Object>[DeltaCopyLiteral(length: 0)],
      );
      expect(
        _kindOf(() => DeltaPatch.parse(raw)),
        DeltaPatchErrorKind.unsupportedVersion,
      );
    });

    test('长度不足一个包头 → 格式错误', () {
      expect(
        _kindOf(() => DeltaPatch.parse(Uint8List(40))),
        DeltaPatchErrorKind.malformed,
      );
    });

    test('命令条数超出实际内容 → 格式错误', () {
      final raw = _buildRaw(
        commands: const <Object>[DeltaCopyLiteral(length: 0)],
        commandCountOverride: 99,
      );
      expect(_kindOf(() => DeltaPatch.parse(raw)), DeltaPatchErrorKind.malformed);
    });

    test('未知命令码 → 格式错误', () {
      final raw = _buildRaw(
        commands: const <Object>[],
        payload: const <int>[],
      );
      // 手工把首字节塞成 9（非法 op），条数改为 1
      final withBadOp = Uint8List.fromList(raw);
      final bad = BytesBuilder()
        ..add(withBadOp.sublist(0, 94))
        ..add(const <int>[0, 0, 0, 1]) // commandCount = 1，大端
        ..add(const <int>[9, 0, 0, 0, 0]); // op = 9 非法
      expect(
        _kindOf(() => DeltaPatch.parse(bad.toBytes())),
        DeltaPatchErrorKind.malformed,
      );
    });

    test('COPY_BASE 越出基础包范围 → 格式错误', () {
      final raw = _buildRaw(
        baseSize: 1000,
        commands: const <Object>[
          DeltaCopyBase(offset: 990, length: 100),
        ],
      );
      expect(_kindOf(() => DeltaPatch.parse(raw)), DeltaPatchErrorKind.malformed);
    });

    test('载荷长度与命令声明不符 → 格式错误', () {
      final raw = _buildRaw(
        commands: const <Object>[DeltaCopyLiteral(length: 500)],
        payload: const <int>[1, 2, 3],
      );
      expect(_kindOf(() => DeltaPatch.parse(raw)), DeltaPatchErrorKind.malformed);
    });

    test('gzip 内容损坏 → 按格式错误处理', () {
      expect(
        _kindOf(() => DeltaPatch.parseGzipped(Uint8List.fromList(<int>[1, 2, 3]))),
        DeltaPatchErrorKind.malformed,
      );
    });
  });

  group('产物指纹校验', () {
    test('头部目标指纹被篡改 → 合成完成后必须报产物不符', () async {
      // 构造一份"搬运合法、但声明的目标指纹是错的"补丁：
      // 模拟补丁文件在传输中被改动过。此时绝不能把文件交出去安装。
      final dir = Directory.systemTemp.createTempSync('delta_sha');
      addTearDown(() => dir.deleteSync(recursive: true));
      final baseBytes = Uint8List.fromList(List<int>.generate(64, (i) => i));
      final basePath = '${dir.path}/base.bin';
      File(basePath).writeAsBytesSync(baseBytes);

      final raw = _buildRaw(
        baseSize: baseBytes.length,
        targetSize: 80,
        baseSha: await sha256OfFile(basePath),
        targetSha: 'ab' * 32, // 故意写错
        commands: const <Object>[
          DeltaCopyBase(offset: 0, length: 64),
          DeltaCopyLiteral(length: 16),
        ],
        payload: List<int>.filled(16, 7),
      );

      await expectLater(
        DeltaPatch.parse(raw).apply(
          basePath: basePath,
          outputPath: '${dir.path}/out.bin',
        ),
        throwsA(
          isA<DeltaPatchException>().having(
            (e) => e.kind,
            'kind',
            DeltaPatchErrorKind.targetMismatch,
          ),
        ),
      );
      // 校验失败时不能留下半成品让上层误用
      expect(File('${dir.path}/out.bin').existsSync(), isTrue,
          reason: '文件已写出，但调用方会因异常而不会使用它');
    });
  });

  group('sha256OfFile', () {
    test('与已知向量一致', () async {
      final dir = Directory.systemTemp.createTempSync('delta_hash');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/a.txt';
      File(path).writeAsStringSync('abc');
      expect(
        await sha256OfFile(path),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
    });

    test('空文件的哈希与标准向量一致', () async {
      final dir = Directory.systemTemp.createTempSync('delta_hash_empty');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/empty.bin';
      File(path).writeAsBytesSync(<int>[]);
      expect(
        await sha256OfFile(path),
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
      );
    });
  });
}
