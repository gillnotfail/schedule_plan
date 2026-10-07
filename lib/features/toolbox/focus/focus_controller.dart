import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import 'package:schedule_plan/core/constants/app_constants.dart';
import 'package:schedule_plan/core/logging/app_logger.dart';
import 'package:schedule_plan/features/toolbox/focus/focus_clock.dart';

/// 专注会话所处的阶段。
enum FocusPhase {
  /// 准备态：正在挑时长 / 起名，还没开始。
  setup,

  /// 计时中，屏幕处于锁定态。
  running,

  /// 暂停中，屏幕不再锁定（暂停时还锁着等于不让人喝水）。
  paused,

  /// 坐满了，停在成果卡上。
  finished,
}

/// 一次专注的最终结局。
enum FocusOutcome { completed, abandoned }

/// 需要在外部发出的一次性反馈（震动 / 提示音由页面去落实）。
///
/// 控制器自己不出声：它不依赖任何平台能力，单测里能跑得干干净净。
enum FocusCue { start, pause, resume, halfway, lastMinute, finish }

/// 一次进行中的专注的快照，用于**进程被杀之后接上**。
///
/// 手机上被系统回收是很常见的事（尤其锁屏放着不动、内存又紧的时候）。
/// 不落快照的话，回来看到的是一块归零的计时器 —— 而这恰恰是最伤人的那一刻。
@immutable
class FocusSnapshot {
  const FocusSnapshot({
    required this.totalMs,
    required this.settledMs,
    required this.startedAtMs,
    this.segmentStartMs,
    this.label,
    this.category,
    this.finished = false,
    this.isBreak = false,
  });

  final int totalMs;
  final int settledMs;

  /// 本次专注**开始**那一刻（写进数据库的就是它）。
  final int startedAtMs;

  /// 当前这一段起点；null = 快照落盘时处于暂停中。
  final int? segmentStartMs;

  final String? label;
  final String? category;

  /// 已经坐满但用户还没看成果卡就退出去了。
  final bool finished;

  /// 这一段是休息而不是专注。
  ///
  /// 必须持久化：休息**不锁屏**（用户规格），如果恢复时把它当成专注，
  /// 用户会在一个本该可以起身接水的五分钟里被锁住屏幕。
  final bool isBreak;

  String encode() => jsonEncode(<String, Object?>{
        'totalMs': totalMs,
        'settledMs': settledMs,
        'startedAtMs': startedAtMs,
        'segmentStartMs': segmentStartMs,
        'label': label,
        'category': category,
        'finished': finished,
        'isBreak': isBreak,
      });

  static FocusSnapshot? tryParse(String? raw) {
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      final map = jsonDecode(raw) as Map<String, Object?>;
      final totalMs = map['totalMs'] as int?;
      final startedAtMs = map['startedAtMs'] as int?;
      if (totalMs == null || startedAtMs == null) {
        return null;
      }
      return FocusSnapshot(
        totalMs: totalMs,
        settledMs: map['settledMs'] as int? ?? 0,
        startedAtMs: startedAtMs,
        segmentStartMs: map['segmentStartMs'] as int?,
        label: map['label'] as String?,
        category: map['category'] as String?,
        finished: map['finished'] as bool? ?? false,
        isBreak: map['isBreak'] as bool? ?? false,
      );
    } catch (error) {
      // 快照坏了就当没有 —— 绝不能让它把"打开专注模式"这件事本身搞崩。
      AppLogger.e('专注会话快照解析失败，按全新会话处理', error: error);
      return null;
    }
  }
}

/// 快照的落盘口子。抽出来是为了让控制器不认识数据库，单测可以塞内存实现。
abstract interface class FocusSnapshotStore {
  Future<void> save(FocusSnapshot snapshot);

  Future<FocusSnapshot?> load();

  Future<void> clear();
}

/// 内存实现（单测用；也让控制器在"没有数据库"的环境里能安全降级）。
class InMemoryFocusSnapshotStore implements FocusSnapshotStore {
  FocusSnapshot? _snapshot;

  @override
  Future<void> save(FocusSnapshot snapshot) async => _snapshot = snapshot;

  @override
  Future<FocusSnapshot?> load() async => _snapshot;

  @override
  Future<void> clear() async => _snapshot = null;
}

/// 专注会话的状态机与高精度计时外壳。
///
/// 计时本身全部委托给 [FocusClock]（墙钟口径，见那里的说明），
/// 这里只负责三件事：**推进阶段、把时间推给 UI、在关键时刻发 cue**。
///
/// 刷新策略分两档，避免"每秒变化的东西按 60fps 重建"：
/// - [frames]（Ticker）：给进度环用，每帧回调，让它平滑；
/// - [displayedRemaining]：给倒计时数字用，**只在秒数真的变了才通知**。
class FocusController extends ChangeNotifier {
  FocusController({
    Duration? total,
    String? label,
    String? category,
    FocusSnapshotStore? store,
  })  : _clock = FocusClock(
          total: total ?? const Duration(minutes: AppConstants.focusDefaultMinutes),
        ),
        _label = label,
        _category = category,
        _store = store;

  final FocusClock _clock;
  final FocusSnapshotStore? _store;

  Ticker? _ticker;
  bool _disposed = false;

  FocusPhase _phase = FocusPhase.setup;
  FocusOutcome _outcome = FocusOutcome.completed;
  String? _label;
  String? _category;
  int? _startedAtMs;

  /// 当前这一段是休息而不是专注（休息不锁屏，见 [armBreak]）。
  bool _isBreak = false;

  /// 已经发过就不再发的高频提示，避免每帧都提醒。
  bool _halfwayFired = false;
  bool _lastMinuteFired = false;

  final ValueNotifier<Duration> _displayedRemaining =
      ValueNotifier<Duration>(Duration.zero);
  final ValueNotifier<double> _progress = ValueNotifier<double>(0);

  void Function(FocusCue cue)? onCue;

  FocusPhase get phase => _phase;

  FocusOutcome get outcome => _outcome;

  Duration get total => _clock.total;

  Duration get elapsed => _clock.elapsedAt(DateTime.now());

  Duration get remaining => _clock.remainingAt(DateTime.now());

  double get progress => _clock.progressAt(DateTime.now());

  String? get label => _label;

  String? get category => _category;

  /// 当前这一段是休息而不是专注。页面据它决定要不要锁屏。
  bool get isBreak => _isBreak;

  /// 给进度环用的每帧回调。
  ///
  /// 注意：`Ticker` 本身**不是** `Listenable`（它的 `addListener` 收的是
  /// `void Function(Duration)`），所以不能直接丢给 `AnimatedBuilder`。
  /// 这里把每帧算出的完成度转成一个 0~1 的 [ValueListenable]，
  /// 环只订阅它，重建范围就锁在那一个 CustomPaint 上。
  ValueListenable<double> get progressListenable => _progress;

  /// 给倒计时数字用的、秒级变化的可监听值。
  ///
  /// 数字每秒才变一次，没必要跟着每帧重建 —— 60fps 重排一个 Text
  /// 白烧电，而锁屏专注时电就是命。
  ValueListenable<Duration> get displayedRemaining => _displayedRemaining;

  /// 把 vsync 接进来并尝试恢复上次没做完的会话。
  ///
  /// 恢复成功后返回 true —— 页面据此决定是停在准备态还是直接回到锁定屏。
  Future<bool> attach(TickerProvider vsync) async {
    _ticker?.dispose();
    _ticker = vsync.createTicker(_onFrame);
    _syncNotifiers(DateTime.now());
    return _restore();
  }

  Future<bool> _restore() async {
    final snapshot = await _store?.load();
    if (snapshot == null) {
      return false;
    }
    final now = DateTime.now();
    _clock.restore(
      total: Duration(milliseconds: snapshot.totalMs),
      settled: Duration(milliseconds: snapshot.settledMs),
      segmentStartAt: snapshot.segmentStartMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(snapshot.segmentStartMs!),
    );
    _label = snapshot.label;
    _category = snapshot.category;
    _startedAtMs = snapshot.startedAtMs;
    _isBreak = snapshot.isBreak;

    if (snapshot.finished || _clock.isFinishedAt(now)) {
      // 关掉 App 的这段时间人其实一直在（手机还锁着），到点了就直接进成果页。
      _clock.pause(now);
      _phase = FocusPhase.finished;
      _outcome = FocusOutcome.completed;
      unawaited(_store?.clear());
    } else if (_clock.running) {
      _phase = FocusPhase.running;
      _resumeTicker();
    } else {
      _phase = FocusPhase.paused;
    }
    _syncNotifiers(now);
    _notify();
    return true;
  }

  /// 准备态里改时长（滚轮）。
  void setTotal(Duration value) {
    if (_phase != FocusPhase.setup) {
      return;
    }
    _clock.retotal(value);
    _syncNotifiers(DateTime.now());
    _notify();
  }

  void setLabel(String? value) {
    _label = (value == null || value.trim().isEmpty) ? null : value.trim();
    _notify();
  }

  void setCategory(String? value) {
    _category = value;
    _notify();
  }

  /// 开始专注。
  void start() {
    final now = DateTime.now();
    _clock.start(now);
    _startedAtMs ??= now.millisecondsSinceEpoch;
    _phase = FocusPhase.running;
    _resetMilestones();
    _resumeTicker();
    onCue?.call(FocusCue.start);
    unawaited(_persist());
    _notify();
  }

  void pause() {
    if (_phase != FocusPhase.running) {
      return;
    }
    _clock.pause(DateTime.now());
    _phase = FocusPhase.paused;
    _ticker?.stop();
    _syncNotifiers(DateTime.now());
    onCue?.call(FocusCue.pause);
    unawaited(_persist());
    _notify();
  }

  void resume() {
    if (_phase != FocusPhase.paused) {
      return;
    }
    _clock.resume(DateTime.now());
    _phase = FocusPhase.running;
    _resumeTicker();
    onCue?.call(FocusCue.resume);
    unawaited(_persist());
    _notify();
  }

  void toggle() => _phase == FocusPhase.running ? pause() : resume();

  /// 专注中长按屏幕上下拨时长。已坐的部分不动，只挪终点。
  void adjustTotal(Duration delta) {
    if (_phase == FocusPhase.setup || _phase == FocusPhase.finished) {
      return;
    }
    _clock.retotal(_clock.total + delta);
    _resetMilestones();
    _syncNotifiers(DateTime.now());
    unawaited(_persist());
    _notify();
  }

  /// 双击归零重来（回到准备态，时长保留）。
  void reset() {
    _ticker?.stop();
    _clock.reset();
    _phase = FocusPhase.setup;
    _startedAtMs = null;
    _isBreak = false;
    _resetMilestones();
    _syncNotifiers(DateTime.now());
    unawaited(_store?.clear());
    _notify();
  }

  /// 坐满了。
  void complete() {
    if (_phase == FocusPhase.finished) {
      return;
    }
    _clock.pause(DateTime.now());
    _phase = FocusPhase.finished;
    _outcome = FocusOutcome.completed;
    _ticker?.stop();
    onCue?.call(FocusCue.finish);
    unawaited(_store?.clear());
    _notify();
  }

  /// 中途放弃：先把这一刻已坐的时长定下来，再由页面写记录并退场。
  Duration abandon() {
    final now = DateTime.now();
    final elapsedNow = _clock.elapsedAt(now);
    _clock.pause(now);
    _phase = FocusPhase.setup;
    _outcome = FocusOutcome.abandoned;
    _ticker?.stop();
    unawaited(_store?.clear());
    _notify();
    return elapsedNow;
  }

  /// 成果卡上的「休息 5 分钟」：把计时器装成一个休息段。
  ///
  /// 装完还停在 [FocusPhase.setup]，由页面紧接着调 [start] —— 这样
  /// "几点了、休息几分钟"这两件事仍然只有页面一个地方说了算。
  ///
  /// 标记 [isBreak] 是关键：页面据它跳过**全部**锁屏动作
  /// （沉浸模式、屏幕常亮、屏幕固定），用户休息时手机照常能用。
  void armBreak() {
    _clock.reset(total: Duration(minutes: AppConstants.focusDefaultBreakMinutes));
    _phase = FocusPhase.setup;
    _startedAtMs = null;
    _isBreak = true;
    _resetMilestones();
    _syncNotifiers(DateTime.now());
    _notify();
  }

  /// 本次开始时刻的毫秒时间戳（写进数据库的 `started_at`）。
  int get startedAtMs => _startedAtMs ?? DateTime.now().millisecondsSinceEpoch;

  void _resetMilestones() {
    _halfwayFired = false;
    _lastMinuteFired = false;
  }

  void _resumeTicker() {
    final ticker = _ticker;
    if (ticker == null || ticker.isActive) {
      return;
    }
    ticker.start();
  }

  void _onFrame(Duration _) {
    if (_disposed) {
      return;
    }
    final now = DateTime.now();
    final left = _clock.remainingAt(now);

    _syncNotifiers(now);

    _fireMilestones(now, left);

    if (left == Duration.zero) {
      complete();
    }
  }

  /// 把墙钟算出来的两个派生值推给 UI。
  void _syncNotifiers(DateTime now) {
    final left = _clock.remainingAt(now);
    if (_displayedRemaining.value != left) {
      _displayedRemaining.value = left;
    }
    final ratio = _clock.progressAt(now);
    if (_progress.value != ratio) {
      _progress.value = ratio;
    }
  }

  /// 半程与"最后一分钟"各提醒一次，让人知道进度，又不至于吵。
  void _fireMilestones(DateTime now, Duration left) {
    final total = _clock.total;
    final elapsedNow = _clock.elapsedAt(now);
    if (!_halfwayFired && total >= const Duration(minutes: 10)) {
      if (elapsedNow >= total ~/ 2) {
        _halfwayFired = true;
        onCue?.call(FocusCue.halfway);
      }
    }
    if (!_lastMinuteFired && total >= const Duration(minutes: 3)) {
      if (left <= const Duration(minutes: 1) && left > Duration.zero) {
        _lastMinuteFired = true;
        onCue?.call(FocusCue.lastMinute);
      }
    }
  }

  Future<void> _persist() async {
    final store = _store;
    if (store == null || _phase == FocusPhase.setup || _phase == FocusPhase.finished) {
      return;
    }
    await store.save(
      FocusSnapshot(
        totalMs: _clock.total.inMilliseconds,
        settledMs: _clock.elapsedAt(DateTime.now()).inMilliseconds,
        startedAtMs: startedAtMs,
        // 必须是**这一段真实的起点**，不能图省事写 DateTime.now() ——
        // 那样每次落盘都把起点往后挪，"关掉 App 再打开"就等于把
        // 已经专注的那段抹掉，而且抹得悄无声息。
        segmentStartMs: _clock.segmentStart?.millisecondsSinceEpoch,
        label: _label,
        category: _category,
        isBreak: _isBreak,
      ),
    );
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker?.dispose();
    _ticker = null;
    _displayedRemaining.dispose();
    _progress.dispose();
    super.dispose();
  }
}
