import 'package:flutter/material.dart';

import 'package:schedule_plan/core/constants/app_constants.dart';
import 'package:schedule_plan/core/theme/app_motion.dart';

/// 设置项 / 功能入口的统一列表行。
///
/// 现代观感要点：
/// - 左侧用**渐变小方块**承载图标，而不是裸图标，增强层次；
/// - 标题与副标题两行排版，副标题只做解释，不抢视觉；
/// - 右侧 chevron 用 Effects Spring 位移，暗示可进入。
class SettingsTile extends StatelessWidget {
  const SettingsTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.trailing,
    this.gradient,
    this.iconColor,
    this.danger = false,
    this.showChevron = true,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;
  final List<Color>? gradient;
  final Color? iconColor;
  final bool danger;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = danger ? scheme.error : scheme.primary;
    final colors = gradient ?? <Color>[accent, accent];

    return InkWell(
      borderRadius: AppRadii.tileAll,
      onTap: onTap == null
          ? null
          : () {
              AppMotion.tap();
              onTap!.call();
            },
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppConstants.spaceM,
          vertical: AppConstants.spaceM,
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: colors,
                ),
                borderRadius: AppRadii.smallAll,
              ),
              child: Icon(
                icon,
                size: 18,
                color: iconColor ?? Colors.white,
              ),
            ),
            const SizedBox(width: AppConstants.spaceM),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: danger ? scheme.error : scheme.onSurface,
                      letterSpacing: -0.1,
                    ),
                  ),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        subtitle!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          height: 1.25,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (trailing != null)
              trailing!
            else if (showChevron)
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: scheme.outline,
              ),
          ],
        ),
      ),
    );
  }
}

/// 设置分组容器：把若干内容行收进一张卡片，中间插入细分割线。
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({
    super.key,
    required this.children,
    this.dividerIndent = AppConstants.spaceL,
  });

  final List<Widget> children;

  /// 分割线左侧缩进（默认与设置行图标对齐）。
  final double dividerIndent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      rows.add(children[i]);
      if (i != children.length - 1) {
        rows.add(
          Divider(
            height: 1,
            thickness: 1,
            indent: dividerIndent,
            endIndent: dividerIndent,
            color: scheme.outlineVariant.withValues(alpha: 0.55),
          ),
        );
      }
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppConstants.spaceL),
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: AppRadii.squircelAll,
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.6),
          ),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: scheme.shadow.withValues(alpha: 0.06),
              blurRadius: 16,
              offset: const Offset(0, 5),
              spreadRadius: -4,
            ),
          ],
        ),
        child: Column(children: rows),
      ),
    );
  }
}

/// 分组标题（设置页 / 统计设置页复用）。
class GroupHeader extends StatelessWidget {
  const GroupHeader({
    super.key,
    required this.title,
    this.icon,
    this.description,
  });

  final String title;
  final IconData? icon;
  final String? description;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.spaceXl,
        AppConstants.spaceXl,
        AppConstants.spaceXl,
        AppConstants.spaceS,
      ),
      child: Row(
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 15, color: scheme.primary),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: scheme.primary,
                    letterSpacing: 0.2,
                  ),
                ),
                if (description != null)
                  Text(
                    description!,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
