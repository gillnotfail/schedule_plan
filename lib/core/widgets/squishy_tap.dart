import 'package:flutter/material.dart';

import 'package:schedule_plan/core/theme/app_motion.dart';

/// 「按的那一块散开」的可按压容器。
///
/// 用户规格（第 9 轮）："交互方式上，点击卡片，反馈从按的那一块散开，
/// 按压回弹，不是从按的地方缩一下就回来，是压过头再弹回来，保证点击的手感。"
///
/// 和老的 [ScaleTap]（整块向中心缩 4%）的区别：
/// - **缩放原点 = 手指按下去的那一点**，视觉上像是"从手指底下散开"；
/// - 按下时快速压到 92% 并轻微过冲（`softSpring`），松开用
///   [AppMotion.elastic]（`elasticOut`）弹回，**会越过 100% 再落回来**，
///   就是"压过头再弹回来"的手感，而不是单调复位。
class SquishyTap extends StatefulWidget {
  const SquishyTap({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.enabled = true,
    this.pressedScale = 0.92,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool enabled;

  /// 按下时压到的目标比例（越小越"压得深"）。
  final double pressedScale;

  @override
  State<SquishyTap> createState() => _SquishyTapState();
}

class _SquishyTapState extends State<SquishyTap>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppMotion.springMedium,
    value: 1.0,
  );

  /// 缩放原点：手指按下的位置（-1..1 的对齐量）。
  Alignment _origin = Alignment.center;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _down(TapDownDetails details) {
    if (!widget.enabled) {
      return;
    }
    final box = context.findRenderObject() as RenderBox?;
    if (box != null && box.hasSize && box.size.width > 0 && box.size.height > 0) {
      final local = box.globalToLocal(details.globalPosition);
      _origin = Alignment(
        (local.dx / box.size.width) * 2 - 1,
        (local.dy / box.size.height) * 2 - 1,
      );
    }
    AppMotion.tap();
    _controller.stop();
    _controller.animateTo(
      widget.pressedScale,
      duration: AppMotion.instant,
      curve: AppMotion.softSpring,
    );
  }

  void _up() {
    if (!widget.enabled) {
      return;
    }
    _controller.stop();
    _controller.animateTo(
      1.0,
      duration: AppMotion.springMedium,
      curve: AppMotion.elastic,
    );
  }

  void _cancel() {
    if (!widget.enabled) {
      return;
    }
    _controller.stop();
    _controller.animateTo(
      1.0,
      duration: AppMotion.quick,
      curve: AppMotion.effects,
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: _down,
      onTapUp: (_) => _up(),
      onTapCancel: _cancel,
      onTap: widget.enabled ? widget.onTap : null,
      onLongPress: widget.enabled ? widget.onLongPress : null,
      child: ScaleTransition(
        scale: _controller,
        alignment: _origin,
        child: widget.child,
      ),
    );
  }
}
