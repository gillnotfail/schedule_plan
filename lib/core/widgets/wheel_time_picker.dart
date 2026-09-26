import 'dart:async';

import 'package:flutter/material.dart';

import 'package:schedule_plan/core/constants/app_constants.dart';
import 'package:schedule_plan/core/theme/app_motion.dart';
import 'package:schedule_plan/core/l10n/l10n_extensions.dart';
import 'package:schedule_plan/core/utils/time_utils.dart';
import 'package:schedule_plan/core/widgets/app_card.dart';
import 'package:schedule_plan/core/widgets/confirm_dialog.dart';

/// iOS 风格分段滚轮时间选择器（时、分两列独立滚动）。
///
/// 规范 6：滚轮选择器统一带速度衰减与吸附效果 ——
/// `ListWheelScrollView` 自带惯性滚动与速度衰减，
/// 停止后额外吸附到最近的 5 分钟刻度（吸附动画 200ms）。
class WheelTimePicker extends StatefulWidget {
  const WheelTimePicker({
    super.key,
    required this.initialTime,
    required this.onChanged,
  });

  /// 初始值，格式 "HH:mm"
  final String initialTime;
  final ValueChanged<String> onChanged;

  @override
  State<WheelTimePicker> createState() => _WheelTimePickerState();
}

class _WheelTimePickerState extends State<WheelTimePicker> {
  late int _hour;
  late int _minute;
  late FixedExtentScrollController _hourController;
  late FixedExtentScrollController _minuteController;
  Timer? _snapTimer;

  @override
  void initState() {
    super.initState();
    final minutes = TimeUtils.tryParseMinutes(widget.initialTime) ?? 0;
    _hour = minutes ~/ 60;
    _minute = minutes % 60;
    _hourController = FixedExtentScrollController(initialItem: _hour);
    _minuteController = FixedExtentScrollController(initialItem: _minute);
  }

  @override
  void dispose() {
    // readme 第六章：Timer 必须在 dispose 中显式取消
    _snapTimer?.cancel();
    _snapTimer = null;
    _hourController.dispose();
    _minuteController.dispose();
    super.dispose();
  }

  void _onHourChanged(int value) {
    _hour = value;
    _emit();
  }

  void _onMinuteChanged(int value) {
    _minute = value;
    _emit();
    _scheduleSnap();
  }

  void _emit() {
    widget.onChanged(TimeUtils.formatMinutes(_hour * 60 + _minute));
  }

  /// 停止滚动后延迟吸附，避免打断惯性滚动的手感。
  void _scheduleSnap() {
    _snapTimer?.cancel();
    _snapTimer = Timer(AppMotion.scrollSettle, () {
      if (!mounted) {
        return;
      }
      final snapped = TimeUtils.snapToStep(_minute);
      if (snapped == _minute) {
        return;
      }
      _minute = snapped;
      _minuteController.animateToItem(
        snapped,
        duration: AppMotion.wheelSnap,
        curve: Curves.easeOut,
      );
      _emit();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 180,
      child: Row(
        children: <Widget>[
          Expanded(child: _buildWheel(_hourController, 24, _hour, _onHourChanged, theme)),
          const SizedBox(width: AppConstants.spaceM),
          Expanded(
            child: _buildWheel(_minuteController, 60, _minute, _onMinuteChanged, theme),
          ),
        ],
      ),
    );
  }

  Widget _buildWheel(
    FixedExtentScrollController controller,
    int count,
    int currentValue,
    ValueChanged<int> onChanged,
    ThemeData theme,
  ) {
    return ListWheelScrollView.useDelegate(
      controller: controller,
      itemExtent: AppConstants.wheelItemExtent,
      diameterRatio: 1.4,
      perspective: 0.005,
      physics: const FixedExtentScrollPhysics(),
      onSelectedItemChanged: onChanged,
      childDelegate: ListWheelChildBuilderDelegate(
        builder: (context, index) {
          final selected = index == currentValue;
          return Center(
            child: Text(
              index.toString().padLeft(2, '0'),
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                color: selected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          );
        },
        childCount: count,
      ),
    );
  }
}

/// 弹出滚轮时间选择器，返回 "HH:mm"；取消时返回 null。
Future<String?> showWheelTimePicker(
  BuildContext context, {
  required String initialTime,
  required String title,
}) {
  return showAppSheet<String>(
    context: context,
    builder: (sheetContext) {
      var value = initialTime;
      final l10n = context.l10n;
      return AppCard(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(title, style: Theme.of(sheetContext).textTheme.titleMedium),
            const SizedBox(height: AppConstants.spaceM),
            WheelTimePicker(
              initialTime: initialTime,
              onChanged: (next) => value = next,
            ),
            const SizedBox(height: AppConstants.spaceM),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(sheetContext).pop(),
                    child: Text(l10n.cancel),
                  ),
                ),
                const SizedBox(width: AppConstants.spaceM),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(sheetContext).pop(value),
                    child: Text(l10n.ok),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );
}
