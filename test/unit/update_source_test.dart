import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_plan/data/services/update_service.dart';

/// 「更新从哪台机器上取」这件事的落点（用户规格第 22 轮）。
///
/// 两条都是会**悄悄**退化的规则：
///   1. 清单地址的顺序（Gitee → GitHub raw → jsDelivr）。排错了不会报错、不会
///      红，只会在国内手机上表现为"检查更新一直失败"——而写这个顺序的人
///      手上往往挂着代理，本地怎么试都是通的。
///   2. 下载地址的来源归类。它只影响日志，但老师报"下载不动"时，
///      日志里分辨不出走的是哪条来路，这一趟就白记了。
///
/// 两者的共同点是"错了也能跑"，所以必须在测试里钉住。
void main() {
  group('UpdateService.manifestUrls', () {
    test('Gitee 第一、GitHub raw 第二、jsDelivr 最后', () {
      final urls = UpdateService.manifestUrls(
        const <String>[],
        epochSeconds: 100,
      );
      expect(urls, hasLength(3));
      expect(
        urls[0],
        'https://gitee.com/jeo-xie/schedule_plan/raw/main/updates/latest.json'
        '?t=100',
      );
      expect(
        urls[1],
        'https://raw.githubusercontent.com/gillnotfail/schedule_plan/main/'
        'updates/latest.json',
      );
      expect(
        urls[2],
        'https://cdn.jsdelivr.net/gh/gillnotfail/schedule_plan@main/'
        'updates/latest.json',
      );
    });

    test('镜像前缀只往后加，不动前三条的顺序', () {
      final urls = UpdateService.manifestUrls(
        const <String>['https://a/', 'https://b/'],
        epochSeconds: 100,
      );
      expect(urls, hasLength(9));
      // 前三条必须原样不动：镜像服务本身也可能挂，不能让它们挡在前面。
      expect(urls.take(3).any((url) => url.startsWith('https://a/')), isFalse);
      expect(urls[3], startsWith('https://a/'));
      expect(urls[6], startsWith('https://b/'));
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

  group('sourceLabelOf', () {
    test('认得清单里那三个源', () {
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
