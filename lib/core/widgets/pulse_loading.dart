import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:schedule_plan/core/constants/app_constants.dart';
import 'package:schedule_plan/core/theme/app_motion.dart';

/// 加载状态统一使用脉冲环动画。
///
/// 规范 9：禁止使用无说明的裸 Loading 圈 —— 本组件总是携带一条说明文案。
class PulseLoading extends StatefulWidget {
  const PulseLoading({super.key, this.message, this.size = 56});

  final String? message;
  final double size;

  @override
  State<PulseLoading> createState() => _PulseLoadingState();
}

class _PulseLoadingState extends State<PulseLoading>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AppMotion.pulse,
    )..repeat();
  }

  @override
  void dispose() {
    // readme 第六章：Timer / 动画控制器必须在 dispose 中显式释放
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              return CustomPaint(
                size: Size(widget.size, widget.size),
                painter: _PulseRingPainter(
                  progress: _controller.value,
                  color: theme.colorScheme.primary,
                ),

              );
            },
          ),
          if (widget.message != null) ...<Widget>[
            const SizedBox(height: AppConstants.spaceM),
            Text(
              widget.message!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PulseRingPainter extends CustomPainter {
  const _PulseRingPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;
    for (var i = 0; i < 3; i++) {
      final phase = (progress + i / 3) % 1.0;
      final radius = maxRadius * phase;
      final opacity = (1 - phase) * 0.9;
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = color.withValues(alpha: opacity.clamp(0.0, 1.0)),
      );
    }
    canvas.drawCircle(
      center,
      maxRadius * 0.18,
      Paint()..color = color.withValues(alpha: 0.9),
    );
  }

  @override
  bool shouldRepaint(covariant _PulseRingPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}

/// 引导用户注意某个新功能入口的交错脉冲提示（模块八：脉冲环/交错动画）。
class PulseHint extends StatefulWidget {
  const PulseHint({super.key, required this.child});

  final Widget child;

  @override
  State<PulseHint> createState() => _PulseHintState();
}

class _PulseHintState extends State<PulseHint>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AppMotion.pulse,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final scale = 1.0 + 0.06 * math.sin(_controller.value * math.pi);
        return Transform.scale(scale: scale, child: child);
      },
      child: widget.child,
    );
  }
}
