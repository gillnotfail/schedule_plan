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
    AttendanceStatus.lateAndEarly => l10n.statusLateAndEarly,
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
/// 组合态 [AttendanceStatus.lateAndEarly] 没有自己的胶囊（靠「迟」「早」
/// 两枚同时高亮表示），但它仍然是合法状态，这里给个短名备用。
String statusShortLabelOf(BuildContext context, AttendanceStatus status) {
  final l10n = context.l10n;
  return switch (status) {
    AttendanceStatus.present => l10n.statusShortPresent,
    AttendanceStatus.late => l10n.statusShortLate,
    AttendanceStatus.earlyLeave => l10n.statusShortEarlyLeave,
    AttendanceStatus.lateAndEarly => l10n.statusShortLateAndEarly,
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
      AttendanceStatus.lateAndEarly => tokens.attendanceLateAndEarly,
      AttendanceStatus.absent => tokens.attendanceAbsent,
      AttendanceStatus.leave => tokens.attendanceLeave,
      AttendanceStatus.suspended => tokens.attendanceSuspended,
      AttendanceStatus.exempt => tokens.attendanceExempt,
      AttendanceStatus.unmarked => tokens.attendanceUnmarked,
    };

/// 平铺在每条学生信息后面的「一键考勤状态」。
///
/// 用户规格（本控件存在的唯一理由）：考勤状态不要再让老师"滑动一个个选"，
/// 也不要循环点击四五次才轮到"请假"。状态摊开摆在学生信息后面，
/// 想点哪个点哪个，**一次点击 = 一次落库**，这是"最快点名"的形态。
/// 位置不够就显示成一个字（见 [statusShortLabelOf]），全称放进 Tooltip。
///
/// 「迟」「早」两枚是**可以同时点亮**的（迟到 and 早退，不是 or）：
/// 一节课点名两次时，同一个学生常常上课迟到了、下课又提前走。
/// 点完「迟」再点「早」是**加上**，不会把迟到冲掉；两枚都亮时落库的是
/// [AttendanceStatus.lateAndEarly]（一条记录，统计只算一次异常）。
/// 出勤 / 缺勤 / 请假仍是单选：点它们就把迟到早退一起清掉。
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
  /// 与 [status] 是**并列**的两件事：[status] 决定日常状态里哪一枚高亮，
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
  /// "未标记"只是显示态，不作为选项摊出来；
  /// 「迟到+早退」也没有自己的胶囊 —— 它由「迟」「早」两枚同时高亮表示。
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
              selected: _isSelected(choices[i], activeLongTermStatus),
              dimmed: locked && choices[i] != activeLongTermStatus,
              onTap: locked && choices[i] != activeLongTermStatus
                  ? null
                  : () => _pick(choices[i]),
            ),
          ],
        ],
      ),
    );
  }

  /// 这一枚此刻该不该高亮。
  ///
  /// 「迟」「早」看的是**位**而不是相等：`lateAndEarly` 时两枚都亮 ——
  /// 老师一眼就能看出"这孩子既迟又早"，不用去记一个组合态名字。
  bool _isSelected(
    AttendanceStatus choice,
    AttendanceStatus? activeLongTermStatus,
  ) {
    if (choice.isLongTerm) {
      return choice == activeLongTermStatus;
    }
    return switch (choice) {
      AttendanceStatus.late => status.isLate,
      AttendanceStatus.earlyLeave => status.isEarlyLeave,
      _ => choice == status,
    };
  }

  /// 点某一枚胶囊时该怎么落库。
  ///
  /// - 「迟」「早」：**加上**这一头，不是替换 —— 点完迟到再点早退得到
  ///   [AttendanceStatus.lateAndEarly]，迟到不会被冲掉；
  /// - 已亮的那一头再点一次 = 减去这一头（组合态 → 只剩另一头）。
  ///   **单迟到再点「迟」不写库**（只回传原状态，由页面给一次触觉反馈）：
  ///   手指抖一下就把"迟到"抹成"出勤"，代价太大；要恢复出勤请显式点「出」；
  /// - 出勤 / 缺勤 / 请假：单选，直接落库，迟到早退一并清掉。
  void _pick(AttendanceStatus tapped) {
    if (tapped != AttendanceStatus.late &&
        tapped != AttendanceStatus.earlyLeave) {
      onPick(tapped);
      return;
    }
    final hasLate = status.isLate;
    final hasEarly = status.isEarlyLeave;
    final tappingLate = tapped == AttendanceStatus.late;
    final wasOn = tappingLate ? hasLate : hasEarly;
    if (!wasOn) {
      onPick(
        AttendanceStatus.fromLateEarly(
          late: tappingLate || hasLate,
          earlyLeave: !tappingLate || hasEarly,
        ),
      );
      return;
    }
    // 已亮着：只有"两枚都亮"时才允许从胶囊上减掉一头
    if (!(hasLate && hasEarly)) {
      onPick(status);
      return;
    }
    onPick(
      AttendanceStatus.fromLateEarly(
        late: tappingLate ? false : hasLate,
        earlyLeave: tappingLate ? hasEarly : false,
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
/// [onTap] 为空 = 这一格此刻不可点（例如学生处于休学，日常状态与免修胶囊被锁）。
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
    final label = statusShortLabelOf(context, status);
    // 胶囊宽度只放得下一个字，英文的两三字缩写（"EL"、"Sus"）按字数缩字号，
    // 宁可小一点也不能溢出或者被省略号截断。
    final fontSize = label.runes.length <= 1
        ? 11.5
        : (label.runes.length == 2 ? 10.0 : 8.8);
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
        label,
        maxLines: 1,
        softWrap: false,
        textAlign: TextAlign.center,
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w800,
          color: foreground,
          fontSize: fontSize,
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
