import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

import 'package:schedule_plan/core/logging/app_logger.dart';
import 'package:schedule_plan/data/models/quote.dart';

/// 语料原文加载器：返回 JSON 原文，`null` 表示读不到（文件不存在 / 平台不支持）。
typedef QuoteTextLoader = Future<String?> Function();

/// 「每日一句」的语料服务（用户规格第 21 轮）。
///
/// 语料有**两个来源**，自定义的追加在内置的后面：
/// 1. **内置**：`assets/data/quotes.json` —— 随包走，改完重新打包即生效；
/// 2. **自定义**：应用文档目录下的 `quotes.json` —— 可选，存在才读。
///
/// 留第二份是为了让老师**不动代码也能加句子**：把同样格式的 `quotes.json`
/// 放进那个目录（路径在卡片长按弹出的说明里能看到）就会被追加进来。
/// 两份都读不到（或都写坏了）时返回空列表，卡片自己降级隐藏 —— **不抛异常**，
/// 因为这份 JSON 是留给用户手写的，写坏一行不该把整块卡片搞崩。
class QuoteService {
  /// 允许测试注入替身：返回语料原文（`null` 表示读不到）。
  QuoteService({
    QuoteTextLoader? assetLoader,
    QuoteTextLoader? userFileLoader,
    Future<String?> Function()? userPathResolver,
  })  : _assetLoader = assetLoader ?? _readAssetText,
        _userFileLoader = userFileLoader ?? _readUserFileText,
        _userPathResolver = userPathResolver ?? _defaultUserPath;

  /// App 全局共用的一份：缓存与"上一句"都挂在它身上，换页/切 Tab 才不会重复。
  static final QuoteService shared = QuoteService();

  /// 内置语料路径（同时也是回答"去哪儿加"的答案）。
  static const String assetPath = 'assets/data/quotes.json';

  /// 自定义语料文件名（放在应用文档目录下）。
  static const String userFileName = 'quotes.json';

  final QuoteTextLoader _assetLoader;
  final QuoteTextLoader _userFileLoader;
  final Future<String?> Function() _userPathResolver;

  List<Quote>? _cache;
  int _builtInCount = 0;
  bool _userFilePresent = false;
  String? _userFilePath;

  /// 上一条抽中的下标：避免"点一下还是同一句"。
  int? _lastIndex;

  final Random _random = Random();

  /// 已加载到的语料（未加载时为空列表；调用方一般走 [next]）。
  List<Quote> get quotes => List<Quote>.unmodifiable(_cache ?? const <Quote>[]);

  /// 内置语料条数。
  int get builtInCount => _builtInCount;

  /// 自定义语料文件是否已经存在。
  bool get hasUserFile => _userFilePresent;

  /// 自定义语料文件路径（[load] 跑过之后才有值）。
  String? get userFilePath => _userFilePath;

  /// 读语料并随机取一句；语料为空时返回 `null`（卡片据此隐藏，不留空壳）。
  Future<Quote?> next({bool force = false}) async {
    final list = await load(force: force);
    if (list.isEmpty) {
      return null;
    }
    final index = pickIndex(list.length, _lastIndex, _random);
    _lastIndex = index;
    return list[index];
  }

  /// 读取语料（带缓存；[force] 用于刷新或用户换过文件之后）。
  Future<List<Quote>> load({bool force = false}) async {
    final cached = _cache;
    if (cached != null && !force) {
      return cached;
    }
    final builtIn = await _loadBuiltIn();
    final user = await _loadUserFile();
    _builtInCount = builtIn.length;
    _cache = <Quote>[...builtIn, ...user];
    // 语料换过之后旧下标就没有意义了，清掉免得被当成"上一句"
    _lastIndex = null;
    return _cache!;
  }

  /// 抽一个下标，**尽量不和 [last] 相同**。
  ///
  /// 语料只有一条时只能返回它自己；否则在"剩下的 n-1 条"里均匀抽一个再
  /// 映射回原下标 —— 这样不需要"抽到重来"的循环，天然不会抽到自己。
  static int pickIndex(int length, int? last, Random random) {
    assert(length > 0, 'pickIndex 不接受空语料');
    if (length == 1) {
      return 0;
    }
    final lastValid = last != null && last >= 0 && last < length ? last : null;
    if (lastValid == null) {
      return random.nextInt(length);
    }
    final offset = random.nextInt(length - 1);
    return offset < lastValid ? offset : offset + 1;
  }

  Future<List<Quote>> _loadBuiltIn() async {
    try {
      final text = await _assetLoader();
      return Quote.parseAll(jsonDecode(text ?? ''));
    } catch (error, stack) {
      AppLogger.e('读取内置语录失败', error: error, stack: stack);
      return const <Quote>[];
    }
  }

  Future<List<Quote>> _loadUserFile() async {
    try {
      _userFilePath = await _userPathResolver();
      final text = await _userFileLoader();
      if (text == null) {
        _userFilePresent = false;
        return const <Quote>[];
      }
      _userFilePresent = true;
      return Quote.parseAll(jsonDecode(text));
    } catch (error, stack) {
      AppLogger.e('读取自定义语录失败', error: error, stack: stack);
      _userFilePresent = false;
      return const <Quote>[];
    }
  }

  static Future<String?> _readAssetText() async => rootBundle.loadString(assetPath);

  static Future<String> _defaultUserPath() async {
    final directory = await getApplicationDocumentsDirectory();
    return '${directory.path}/$userFileName';
  }

  static Future<String?> _readUserFileText() async {
    final path = await _defaultUserPath();
    final file = File(path);
    if (!await file.exists()) {
      return null;
    }
    return file.readAsString();
  }
}
