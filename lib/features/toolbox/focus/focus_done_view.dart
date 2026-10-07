import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:schedule_plan/core/constants/app_constants.dart';
import 'package:schedule_plan/core/l10n/l10n_extensions.dart';
import 'package:schedule_plan/core/theme/app_motion.dart';
import 'package:schedule_plan/core/widgets/app_card.dart';
import 'package:schedule_plan/features/toolbox/focus/focus_clock.dart';

/// 完成态：庆祝动效 + 成果卡 + 下一步。
///
/// 三个数字（本次 / 今日累计 / 连续）是**回报**，不是统计报表 ——
/// 用户坚持完这一段最想知道的是"我这一下值不值"，所以放在最上面、
/// 字号比说明文字大一号。
class FocusDoneView extends StatelessWidget {
  const FocusDoneView({
    super.key,
    required this.sessionDuration,
    required this.todayTotal,
    required this.streakDays,
    required this.praise,
    required this.accent,
    required this.onBreak,
    required this.onAgain,
    required this.onFinish,
  });

  /// 这一次坐了多久。
  final Duration sessionDuration;

  /// 今天累计（含这一次）。
  final Duration todayTotal;

  /// 连续专注天数（含今天）。
  final int streakDays;

  /// 鼓励语。**由页面在完成那一刻选好再传进来** ——
  /// 在这里随机的话，每次重建都会跳一句，看着像出了 bug。
  final String praise;

  final Color accent;
  final VoidCallback onBreak;
  final VoidCallback onAgain;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.spaceL,
        AppConstants.spaceXl,
        AppConstants.spaceL,
        AppConstants.spaceXl,
      ),
      children: <Widget>[
        Center(child: _CelebrationBurst(accent: accent)),
        const SizedBox(height: AppConstants.spaceXl),
        Text(
          l10n.focusDone,
          textAlign: TextAlign.center,
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppConstants.spaceXs),
        Text(
          l10n.focusDoneHeadline,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: AppConstants.spaceS),
        Text(
          praise,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppConstants.spaceXl),
        _statsCard(context),
        const SizedBox(height: AppConstants.spaceL),
        FilledButton.icon(
          onPressed: onBreak,
          icon: const Icon(Icons.local_cafe_outlined),
          label: Text(l10n.focusTakeBreak),
        ),
        const SizedBox(height: AppConstants.spaceM),
        OutlinedButton.icon(
          onPressed: onAgain,
          icon: const Icon(Icons.replay_rounded),
          label: Text(l10n.focusAgain),
        ),
        const SizedBox(height: AppConstants.spaceS),
        TextButton(onPressed: onFinish, child: Text(l10n.focusFinishAction)),
      ],
    );
  }

  Widget _statsCard(BuildContext context) {
    final l10n = context.l10n;
    return AppCard(
      child: Column(
        children: <Widget>[
          _StatRow(
            label: l10n.focusStatThisSession,
            value: formatFocusSpoken(sessionDuration),
          ),
          const Divider(height: AppConstants.spaceXl),
          _StatRow(
            label: l10n.focusStatToday,
            value: todayTotal <= Duration.zero
                ? l10n.focusStatEmpty
                : formatFocusSpoken(todayTotal),
          ),
          const Divider(height: AppConstants.spaceXl),
          _StatRow(
            label: l10n.focusStatStreak,
            value: streakDays <= 0
                ? l10n.focusStatEmpty
                : l10n.focusStreakDays(streakDays),
          ),
        ],
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.primary,
          ),
        ),
      ],
    );
  }
}

/// 完成那一刻的庆祝：一圈打勾弹出来，外面荡开三圈涟漪。
///
/// **一次性播放（不是循环）**：一来"完成"本身就是一个瞬间，
/// 二来循环动画会让 `pumpAndSettle` 永远等不到静止，组件测试没法写。
class _CelebrationBurst extends StatefulWidget {
  const _CelebrationBurst({required this.accent});

  final Color accent;

  @override
  State<_CelebrationBurst> createState() => _CelebrationBurstState();
}

class _CelebrationBurstState extends State<_CelebrationBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    // 复用「成就类脉冲」的时长，不另造一个魔法值。
    duration: AppMotion.pulse,
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 148,
      height: 148,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return CustomPaint(
            painter: _BurstPainter(
              progress: _controller.value,
              color: widget.accent,
            ),
            child: child,
          );
        },
        child: Center(
          child: ScaleTransition(
            scale: CurvedAnimation(
              parent: _controller,
              curve: AppMotion.softSpring,
            ),
            child: Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: widget.accent,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.check_rounded,
                size: 44,
                color: scheme.onPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BurstPainter extends CustomPainter {
  const _BurstPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final maxRadius = size.shortestSide / 2;
    for (var i = 0; i < 3; i++) {
      // 三圈错开出发，看起来是一圈接一圈荡开。
      final local = ((progress - i * 0.16) / 0.62).clamp(0.0, 1.0);
      if (local <= 0 || local >= 1) {
        continue;
      }
      final radius = maxRadius * (0.42 + 0.58 * local);
      final alpha = (1 - local) * 0.38;
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = color.withValues(alpha: alpha),
      );
    }
    // 最里面那圈做个柔和的底，衬住中间的勾。
    canvas.drawCircle(
      center,
      math.min(maxRadius, 46),
      Paint()..color = color.withValues(alpha: 0.16),
    );
  }

  @override
  bool shouldRepaint(covariant _BurstPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}
