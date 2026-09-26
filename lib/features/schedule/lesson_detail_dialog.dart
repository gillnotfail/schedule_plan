import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:schedule_plan/core/constants/app_constants.dart';
import 'package:schedule_plan/core/l10n/l10n_extensions.dart';
import 'package:schedule_plan/core/theme/app_colors.dart';
import 'package:schedule_plan/core/theme/app_motion.dart';
import 'package:schedule_plan/core/theme/theme_controller.dart';
import 'package:schedule_plan/core/utils/color_utils.dart';
import 'package:schedule_plan/data/models/course_detail.dart';
import 'package:schedule_plan/data/models/lesson.dart';

/// 课程详情弹窗里的动作（用户规格：右下角「去点名」/ 左下角「取消」）。
enum LessonDetailAction {
  /// 跳到考勤页，定位到这一节所在周几最近的日期与这门课**全部班级**的名单
  rollCall,

  /// 换一个课程放进这一格（收在右上角溢出菜单里，不占主操作位）
  changeCourse,

  /// 把这一格移出课表（课程本身仍留在课程管理里）
  remove,
}

/// 点已有课程的格子 → 弹**对话框**（用户规格）。
///
/// 为什么不是底部抽屉：抽屉只适合"看完就走"的信息展示，而这里的下一步动作
/// 是「去点名」，抽屉占掉下半屏、还压着课表，点完没有后续。用户明确要求换成
/// 圆角矩形对话框 —— 中间是课程详情，右下角「去点名」直接跳考勤页，
/// 左下角「取消」退出并把课表恢复成默认等宽。
///
/// 遮罩刻意比 Flutter 默认（54% 黑）浅，取 M3 规范的 32%：
/// 点格子时那一列会**先变宽**再弹窗，遮罩太黑就看不见这个反馈了。
Future<LessonDetailAction?> showLessonDetailDialog(
  BuildContext context, {
  required LessonWithTime lesson,
  required CourseDetail? detail,
}) {
  return showDialog<LessonDetailAction>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.32),
    builder: (_) => _LessonDetailDialog(lesson: lesson, detail: detail),
  );
}

/// 课程详情对话框。
///
/// 版式（用户规格："对话框和单元格部分的展示，字体需要居中"）：
/// - 顶部一条**课程色渐变带**（底色，不再是一张白纸），课程名居中、班级·时间居中；
/// - 中间每条信息是一枚**底色卡片**：标签靠左、内容居中——
///   标签统一宽度，值在剩余空间里居中，几行读下来是齐的；
/// - 底部左「取消」右「去点名」，次要动作（换课 / 移出）收进右上角。
class _LessonDetailDialog extends StatelessWidget {
  const _LessonDetailDialog({required this.lesson, required this.detail});

  final LessonWithTime lesson;
  final CourseDetail? detail;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tokens = context.watch<ThemeController>().tokens;
    // 配色与课表格子同一个来源：课程自己锁定的颜色优先，没锁过才回落班级色
    final accent = parseHexColor(
      detail?.color ?? lesson.classColor,
      scheme.primary,
    );

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(
        horizontal: AppConstants.spaceL,
        vertical: AppConstants.spaceXl,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          // 底色走主题 surface，深浅两套主题各自适配（用户规格：底色适配）
          color: tokens.surface,
          borderRadius: AppRadii.dialogAll,
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: tokens.shadow,
              blurRadius: 28,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: AppRadii.dialogAll,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _buildHeader(context, theme, scheme, tokens, accent),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppConstants.spaceL,
                  AppConstants.spaceM,
                  AppConstants.spaceL,
                  AppConstants.spaceM,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _InfoTile(
                      label: l10n.courseCountLabel,
                      value: l10n.cellStudentCount(detail?.studentCount ?? 0),
                      icon: Icons.groups_2_outlined,
                      accent: accent,
                      highlight: true,
                    ),
                    _InfoTile(
                      label: l10n.courseClassLabel,
                      value: _joinOrDash(
                        detail?.classNames ?? const <String>[],
                        lesson.className,
                      ),
                      icon: Icons.meeting_room_outlined,
                    ),
                    _InfoTile(
                      label: l10n.courseRoomLabel,
                      value: (detail?.room ?? '').trim().isEmpty
                          ? '—'
                          : detail!.room,
                      icon: Icons.map_outlined,
                    ),
                    _InfoTile(
                      label: l10n.headTeacher,
                      value: _joinOrDash(
                        detail?.headTeachers ?? const <String>[],
                        '',
                      ),
                      icon: Icons.badge_outlined,
                    ),
                    const SizedBox(height: AppConstants.spaceM),
                    // 左下角「取消」、右下角「去点名」——按用户规格固定这一版式
                    Row(
                      children: <Widget>[
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: Text(l10n.cancel),
                        ),
                        const Spacer(),
                        FilledButton.icon(
                          // 主题里的 FilledButton 是 `minimumSize: Size.fromHeight(52)`
                          // ——宽度是 infinity（表单里要撑满一行）。一旦它和 Spacer
                          // 并排，非 flex 子节点拿到的是无界宽度约束，整颗按钮会直接
                          // 抛 "BoxConstraints forces an infinite width"。所以这里
                          // 必须把最小宽度收回来，让它按内容自适应。
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(0, 48),
                          ),
                          onPressed: () {
                            AppMotion.confirm();
                            Navigator.of(context)
                                .pop(LessonDetailAction.rollCall);
                          },
                          icon: const Icon(Icons.how_to_reg_outlined, size: 18),
                          label: Text(l10n.goRollCall),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 顶部：课程色渐变带 + 居中的课程名 / 班级·时间，右上角是溢出菜单。
  Widget _buildHeader(
    BuildContext context,
    ThemeData theme,
    ColorScheme scheme,
    AppColorTokens tokens,
    Color accent,
  ) {
    final l10n = context.l10n;
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.spaceL,
        AppConstants.spaceXs,
        AppConstants.spaceS,
        AppConstants.spaceM,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            accent.withValues(alpha: 0.22),
            accent.withValues(alpha: 0.05),
          ],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              const SizedBox(width: 40),
              const Spacer(),
              // 次要动作（换课 / 移出）收进溢出菜单，主操作位只留给「去点名」
              PopupMenuButton<LessonDetailAction>(
                icon: Icon(
                  Icons.more_vert_rounded,
                  size: 20,
                  color: scheme.onSurfaceVariant,
                ),
                tooltip: l10n.moreActions,
                onSelected: (action) => Navigator.of(context).pop(action),
                itemBuilder: (_) => <PopupMenuEntry<LessonDetailAction>>[
                  PopupMenuItem<LessonDetailAction>(
                    value: LessonDetailAction.changeCourse,
                    child: Text(l10n.changeLessonCourse),
                  ),
                  PopupMenuItem<LessonDetailAction>(
                    value: LessonDetailAction.remove,
                    child: Text(
                      l10n.removeFromSchedule,
                      style: TextStyle(color: scheme.error),
                    ),
                  ),
                ],
              ),
            ],
          ),
          // 课程色圆形徽标 + 居中的课程名（用户规格：字体居中）
          Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.18),
              shape: BoxShape.circle,
              border: Border.all(color: accent.withValues(alpha: 0.5)),
            ),
            child: Icon(Icons.menu_book_rounded, size: 22, color: accent),
          ),
          const SizedBox(height: AppConstants.spaceS),
          Text(
            lesson.courseName,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: accent,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            '${lesson.className} · ${lesson.timeRangeText}',
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  String _joinOrDash(List<String> values, String fallback) {
    final list = values.where((item) => item.trim().isNotEmpty).toList();
    if (list.isNotEmpty) {
      return list.join('、');
    }
    return fallback.trim().isEmpty ? '—' : fallback;
  }
}

/// 详情里的一行：**标签靠左、内容居中**（用户规格），整行包一层底色卡片。
class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.label,
    required this.value,
    required this.icon,
    this.highlight = false,
    this.accent,
  });

  final String label;
  final String value;
  final IconData icon;
  final bool highlight;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tint = accent ?? scheme.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppConstants.spaceS),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppConstants.spaceM,
          vertical: 9,
        ),
        decoration: BoxDecoration(
          // 每行一块淡底：好几行叠起来才不显得空（用户规格：加点底色）
          color: highlight
              ? tint.withValues(alpha: 0.12)
              : scheme.surfaceContainer.withValues(alpha: 0.75),
          borderRadius: AppRadii.tileAll,
          border: Border.all(
            color: highlight
                ? tint.withValues(alpha: 0.35)
                : scheme.outlineVariant.withValues(alpha: 0.6),
          ),
        ),
        child: Row(
          children: <Widget>[
            Icon(
              icon,
              size: 15,
              color: highlight ? tint : scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            // 标签：固定宽度靠左，几行标签左边缘对齐
            SizedBox(
              width: AppConstants.dialogLabelWidth,
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: highlight ? tint : scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: AppConstants.spaceS),
            // 两列之间立一条细线：标签左、内容中，看起来才像"有意为之"的两列
            Container(
              width: 1,
              height: 16,
              color: scheme.outlineVariant,
            ),
            const SizedBox(width: AppConstants.spaceS),
            // 内容：在剩余空间里居中（用户规格：具体内容居中显示）
            Expanded(
              child: Text(
                value,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: highlight ? FontWeight.w800 : FontWeight.w600,
                  color: highlight ? tint : scheme.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
