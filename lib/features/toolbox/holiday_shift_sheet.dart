import 'package:flutter/material.dart';

import 'package:schedule_plan/core/constants/app_constants.dart';
import 'package:schedule_plan/core/l10n/l10n_extensions.dart';
import 'package:schedule_plan/core/theme/app_motion.dart';
import 'package:schedule_plan/core/widgets/app_card.dart';
import 'package:schedule_plan/core/widgets/confirm_dialog.dart';

/// 老师对某个调休日"上周几的课"的选择结果。
///
/// 单独包一层是因为 [Future] 只能区分"取消"(null) 和"有结果"，
/// 而"选不调整"本身也是一个有效结果（要清掉之前存的映射）。
class HolidayShiftChoice {
  const HolidayShiftChoice(this.weekday);

  /// null = 不调整（按当天自己的星期几）。
  final int? weekday;
}

/// 「这天上周几的课？」选择弹层（调休上班日专用）。
///
/// 用户规格（第 13 轮）："如果周六日轮到调休，最好有个功能，在调休那天提醒老师
/// 上周几的课。" 国务院只规定哪天上班，**没说**补班那天上星期几的课——
/// 那是各校自己的通知（同一个市的不同学校都可能不一样），所以这里不替老师猜，
/// 而是让他选一次，之后课时结算按他选的算。
///
/// 返回 null 表示放弃（没改任何东西）。
Future<HolidayShiftChoice?> showHolidayShiftSheet(
  BuildContext context, {
  required DateTime date,
  required int? currentWeekday,
  int? suggestWeekday,
}) {
  return showAppSheet<HolidayShiftChoice>(
    context: context,
    builder: (_) => _HolidayShiftSheet(
      date: date,
      currentWeekday: currentWeekday,
      suggestWeekday: suggestWeekday,
    ),
  );
}

class _HolidayShiftSheet extends StatefulWidget {
  const _HolidayShiftSheet({
    required this.date,
    required this.currentWeekday,
    required this.suggestWeekday,
  });

  final DateTime date;
  final int? currentWeekday;

  /// 上次为别的调休日选过的星期几，做预选（老师通常两三次选的都是同一个）。
  final int? suggestWeekday;

  @override
  State<_HolidayShiftSheet> createState() => _HolidayShiftSheetState();
}

class _HolidayShiftSheetState extends State<_HolidayShiftSheet> {
  /// -1 表示"不调整"，1~7 表示上周几的课。
  late int _picked;

  @override
  void initState() {
    super.initState();
    _picked = widget.currentWeekday ?? widget.suggestWeekday ?? -1;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final date = widget.date;
    return AppCard(
      radius: AppRadii.sheet,
      padding: const EdgeInsets.all(AppConstants.spaceL),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: scheme.tertiary.withValues(alpha: 0.14),
                  borderRadius: AppRadii.smallAll,
                ),
                child: Icon(
                  Icons.swap_horiz_rounded,
                  size: 19,
                  color: scheme.tertiary,
                ),
              ),
              const SizedBox(width: AppConstants.spaceM),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      l10n.holidayShiftTitle,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      '${date.month} 月 ${date.day} 日 · '
                      '${l10n.weekdayShort(date.weekday)}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppConstants.spaceM),
          Text(l10n.holidayShiftBody, style: theme.textTheme.bodySmall),
          const SizedBox(height: AppConstants.spaceL),
          Wrap(
            spacing: AppConstants.spaceS,
            runSpacing: AppConstants.spaceS,
            children: <Widget>[
              for (var weekday = 1; weekday <= 7; weekday++)
                _WeekdayChip(
                  label: l10n.weekdayShort(weekday),
                  selected: _picked == weekday,
                  onTap: () => setState(() => _picked = weekday),
                ),
            ],
          ),
          const SizedBox(height: AppConstants.spaceM),
          _WeekdayChip(
            label: l10n.holidayShiftNone,
            selected: _picked == -1,
            onTap: () => setState(() => _picked = -1),
          ),
          const SizedBox(height: AppConstants.spaceL),
          FilledButton(
            style: FilledButton.styleFrom(
              // 弹层里的主按钮必须是整宽实高：默认高度在窄屏上只有 36，
              // 点起来太抠（课表设置、导入页同一口径）。
              minimumSize: const Size(0, 48),
            ),
            onPressed: () => Navigator.of(context).pop(
              HolidayShiftChoice(_picked == -1 ? null : _picked),
            ),
            child: Text(l10n.save),
          ),
        ],
      ),
    );
  }
}

class _WeekdayChip extends StatelessWidget {
  const _WeekdayChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppMotion.quick,
        padding: const EdgeInsets.symmetric(
          horizontal: AppConstants.spaceL,
          vertical: AppConstants.spaceS,
        ),
        decoration: BoxDecoration(
          color: selected ? scheme.primary : scheme.surfaceContainerHigh,
          borderRadius: AppRadii.stadiumAll,
        ),
        child: Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(
            color: selected ? scheme.onPrimary : scheme.onSurface,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
