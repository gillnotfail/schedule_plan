import 'package:flutter/material.dart';

import 'package:schedule_plan/core/constants/app_constants.dart';
import 'package:schedule_plan/core/l10n/l10n_extensions.dart';
import 'package:schedule_plan/core/theme/app_colors.dart';
import 'package:schedule_plan/core/theme/app_motion.dart';
import 'package:schedule_plan/data/models/attendance.dart';

/// 考勤状态的全称文案（表头提示 / 复制摘要 / 胶囊 Tooltip 共用）。
///
/// 全项目**只有这一处**状态文案映射：行内 Tooltip、复制摘要、设置页下拉、
/// 统计页图例都从这里取，避免新增状态时漏改某一处造成"同一个状态两个叫法"。
String statusLabelOf(BuildContext context, AttendanceStatus status) {
  final l10n = context.l10n;
  return switch (status) {
    AttendanceStatus.present => l10n.statusPresent,
    AttendanceStatus.late => l10n.statusLate,
    AttendanceStatus.earlyLeave => l10n.statusEarlyLeave,
    AttendanceStatus.absent => l10n.statusAbsent,
    AttendanceStatus.leave => l10n.statusLeave,
    AttendanceStatus.suspended => l10n.statusSuspended,
    AttendanceStatus.exempt => l10n.statusExempt,
    AttendanceStatus.unmarked => l10n.statusUnmarked,
  };
}

/// 考勤状态的**单字**文案：一键胶囊上用的就是它。
///
/// 用户规格："如果大小不够，可以简化成一个字" —— 宁可缩成一个字，
/// 也不要让老师为了标记一个状态去滑动挑选或者循环点击。
String statusShortLabelOf(BuildContext context, AttendanceStatus status) {
  final l10n = context.l10n;
  return switch (status) {
    AttendanceStatus.present => l10n.statusShortPresent,
    AttendanceStatus.late => l10n.statusShortLate,
    AttendanceStatus.earlyLeave => l10n.statusShortEarlyLeave,
    AttendanceStatus.absent => l10n.statusShortAbsent,
    AttendanceStatus.leave => l10n.statusShortLeave,
    AttendanceStatus.suspended => l10n.statusShortSuspended,
    AttendanceStatus.exempt => l10n.statusShortExempt,
    AttendanceStatus.unmarked => l10n.statusShortUnmarked,
  };
}

/// 考勤状态的语义色（出勤绿 / 迟到橙 / 早退紫 / 缺勤红 / 请假蓝）。
///
/// 状态色**不随主题色漂移**，只随明暗模式切换 —— 换主题之后
/// "红=缺勤"这种全国通用的认知不能变，否则老师一眼扫不出异常。
Color statusColorOf(AppColorTokens tokens, AttendanceStatus status) =>
    switch (status) {
      AttendanceStatus.present => tokens.attendancePresent,
      AttendanceStatus.late => tokens.attendanceLate,
      AttendanceStatus.earlyLeave => tokens.attendanceEarlyLeave,
      AttendanceStatus.absent => tokens.attendanceAbsent,
      AttendanceStatus.leave => tokens.attendanceLeave,
      AttendanceStatus.suspended => tokens.attendanceSuspended,
      AttendanceStatus.exempt => tokens.attendanceExempt,
      AttendanceStatus.unmarked => tokens.attendanceUnmarked,
    };

/// 平铺在每条学生信息后面的「一键考勤状态」。
///
/// 用户规格（本控件存在的唯一理由）：考勤状态不要再让老师"滑动一个个选"，
/// 也不要循环点击四五次才轮到"请假"。五种状态摊开摆在学生信息后面，
/// 想点哪个点哪个，**一次点击 = 一次落库**，这是"最快点名"的形态。
/// 位置不够就显示成一个字（见 [statusShortLabelOf]），全称放进 Tooltip。
class AttendanceStatusStrip extends StatelessWidget {
  const AttendanceStatusStrip({
    super.key,
    required this.status,
    required this.tokens,
    required this.onPick,
    this.activeLongTerm,
    this.locked = false,
  });

  /// 当前有效的**日常**状态（已落库状态，或设置里的默认状态）。
  ///
  /// 休学时这里传的是「休学」本身（整行锁死，休学胶囊就是唯一高亮）；
  /// 免修时这里仍是日常状态——免修不覆盖迟到早退，两者是并列的。
  final AttendanceStatus status;
  final AppColorTokens tokens;
  final ValueChanged<AttendanceStatus> onPick;

  /// 生效中的长期状态（休学 / 免修），为 null 表示正常点名。
  ///
  /// 与 [status] 是**并列**的两件事：[status] 决定日常五态里哪一枚高亮，
  /// [activeLongTerm] 决定长期两态里哪一枚高亮——这正是「免修与迟到早退可以
  /// 同时存在」的形态：日常胶囊亮「迟」，免修胶囊亮「免」。
  final AttendanceStatus? activeLongTerm;

  /// 该生在这门课上处于「休学」时置真。
  ///
  /// 休学期间这个学生不来了，所以**除休学胶囊以外的全部胶囊置灰不可点**
  /// （想恢复点名就再点那枚休学胶囊，由调用方弹出「复学」确认）。
  /// 免修**不**置锁：免修的学生仍会来上课，迟到早退照常标记。
  final bool locked;

  /// 可一键选中的七个状态（日常五种 + 长期两种）。
  /// "未标记"只是显示态，不作为选项摊出来。
  static const List<AttendanceStatus> choices = AttendanceStatus.choices;

  @override
  Widget build(BuildContext context) {
    // 生效中的长期胶囊：优先用显式传入的 activeLongTerm；
    // 老调用方只传 status（且 status 本身就是长期状态）时回落到它，保证兼容。
    final activeLongTermStatus =
        activeLongTerm ?? (status.isLongTerm ? status : null);
    return SizedBox(
      width: AppConstants.attendanceStatusStripWidth,
      child: Row(
        children: <Widget>[
          for (var i = 0; i < choices.length; i++) ...<Widget>[
            if (i > 0)
              SizedBox(
                // 长期状态自成一组的视觉分隔
                width: _gapBefore(i),
              ),
            _StatusChip(
              status: choices[i],
              color: statusColorOf(tokens, choices[i]),
              selected:
                  choices[i] == status || choices[i] == activeLongTermStatus,
              dimmed: locked && choices[i] != activeLongTermStatus,
              onTap: locked && choices[i] != activeLongTermStatus
                  ? null
                  : () => onPick(choices[i]),
            ),
          ],
        ],
      ),
    );
  }

  /// 第 [index] 枚胶囊左侧的间距：跨进长期状态那一组时用更宽的缝。
  double _gapBefore(int index) {
    final previous = choices[index - 1];
    final current = choices[index];
    return current.isLongTerm && !previous.isLongTerm
        ? AppConstants.attendanceLongTermGroupGap
        : AppConstants.attendanceStatusChipGap;
  }
}

/// 单个考勤状态胶囊：一个字、点一下直接落库。
///
/// [onTap] 为空 = 这一格此刻不可点（例如学生处于休学，日常五态与免修胶囊被锁）。
class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.status,
    required this.color,
    required this.selected,
    required this.onTap,
    this.dimmed = false,
  });

  final AttendanceStatus status;
  final Color color;
  final bool selected;
  final VoidCallback? onTap;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 状态色在深色主题下是浅色（如 #6BD98F），白字会看不清 ——
    // 按底色亮度选前景色，两套主题都要可读。
    final foreground = selected
        ? (ThemeData.estimateBrightnessForColor(color) == Brightness.dark
              ? Colors.white
              : Colors.black87)
        : color;
    final chip = AnimatedContainer(
      duration: AppMotion.quick,
      curve: AppMotion.effects,
      width: AppConstants.attendanceStatusChipWidth,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: selected ? color : color.withValues(alpha: 0.10),
        borderRadius: AppRadii.smallAll,
        border: Border.all(
          color: color.withValues(alpha: selected ? 1 : 0.3),
          width: selected ? 1.4 : 1,
        ),
      ),
      child: Text(
        statusShortLabelOf(context, status),
        maxLines: 1,
        softWrap: false,
        textAlign: TextAlign.center,
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w800,
          color: foreground,
          fontSize: 11.5,
          letterSpacing: 0,
        ),
      ),
    );
    return Tooltip(
      message: statusLabelOf(context, status),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: dimmed ? Opacity(opacity: 0.32, child: chip) : chip,
      ),
    );
  }
}
