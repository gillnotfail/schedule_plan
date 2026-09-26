import 'package:flutter/foundation.dart';

import 'package:schedule_plan/core/constants/setting_keys.dart';
import 'package:schedule_plan/core/logging/app_logger.dart';
import 'package:schedule_plan/data/repositories/holiday_repository.dart';
import 'package:schedule_plan/data/repositories/settings_repository.dart';
import 'package:schedule_plan/data/services/china_holiday_calendar.dart';
import 'package:schedule_plan/data/services/holiday_remote_source.dart';

/// 一次同步的结局。
enum HolidaySyncStatus {
  /// 还没到该更新的时候（或该有的年份都齐了），压根没发请求。
  skipped,

  /// 拿到了新数据并写进缓存。
  updated,

  /// 网络通了，但目标年份还没公布（每年 11 月前后才发布次年安排）。
  notPublished,

  /// 请求失败（断网 / 超时 / 接口变形）。
  failed,

  /// 用户在设置里关掉了「自动获取节假日数据」。
  disabled,
}

/// 同步结果（给 UI 决定提示文案用）。
@immutable
class HolidaySyncResult {
  const HolidaySyncResult({
    required this.status,
    this.years = const <int>{},
    this.message,
  });

  final HolidaySyncStatus status;
  final Set<int> years;
  final String? message;

  /// 这次同步算不算"正常收场"——决定提示口气是"更新完成"还是"更新失败"。
  bool get isOk =>
      status == HolidaySyncStatus.updated ||
      status == HolidaySyncStatus.skipped ||
      status == HolidaySyncStatus.notPublished;
}

/// 节假日数据的"保鲜"服务：让内置表不至于过期。
///
/// ## 它解决什么问题
///
/// 内置表（[ChinaHolidayCalendar]）把国务院通知抄成了常量——好处是完全离线、
/// 永远算得对；坏处是**每年都得改代码重新发版**。老师手机上装好的 App
/// 不会因为新年到了就自动知道新一年的假期，跨年后就"看不见假期"了。
///
/// 所以这里加一条**联网保鲜**的路子：把取回来的年度安排存进 `holiday_day` 表，
/// 启动时灌进内存，覆盖掉内置表缺的年份。内置表从此退化成**兜底**——
/// 没网、接口全挂、用户关掉开关，都还能用，只是少了新一年的安排，
/// 绝不会比现在更差。
///
/// ## 为什么不用"读手机自带日历"
///
/// 想过，但不靠谱：国产 ROM 的日历 App 各写各的，调休数据**不一定**写进系统的
/// CalendarProvider；就算写了，事件标题也没标准（"休"/"班"/"国庆节"…）只能靠猜；
/// iOS 那边 Apple 的「中国大陆节假日」日历**只标放假、不标补班**，等于半残。
/// 再加上要多要一个日历读取权限（用户会犹豫），收益远不如直接取一份结构化数据。
///
/// ## 什么时候才去请求（节流）
///
/// 不是每次启动都请求——那既费流量，也顺带暴露了"这台手机什么时候被打开过"。
/// 判断规则全部收在 [shouldFetch] 这个纯函数里，见那里的注释。
///
/// ## 为什么是个 [ChangeNotifier]
///
/// 刷新是在启动后**后台**跑的（不能卡住启动）。等它拿到数据时，课表页和日历页
/// 早就渲染完一轮了——它们是常驻 `IndexedStack` 的子页，切走再切回也不会重建。
/// 所以数据一落地就得喊一声，让这两页跟着重画，否则老师会对着"还没更新的
/// 旧视图"纳闷为什么假期没显示出来。
class HolidaySyncService extends ChangeNotifier {
  HolidaySyncService({
    HolidayRepository? repository,
    SettingsRepository? settings,
    HolidayRemoteSource? source,
    DateTime Function()? clock,
  })  : _repository = repository ?? HolidayRepository(),
        _settings = settings ?? SettingsRepository(),
        _source = source ?? ChainedHolidaySource.standard(),
        _now = clock ?? DateTime.now;

  /// 上次失败后隔多久再试（别把网络打爆，也别让老师等太久）。
  static const Duration retryAfterFailure = Duration(hours: 6);

  /// 公布窗口期内，隔多久看一眼次年安排。
  static const Duration retryInPublishWindow = Duration(days: 3);

  /// 公布窗口期外，隔多久看一眼（这段时间基本不会有新通知）。
  static const Duration retryOutsidePublishWindow = Duration(days: 30);

  /// 该有的年份都齐了之后，隔多久复查一次（国务院偶尔会修订安排）。
  static const Duration recheckComplete = Duration(days: 90);

  final HolidayRepository _repository;
  final SettingsRepository _settings;
  final HolidayRemoteSource _source;
  final DateTime Function() _now;

  /// 当前需要覆盖的年份：今年 + 明年。
  ///
  /// 必须带上下一年：等到 12 月 31 日再去取次年的安排就来不及了，
  /// 老师整个 1 月的课表都会算错。
  @visibleForTesting
  static Set<int> targetYears(DateTime now) => <int>{now.year, now.year + 1};

  /// 国务院一般在 10 月下旬 ~ 11 月中旬公布次年安排。
  @visibleForTesting
  static bool inPublishWindow(DateTime now) => now.month >= 10;

  /// 该不该发这次请求（纯函数，单测直接喂时间）。
  ///
  /// [missingYears] 是"该覆盖但还没拿到"的年份——空集合就说明没事可做。
  @visibleForTesting
  static bool shouldFetch({
    required DateTime now,
    required int? lastAttemptMs,
    required bool lastOk,
    required Set<int> missingYears,
  }) {
    if (lastAttemptMs == null) {
      return true; // 从来没试过
    }
    final elapsedMs = now.millisecondsSinceEpoch - lastAttemptMs;
    if (elapsedMs < 0) {
      // 系统时间被往回调过（手改时间 / 换时区）。当成"该试一次"，
      // 否则会被负间隔永久卡住，再也不同步
      return true;
    }
    final passed = Duration(milliseconds: elapsedMs);

    if (missingYears.isEmpty) {
      // 数据齐了，只需要很久复查一次
      return passed >= recheckComplete;
    }
    if (!lastOk) {
      return passed >= retryAfterFailure;
    }
    // 上次成功但年份仍缺，分两种情况：
    // - 缺的是**今年或更早**：数据早该公布了（内置表没跟上、刚装上 App、
    //   或者上次只拉到一半），那就不管几月都得勤快重试——慢一拍就是
    //   老师整年的课表都算错。
    // - **只缺明年**：那才轮到"是不是还没发通知"，窗口期外一个月瞄一眼就够。
    final overdue = missingYears.any((year) => year <= now.year);
    if (overdue) {
      return passed >= retryInPublishWindow;
    }
    return passed >=
        (inPublishWindow(now) ? retryInPublishWindow : retryOutsidePublishWindow);
  }

  /// App 启动时调一次：先把已有缓存灌进来（保证本次会话立刻能用）。
  ///
  /// 只注入、不发请求——"要不要联网"交给调用方决定，
  /// 免得服务里偷偷做 fire-and-forget 的网络动作。
  Future<void> bootstrap() async {
    try {
      await injectCache();
    } catch (error, stack) {
      AppLogger.e('初始化节假日缓存失败，按内置数据运行', error: error, stack: stack);
    }
  }

  /// 后台刷新：**绝不往外抛异常**。
  ///
  /// 给启动路径用的——那里是 `unawaited(...)`，一旦抛出去就变成
  /// 没人接的异步异常。刷新失败本来就是可接受的（内置表还在兜底），
  /// 记一笔日志就够了。
  Future<void> refreshQuietly({bool force = false}) async {
    try {
      await refresh(force: force);
    } catch (error, stack) {
      AppLogger.e('节假日数据后台刷新失败', error: error, stack: stack);
    }
  }

  /// 把库里的缓存读出来灌给内置表（进程内有效，重启后再灌一次）。
  Future<void> injectCache() async {
    ChinaHolidayCalendar.overrideWith(await _repository.loadAll());
  }

  /// 目前"有官方数据"的年份 = 内置表覆盖的 + 缓存里已有的。
  Future<Set<int>> coveredYears() async => <int>{
        ...ChinaHolidayCalendar.builtinYears,
        ...await _repository.cachedYears(),
      };

  /// 该覆盖但还没拿到的年份。
  Future<Set<int>> missingYears(DateTime now) async =>
      targetYears(now).difference(await coveredYears());

  /// 上次检查时间（UI 显示用，不管成败都会记）。
  Future<DateTime?> lastCheckedAt() async {
    final parsed = int.tryParse(await _settings.read(SettingKeys.holidayLastSyncAt));
    if (parsed == null || parsed <= 0) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(parsed);
  }

  /// 试着把缺的年份补齐。
  ///
  /// [force] = 老师在设置页手动点了「立即更新」：跳过节流判断，
  /// 并且把今年 + 明年整份重取一遍（手动点的大概率是"我觉得数据不对"）。
  Future<HolidaySyncResult> refresh({bool force = false, DateTime? now}) async {
    final moment = now ?? _now();

    if (!await _settings.readBool(SettingKeys.holidayRemoteEnabled)) {
      return const HolidaySyncResult(status: HolidaySyncStatus.disabled);
    }

    final missing = await missingYears(moment);
    if (!force) {
      final should = shouldFetch(
        now: moment,
        lastAttemptMs: await _lastAttemptMs(),
        lastOk: await _settings.readBool(SettingKeys.holidayLastSyncOk),
        missingYears: missing,
      );
      if (!should) {
        return HolidaySyncResult(status: HolidaySyncStatus.skipped, years: missing);
      }
    }

    // 先记下"我试过了"：后面无论成不成，节流窗口都该从这一刻起算
    await _settings.writeInt(
      SettingKeys.holidayLastSyncAt,
      moment.millisecondsSinceEpoch,
    );

    final wanted = force ? targetYears(moment) : missing;
    final updated = <int>{};
    final stillMissing = <int>{};
    var failures = 0;

    for (final year in wanted) {
      try {
        final fetched = await _source.fetchYear(year);
        if (fetched.isEmpty) {
          // 接口活着但没这一年的数据 = 还没公布，不算失败
          stillMissing.add(year);
          continue;
        }
        await _repository.replaceYear(
          year,
          fetched.days,
          source: fetched.source,
          fetchedAt: moment.millisecondsSinceEpoch,
        );
        updated.add(year);
      } catch (error, stack) {
        failures++;
        stillMissing.add(year);
        AppLogger.e('拉取 $year 年节假日安排失败', error: error, stack: stack);
      }
    }

    // 只要不是"全军覆没"就按成功记，下一轮走慢档节流
    await _settings.writeBool(SettingKeys.holidayLastSyncOk, failures == 0);

    // 数据落库后立刻灌进内存，本次会话就能用上新数据
    await injectCache();

    if (updated.isNotEmpty) {
      AppLogger.i('节假日数据已更新：${updated.join('、')} 年');
      // 通知常驻页面（课表页 / 日历页）重画，否则它们还停在旧视图上
      notifyListeners();
      return HolidaySyncResult(status: HolidaySyncStatus.updated, years: updated);
    }
    if (failures > 0 && stillMissing.length == wanted.length) {
      return const HolidaySyncResult(
        status: HolidaySyncStatus.failed,
        message: '网络不通或数据源暂不可用',
      );
    }
    if (stillMissing.isNotEmpty) {
      return HolidaySyncResult(
        status: HolidaySyncStatus.notPublished,
        years: stillMissing,
      );
    }
    return const HolidaySyncResult(status: HolidaySyncStatus.skipped);
  }

  /// 设置页「恢复内置数据」：清掉联网缓存，回到出厂内置表。
  Future<void> clearCache() async {
    await _repository.clear();
    ChinaHolidayCalendar.resetOverride();
    await _settings.writeInt(SettingKeys.holidayLastSyncAt, 0);
    await _settings.writeBool(SettingKeys.holidayLastSyncOk, false);
    AppLogger.i('节假日缓存已清空，回到内置数据');
    notifyListeners();
  }

  Future<int?> _lastAttemptMs() async {
    final parsed = int.tryParse(await _settings.read(SettingKeys.holidayLastSyncAt));
    return parsed == null || parsed <= 0 ? null : parsed;
  }
}
