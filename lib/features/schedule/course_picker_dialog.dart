import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:schedule_plan/core/constants/app_constants.dart';
import 'package:schedule_plan/core/l10n/l10n_extensions.dart';
import 'package:schedule_plan/core/theme/app_motion.dart';
import 'package:schedule_plan/core/theme/theme_controller.dart';
import 'package:schedule_plan/core/utils/color_utils.dart';
import 'package:schedule_plan/data/models/course_detail.dart';

/// 点空格子 → 弹**对话框**挑一门课放进这一格（用户规格）。
///
/// 为什么从底部抽屉改回对话框、从"左右滑动"改成"上下滑动"：
/// - 抽屉从底部升起，把小半个课表盖住，老师看不到自己点的是哪一格；
/// - 左右翻页一屏只能看一门课，课多的时候要滑很多次才知道有哪些课，
///   而且翻页手势与"放进这一格"的确认动作叠在一起，容易误操作。
///
/// 现在是：圆角对话框 + **带课程色的卡片列表**上下滚动，一眼能扫完所有课，
/// 点一下选中（再点右下角才真正放进去），错了随时取消。
Future<CourseDetail?> showCoursePickerDialog(
  BuildContext context, {
  required List<CourseDetail> courses,
  required String slotLabel,
}) {
  if (courses.isEmpty) {
    return Future<CourseDetail?>.value();
  }
  return showDialog<CourseDetail>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.32),
    builder: (_) => _CoursePickerDialog(courses: courses, slotLabel: slotLabel),
  );
}

class _CoursePickerDialog extends StatefulWidget {
  const _CoursePickerDialog({required this.courses, required this.slotLabel});

  final List<CourseDetail> courses;

  /// 「周一 · 第 3 节」——让老师确认正在往哪一格排课
  final String slotLabel;

  @override
  State<_CoursePickerDialog> createState() => _CoursePickerDialogState();
}

class _CoursePickerDialogState extends State<_CoursePickerDialog> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tokens = context.watch<ThemeController>().tokens;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(
        horizontal: AppConstants.spaceL,
        vertical: AppConstants.spaceXl,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
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
              // 顶带：目标格子 + 标题，全部居中（用户规格：对话框字体居中）
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppConstants.spaceL,
                  vertical: AppConstants.spaceM,
                ),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer.withValues(alpha: 0.38),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      l10n.pickCourseTitle,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.slotLabel,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: scheme.onPrimaryContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppConstants.spaceM,
                  AppConstants.spaceS,
                  AppConstants.spaceM,
                  0,
                ),
                child: Text(
                  l10n.pickCourseHint,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: AppConstants.spaceS),
              // 卡片列表：上下滚动，一屏能扫完所有课
              ConstrainedBox(
                constraints: const BoxConstraints(
                  maxHeight: AppConstants.pickCourseListMaxHeight,
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppConstants.spaceM,
                  ),
                  itemCount: widget.courses.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: AppConstants.spaceXs + 2),
                  itemBuilder: (context, index) => _CourseCard(
                    detail: widget.courses[index],
                    selected: index == _index,
                    onTap: () {
                      AppMotion.select();
                      setState(() => _index = index);
                    },
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppConstants.spaceL,
                  AppConstants.spaceM,
                  AppConstants.spaceL,
                  AppConstants.spaceM,
                ),
                child: Row(
                  children: <Widget>[
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(l10n.cancel),
                    ),
                    const Spacer(),
                    FilledButton.icon(
                      // 主题里的 FilledButton 最小宽度是 infinity，与 Spacer
                      // 并排会抛 "BoxConstraints forces an infinite width"
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 48),
                      ),
                      onPressed: () {
                        AppMotion.confirm();
                        Navigator.of(context).pop(widget.courses[_index]);
                      },
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: Text(l10n.placeHere),
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
}

/// 一张课程小卡片：课程色徽标 + **着色课程名** + 人数与班级，选中时整体提亮。
class _CourseCard extends StatelessWidget {
  const _CourseCard({
    required this.detail,
    required this.selected,
    required this.onTap,
  });

  final CourseDetail detail;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = parseHexColor(detail.color, scheme.primary);
    final headTeachers = detail.headTeachers.where((item) => item.isNotEmpty);
    final room = detail.room.trim();
    final subtitle = <String>[
      l10n.cellStudentCount(detail.studentCount),
      if (detail.classNames.isNotEmpty) detail.classNames.join('、'),
      if (room.isNotEmpty) room,
      if (headTeachers.isNotEmpty) headTeachers.join('、'),
    ].join(' · ');

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppMotion.standard,
        // 这里动的是**颜色 / 描边 / 阴影**，必须用 monotonic 的 effects 曲线。
        // 换成带过冲的 softSpring 会让插值参数越过 1，BoxShadow.lerp 把
        // blurRadius 算成负数，dart:ui 的 Shadow 断言当场炸（debug 直接崩，
        // release 下渲染也不可预期）。项目约定：位移才用 expressive/spring。
        curve: AppMotion.effects,
        padding: const EdgeInsets.symmetric(
          horizontal: AppConstants.spaceM,
          vertical: AppConstants.spaceS + 2,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[
              accent.withValues(alpha: selected ? 0.20 : 0.09),
              accent.withValues(alpha: selected ? 0.10 : 0.03),
            ],
          ),
          borderRadius: AppRadii.tileAll,
          border: Border.all(
            color: accent.withValues(alpha: selected ? 0.75 : 0.28),
            width: selected ? 1.6 : 1,
          ),
          boxShadow: selected
              ? <BoxShadow>[
                  BoxShadow(
                    color: accent.withValues(alpha: 0.26),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: <Widget>[
            // 课程色徽标：首字压在课程色上，颜色与课表格子一一对应
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: selected ? 0.9 : 0.7),
                borderRadius: AppRadii.smallAll,
              ),
              child: Text(
                _initial(detail.name),
                maxLines: 1,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: _onAccent(accent),
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: AppConstants.spaceM),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    detail.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: accent,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppConstants.spaceS),
            // 选中标记：一眼看出"就是这门课"
            AnimatedScale(
              duration: AppMotion.quick,
              curve: AppMotion.effects,
              scale: selected ? 1 : 0,
              child: Icon(
                Icons.check_circle_rounded,
                size: 20,
                color: accent,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 课程名首字（中英皆可），空名兜一个中性符号。
  String _initial(String name) {
    final trimmed = name.trim();
    return trimmed.isEmpty ? '课' : trimmed.characters.first;
  }

  /// 徽标上的字色：底色是课程色，按亮度选黑/白，六套主题都读得清。
  Color _onAccent(Color accent) =>
      ThemeData.estimateBrightnessForColor(accent) == Brightness.dark
          ? Colors.white
          : Colors.black87;
}
