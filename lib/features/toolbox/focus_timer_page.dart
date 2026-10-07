import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:schedule_plan/core/constants/setting_keys.dart';
import 'package:schedule_plan/core/l10n/l10n_extensions.dart';
import 'package:schedule_plan/core/logging/app_logger.dart';
import 'package:schedule_plan/core/theme/app_motion.dart';
import 'package:schedule_plan/core/widgets/app_snackbar.dart';
import 'package:schedule_plan/data/models/schedule_event.dart';
import 'package:schedule_plan/data/repositories/schedule_event_repository.dart';
import 'package:schedule_plan/data/repositories/settings_repository.dart';
import 'package:schedule_plan/data/settings_state.dart';
import 'package:schedule_plan/features/toolbox/focus/focus_clock.dart';
import 'package:schedule_plan/features/toolbox/focus/focus_controller.dart';
import 'package:schedule_plan/features/toolbox/focus/focus_done_view.dart';
import 'package:schedule_plan/features/toolbox/focus/focus_exit_sheet.dart';
import 'package:schedule_plan/features/toolbox/focus/focus_lock_service.dart';
import 'package:schedule_plan/features/toolbox/focus/focus_presets.dart';
import 'package:schedule_plan/features/toolbox/focus/focus_running_view.dart';
import 'package:schedule_plan/features/toolbox/focus/focus_session_store.dart';
import 'package:schedule_plan/features/toolbox/focus/focus_setup_view.dart';

/// 专注模式（模块五 5.1）。
///
/// 这一版的核心不是"番茄钟"，而是用户提的那个问题：**玩手机会把注意力
/// 抢走，重新回到专注要花很久**。所以流程是"坐下 → 锁住 → 到点给回报"：
///
/// ```
/// 准备态 ──开始──▶ 专注态 ──到点──▶ 成果态 ──再来一次──▶ 准备态
///                   │  ▲                                  │
///                 暂停 继续                            休息 5 分钟
///                   │  │
///                   └──┘（暂停时**不锁屏**，不然连水都喝不上）
///                   │
///                退出 → 拦截（报已坚持多久 / 还差多少）→ 二次确认才放行
/// ```
///
/// **只有专注态锁屏**，休息段一律不锁（用户规格）。
///
/// 计时本身全部委托给 [FocusController]（墙钟口径，见 `focus_clock.dart`），
/// 这个页面只做四件事：推进界面、锁/解锁、到点写库、算成果数字。
class FocusTimerPage extends StatefulWidget {
  const FocusTimerPage({super.key});

  @override
  State<FocusTimerPage> createState() => _FocusTimerPageState();
}

class _FocusTimerPageState extends State<FocusTimerPage>
    with SingleTickerProviderStateMixin {
  late final FocusController _controller;
  late final FocusLockService _lock;
  final TextEditingController _labelController = TextEditingController();

  bool _soundEnabled = true;
  bool _strongLockEnabled = false;

  /// 当前是否真的处在系统锁定态（屏幕固定成功过）。
  bool _screenLocked = false;

  String _praise = '';
  _FocusStats _stats = const _FocusStats(
    todayTotal: Duration.zero,
    streakDays: 0,
  );

  /// 上一次看到的阶段，用来识别"刚刚坐满"这一次跳变。
  FocusPhase _lastPhase = FocusPhase.setup;

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsState>();
    _soundEnabled = settings.focusSoundEnabled;
    _strongLockEnabled = settings.focusStrongLockEnabled;

    _lock = FocusLockService();
    _controller = FocusController(
      total: Duration(minutes: settings.focusMinutes),
      store: FocusSnapshotSettingsStore(context.read<SettingsRepository>()),
    )..onCue = _fireCue;
    _controller.addListener(_onControllerChanged);
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    _labelController.dispose();
    // 退出页面一定要把锁和常亮还回去 —— 忘了关就是"退出专注后手机再也不息屏"，
    // 用户会以为是手机坏了。三件事都不 await：dispose 里等不了异步。
    unawaited(_releaseLock());
    super.dispose();
  }

  /// 接上 vsync，并尝试恢复上次没做完的会话。
  Future<void> _bootstrap() async {
    final restored = await _controller.attach(this);
    if (!mounted) {
      return;
    }
    if (restored && _controller.phase == FocusPhase.running) {
      await _applyLock(lock: true);
    }
    if (mounted) {
      setState(() {});
    }
  }

  // ---------------------------------------------------------------------------
  // 锁 / 解锁
  // ---------------------------------------------------------------------------

  /// 锁屏分两档（细节见 [FocusLockService]）：
  /// - 基础档：沉浸全屏 + 屏幕常亮 + 拦返回，**任何手机都能用**；
  /// - 增强档：额外尝试系统「屏幕固定」，**先做后验**，没成功就如实告知。
  Future<void> _applyLock({required bool lock}) async {
    if (lock) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      await _lock.setKeepScreenOn(true);
      if (!_strongLockEnabled) {
        return;
      }
      final entered = await _lock.enterLockTask();
      _screenLocked = entered;
      if (!entered && mounted) {
        // 不假装锁上了：说清楚为什么没锁成，用户才知道该去系统设置里开什么。
        showAppSnackBar(context, context.l10n.focusStrongLockUnavailable);
      }
      return;
    }
    await _releaseLock();
  }

  Future<void> _releaseLock() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    await _lock.setKeepScreenOn(false);
    if (_screenLocked) {
      _screenLocked = false;
      await _lock.exitLockTask();
    }
  }

  // ---------------------------------------------------------------------------
  // 提示音 / 震动
  // ---------------------------------------------------------------------------

  /// 控制器只负责"该发信号了"，怎么发由这里决定（见 [FocusCue]）。
  void _fireCue(FocusCue cue) {
    // 休息段是"手机可以用"的时间，不该再震再响。
    if (_controller.isBreak) {
      return;
    }
    if (cue == FocusCue.finish || cue == FocusCue.lastMinute) {
      AppMotion.confirm();
    } else if (cue == FocusCue.halfway) {
      AppMotion.tap();
    } else {
      AppMotion.select();
    }
    if (_soundEnabled) {
      unawaited(_lock.playCue(cue));
    }
  }

  // ---------------------------------------------------------------------------
  // 状态变化
  // ---------------------------------------------------------------------------

  void _onControllerChanged() {
    final phase = _controller.phase;
    final justFinished = phase != _lastPhase && phase == FocusPhase.finished;
    _lastPhase = phase;
    if (justFinished) {
      unawaited(_handleFinished());
    }
    if (mounted) {
      setState(() {});
    }
  }

  /// 坐满了。
  ///
  /// 休息段和专注段在这里分道扬镳：休息**不写库**（那是休息，不是专注投入，
  /// 记进去会把"本周专注次数"灌水），只回到准备态打声招呼。
  Future<void> _handleFinished() async {
    final isBreak = _controller.isBreak;
    await _releaseLock();
    if (!mounted) {
      return;
    }
    if (isBreak) {
      _controller.reset();
      _controller.setTotal(
        Duration(minutes: context.read<SettingsState>().focusMinutes),
      );
      showAppSnackBar(context, context.l10n.focusBreakDone);
      return;
    }

    await _saveSession(duration: _controller.total, completed: true);
    final stats = await _loadStats();
    if (!mounted) {
      return;
    }
    setState(() {
      _praise = _pickPraise();
      _stats = stats;
    });
  }

  // ---------------------------------------------------------------------------
  // 交互
  // ---------------------------------------------------------------------------

  Future<void> _start() async {
    _controller.setLabel(_labelController.text);
    final isBreak = _controller.isBreak;
    _controller.start();
    if (!isBreak) {
      await _applyLock(lock: true);
    }
  }

  Future<void> _toggle() async {
    final wasRunning = _controller.phase == FocusPhase.running;
    _controller.toggle();
    if (wasRunning) {
      // 暂停就放手：暂停时还锁着等于不让人喝水。
      await _releaseLock();
    } else if (!_controller.isBreak) {
      await _applyLock(lock: true);
    }
  }

  void _adjust(Duration delta) => _controller.adjustTotal(delta);

  Future<void> _resetSession() async {
    await _releaseLock();
    _controller.reset();
  }

  /// 拦截退出：**先劝一句再放行**（用户规格）。
  Future<void> _requestExit() async {
    if (!mounted) {
      return;
    }
    final confirmed = await showFocusExitSheet(
      context,
      elapsed: _controller.elapsed,
      remaining: _controller.remaining,
    );
    if (!confirmed || !mounted) {
      return;
    }
    await _abandon();
  }

  Future<void> _abandon() async {
    final wasBreak = _controller.isBreak;
    final elapsed = _controller.abandon();
    await _releaseLock();
    if (!wasBreak && elapsed.inSeconds >= 30) {
      // 半分钟以内退出就不提"已记录"了 —— 那更像在提醒他"你刚白坐了"。
      await _saveSession(duration: elapsed, completed: false);
      if (mounted) {
        showAppSnackBar(
          context,
          context.l10n.focusAbandonedHint(formatFocusSpoken(elapsed)),
        );
      }
    }
  }

  Future<void> _startBreak() async {
    _controller.setLabel(null);
    _labelController.clear();
    _controller.armBreak();
    _controller.start();
  }

  Future<void> _again() async {
    _controller.reset();
  }

  void _finish() {
    Navigator.of(context).maybePop();
  }

  Future<void> _setSoundEnabled(bool value) async {
    setState(() => _soundEnabled = value);
    await context.read<SettingsState>().update(
          SettingKeys.focusSoundEnabled,
          value ? '1' : '0',
        );
  }

  Future<void> _setStrongLockEnabled(bool value) async {
    setState(() => _strongLockEnabled = value);
    await context.read<SettingsState>().update(
          SettingKeys.focusStrongLockEnabled,
          value ? '1' : '0',
        );
  }

  Future<void> _setTotal(Duration value) async {
    _controller.setTotal(value);
  }

  // ---------------------------------------------------------------------------
  // 写库 / 算数字
  // ---------------------------------------------------------------------------

  Future<void> _saveSession({
    required Duration duration,
    required bool completed,
  }) async {
    try {
      await context.read<ScheduleEventRepository>().saveFocusSession(
            FocusSession(
              // started_at 必须是**开始**那一刻：统计按它落在哪一周来汇总，
              // 写成结束时刻会让跨零点的那一节整段算进第二天。
              startedAt: _controller.startedAtMs,
              durationMinutes: duration.inSeconds ~/ 60,
              completed: completed,
              label: _controller.label,
              category: _controller.category,
            ),
          );
    } catch (error, stack) {
      AppLogger.e('保存专注记录失败', error: error, stack: stack);
    }
  }

  /// 今日累计 + 连续天数。
  ///
  /// 只看 `completed` 为真的那些 —— 跟教学成果页的口径保持一致，
  /// 中途放弃的记录不该把"累计专注"拉低成莫名其妙的数字。
  Future<_FocusStats> _loadStats() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    try {
      final sessions = await context.read<ScheduleEventRepository>().focusSessionsBetween(
            fromMs: DateTime(today.year, today.month, today.day - 59)
                .millisecondsSinceEpoch,
            toMs: now.millisecondsSinceEpoch,
          );
      final days = <DateTime>{};
      var todayMinutes = 0;
      for (final session in sessions) {
        if (!session.completed) {
          continue;
        }
        final at = DateTime.fromMillisecondsSinceEpoch(session.startedAt);
        final day = DateTime(at.year, at.month, at.day);
        days.add(day);
        if (day == today) {
          todayMinutes += session.durationMinutes;
        }
      }
      var streak = 0;
      var cursor = today;
      while (days.contains(cursor)) {
        streak++;
        // 用 DateTime(y, m, d - 1) 而不是 subtract(Duration(days: 1))：
        // 后者在夏令时切换那天会偏一小时，日期就可能对不上。
        cursor = DateTime(cursor.year, cursor.month, cursor.day - 1);
      }
      return _FocusStats(
        todayTotal: Duration(minutes: todayMinutes),
        streakDays: streak,
      );
    } catch (error, stack) {
      AppLogger.e('读取专注统计失败', error: error, stack: stack);
      return const _FocusStats(todayTotal: Duration.zero, streakDays: 0);
    }
  }

  /// 完成那一刻挑一句鼓励，**挑完就定住**（在 build 里随机的话每次重画都会跳）。
  String _pickPraise() {
    final l10n = context.l10n;
    final lines = <String>[
      l10n.focusPraiseFragments,
      l10n.focusPraiseSteady,
      l10n.focusPraiseComeback,
      l10n.focusPraiseTime,
    ];
    return lines[math.Random().nextInt(lines.length)];
  }

  // ---------------------------------------------------------------------------
  // 界面
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final phase = _controller.phase;
    final immersive =
        phase == FocusPhase.running || phase == FocusPhase.paused;
    final accent = _controller.isBreak ? scheme.tertiary : scheme.primary;

    return PopScope(
      // 锁屏时不许直接返回：必须走"劝一句 → 二次确认"那条路。
      canPop: !immersive,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          unawaited(_requestExit());
        }
      },
      child: Scaffold(
        backgroundColor: scheme.surface,
        appBar: immersive ? null : AppBar(title: Text(l10n.focusTimer)),
        body: switch (phase) {
          FocusPhase.setup => FocusSetupView(
              total: _controller.total,
              category: FocusCategory.fromStorage(_controller.category),
              label: _controller.label,
              labelController: _labelController,
              soundEnabled: _soundEnabled,
              strongLockEnabled: _strongLockEnabled,
              onTotalChanged: (value) => unawaited(_setTotal(value)),
              onCategoryChanged: (value) =>
                  _controller.setCategory(value?.storageKey),
              onLabelChanged: _controller.setLabel,
              onSoundChanged: (value) => unawaited(_setSoundEnabled(value)),
              onStrongLockChanged: (value) =>
                  unawaited(_setStrongLockEnabled(value)),
              onStart: () => unawaited(_start()),
            ),
          FocusPhase.running || FocusPhase.paused => FocusRunningView(
              controller: _controller,
              accent: accent,
              isBreak: _controller.isBreak,
              onToggle: () => unawaited(_toggle()),
              onAdjust: _adjust,
              onReset: () => unawaited(_resetSession()),
              onExit: () => unawaited(_requestExit()),
            ),
          FocusPhase.finished => FocusDoneView(
              sessionDuration: _controller.total,
              todayTotal: _stats.todayTotal,
              streakDays: _stats.streakDays,
              praise: _praise,
              accent: accent,
              onBreak: () => unawaited(_startBreak()),
              onAgain: () => unawaited(_again()),
              onFinish: _finish,
            ),
        },
      ),
    );
  }
}

/// 成果卡上的三个数字。
@immutable
class _FocusStats {
  const _FocusStats({required this.todayTotal, required this.streakDays});

  final Duration todayTotal;
  final int streakDays;
}
