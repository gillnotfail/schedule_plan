import 'package:flutter/material.dart';

import 'package:schedule_plan/core/constants/app_constants.dart';
import 'package:schedule_plan/core/theme/app_motion.dart';

/// 现代卡片（Material 3 Expressive 的 Squircel 形状）。
///
/// 与旧版的区别：
/// - 圆角从 16dp 提到 22dp 的高曲率 Squircel，与内部的胶囊按钮形成**形状对比**；
/// - 用极低透明度的柔和阴影替代老式 elevation，避免"卡片浮在纸板上"的廉价感；
/// - 按下时用 Spatial Spring（软过冲）缩放，配合触觉反馈。
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppConstants.spaceL),
    this.onTap,
    this.onLongPress,
    this.color,
    this.borderColor,
    this.radius = AppRadii.squircel,
    this.elevated = true,
    this.gradient,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Color? color;
  final Color? borderColor;
  final double radius;

  /// 是否绘制柔和阴影（嵌套在另一个卡片内时应关闭）。
  final bool elevated;

  /// 可选的强调渐变背景。
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
    );
    final card = AnimatedContainer(
      duration: AppMotion.standard,
      curve: AppMotion.effects,
      padding: padding,
      decoration: BoxDecoration(
        color: gradient == null ? (color ?? scheme.surface) : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(radius),
        border: borderColor == null
            ? Border.all(
                color: scheme.outlineVariant.withValues(alpha: 0.6),
                width: 1,
              )
            : Border.all(color: borderColor!, width: 1),
        boxShadow: !elevated || gradient != null
            ? null
            : <BoxShadow>[
                BoxShadow(
                  color: (color == null ? scheme.shadow : scheme.shadow)
                      .withValues(alpha: scheme.brightness == Brightness.dark
                          ? 0.34
                          : 0.07),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                  spreadRadius: -4,
                ),
              ],
      ),
      child: child,
    );
    if (onTap == null && onLongPress == null) {
      return card;
    }
    return _PressableCard(
      shape: shape,
      onTap: onTap,
      onLongPress: onLongPress,
      child: card,
    );
  }
}

class _PressableCard extends StatefulWidget {
  const _PressableCard({
    required this.child,
    required this.shape,
    this.onTap,
    this.onLongPress,
  });

  final Widget child;
  final ShapeBorder shape;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  State<_PressableCard> createState() => _PressableCardState();
}

class _PressableCardState extends State<_PressableCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: () {
        AppMotion.tap();
        widget.onTap?.call();
      },
      onLongPress: widget.onLongPress == null
          ? null
          : () {
              AppMotion.confirm();
              widget.onLongPress?.call();
            },
      child: AnimatedScale(
        scale: _pressed ? AppConstants.pressScale : 1.0,
        duration: AppMotion.instant,
        curve: AppMotion.softSpring,
        child: widget.child,
      ),
    );
  }
}

/// 分区标题（设置页、工具箱页的分组头）。
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.trailing,
    this.icon,
    this.description,
  });

  final String title;
  final Widget? trailing;
  final IconData? icon;
  final String? description;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.spaceL,
        AppConstants.spaceXl,
        AppConstants.spaceL,
        AppConstants.spaceS,
      ),
      child: Row(
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: scheme.secondaryContainer.withValues(alpha: 0.7),
                borderRadius: AppRadii.smallAll,
              ),
              child: Icon(icon, size: 17, color: scheme.onSecondaryContainer),
            ),
            const SizedBox(width: AppConstants.spaceM),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                  ),
                ),
                if (description != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      description!,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// 空状态占位。
class EmptyView extends StatelessWidget {
  const EmptyView({
    super.key,
    required this.message,
    this.icon,
    this.action,
  });

  final String message;
  final IconData? icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.spaceXl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(AppRadii.squircel),
              ),
              child: Icon(
                icon ?? Icons.inbox_outlined,
                size: 38,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppConstants.spaceL),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            if (action != null) ...<Widget>[
              const SizedBox(height: AppConstants.spaceL),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
