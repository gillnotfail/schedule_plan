import 'package:flutter/material.dart';

import 'package:schedule_plan/core/theme/app_motion.dart';

/// 列表项错峰入场（M3 Expressive 的 choreographed entrance）。
///
/// 每一项：淡入 + 从下方 14dp 上移 + 轻微缩放，
/// 相邻项间隔 [AppMotion.listStaggerStep]，超过 [AppMotion.listStaggerCap]
/// 后不再累加，避免长列表尾部"排队等太久"。
class StaggeredEntrance extends StatefulWidget {
  const StaggeredEntrance({
    super.key,
    required this.index,
    required this.child,
    this.enabled = true,
  });

  final int index;
  final Widget child;

  /// 关闭动画（用于单元测试与超长列表）。
  final bool enabled;

  @override
  State<StaggeredEntrance> createState() => _StaggeredEntranceState();
}

class _StaggeredEntranceState extends State<StaggeredEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _offset;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AppMotion.springMedium,
    );
    final curved = CurvedAnimation(
      parent: _controller,
      curve: AppMotion.expressive,
    );
    _opacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0, 0.6, curve: AppMotion.enter),
    );
    _offset = Tween<Offset>(
      begin: const Offset(0, 0.14),
      end: Offset.zero,
    ).animate(curved);
    _scale = Tween<double>(begin: 0.96, end: 1.0).animate(curved);
    _schedule();
  }

  Future<void> _schedule() async {
    if (!widget.enabled) {
      _controller.value = 1;
      return;
    }
    await Future<void>.delayed(AppMotion.staggerFor(widget.index));
    if (mounted) {
      await _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) {
      return widget.child;
    }
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(
        position: _offset,
        child: ScaleTransition(scale: _scale, child: widget.child),
      ),
    );
  }
}
