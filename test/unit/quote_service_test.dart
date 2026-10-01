import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:schedule_plan/data/models/quote.dart';
import 'package:schedule_plan/data/services/quote_service.dart';

/// 「每日一句」语料解析 + 抽句规则（用户规格第 21 轮）。
///
/// 这份 JSON 是**留给用户自己手写**的，所以两个口径必须钉死：
/// 1. **解析要宽容**：写坏一条只跳过那一条，不能让整块卡片消失；
/// 2. **抽句不许连着重复**：点了"轻触换一句"却还是同一句，用户会以为点坏了。
void main() {
  group('Quote.parseAll 宽容解析', () {
    test('顶层是纯字符串数组', () {
      final quotes = Quote.parseAll(<Object?>['大鹏一日同风起', '会当凌绝顶']);
      expect(quotes.map((q) => q.text), <String>['大鹏一日同风起', '会当凌绝顶']);
      expect(quotes.every((q) => q.from == null), isTrue);
    });

    test('顶层是对象里的 quotes 数组（内置文件的真实结构）', () {
      final quotes = Quote.parseAll(<String, Object?>{
        'note': '随便写点说明',
        'quotes': <Object?>[
          <String, Object?>{'text': '长风破浪会有时', 'from': '李白《行路难》'},
        ],
      });
      expect(quotes, hasLength(1));
      expect(quotes.single.text, '长风破浪会有时');
      expect(quotes.single.from, '李白《行路难》');
    });

    test('from / author / source 都认，text / content / quote 也都认', () {
      expect(
        Quote.parseAll(<Object?>[
          <String, Object?>{'content': 'a', 'author': '甲'},
          <String, Object?>{'quote': 'b', 'source': '乙'},
          <String, Object?>{'text': 'c'},
        ]).map((q) => '${q.text}:${q.from}'),
        <String>['a:甲', 'b:乙', 'c:null'],
      );
    });

    test('坏条目不抛异常，只是被跳过', () {
      final quotes = Quote.parseAll(<Object?>[
        '正常的句子',
        42,
        null,
        <String, Object?>{'from': '没有正文'},
        <String, Object?>{'text': '   '},
        <String, Object?>{'text': 123},
        <String, Object?>{'text': '  首尾空白会被裁掉  ', 'from': '  出处  '},
      ]);
      expect(quotes, hasLength(2));
      expect(quotes.last.text, '首尾空白会被裁掉');
      expect(quotes.last.from, '出处');
    });

    test('顶层既不是数组也不是对象 → 空列表（不抛）', () {
      expect(Quote.parseAll(null), isEmpty);
      expect(Quote.parseAll('一个字符串'), isEmpty);
      expect(Quote.parseAll(7), isEmpty);
      // 对象里没有 quotes 数组（比如用户把文件写成了别的东西）
      expect(Quote.parseAll(<String, Object?>{'note': '我只写了个说明'}), isEmpty);
    });

    test('hasFrom 把空白串当成没有出处', () {
      expect(const Quote(text: 'a', from: '').hasFrom, isFalse);
      expect(const Quote(text: 'a', from: '  ').hasFrom, isFalse);
      expect(const Quote(text: 'a', from: '李白').hasFrom, isTrue);
    });
  });

  group('QuoteService.load 两个来源', () {
    /// 造一个语料服务：内置 / 自定义文件都用替身喂进去。
    QuoteService build({String? asset, String? userFile}) {
      return QuoteService(
        assetLoader: () async => asset,
        userFileLoader: () async => userFile,
        userPathResolver: () async => '/tmp/quotes.json',
      );
    }

    test('内置 + 自定义是叠加关系，内置在前', () async {
      final service = build(
        asset: jsonEncode(<Object?>['内置一', '内置二']),
        userFile: jsonEncode(<Object?>['自定一']),
      );
      final list = await service.load();
      expect(list.map((q) => q.text), <String>['内置一', '内置二', '自定一']);
      expect(service.builtInCount, 2);
      expect(service.hasUserFile, isTrue);
      expect(service.userFilePath, '/tmp/quotes.json');
    });

    test('没有自定义文件时只吃内置，且标记 hasUserFile=false', () async {
      final service = build(asset: jsonEncode(<Object?>['内置一']));
      expect(await service.load(), hasLength(1));
      expect(service.hasUserFile, isFalse);
    });

    test('两份都读不到 → 空列表（卡片据此隐藏，不能抛）', () async {
      final service = build();
      expect(await service.load(), isEmpty);
      expect(await service.next(), isNull);
    });

    test('JSON 写坏了 → 空列表，不把异常抛到界面上', () async {
      final service = build(asset: '{这不是 json', userFile: '{{{');
      expect(await service.load(), isEmpty);
    });

    test('内置坏了但自定义是好的 → 至少还能读到自定义那部分', () async {
      final service = build(asset: 'not json', userFile: jsonEncode(<Object?>['自定一']));
      expect((await service.load()).map((q) => q.text), <String>['自定一']);
    });

    test('带缓存：第二次 load 不会再去读文件，force 才会重读', () async {
      var reads = 0;
      final service = QuoteService(
        assetLoader: () async {
          reads++;
          return jsonEncode(<Object?>['内置一']);
        },
        userFileLoader: () async => null,
        userPathResolver: () async => '/tmp/quotes.json',
      );
      await service.load();
      await service.load();
      expect(reads, 1);
      await service.load(force: true);
      expect(reads, 2);
    });
  });

  group('QuoteService.pickIndex 抽句规则', () {
    test('只有一条语料时只能返回它自己', () {
      final random = Random(1);
      for (var i = 0; i < 20; i++) {
        expect(QuoteService.pickIndex(1, 0, random), 0);
      }
    });

    test('永远不返回上一次那个下标', () {
      final random = Random(7);
      for (final length in <int>[2, 3, 9, 87]) {
        for (var last = 0; last < length; last++) {
          for (var i = 0; i < 40; i++) {
            final index = QuoteService.pickIndex(length, last, random);
            expect(index, inInclusiveRange(0, length - 1));
            expect(index, isNot(last));
          }
        }
      }
    });

    test('上次下标越界 / 为 null 时当作"随便抽"', () {
      final random = Random(3);
      for (var i = 0; i < 30; i++) {
        expect(QuoteService.pickIndex(4, null, random), inInclusiveRange(0, 3));
        expect(QuoteService.pickIndex(4, -1, random), inInclusiveRange(0, 3));
        expect(QuoteService.pickIndex(4, 99, random), inInclusiveRange(0, 3));
      }
    });

    test('除"上一句"之外的每条都抽得到（不是把候选压到了某一段）', () {
      final random = Random(11);
      final seen = <int>{};
      for (var i = 0; i < 400; i++) {
        seen.add(QuoteService.pickIndex(5, 2, random));
      }
      expect(seen, <int>{0, 1, 3, 4});
    });
  });

  group('QuoteService.next 连续抽句', () {
    test('语料非空时永远拿得到句子，且不会连着两次同一句', () async {
      final service = QuoteService(
        assetLoader: () async => jsonEncode(<Object?>['甲', '乙', '丙']),
        userFileLoader: () async => null,
        userPathResolver: () async => '/tmp/quotes.json',
      );
      String? previous;
      for (var i = 0; i < 60; i++) {
        final quote = await service.next();
        expect(quote, isNotNull);
        expect(quote!.text, isNot(previous));
        previous = quote.text;
      }
    });
  });

  group('内置语料文件本体', () {
    /// 直接读磁盘上的那份资源，而不是通过 rootBundle。
    ///
    /// 目的不是"测 JSON 库"，而是守住三件很容易被忽略的事：
    /// 文件真的在 `assets/data/quotes.json`、内容真的能解析、条数够撑住"换一句"。
    test('assets/data/quotes.json 存在、能解析、条数够多', () {
      final file = File(QuoteService.assetPath);
      expect(file.existsSync(), isTrue,
          reason: '内置语料不见了：${QuoteService.assetPath}（改路径要同步 pubspec 的 assets）');

      final quotes = Quote.parseAll(jsonDecode(file.readAsStringSync()));
      expect(quotes.length, greaterThanOrEqualTo(50),
          reason: '语料太少的话"轻触换一句"很快就重复了');
      for (final quote in quotes) {
        expect(quote.text.trim(), isNotEmpty);
        // 出处允许没有，但内置语料目前每条都写了，缺了就说明有人手滑删了
        expect(quote.hasFrom, isTrue, reason: '这条没有出处：${quote.text}');
      }
      expect(
        quotes.map((q) => q.text).toSet(),
        hasLength(quotes.length),
        reason: '内置语料里有重复句子',
      );
    });
  });
}
