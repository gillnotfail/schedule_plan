import 'package:flutter/material.dart';

import 'package:schedule_plan/core/constants/app_constants.dart';
import 'package:schedule_plan/core/l10n/l10n_extensions.dart';
import 'package:schedule_plan/core/widgets/sort_arrow.dart';
import 'package:schedule_plan/data/models/student.dart';

/// 考勤名单里的**班级分组横带**。
///
/// 用户规格（本轮核心）："最好如图，按班级排序，每个班的学生划在区分线。
/// ui 还是你的 ui 那一套，只是思路是，按照班级分类学生，
/// 同时每个班支持姓名，学号，考勤等排序。"
///
/// 所以横带就是"这个班的表头"：左边是班名（带一道主色脊，把整组圈住）+
/// 这个班的人数，右边三枚紧凑排序胶囊。
///
/// 排序状态是**全班共用的那一份**（并记忆在本地），在任意一个班的横带上点一下，
/// 所有班都按同一口径重排 —— 每个班各自记住一套排序反而会让人对不上号；
/// 参考图里两个班的横带也都显示同一种激活排序，与此一致。
///
/// 这个组件单独抽成一个文件（而不是留在 `attendance_page.dart` 里当私有类），
/// 是为了能像 [AttendanceStatusStrip] 那样被 widget 测试直接渲染 ——
/// 横带是全页最挤的一行（班名 + 人数 + 三枚排序），必须守住"窄屏不溢出"。
class ClassGroupBand extends StatelessWidget {
  const ClassGroupBand({
    super.key,
    required this.className,
    required this.fallbackLabel,
    required this.count,
    required this.sortMode,
    required this.direction,
    required this.onSortTap,
    this.topGap = false,
  });

  final String className;

  /// 班级表里查不到名字时的兜底文案（不让横带变成一条空白）
  final String fallbackLabel;

  /// 这个班的人数
  final int count;

  /// 当前生效的排序列（所有班共用一份）
  final StudentSortMode sortMode;
  final SortDirection direction;
  final ValueChanged<StudentSortMode> onSortTap;

  /// 非首个分组时上方多留一点空隙，让班与班之间"划得开"
  final bool topGap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final name = className.trim().isEmpty ? fallbackLabel : className;
    return Padding(
      padding: EdgeInsets.only(
        top: topGap ? AppConstants.spaceM : AppConstants.spaceXs,
        bottom: AppConstants.spaceS,
      ),
      child: Container(
        height: AppConstants.rosterGroupBandHeight,
        padding: const EdgeInsets.symmetric(horizontal: AppConstants.spaceM),
        decoration: BoxDecoration(
          color: scheme.secondaryContainer.withValues(alpha: 0.55),
          borderRadius: AppRadii.stadiumAll,
        ),
        child: Row(
          children: <Widget>[
            // 左色脊：横带和它下面的名单在视觉上连成一组
            Container(
              width: 3,
              height: 18,
              decoration: BoxDecoration(
                color: scheme.primary,
                borderRadius: AppRadii.stadiumAll,
              ),
            ),
            const SizedBox(width: AppConstants.spaceS),
            Flexible(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: scheme.onSecondaryContainer,
                  letterSpacing: -0.2,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              context.l10n.rosterGroupCount(count),
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSecondaryContainer.withValues(alpha: 0.75),
              ),
            ),
            const Spacer(),
            for (final mode in StudentSortMode.values)
              SortHeaderButton(
                label: studentSortLabelOf(context, mode),
                direction: direction,
                active: sortMode == mode,
                compact: true,
                onTap: (_) => onSortTap(mode),
              ),
          ],
        ),
      ),
    );
  }
}

/// 班内排序列的显示名：姓名 / 学号 / 考勤。
///
/// 字号必须短——横带里要和班名、人数并排放下三枚，长了就挤。
String studentSortLabelOf(BuildContext context, StudentSortMode mode) {
  final l10n = context.l10n;
  return switch (mode) {
    StudentSortMode.namePinyin => l10n.studentNameShort,
    StudentSortMode.studentNo => l10n.studentNoShort,
    StudentSortMode.attendanceStatus => l10n.attendanceColumn,
  };
}
