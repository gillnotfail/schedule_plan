import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_plan/data/models/app_release.dart';

/// 应用内更新清单的解析与取舍决策。
///
/// 这一层是纯函数，所以"清单不合法怎么办、分差该不该用、跨太多版本要不要
/// 禁用分差"这些判断全都能在这里锁死——它们是发布链路里最容易悄悄退化的
/// 部分：代码改错了不会报错，只会在某台旧手机上默默下整包或者装错包。
///
/// 用相邻字符串字面量拼 64 位十六进制串：Dart 没有字符串乘法，
/// 手写 64 个字符又极易数错（少一位 `isSha256` 就返回 false，
/// 而失败信息只会说"清单不可用"，很难看出是自己的测试数据写错了）。

const String _shaBase = 'aaaaaaaaaaaaaaaa'
    'aaaaaaaaaaaaaaaa'
    'aaaaaaaaaaaaaaaa'
    'aaaaaaaaaaaaaaaa';
const String _shaBaseUpper = 'AAAAAAAAAAAAAAAA'
    'AAAAAAAAAAAAAAAA'
    'AAAAAAAAAAAAAAAA'
    'AAAAAAAAAAAAAAAA';
const String _shaOther = 'bbbbbbbbbbbbbbbb'
    'bbbbbbbbbbbbbbbb'
    'bbbbbbbbbbbbbbbb'
    'bbbbbbbbbbbbbbbb';
const String _shaPatch = 'cccccccccccccccc'
    'cccccccccccccccc'
    'cccccccccccccccc'
    'cccccccccccccccc';
const String _shaMixed = '0123456789abcdef'
    '0123456789abcdef'
    '0123456789abcdef'
    '0123456789abcdef';

const int _apkSize = 24000000;

Map<String, Object?> assetJson({
  String abi = 'arm64-v8a',
  String file = 'app-arm64-v8a-release.apk',
  Object? size = _apkSize,
  Object? sha256 = _shaBase,
  Object? url,
}) =>
    <String, Object?>{
      'abi': abi,
      'file': file,
      'size': size,
      'sha256': sha256,
      'url': ?url,
    };

Map<String, Object?> deltaJson({
  Object? fromVersionCode = 1,
  String abi = 'arm64-v8a',
  String file = 'patch-1-2-arm64-v8a.spdp',
  Object? size = 300000,
  Object? targetSize = _apkSize,
  Object? sha256 = _shaPatch,
  Object? baseSha256 = _shaBase,
  Object? url,
}) =>
    <String, Object?>{
      'fromVersionCode': fromVersionCode,
      'abi': abi,
      'file': file,
      'size': size,
      'targetSize': targetSize,
      'sha256': sha256,
      'baseSha256': baseSha256,
      'url': ?url,
    };

Map<String, Object?> releaseJson({
  int versionCode = 2,
  String versionName = '1.0.1',
  Object? tag,
  List<Object?>? assets,
  List<Object?>? deltas,
  List<Object?>? notes,
}) =>
    <String, Object?>{
      'versionCode': versionCode,
      'versionName': versionName,
      'tag': ?tag,
      // 默认值里刻意混入空白串、空串和非字符串：它们都该被丢掉。
      'notes': notes ?? <Object?>[' 改了标题栏 ', '', '   ', 42, '修了考勤圆环'],
      'assets': assets ?? <Object?>[assetJson()],
      'deltas': deltas ?? <Object?>[deltaJson()],
    };

String manifestBody({
  Object? schemaVersion = 1,
  Object? assetsBase = 'https://example.com/releases/download',
  Object? assetsBases,
  Object? minSupportedVersionCode = 1,
  Object? releases,
}) =>
    jsonEncode(<String, Object?>{
      'schemaVersion': schemaVersion,
      'assetsBase': assetsBase,
      // 老清单没有这个字段，所以只有显式传了才写进去——默认那份必须是
      // "只有单数 assetsBase"的形态，兼容性才真的被测到。
      'assetsBases': ?assetsBases,
      'minSupportedVersionCode': minSupportedVersionCode,
      'releases': releases ?? <Object?>[releaseJson()],
    });

/// 解析失败的便捷断言：`null` 就是"这份清单不可用"。
void expectUnusable(String body) {
  expect(UpdateManifest.tryParse(body), isNull, reason: body);
}

void main() {
  group('isSha256', () {
    test('接受 64 位十六进制（大小写都行）', () {
      expect(isSha256(_shaBase), isTrue);
      expect(isSha256(_shaBaseUpper), isTrue);
      expect(isSha256(_shaMixed), isTrue);
    });

    test('长度、字符不对就拒绝', () {
      expect(isSha256(''), isFalse);
      expect(isSha256('${_shaBase}0'), isFalse); // 65 位
      expect(isSha256(_shaBase.substring(1)), isFalse); // 63 位
      expect(isSha256('${_shaBase.substring(0, 63)}z'), isFalse); // 非十六进制
      expect(isSha256('g' 'ggggggggggggggg'), isFalse); // 太短且非十六进制
    });
  });

  group('formatBytes', () {
    test('按 1024 进位并挑选可读单位', () {
      expect(formatBytes(0), '0 B');
      expect(formatBytes(512), '512 B');
      expect(formatBytes(1024), '1.0 KB');
      expect(formatBytes(1500), '1.5 KB');
      expect(formatBytes(_apkSize), '23 MB');
      expect(formatBytes(1073741824), '1.0 GB');
    });

    test('小于 10 保留一位小数，大于等于 10 取整', () {
      // 两种写法混着来，用户看到的才是"1.1 MB / 19 MB"这种自然读法，
      // 而不是"1 MB / 19.0 MB"。
      expect(formatBytes(1200000), '1.1 MB');
      expect(formatBytes(20000000), '19 MB');
    });
  });

  group('UpdateManifest.tryParse · 不可用的清单', () {
    test('非法 JSON', () {
      expectUnusable('这根本不是 json');
      expectUnusable('{');
    });

    test('根不是对象', () {
      expectUnusable('[]');
      expectUnusable('"字符串"');
      expectUnusable('123');
    });

    test('schemaVersion 缺失或更高版本', () {
      expectUnusable(manifestBody(schemaVersion: null));
      expectUnusable(manifestBody(schemaVersion: 'abc'));
      // 生成端用了本 App 不认识的说法 —— 宁可当作没拿到，也不能瞎猜。
      expectUnusable(manifestBody(
        schemaVersion: UpdateManifest.supportedSchemaVersion + 1,
      ));
    });

    test('releases 不是列表、为空、或全部不可用', () {
      expectUnusable(manifestBody(releases: 'nope'));
      expectUnusable(manifestBody(releases: <Object?>[]));
      // 元素不是对象
      expectUnusable(manifestBody(releases: <Object?>['x', 7]));
      // 缺 versionCode / versionName
      expectUnusable(manifestBody(releases: <Object?>[
        <String, Object?>{
          'versionName': '1.0.1',
          'assets': <Object?>[assetJson()],
        },
      ]));
      // 一个可校验的包都没有
      expectUnusable(manifestBody(releases: <Object?>[
        releaseJson(assets: <Object?>[
          assetJson(sha256: null),
          assetJson(size: 0),
        ]),
      ]));
    });

    test('assets 字段缺失也算不可用', () {
      expectUnusable(manifestBody(releases: <Object?>[
        <String, Object?>{'versionCode': 2, 'versionName': '1.0.1'},
      ]));
    });
  });

  group('UpdateManifest.tryParse · 正常路径', () {
    test('解析出基础字段并保留 notes', () {
      final manifest = UpdateManifest.tryParse(manifestBody())!;
      expect(manifest.schemaVersion, 1);
      expect(manifest.assetsBase, 'https://example.com/releases/download');
      expect(manifest.minSupportedVersionCode, 1);
      expect(manifest.releases, hasLength(1));

      final release = manifest.latest!;
      expect(release.versionCode, 2);
      expect(release.versionName, '1.0.1');
      // 空白串、空串、非字符串都被剔除，留下的还做了 trim。
      expect(release.notes, <String>['改了标题栏', '修了考勤圆环']);
    });

    test('tag 缺省时按版本名补一个', () {
      expect(UpdateManifest.tryParse(manifestBody())!.latest!.tag, 'v1.0.1');
      expect(
        UpdateManifest.tryParse(
          manifestBody(releases: <Object?>[releaseJson(tag: 'v1.0.1-rc1')]),
        )!.latest!.tag,
        'v1.0.1-rc1',
      );
    });

    test('清单被手改乱了顺序也能兜回"最新在最前"', () {
      final manifest = UpdateManifest.tryParse(manifestBody(releases: <Object?>[
        releaseJson(versionCode: 3, versionName: '1.0.2'),
        releaseJson(versionCode: 9, versionName: '1.1.0'),
        releaseJson(versionCode: 5, versionName: '1.0.3'),
      ]))!;
      expect(manifest.releases.map((r) => r.versionCode), <int>[9, 5, 3]);
      expect(manifest.latest!.versionName, '1.1.0');
    });

    test('缺 sha256 的 asset 被丢掉，但不影响同版本其它 asset', () {
      final manifest = UpdateManifest.tryParse(manifestBody(releases: <Object?>[
        releaseJson(assets: <Object?>[
          assetJson(sha256: null),
          assetJson(abi: 'armeabi-v7a', file: 'app-armeabi-v7a-release.apk'),
        ]),
      ]))!;
      final release = manifest.latest!;
      expect(release.assets, hasLength(1));
      expect(release.assets.single.abi, 'armeabi-v7a');
    });

    test('minSupportedVersionCode 缺省为 0', () {
      final manifest = UpdateManifest.tryParse(
          manifestBody(minSupportedVersionCode: null))!;
      expect(manifest.minSupportedVersionCode, 0);
    });

    test('releasesAfter 返回全部比它新的版本', () {
      final manifest = UpdateManifest.tryParse(manifestBody(releases: <Object?>[
        releaseJson(versionCode: 2, versionName: '1.0.1'),
        releaseJson(versionCode: 3, versionName: '1.0.2'),
        releaseJson(versionCode: 4, versionName: '1.0.3'),
      ]))!;
      // 用户装的是 1.0.0(1)：中间跳过的 1.0.1 / 1.0.2 的说明也该看到。
      expect(manifest.releasesAfter(1).map((r) => r.versionName),
          <String>['1.0.3', '1.0.2', '1.0.1']);
      expect(
          manifest.releasesAfter(3).map((r) => r.versionName), <String>['1.0.3']);
      expect(manifest.releasesAfter(4), isEmpty);
    });
  });

  group('UpdatePlan.plan', () {
    UpdateManifest manifestWithDelta(Object? deltaSize) =>
        UpdateManifest.tryParse(manifestBody(releases: <Object?>[
          releaseJson(deltas: <Object?>[deltaJson(size: deltaSize)]),
        ]))!;

    test('没有更新版本就返回 null', () {
      final manifest = UpdateManifest.tryParse(manifestBody())!;
      expect(
        manifest.plan(
            currentVersionCode: 2,
            currentVersionName: '1.0.1',
            abi: 'arm64-v8a'),
        isNull,
      );
      expect(
        manifest.plan(
            currentVersionCode: 9,
            currentVersionName: '9.9.9',
            abi: 'arm64-v8a'),
        isNull,
      );
    });

    test('本 ABI 没有包时不硬塞别的架构的包', () {
      final manifest = UpdateManifest.tryParse(manifestBody())!;
      expect(
        manifest.plan(
            currentVersionCode: 1,
            currentVersionName: '1.0.0',
            abi: 'x86_64'),
        isNull,
      );
    });

    test('拿不到本机包指纹时只走整包', () {
      final manifest = manifestWithDelta(300000);
      final plan = manifest.plan(
        currentVersionCode: 1,
        currentVersionName: '1.0.0',
        abi: 'arm64-v8a',
      )!;
      expect(plan.usesDelta, isFalse);
      expect(plan.downloadBytes, _apkSize);
      expect(plan.savedRatio, 0);
    });

    test('补丁指纹对不上就走整包', () {
      final manifest = manifestWithDelta(300000);
      final plan = manifest.plan(
        currentVersionCode: 1,
        currentVersionName: '1.0.0',
        abi: 'arm64-v8a',
        baseApkSha256: _shaOther,
      )!;
      expect(plan.usesDelta, isFalse);
    });

    test('补丁的 fromVersionCode 对不上就走整包', () {
      final manifest = UpdateManifest.tryParse(manifestBody(releases: <Object?>[
        releaseJson(deltas: <Object?>[deltaJson(fromVersionCode: 7)]),
      ]))!;
      final plan = manifest.plan(
        currentVersionCode: 1,
        currentVersionName: '1.0.0',
        abi: 'arm64-v8a',
        baseApkSha256: _shaBase,
      )!;
      expect(plan.usesDelta, isFalse);
    });

    test('baseSha256 大小写不敏感', () {
      final manifest = manifestWithDelta(300000);
      final plan = manifest.plan(
        currentVersionCode: 1,
        currentVersionName: '1.0.0',
        abi: 'arm64-v8a',
        // 补丁里记的是小写，设备算出来可能是大写：必须照样认账，
        // 否则用户莫名其妙被降级成下整包。
        baseApkSha256: _shaBaseUpper,
      )!;
      expect(plan.usesDelta, isTrue);
    });

    test('补丁够小就用分差，并算清省了多少', () {
      final manifest = manifestWithDelta(300000);
      final plan = manifest.plan(
        currentVersionCode: 1,
        currentVersionName: '1.0.0',
        abi: 'arm64-v8a',
        baseApkSha256: _shaBase,
      )!;
      expect(plan.usesDelta, isTrue);
      expect(plan.downloadBytes, 300000);
      expect(plan.fullBytes, _apkSize);
      expect(plan.savedRatio, closeTo(1 - 300000 / _apkSize, 1e-9));
      expect(plan.changelog, hasLength(1));
    });

    test('补丁省得不够就退回整包：恰好等于阈值不放行', () {
      final threshold = (_apkSize * UpdateManifest.deltaWorthwhileRatio).toInt();
      // 边界必须是"小于"而不是"小于等于"，否则刚好九折的补丁也会被用上。
      expect(
        manifestWithDelta(threshold)
            .plan(
              currentVersionCode: 1,
              currentVersionName: '1.0.0',
              abi: 'arm64-v8a',
              baseApkSha256: _shaBase,
            )!
            .usesDelta,
        isFalse,
      );
      expect(
        manifestWithDelta(threshold - 1)
            .plan(
              currentVersionCode: 1,
              currentVersionName: '1.0.0',
              abi: 'arm64-v8a',
              baseApkSha256: _shaBase,
            )!
            .usesDelta,
        isTrue,
      );
    });

    test('版本太老时禁用分差，并标出原因', () {
      final manifest = UpdateManifest.tryParse(manifestBody(
        minSupportedVersionCode: 5,
        releases: <Object?>[
          releaseJson(deltas: <Object?>[deltaJson(size: 300000)]),
        ],
      ))!;
      final plan = manifest.plan(
        currentVersionCode: 1,
        currentVersionName: '1.0.0',
        abi: 'arm64-v8a',
        baseApkSha256: _shaBase,
      )!;
      expect(plan.deltaBlockedByAge, isTrue);
      expect(plan.usesDelta, isFalse);
      expect(plan.downloadBytes, _apkSize);
    });

    test('刚好等于最低支持版本时仍然给分差', () {
      final manifest = UpdateManifest.tryParse(manifestBody(
        minSupportedVersionCode: 1,
        releases: <Object?>[
          releaseJson(deltas: <Object?>[deltaJson(size: 300000)]),
        ],
      ))!;
      final plan = manifest.plan(
        currentVersionCode: 1,
        currentVersionName: '1.0.0',
        abi: 'arm64-v8a',
        baseApkSha256: _shaBase,
      )!;
      expect(plan.deltaBlockedByAge, isFalse);
      expect(plan.usesDelta, isTrue);
    });

    test('changelog 是"从我这版到最新"的全部版本', () {
      final manifest = UpdateManifest.tryParse(manifestBody(releases: <Object?>[
        releaseJson(versionCode: 2, versionName: '1.0.1'),
        releaseJson(versionCode: 3, versionName: '1.0.2'),
        releaseJson(versionCode: 4, versionName: '1.0.3', deltas: <Object?>[
          // 分差只针对"从 1.0.1(2) 升上来"，所以要的是 fromVersionCode=2 的那条。
          deltaJson(fromVersionCode: 2),
        ]),
      ]))!;
      final plan = manifest.plan(
        currentVersionCode: 2,
        currentVersionName: '1.0.1',
        abi: 'arm64-v8a',
        baseApkSha256: _shaBase,
      )!;
      expect(plan.latest.versionName, '1.0.3');
      expect(
          plan.changelog.map((r) => r.versionName), <String>['1.0.3', '1.0.2']);
      expect(plan.delta!.fromVersionCode, 2);
    });
  });

  group('下载地址', () {
    test('直连排第一，镜像依次兜底', () {
      final manifest = UpdateManifest.tryParse(manifestBody())!;
      final plan = manifest.plan(
        currentVersionCode: 1,
        currentVersionName: '1.0.0',
        abi: 'arm64-v8a',
        baseApkSha256: _shaBase,
        mirrorPrefixes: const <String>['https://a/', 'https://b/'],
      )!;
      expect(plan.candidateUrls(forDelta: false), <String>[
        'https://example.com/releases/download/v1.0.1/app-arm64-v8a-release.apk',
        'https://a/https://example.com/releases/download/v1.0.1/app-arm64-v8a-release.apk',
        'https://b/https://example.com/releases/download/v1.0.1/app-arm64-v8a-release.apk',
      ]);
    });

    test('没有镜像就只给直连', () {
      final manifest = UpdateManifest.tryParse(manifestBody())!;
      final plan = manifest.plan(
        currentVersionCode: 1,
        currentVersionName: '1.0.0',
        abi: 'arm64-v8a',
        baseApkSha256: _shaBase,
      )!;
      expect(plan.candidateUrls(forDelta: true), hasLength(1));
      expect(plan.candidateUrls(forDelta: true).single, endsWith('.spdp'));
    });

    test('清单里给了完整地址时优先用它', () {
      final manifest = UpdateManifest.tryParse(manifestBody(releases: <Object?>[
        releaseJson(assets: <Object?>[
          assetJson(url: 'https://cdn.example.com/custom.apk'),
        ]),
      ]))!;
      final plan = manifest.plan(
        currentVersionCode: 1,
        currentVersionName: '1.0.0',
        abi: 'arm64-v8a',
      )!;
      expect(plan.candidateUrls(forDelta: false), <String>[
        'https://cdn.example.com/custom.apk',
      ]);
    });
  });

  group('多下载源', () {
    const gitee = 'https://gitee.com/jeo-xie/schedule_plan/releases/download';
    const github =
        'https://github.com/gillnotfail/schedule_plan/releases/download';

    test('assetsBases 按清单顺序取用，Gitee 在前', () {
      final manifest = UpdateManifest.tryParse(
        manifestBody(assetsBases: <Object?>[gitee, github]),
      )!;
      expect(manifest.assetBaseList, <String>[gitee, github]);
    });

    test('没有 assetsBases 的老清单退回单数 assetsBase', () {
      final manifest = UpdateManifest.tryParse(manifestBody())!;
      expect(manifest.assetBaseList, <String>[
        'https://example.com/releases/download',
      ]);
      // 单数字段本身仍要原样读出来：它服务的正是只会读它的老客户端。
      expect(manifest.assetsBase, 'https://example.com/releases/download');
    });

    test('assetsBases 里的空串与非字符串被剔掉', () {
      final manifest = UpdateManifest.tryParse(
        manifestBody(assetsBases: <Object?>[gitee, '', '  ', 42, null, github]),
      )!;
      expect(manifest.assetBaseList, <String>[gitee, github]);
    });

    test('assetsBases 全部不可用时退回单数 assetsBase', () {
      final manifest = UpdateManifest.tryParse(
        manifestBody(assetsBases: <Object?>['', 42]),
      )!;
      expect(manifest.assetBaseList, <String>[
        'https://example.com/releases/download',
      ]);
    });

    test('候选地址按源顺序排列，镜像前缀排最后', () {
      final manifest = UpdateManifest.tryParse(
        manifestBody(assetsBases: <Object?>[gitee, github]),
      )!;
      final plan = manifest.plan(
        currentVersionCode: 1,
        currentVersionName: '1.0.0',
        abi: 'arm64-v8a',
        mirrorPrefixes: const <String>['https://ghproxy.example/'],
      )!;
      expect(plan.candidateUrls(forDelta: false), <String>[
        '$gitee/v1.0.1/app-arm64-v8a-release.apk',
        '$github/v1.0.1/app-arm64-v8a-release.apk',
        'https://ghproxy.example/$gitee/v1.0.1/app-arm64-v8a-release.apk',
        'https://ghproxy.example/$github/v1.0.1/app-arm64-v8a-release.apk',
      ]);
    });

    test('分差补丁走同一套源顺序', () {
      final manifest = UpdateManifest.tryParse(
        manifestBody(assetsBases: <Object?>[gitee, github]),
      )!;
      final plan = manifest.plan(
        currentVersionCode: 1,
        currentVersionName: '1.0.0',
        abi: 'arm64-v8a',
        baseApkSha256: _shaBase,
      )!;
      expect(plan.usesDelta, isTrue);
      expect(plan.candidateUrls(forDelta: true), <String>[
        '$gitee/v1.0.1/patch-1-2-arm64-v8a.spdp',
        '$github/v1.0.1/patch-1-2-arm64-v8a.spdp',
      ]);
    });

    test('条目自带完整地址时唯一来路，不再套镜像前缀', () {
      final manifest = UpdateManifest.tryParse(manifestBody(
        assetsBases: <Object?>[gitee, github],
        releases: <Object?>[
          releaseJson(assets: <Object?>[
            assetJson(url: 'https://cdn.example.com/custom.apk'),
          ]),
        ],
      ))!;
      final plan = manifest.plan(
        currentVersionCode: 1,
        currentVersionName: '1.0.0',
        abi: 'arm64-v8a',
        mirrorPrefixes: const <String>['https://ghproxy.example/'],
      )!;
      expect(plan.candidateUrls(forDelta: false), <String>[
        'https://cdn.example.com/custom.apk',
      ]);
    });
  });

  group('deltaFor', () {
    test('三个条件都满足才命中', () {
      final release = AppRelease.tryParse(releaseJson())!;
      expect(
        release.deltaFor(
            fromVersionCode: 1, abi: 'arm64-v8a', baseSha256: _shaBase),
        isNotNull,
      );
      expect(
        release.deltaFor(
            fromVersionCode: 1, abi: 'arm64-v8a', baseSha256: _shaBaseUpper),
        isNotNull,
        reason: '大小写不敏感',
      );
      expect(
        release.deltaFor(
            fromVersionCode: 2, abi: 'arm64-v8a', baseSha256: _shaBase),
        isNull,
      );
      expect(
        release.deltaFor(
            fromVersionCode: 1, abi: 'armeabi-v7a', baseSha256: _shaBase),
        isNull,
      );
      expect(
        release.deltaFor(
            fromVersionCode: 1, abi: 'arm64-v8a', baseSha256: _shaOther),
        isNull,
      );
    });

    test('缺 targetSize 或指纹的补丁条目被丢弃', () {
      final release = AppRelease.tryParse(releaseJson(deltas: <Object?>[
        deltaJson(targetSize: null),
        deltaJson(sha256: 'not-a-sha'),
        deltaJson(baseSha256: null),
        deltaJson(size: 0),
      ]))!;
      expect(release.deltas, isEmpty);
    });
  });
}
