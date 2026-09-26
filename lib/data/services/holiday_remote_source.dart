import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:schedule_plan/core/logging/app_logger.dart';
import 'package:schedule_plan/data/models/china_holiday.dart';

/// 从网上取回来的「某一年」的节假日 / 调休安排。
@immutable
class RemoteHolidayYear {
  const RemoteHolidayYear({
    required this.year,
    required this.days,
    required this.source,
  });

  /// 接口正常应答，但这一年还没公布（每年 11 月之前去拉次年就会这样）。
  ///
  /// 这**不是错误**：要跟上层的"请求失败"区分开，前者过几天再看就行，
  /// 后者该歇久一点别把网络打爆。
  const RemoteHolidayYear.empty({required this.year, required this.source})
      : days = const <String, ChinaHoliday>{};

  final int year;

  /// key = `YYYY-MM-DD`。只装**有"国家安排"含义**的日子：
  /// 法定放假日（`holiday`）和调休上班日（`makeupWorkday`）。
  ///
  /// 普通工作日 / 普通周末**不入表**——那两种看 `DateTime.weekday` 就能推出来，
  /// 存进来白占地方不说，还会跟内置表抢解释权：万一远程说某天是普通工作日、
  /// 内置表说它是假日，合并时就得分个高下。这类冲突本来可以不产生。
  final Map<String, ChinaHoliday> days;

  /// 数据来自哪个源，写进库里备查。
  final String source;

  bool get isEmpty => days.isEmpty;

  bool get isNotEmpty => days.isNotEmpty;
}

/// 远程数据源：只要能按年份交出「放假日 + 调休日」，谁实现都行。
abstract interface class HolidayRemoteSource {
  /// 源的名字（写进缓存表与日志）。
  String get label;

  /// 取某年的安排。
  ///
  /// **"这一年还没公布"必须返回空结果、不要抛异常**——上层靠这个区别
  /// 决定是"过几天再来问"还是"网络有问题，歇久一点"。
  Future<RemoteHolidayYear> fetchYear(int year);
}

/// 拉取失败（网络不通 / 超时 / 状态码异常 / 返回体结构不认得）。
class HolidayFetchException implements Exception {
  HolidayFetchException(this.source, this.message, {this.cause});

  final String source;
  final String message;
  final Object? cause;

  @override
  String toString() => '节假日数据获取失败（$source）：$message';
}

/// 主源：timor.tech 的免费节假日接口（免注册、免密钥）。
///
/// 选它当主源是因为**口径最全**：`type` 段一次给全四态
/// （0 工作日 / 1 周末 / 2 节日 / 3 调休），调休上班日不用反推。
/// 缺点同样明确：个人维护的免费站，随时可能关门或改格式——
/// 所以后面还串了备用源，而且全部失败也只是退回内置表，功能不会坏。
class TimorHolidaySource implements HolidayRemoteSource {
  TimorHolidaySource({
    http.Client? client,
    this.timeout = const Duration(seconds: 8),
  }) : _client = client;

  static const String _base = 'https://timor.tech/api/holiday/year';

  /// 仅供测试注入。生产走 [http.get] 这个一次性请求，不长期持有连接。
  final http.Client? _client;

  final Duration timeout;

  @override
  String get label => 'timor.tech';

  @override
  Future<RemoteHolidayYear> fetchYear(int year) async {
    // type=Y 才会返回四态明细；week=Y 带星期几（眼下用不上，
    // 但省得以后想要时又得改接口）
    final uri = Uri.parse('$_base/$year?type=Y&week=Y');
    return RemoteHolidayYear(
      year: year,
      days: parseTimorYear(await _getJson(uri)),
      source: label,
    );
  }

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    try {
      final response = await _send(uri).timeout(timeout);
      if (response.statusCode != 200) {
        throw HolidayFetchException(label, 'HTTP ${response.statusCode}');
      }
      // 显式按 UTF-8 解码：返回体里有中文节日名，
      // 交给 http 包自己猜编码会乱码
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, dynamic>) {
        throw HolidayFetchException(label, '返回体不是 JSON 对象');
      }
      return decoded;
    } on HolidayFetchException {
      rethrow;
    } catch (error, stack) {
      AppLogger.e('主节假日接口请求失败', error: error, stack: stack);
      throw HolidayFetchException(label, '$error', cause: error);
    }
  }

  Future<http.Response> _send(Uri uri) {
    const Map<String, String> headers = <String, String>{
      'Accept': 'application/json',
      // 自报家门，但不夹带任何设备标识 / 用户信息
      'User-Agent': 'schedule-plan-holiday/1.0',
    };
    final client = _client;
    if (client != null) {
      return client.get(uri, headers: headers);
    }
    return http.get(uri, headers: headers);
  }
}

/// 备用源：holiday-cn（把国务院通知整理成静态 JSON 的开源项目，走 jsDelivr CDN）。
///
/// 它是**纯静态文件**，比接口更抗压、几乎不会被限流；代价是只有
/// 「放假 / 上班」两态（`isOffDay`），节日名要靠文件里的 `name` 认。
class HolidayCnSource implements HolidayRemoteSource {
  HolidayCnSource({
    http.Client? client,
    this.timeout = const Duration(seconds: 8),
  }) : _client = client;

  static const String _base =
      'https://cdn.jsdelivr.net/gh/NateScarlet/holiday-cn@master';

  final http.Client? _client;

  final Duration timeout;

  @override
  String get label => 'holiday-cn';

  @override
  Future<RemoteHolidayYear> fetchYear(int year) async {
    final uri = Uri.parse('$_base/$year.json');
    try {
      final response = await _send(uri).timeout(timeout);
      if (response.statusCode == 404) {
        // CDN 上没有这一年的文件 = 国务院还没发通知，属于正常状态
        return RemoteHolidayYear.empty(year: year, source: label);
      }
      if (response.statusCode != 200) {
        throw HolidayFetchException(label, 'HTTP ${response.statusCode}');
      }
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, dynamic>) {
        throw HolidayFetchException(label, '返回体不是 JSON 对象');
      }
      return RemoteHolidayYear(
        year: year,
        days: parseHolidayCnYear(decoded),
        source: label,
      );
    } on HolidayFetchException {
      rethrow;
    } catch (error, stack) {
      AppLogger.e('备用节假日源请求失败', error: error, stack: stack);
      throw HolidayFetchException(label, '$error', cause: error);
    }
  }

  Future<http.Response> _send(Uri uri) {
    const Map<String, String> headers = <String, String>{
      'Accept': 'application/json',
      'User-Agent': 'schedule-plan-holiday/1.0',
    };
    final client = _client;
    if (client != null) {
      return client.get(uri, headers: headers);
    }
    return http.get(uri, headers: headers);
  }
}

/// 把多个源串起来用：按顺序试，谁先拿到非空数据就用谁的。
///
/// 刻意不"挑一个最可靠的写死"：这些都是免费的公开源，没有谁承诺过长期可用。
/// 串起来之后挂掉一个还有下一个；**全部失败也只是退回内置表**——
/// 功能不会变坏，顶多少了新一年的安排。
class ChainedHolidaySource implements HolidayRemoteSource {
  ChainedHolidaySource(this.sources);

  /// 生产环境用这个默认组合（主接口 + 静态 JSON 备胎）。
  factory ChainedHolidaySource.standard({http.Client? client}) =>
      ChainedHolidaySource(<HolidayRemoteSource>[
        TimorHolidaySource(client: client),
        HolidayCnSource(client: client),
      ]);

  final List<HolidayRemoteSource> sources;

  @override
  String get label => sources.map((source) => source.label).join(' + ');

  @override
  Future<RemoteHolidayYear> fetchYear(int year) async {
    // 有源"活着但确实没这一年的数据"，和"所有源都挂了"是两回事：
    // 前者说明通知还没发（正常），后者才值得记一笔错误
    var sawEmpty = false;
    Object? lastError;
    for (final source in sources) {
      try {
        final result = await source.fetchYear(year);
        if (result.isNotEmpty) {
          return result;
        }
        sawEmpty = true;
      } catch (error) {
        lastError = error;
        AppLogger.w('节假日源 ${source.label} 取 $year 年数据失败，改试下一个：$error');
      }
    }
    if (sawEmpty) {
      return RemoteHolidayYear.empty(year: year, source: label);
    }
    throw HolidayFetchException(
      label,
      lastError == null ? '没有可用的数据源' : '$lastError',
      cause: lastError,
    );
  }
}

/// 解析 timor.tech 年度接口的返回体（纯函数，单测直接喂 JSON）。
///
/// 返回体形如：
/// ```json
/// {
///   "code": 0,
///   "holiday": { "10-01": { "holiday": true, "name": "国庆节", "date": "2026-10-01" } },
///   "type":    { "2026-10-01": { "type": 2, "name": "国庆节", "week": 4 } }
/// }
/// ```
///
/// 解析顺序有讲究：**先吃 `type` 段，再吃 `holiday` 段**。
/// `type` 是四态口径（认得调休），`holiday` 只标"这天放假"——
/// 只认 `holiday` 的话，调休上班日会整个丢掉，而那正是本功能最要紧的部分。
Map<String, ChinaHoliday> parseTimorYear(Map<String, dynamic> json) {
  final result = <String, ChinaHoliday>{};

  final types = json['type'];
  if (types is Map<String, dynamic>) {
    for (final entry in types.entries) {
      final date = entry.key;
      final payload = entry.value;
      if (!_isIsoDate(date) || payload is! Map<String, dynamic>) {
        continue;
      }
      final kind = _kindOfTimorCode(payload['type']);
      if (kind == null) {
        continue;
      }
      result[date] = ChinaHoliday(
        date: date,
        kind: kind,
        name: _nameOf(payload['name']),
      );
    }
  }

  final holidays = json['holiday'];
  if (holidays is Map<String, dynamic>) {
    for (final payload in holidays.values) {
      if (payload is! Map<String, dynamic>) {
        continue;
      }
      // `holiday` 段的 key 只有 "MM-DD"，年份得靠 payload 里的完整日期补齐；
      // 补不齐就丢掉——宁可少一天，也不要猜出一个错的年份
      final date = payload['date'];
      if (date is! String || !_isIsoDate(date)) {
        continue;
      }
      result.putIfAbsent(
        date,
        () => ChinaHoliday(
          date: date,
          kind: CalendarDayKind.holiday,
          name: _nameOf(payload['name']),
        ),
      );
    }
  }

  return result;
}

/// 解析 holiday-cn 年度 JSON（纯函数）。
///
/// ```json
/// { "year": 2026, "days": [
///     { "name": "元旦", "date": "2026-01-01", "isOffDay": true },
///     { "name": "元旦", "date": "2026-01-04", "isOffDay": false } ] }
/// ```
///
/// 这个格式只有"放假 / 补班"两态，恰好就是我们要缓存的那两种，
/// 所以直接一一对应，不用像 timor 那样过滤 0/1。
Map<String, ChinaHoliday> parseHolidayCnYear(Map<String, dynamic> json) {
  final result = <String, ChinaHoliday>{};
  final days = json['days'];
  if (days is! List) {
    return result;
  }
  for (final item in days) {
    if (item is! Map<String, dynamic>) {
      continue;
    }
    final date = item['date'];
    final offDay = item['isOffDay'];
    if (date is! String || !_isIsoDate(date) || offDay is! bool) {
      continue;
    }
    result[date] = ChinaHoliday(
      date: date,
      kind: offDay ? CalendarDayKind.holiday : CalendarDayKind.makeupWorkday,
      name: _nameOf(item['name']),
    );
  }
  return result;
}

/// timor 的 `type` 码 → 我们的日历属性。
///
/// 0（工作日）和 1（周末）是"天生"属性，不入缓存，因此返回 null 让调用方跳过。
CalendarDayKind? _kindOfTimorCode(Object? code) => switch (int.tryParse('$code')) {
      2 => CalendarDayKind.holiday,
      3 => CalendarDayKind.makeupWorkday,
      _ => null,
    };

/// 中文节日名 → 枚举。认不出来返回 null（名字只影响展示，不值得为它报错）。
HolidayName? _nameOf(Object? raw) {
  if (raw is! String || raw.isEmpty) {
    return null;
  }
  // 合体假必须先判：2025、2028 都是「国庆节 + 中秋节」连放，
  // 只按"国庆"匹配会把"中秋"那层含义吃掉
  if (raw.contains('国庆') && raw.contains('中秋')) {
    return HolidayName.nationalDayMidAutumn;
  }
  if (raw.contains('国庆')) {
    return HolidayName.nationalDay;
  }
  if (raw.contains('中秋')) {
    return HolidayName.midAutumn;
  }
  if (raw.contains('端午')) {
    return HolidayName.dragonBoat;
  }
  if (raw.contains('劳动')) {
    return HolidayName.labourDay;
  }
  if (raw.contains('清明')) {
    return HolidayName.qingming;
  }
  if (raw.contains('春节')) {
    return HolidayName.springFestival;
  }
  if (raw.contains('元旦')) {
    return HolidayName.newYear;
  }
  return null;
}

final RegExp _isoDatePattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');

bool _isIsoDate(String value) => _isoDatePattern.hasMatch(value);
