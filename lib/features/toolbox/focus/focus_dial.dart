import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:schedule_plan/core/theme/app_motion.dart';
import 'package:schedule_plan/features/toolbox/focus/focus_clock.dart';

/// 纯绘制的环形进度（可单独当静态圆环用）。
///
/// 从 12 点方向顺时针长出来，[progress] 会被钳到 0~1 —— 计时器用墙钟口径
/// 现算剩余，理论上不会越界，但**绘画代码不该假设上游永远正确**。
class FocusRing extends StatelessWidget {
  const FocusRing({
    super.key,
    required this.progress,
    this.diameter = 268,
    this.strokeWidth = 14,
    this.accent,
    this.trackColor,
    this.child,
  });

  final double progress;
  final double diameter;
  final double strokeWidth;
  final Color? accent;
  final Color? trackColor;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: diameter,
      height: diameter,
      child: CustomPaint(
        painter: _RingPainter(
          progress: progress.clamp(0.0, 1.0),
          accent: accent ?? scheme.primary,
          track: trackColor ?? scheme.surfaceContainerHighest,
          strokeWidth: strokeWidth,
        ),
        child: child == null ? null : Center(child: child),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.progress,
    required this.accent,
    required this.track,
    required this.strokeWidth,
  });

  final double progress;
  final Color accent;
  final Color track;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide - strokeWidth) / 2;
    if (radius <= 0) {
      return;
    }
    final rect = Rect.fromCircle(center: center, radius: radius);

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..color = track,
    );

    if (progress <= 0) {
      return;
    }
    // 弧头稍亮、弧尾稍淡，转起来才有"走过去"的方向感。
    final shader = SweepGradient(
      colors: <Color>[
        accent.withValues(alpha: 0.65),
        accent,
      ],
      transform: const GradientRotation(-math.pi / 2),
    ).createShader(rect);

    canvas.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..shader = shader,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.accent != accent ||
      oldDelegate.track != track ||
      oldDelegate.strokeWidth != strokeWidth;
}

/// 环形进度 + 中心内容（专注态的中间那层）。
///
/// [progress] 收的是 `ValueListenable` 而不是裸 double，为的是把**重建范围
/// 锁在这一环上**：进度每帧都在变，而外面的文案、按钮一秒都不需要重画。
/// 中心内容通过 `child` 透传进来，构建一次就不再跟着每帧重建。
class FocusDial extends StatelessWidget {
  const FocusDial({
    super.key,
    required this.progress,
    required this.child,
    this.diameter = 268,
    this.strokeWidth = 14,
    this.accent,
  });

  final ValueListenable<double> progress;
  final Widget child;
  final double diameter;
  final double strokeWidth;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: progress,
      builder: (context, value, innerChild) => FocusRing(
        progress: value,
        diameter: diameter,
        strokeWidth: strokeWidth,
        accent: accent,
        child: innerChild,
      ),
      child: child,
    );
  }
}

/// 倒计时数字的统一样式。
///
/// 抽出来是因为同一个 `00:00:00` 会出现在三个地方（准备态预览、专注态、
/// 成果页），三处各写一套迟早会飘。等宽数字尤其不能漏：少了它，秒数从
/// 9 跳到 10 时整串数字会左右抖一下。
TextStyle focusDigitTextStyle(
  BuildContext context, {
  double fontSize = 46,
  Color? color,
  FontWeight fontWeight = FontWeight.w800,
}) {
  return Theme.of(context).textTheme.displaySmall!.copyWith(
        fontSize: fontSize,
        fontWeight: fontWeight,
        letterSpacing: -1,
        fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
        color: color ?? Theme.of(context).colorScheme.onSurface,
      );
}

/// 中心的大号倒计时数字，数字变化时上滑淡入。
///
/// **只订阅秒级的 [remaining]**（不是每帧的进度），因为数字一秒才变一次；
/// 60fps 重排一个 Text 是白烧电，而锁屏专注时电就是命。
class FocusDigits extends StatelessWidget {
  const FocusDigits({
    super.key,
    required this.remaining,
    this.color,
    this.fontSize = 46,
    this.animate = true,
  });

  final ValueListenable<Duration> remaining;
  final Color? color;
  final double fontSize;

  /// 关掉动画（进度环预演、成果页这种静态展示场景）。
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final style = focusDigitTextStyle(
      context,
      fontSize: fontSize,
      color: color,
    );
    return ValueListenableBuilder<Duration>(
      valueListenable: remaining,
      builder: (context, value, _) {
        final text = Text(
          formatFocusDuration(value),
          key: ValueKey<int>(value.inSeconds),
          style: style,
        );
        if (!animate) {
          return text;
        }
        return AnimatedSwitcher(
          duration: AppMotion.quick,
          switchInCurve: AppMotion.enter,
          switchOutCurve: AppMotion.exit,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.4),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          ),
          child: text,
        );
      },
    );
  }
}
