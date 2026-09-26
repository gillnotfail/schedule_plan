import 'package:flutter/material.dart';

import 'package:schedule_plan/core/constants/app_constants.dart';
import 'package:schedule_plan/core/theme/app_motion.dart';

/// 按钮/卡片的按下缩放反馈。
///
/// M3E 规范 3：按下缩小至 96%，松开以 **轻微回弹** 的方式弹回（约 100ms）。
/// 用 `AppMotion.softSpring` 而不是 `easeOut`——纯单调上升的曲线会让
/// 「松手」变成一个无声的复位，缺少 Expressive 的手感。
class ScaleTap extends StatefulWidget {
  const ScaleTap({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.enabled = true,
    this.scale = AppConstants.pressScale,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool enabled;
  final double scale;

  @override
  State<ScaleTap> createState() => _ScaleTapState();
}

class _ScaleTapState extends State<ScaleTap> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (!widget.enabled) {
      return;
    }
    if (_pressed == value) {
      return;
    }
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      onTap: widget.enabled ? widget.onTap : null,
      onLongPress: widget.enabled ? widget.onLongPress : null,
      child: AnimatedScale(
        scale: _pressed ? widget.scale : 1.0,
        duration: AppMotion.instant,
        curve: AppMotion.softSpring,
        child: widget.child,
      ),
    );
  }
}

/// 带缩放反馈的实心按钮。
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final child = icon == null
        ? Text(label)
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[Icon(icon, size: 18), const SizedBox(width: 8), Text(label)],
          );
    final button = FilledButton(
      onPressed: onPressed,
      child: child,
    );
    return ScaleTap(
      enabled: onPressed != null,
      child: expand ? SizedBox(width: double.infinity, child: button) : button,
    );
  }
}
