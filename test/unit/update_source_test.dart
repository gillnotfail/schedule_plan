import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_plan/data/services/update_service.dart';

/// 「更新从哪台机器上取」这件事的落点（用户规格第 22 轮）。
///
/// 两条都是会**悄悄**退化的规则：
///   1. 清单地址的顺序与条数。排错了不会报错、不会红，只会在国内手机上表现为
///      "检查更新一直失败"——而写这个顺序的人手上往往挂着代理，本地怎么试都是通的。
///   2. 下载地址的来源归类。它只影响日志，但老师报"下载不动"时，
///      日志里分辨不出走的是哪条来路，这一趟就白记了。
///
/// 两者的共同点是"错了也能跑"，所以必须在测试里钉住。
void main() {
  /// 一份最小的可用清单。[content] 之外的东西都不影响解析。
  String manifestJson({int versionCode = 5, String versionName = '1.0.4'}) {
    return jsonEncode(<String, Object?>{
      'schemaVersion': 1,
      'assetsBase': 'https://gitee.com/jeo-xie/schedule_plan/releases/download',
      'releases': <Object?>[
        <String, Object?>{
          'versionCode': versionCode,
          'versionName': versionName,
          'tag': 'v$versionName',
          'notes': <String>['改了点东西'],
          'assets': <Object?>[
            <String, Object?>{
              'abi': 'arm64-v8a',
              'file': 'app-arm64-v8a-release.apk',
              'size': 24000000,
              'sha256': List<String>.filled(64, 'a').join(),
            },
          ],
        },
      ],
    });
  }

  group('UpdateService.manifestUrls', () {
    test('Gitee 三种写法在最前，GitHub raw 第四，jsDelivr 三个域名收尾', () {
      final urls = UpdateService.manifestUrls(
        const <String>[],
        epochSeconds: 100,
      );
      expect(urls, hasLength(7));
      expect(
        urls[0],
        'https://gitee.com/jeo-xie/schedule_plan/raw/main/updates/latest.json'
        '?t=100',
      );
      // 绕开 raw 子域的那条：Gitee 的 raw 会 302 到 raw.giteeusercontent.com，
      // 有些网络只放行 gitee.com 正域。这条必须存在，且必须排在前面。
      expect(
        urls[1],
        'https://gitee.com/api/v5/repos/jeo-xie/schedule_plan/contents/'
        'updates/latest.json?ref=main',
      );
      // 不带 query 的同一条 raw：用于绕开 Gitee 对密集 raw 请求的 451 风控
      expect(
        urls[2],
        'https://gitee.com/jeo-xie/schedule_plan/raw/main/updates/latest.json',
      );
      expect(
        urls[3],
        'https://raw.githubusercontent.com/gillnotfail/schedule_plan/main/'
        'updates/latest.json',
      );
      expect(
        urls.sublist(4),
        <String>[
          'https://cdn.jsdelivr.net/gh/gillnotfail/schedule_plan@main/'
              'updates/latest.json',
          'https://fastly.jsdelivr.net/gh/gillnotfail/schedule_plan@main/'
              'updates/latest.json',
          'https://gcore.jsdelivr.net/gh/gillnotfail/schedule_plan@main/'
              'updates/latest.json',
        ],
      );
    });

    test('镜像前缀只往后加，不动前七条的顺序', () {
      final urls = UpdateService.manifestUrls(
        const <String>['https://a/', 'https://b/'],
        epochSeconds: 100,
      );
      expect(urls, hasLength(21));
      // 前七条必须原样不动：镜像服务本身也可能挂，不能让它们挡在前面。
      expect(urls.take(7).any((url) => url.startsWith('https://a/')), isFalse);
      expect(urls[7], startsWith('https://a/'));
      expect(urls[14], startsWith('https://b/'));
    });

    test('Gitee 那条带时间戳，绕开它自己的 CDN 缓存', () {
      final first =
          UpdateService.manifestUrls(const <String>[], epochSeconds: 1).first;
      final second =
          UpdateService.manifestUrls(const <String>[], epochSeconds: 2).first;
      expect(first, isNot(second), reason: '两次取到的地址必须不同，否则缓存会一直命中');
      expect(first, startsWith('https://gitee.com/'));
    });
  });

  group('probeLabelOf', () {
    test('三种 Gitee 写法能分辨，jsDelivr 三个域名分开报', () {
      expect(
        UpdateService.probeLabelOf('https://gitee.com/a/b/raw/main/x.json?t=1'),
        'gitee',
      );
      expect(
        UpdateService.probeLabelOf('https://gitee.com/api/v5/repos/a/b/contents/x.json'),
        'gitee-api',
      );
      expect(
        UpdateService.probeLabelOf('https://raw.githubusercontent.com/a/b/main/x.json'),
        'github',
      );
      expect(UpdateService.probeLabelOf('https://cdn.jsdelivr.net/gh/a/b@main/x.json'), 'cdn');
      expect(
        UpdateService.probeLabelOf('https://fastly.jsdelivr.net/gh/a/b@main/x.json'),
        'fastly',
      );
      expect(
        UpdateService.probeLabelOf('https://gcore.jsdelivr.net/gh/a/b@main/x.json'),
        'gcore',
      );
    });
  });

  group('parseManifestBody', () {
    test('raw 那种直接给清单的，原样解析', () {
      final manifest = UpdateService.parseManifestBody(manifestJson());
      expect(manifest, isNotNull);
      expect(manifest!.assetsBase, contains('gitee.com'));
      expect(manifest.releases.single.versionCode, 5);
      expect(manifest.releases.single.notes, <String>['改了点东西']);
    });

    test('Gitee 内容 API 包了一层 base64，也要认', () {
      final wrapped = jsonEncode(<String, Object?>{
        'encoding': 'base64',
        'content': base64Encode(utf8.encode(manifestJson())),
      });
      final manifest = UpdateService.parseManifestBody(wrapped);
      expect(manifest, isNotNull, reason: '这条兜底就是为绕开 raw 子域存在的');
      expect(manifest!.releases.single.versionName, '1.0.4');
    });

    test('Gitee 的 base64 会按行折断，换行不影响解码', () {
      final raw = base64Encode(utf8.encode(manifestJson()));
      final folded = <String>[
        for (var i = 0; i < raw.length; i += 60)
          raw.substring(i, i + 60 > raw.length ? raw.length : i + 60),
      ].join('\n');
      final manifest = UpdateService.parseManifestBody(
        jsonEncode(<String, Object?>{'encoding': 'base64', 'content': folded}),
      );
      expect(manifest, isNotNull);
      expect(manifest!.releases.single.versionCode, 5);
    });

    test('不是 JSON、不是清单、也不是 base64 包装，一律返回 null', () {
      expect(UpdateService.parseManifestBody('<html>登录</html>'), isNull);
      expect(UpdateService.parseManifestBody('{"foo":1}'), isNull);
      expect(
        UpdateService.parseManifestBody('{"encoding":"base64","content":"%%%"}'),
        isNull,
      );
      // 没有 assets 的版本等于装不了，整份清单作废（见 AppRelease.tryParse）
      expect(
        UpdateService.parseManifestBody(
          '{"schemaVersion":1,"releases":[{"versionCode":9,'
          '"versionName":"9.9.9"}]}',
        ),
        isNull,
      );
    });
  });

  group('ManifestFetchResult', () {
    test('没连上时 reachedServer 为假，连上但内容不认时为真', () {
      const offline = ManifestFetchResult(
        manifest: null,
        attempts: <String, String>{'gitee': '超时', 'github': '握手失败'},
        reachedServer: false,
      );
      expect(offline.reachedServer, isFalse);
      expect(offline.summary, 'gitee 超时 · github 握手失败');

      const wrongBody = ManifestFetchResult(
        manifest: null,
        attempts: <String, String>{'gitee-api': '内容不可用'},
        reachedServer: true,
      );
      expect(wrongBody.reachedServer, isTrue);
    });

    test('源太多时只列四条，其余折成「另 N 条」', () {
      const many = ManifestFetchResult(
        manifest: null,
        attempts: <String, String>{
          'gitee': '451',
          'gitee-api': '超时',
          'github': '超时',
          'cdn': '超时',
          'fastly': '超时',
        },
        reachedServer: false,
      );
      expect(many.summary, 'gitee 451 · gitee-api 超时 · github 超时 · cdn 超时 · 另 1 条');
    });
  });

  group('shortErrorOf', () {
    test('压成两个字，用户看得懂', () {
      expect(UpdateService.shortErrorOf(const SocketException('x')), '连不上');
      expect(UpdateService.shortErrorOf(const HandshakeException('x')), '握手失败');
      expect(UpdateService.shortErrorOf(const FormatException('x')), '地址无效');
    });
  });

  group('sourceLabelOf', () {
    test('认得清单里那几个源', () {
      expect(sourceLabelOf('https://gitee.com/a/b/raw/main/x.json'), 'Gitee');
      expect(
        sourceLabelOf('https://raw.githubusercontent.com/a/b/main/x.json'),
        'GitHub',
      );
      expect(sourceLabelOf('https://github.com/a/b/releases/download/v1/x'), 'GitHub');
      expect(
        sourceLabelOf('https://cdn.jsdelivr.net/gh/a/b@main/x.json'),
        'jsDelivr',
      );
    });

    test('认不出就退回域名，代理前缀不会被误判成 Gitee', () {
      // 镜像前缀把别人的域名套在前面，所以只能按 host 判，不能按子串判。
      expect(
        sourceLabelOf('https://ghproxy.example/https://gitee.com/a/b/raw/main'),
        'ghproxy.example',
      );
      expect(sourceLabelOf('not a url'), 'not a url');
    });
  });
}
