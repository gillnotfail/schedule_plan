import 'package:flutter/material.dart';

import 'package:schedule_plan/core/constants/app_constants.dart';
import 'package:schedule_plan/core/theme/app_motion.dart';

/// 排序方向。
enum SortDirection {
  ascending,
  descending;

  SortDirection get toggled =>
      this == SortDirection.ascending ? descending : ascending;
}

/// 「两个三角形叠加」的排序指示器。
///
/// 交互契约（用户规格）：
/// - 未选中时两个三角都是淡色；
/// - 点一下 → 升序，**上面**三角高亮；
/// - 再点一下 → 降序，**下面**三角高亮；
/// - 再点一下 → 回到升序（不提供"取消排序"，避免列表乱序）。
///
/// 三角形用 CustomPaint 绘制而非图标字体，保证上下两枚严格贴合、
/// 高亮切换时是 Effects Spring 过渡而不是硬切。
class SortArrow extends StatelessWidget {
  const SortArrow({
    super.key,
    required this.direction,
    required this.active,
    required this.color,
    this.size = 16,
  });

  final SortDirection direction;
  final bool active;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _SortArrowPainter(
        direction: direction,
        active: active,
        color: color,
      ),
    );
  }
}

class _SortArrowPainter extends CustomPainter {
  const _SortArrowPainter({
    required this.direction,
    required this.active,
    required this.color,
  });

  final SortDirection direction;
  final bool active;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    // 单个三角高度：留出中间 14% 的缝隙，形成"叠加"观感
    final gap = size.height * 0.14;
    final h = (size.height - gap) / 2;

    final dim = color.withValues(alpha: active ? 0.32 : 0.32);
    final lit = color;

    _drawTriangle(
      canvas,
      Rect.fromLTWH(0, 0, w, h),
      active && direction == SortDirection.ascending ? lit : dim,
      up: true,
    );
    _drawTriangle(
      canvas,
      Rect.fromLTWH(0, h + gap, w, h),
      active && direction == SortDirection.descending ? lit : dim,
      up: false,
    );
  }

  void _drawTriangle(Canvas canvas, Rect rect, Color color, {required bool up}) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    final path = Path();
    if (up) {
      path.moveTo(rect.center.dx, rect.top);
      path.lineTo(rect.right, rect.bottom);
      path.lineTo(rect.left, rect.bottom);
    } else {
      path.moveTo(rect.center.dx, rect.bottom);
      path.lineTo(rect.right, rect.top);
      path.lineTo(rect.left, rect.top);
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SortArrowPainter oldDelegate) =>
      oldDelegate.direction != direction ||
      oldDelegate.active != active ||
      oldDelegate.color != color;
}

/// 表头排序按钮：图标 + 文案 + 双三角标志。
///
/// 点击后在 升序 → 降序 之间切换，并触发触觉反馈。
///
/// [compact] 用于**空间紧张的横向容器**（例如考勤页每个班级分组横带右侧
/// 那三枚"姓名 / 学号 / 考勤"）——省掉图标、收紧内边距和字号，
/// 三枚并排也放得下，视觉上仍然和普通表头是同一套语言。
class SortHeaderButton extends StatelessWidget {
  const SortHeaderButton({
    super.key,
    required this.label,
    required this.direction,
    required this.active,
    required this.onTap,
    this.icon,
    this.compact = false,
  });

  final String label;

  /// 紧凑模式下不显示图标
  final IconData? icon;
  final SortDirection direction;
  final bool active;
  final ValueChanged<SortDirection> onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = active ? scheme.primary : scheme.onSurfaceVariant;
    final icon = this.icon;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: AppRadii.stadiumAll,
        onTap: () {
          AppMotion.select();
          onTap(active ? direction.toggled : SortDirection.ascending);
        },
        child: AnimatedContainer(
          duration: AppMotion.quick,
          curve: AppMotion.effects,
          padding: EdgeInsets.symmetric(
            horizontal: compact ? AppConstants.spaceS : AppConstants.spaceM,
            vertical: compact ? 3 : 6,
          ),
          decoration: BoxDecoration(
            color: active
                ? scheme.secondaryContainer.withValues(alpha: 0.75)
                : Colors.transparent,
            borderRadius: AppRadii.stadiumAll,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (icon != null && !compact) ...<Widget>[
                Icon(icon, size: 15, color: accent),
                const SizedBox(width: 5),
              ],
              Text(
                label,
                style: (compact
                        ? theme.textTheme.labelSmall
                        : theme.textTheme.labelMedium)
                    ?.copyWith(
                  color: accent,
                  fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
              SizedBox(width: compact ? 2 : 4),
              SortArrow(
                direction: direction,
                active: active,
                color: accent,
                size: compact ? 13 : 16,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
