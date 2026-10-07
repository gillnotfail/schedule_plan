import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:schedule_plan/core/constants/app_constants.dart';
import 'package:schedule_plan/core/l10n/l10n_extensions.dart';
import 'package:schedule_plan/core/theme/app_motion.dart';
import 'package:schedule_plan/features/toolbox/focus/focus_controller.dart';
import 'package:schedule_plan/features/toolbox/focus/focus_dial.dart';
import 'package:schedule_plan/features/toolbox/focus/focus_presets.dart';

/// 专注态：整屏三层叠加。
///
/// 层次是刻意分开的（用户规格里的 ZStack 三层）：
/// 1. **背景**：一层随进度缓缓变深的渐变，让"时间在往下走"有体感；
/// 2. **环形进度**：订阅每帧的进度，只重画这一圈；
/// 3. **内容**：名称、倒计时数字、提示、控制。
///
/// 为什么把数字和环分开订阅：环必须每帧画才平滑，数字一秒才变一次。
/// 让数字跟着 60fps 重建，等于锁屏专注时白烧电，而这里电就是命。
///
/// 休息段复用同一套界面（[isBreak]），只是不锁屏、文案换成「休息中」——
/// 另做一套休息界面既不划算，也会让"点哪儿暂停"这种肌肉记忆失效。
class FocusRunningView extends StatefulWidget {
  const FocusRunningView({
    super.key,
    required this.controller,
    required this.accent,
    required this.isBreak,
    required this.onToggle,
    required this.onAdjust,
    required this.onReset,
    required this.onExit,
  });

  final FocusController controller;
  final Color accent;

  /// 这一段是休息而不是专注。休息不锁屏，说法也跟着换。
  final bool isBreak;
  final VoidCallback onToggle;

  /// 长按上下滑动调时长：上滑变长、下滑变短。
  final ValueChanged<Duration> onAdjust;
  final VoidCallback onReset;
  final VoidCallback onExit;

  @override
  State<FocusRunningView> createState() => _FocusRunningViewState();
}

class _FocusRunningViewState extends State<FocusRunningView> {
  /// 长按拖动已经折算出的分钟数，用来按"格"发增量、不重复发同一步。
  int _draggedMinutes = 0;

  /// 纵向每滑动这么多像素才算拨动一分钟。
  static const double _pixelsPerMinute = 36;

  void _onLongPressMove(LongPressMoveUpdateDetails details) {
    final minutes = (-details.offsetFromOrigin.dy / _pixelsPerMinute).round();
    final delta = minutes - _draggedMinutes;
    if (delta == 0) {
      return;
    }
    _draggedMinutes = minutes;
    AppMotion.select();
    widget.onAdjust(Duration(minutes: delta));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final controller = widget.controller;
    final paused = controller.phase == FocusPhase.paused;

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        // 第一层：背景
        _GradientBackdrop(
          remaining: controller.displayedRemaining,
          total: controller.total,
          accent: widget.accent,
        ),
        // 第二、三层：环与内容（手势铺在整屏上，点哪儿都认）
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onToggle,
          onDoubleTap: widget.onReset,
          onLongPressStart: (_) => _draggedMinutes = 0,
          onLongPressMoveUpdate: _onLongPressMove,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppConstants.spaceL,
                vertical: AppConstants.spaceS,
              ),
              child: Column(
                children: <Widget>[
                  _topBar(context, paused, widget.isBreak),
                  const Spacer(),
                  _dial(context, paused, widget.isBreak),
                  const SizedBox(height: AppConstants.spaceL),
                  Text(
                    paused ? l10n.focusTapToResume : l10n.focusTapToPause,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  _controls(context, paused),
                  const SizedBox(height: AppConstants.spaceM),
                  Text(
                    l10n.focusGestureHint,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------

  Widget _topBar(BuildContext context, bool paused, bool isBreak) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final name = _sessionName(context);
    return Row(
      children: <Widget>[
        // 左边的占位与右边「退出」等宽，名称才会真正居中。
        const SizedBox(width: 64),
        Expanded(
          child: Column(
            children: <Widget>[
              Text(
                paused
                    ? l10n.focusPausedTitle
                    : (isBreak ? l10n.focusBreakRunning : l10n.focusRunningTitle),
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (name.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
        ),
        SizedBox(
          width: 64,
          child: TextButton(
            onPressed: widget.onExit,
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              foregroundColor: theme.colorScheme.onSurfaceVariant,
            ),
            child: Text(l10n.focusExitAction),
          ),
        ),
      ],
    );
  }

  String _sessionName(BuildContext context) {
    final label = widget.controller.label;
    if (label != null && label.isNotEmpty) {
      return focusLabelText(context, label);
    }
    // 控制器存的是落库用的字符串 id，显示前要转回枚举。
    final category = FocusCategory.fromStorage(widget.controller.category);
    if (category != null) {
      return focusCategoryLabel(context, category);
    }
    return '';
  }

  Widget _dial(BuildContext context, bool paused, bool isBreak) {
    final scheme = Theme.of(context).colorScheme;
    return FocusDial(
      progress: widget.controller.progressListenable,
      diameter: 280,
      strokeWidth: 16,
      accent: paused ? scheme.outline : widget.accent,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          FocusDigits(
            remaining: widget.controller.displayedRemaining,
            fontSize: 48,
            color: paused ? scheme.onSurfaceVariant : scheme.onSurface,
          ),
          const SizedBox(height: AppConstants.spaceXs),
          Text(
            paused
                ? context.l10n.focusPausedTitle
                : (isBreak
                    ? context.l10n.focusBreakRunning
                    : context.l10n.focusRunningTitle),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }

  Widget _controls(BuildContext context, bool paused) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton.filledTonal(
      onPressed: widget.onToggle,
      iconSize: 38,
      padding: const EdgeInsets.all(AppConstants.spaceL),
      style: IconButton.styleFrom(
        backgroundColor: scheme.primaryContainer,
        foregroundColor: scheme.onPrimaryContainer,
      ),
      icon: Icon(
        paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
      ),
      tooltip: paused ? context.l10n.focusResume : context.l10n.focusPause,
    );
  }
}

/// 第一层：随进度缓缓变深的渐变底。
///
/// 订阅的是**秒级**的剩余时长而不是每帧进度 —— 底色一秒挪一点点，
/// 肉眼完全跟得上，而重建次数从 60 次/秒降到 1 次/秒。
class _GradientBackdrop extends StatelessWidget {
  const _GradientBackdrop({
    required this.remaining,
    required this.total,
    required this.accent,
  });

  final ValueListenable<Duration> remaining;
  final Duration total;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tint = Color.alphaBlend(accent.withValues(alpha: 0.20), scheme.surface);
    return ValueListenableBuilder<Duration>(
      valueListenable: remaining,
      builder: (context, value, _) {
        final totalMs = total.inMilliseconds;
        final ratio = totalMs <= 0
            ? 0.0
            : (1 - value.inMilliseconds / totalMs).clamp(0.0, 1.0);
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[
                Color.lerp(scheme.surface, tint, ratio)!,
                scheme.surface,
              ],
            ),
          ),
          child: const SizedBox.expand(),
        );
      },
    );
  }
}
