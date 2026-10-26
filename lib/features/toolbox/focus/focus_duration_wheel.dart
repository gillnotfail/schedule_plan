import 'dart:async';

import 'package:flutter/material.dart';

import 'package:schedule_plan/core/constants/app_constants.dart';
import 'package:schedule_plan/core/theme/app_motion.dart';

/// 专注时长选择器：`时 : 分 : 秒` 三列独立滚轮（用户规格里的 `00:00:00`）。
///
/// 手感照 [WheelTimePicker] 来 —— 惯性衰减、停稳后吸附、选中项加粗换色，
/// 不另造一套交互。两处与它有意的不同：
/// - 秒列**步长 5 秒**：专注计时精确到秒没有意义，60 格缩到 12 格少滚一半圈；
/// - 三列之间有联动约束（见下）。
///
/// 两条边界规则，都是为了让"滚轮显示的数字"和"真正会倒计时的时长"永远一致：
/// - **上限 3 小时**：拨到 3 小时时，分 / 秒自动归零并回弹 —— 否则会出现
///   `03:59:59` 这种被内部钳到 3 小时、界面却写着另一个数的状态；
/// - **下限 1 分钟**：本组件**不**替用户改数字（硬掰会跟正在滑的手抢），
///   而是把 `00:00:00` 如实报上去，由「开始」按钮去拦住并给出提示。
class FocusDurationWheel extends StatefulWidget {
  const FocusDurationWheel({
    super.key,
    required this.value,
    required this.onChanged,
  });

  /// 当前时长。外部改变它（重置、休息）时滚轮会跟着归位。
  final Duration value;

  /// 用户拨动后回调。可能是 `00:00:00`，见类文档的说明。
  final ValueChanged<Duration> onChanged;

  @override
  State<FocusDurationWheel> createState() => _FocusDurationWheelState();
}

class _FocusDurationWheelState extends State<FocusDurationWheel> {
  static const int _maxHours = AppConstants.focusMaxHours;
  static const int _secondStep = AppConstants.focusSecondStep;
  static const int _secondCount = 60 ~/ _secondStep;

  late int _hours;
  late int _minutes;

  /// 秒列的下标（0 ~ 11），实际秒数 = 下标 × 步长。
  late int _secondIndex;

  late final FixedExtentScrollController _hourController;
  late final FixedExtentScrollController _minuteController;
  late final FixedExtentScrollController _secondController;

  /// 正在程序化地拨轮子，用来忽略随之而来的回调，避免自激循环。
  bool _programmatic = false;

  /// 自己**上一次上报出去**的秒数。
  ///
  /// 这里踩过一个很坑的 bug：滚一格 → 上报 → 页面 setState → 新值又传回来
  /// → [didUpdateWidget] 里 `jumpToItem` 三列 → **正在进行的惯性滚动被当场掐断**。
  /// 表现就是"滚一格就停、怎么甩都很慢"。所以凡是与自己上报的值相同，
  /// 一律当作回音忽略，只同步内部字段、绝不碰 controller。
  int _lastEmittedSeconds = -1;

  @override
  void initState() {
    super.initState();
    _adopt(widget.value);
    _hourController = FixedExtentScrollController(initialItem: _hours);
    _minuteController = FixedExtentScrollController(initialItem: _minutes);
    _secondController = FixedExtentScrollController(initialItem: _secondIndex);
  }

  @override
  void didUpdateWidget(covariant FocusDurationWheel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value == oldWidget.value) {
      return;
    }
    // 这是刚刚从自己这里上报出去的值，绕了一圈回来了 —— 内部状态早就是
    // 对的，再 jump 一次只会把用户正在甩的滚轮拽停。见 [_lastEmittedSeconds]。
    if (widget.value.inSeconds == _lastEmittedSeconds) {
      return;
    }
    // 真·外部改动（重置 / 换默认时长 / 休息段结束）：这时才归位。
    _adopt(widget.value);
    if (_hourController.hasClients) {
      _programmatic = true;
      _hourController.jumpToItem(_hours);
      _minuteController.jumpToItem(_minutes);
      _secondController.jumpToItem(_secondIndex);
      _programmatic = false;
    }
  }

  @override
  void dispose() {
    _hourController.dispose();
    _minuteController.dispose();
    _secondController.dispose();
    super.dispose();
  }

  void _adopt(Duration value) {
    final total = value.inSeconds;
    _hours = (total ~/ 3600).clamp(0, _maxHours);
    _minutes = ((total % 3600) ~/ 60).clamp(0, 59);
    // 秒列只停得在 5 秒的整数倍上；落不到格上就往下取，别让初始值
    // 跟控件实际显示的位置对不上。
    _secondIndex = ((total % 60) ~/ _secondStep).clamp(0, _secondCount - 1);
  }

  Duration get _current => Duration(
        hours: _hours,
        minutes: _minutes,
        seconds: _secondIndex * _secondStep,
      );

  /// 拨到 3 小时时把分 / 秒拉回 0。
  ///
  /// 用动画而不是硬跳：手指刚停下，数字自己滑回去，比"突然变成 0"好懂 ——
  /// 那看起来像滑错了。
  Future<void> _collapseTail() async {
    if (_hours < _maxHours) {
      return;
    }
    final minuteTarget = _minutes;
    final secondTarget = _secondIndex;
    if (minuteTarget == 0 && secondTarget == 0) {
      return;
    }
    _programmatic = true;
    _minutes = 0;
    _secondIndex = 0;
    await Future.wait<void>(<Future<void>>[
      _minuteController.animateToItem(
        0,
        duration: AppMotion.wheelSnap,
        curve: AppMotion.decelerate,
      ),
      _secondController.animateToItem(
        0,
        duration: AppMotion.wheelSnap,
        curve: AppMotion.decelerate,
      ),
    ]);
    if (!mounted) {
      return;
    }
    _programmatic = false;
    _emit();
  }

  void _emit() {
    if (_programmatic) {
      return;
    }
    final value = _current;
    _lastEmittedSeconds = value.inSeconds;
    widget.onChanged(value);
    if (_hours >= _maxHours) {
      unawaited(_collapseTail());
    }
  }

  void _onHourChanged(int index) {
    _hours = index;
    _emit();
  }

  void _onMinuteChanged(int index) {
    _minutes = index;
    _emit();
  }

  void _onSecondChanged(int index) {
    _secondIndex = index;
    _emit();
  }

  @override
  Widget build(BuildContext context) {
    // 4 格高（40×4）。比原来的 190 矮一截，是为了让整个准备态塞进一屏。
    return SizedBox(
      height: AppConstants.focusWheelItemExtent * 4,
      child: Row(
        children: <Widget>[
          Expanded(
            child: _buildWheel(
              controller: _hourController,
              count: _maxHours + 1,
              current: _hours,
              onChanged: _onHourChanged,
            ),
          ),
          _buildColon(),
          Expanded(
            child: _buildWheel(
              controller: _minuteController,
              count: 60,
              current: _minutes,
              onChanged: _onMinuteChanged,
            ),
          ),
          _buildColon(),
          Expanded(
            child: _buildWheel(
              controller: _secondController,
              count: _secondCount,
              current: _secondIndex,
              onChanged: _onSecondChanged,
              scale: _secondStep,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildColon() {
    return Text(
      ':',
      style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
    );
  }

  Widget _buildWheel({
    required FixedExtentScrollController controller,
    required int count,
    required int current,
    required ValueChanged<int> onChanged,
    int scale = 1,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return NotificationListener<ScrollEndNotification>(
      onNotification: (notification) {
        // 震动从"每过一格"挪到"停稳之后震一次"：连续滑动时每格都震会让
        // 反馈连成一串、还把主线程的 haptic 排满，手感发涩。程序化归位不震。
        if (notification.depth == 0 && !_programmatic) {
          AppMotion.select();
        }
        return false;
      },
      child: ListWheelScrollView.useDelegate(
        controller: controller,
        itemExtent: AppConstants.focusWheelItemExtent,
        diameterRatio: 1.4,
        perspective: 0.005,
        physics: const FixedExtentScrollPhysics(),
        onSelectedItemChanged: onChanged,
        childDelegate: ListWheelChildBuilderDelegate(
          builder: (context, index) {
            final selected = index == current;
            return Center(
              child: Text(
                (index * scale).toString().padLeft(2, '0'),
                style: theme.textTheme.headlineSmall?.copyWith(
                  // 数字宽度固定，滚动时不会被 1 和 8 的宽度差带得左右晃。
                  fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w400,
                  color: selected ? scheme.primary : scheme.onSurfaceVariant,
                ),
              ),
            );
          },
          childCount: count,
        ),
      ),
    );
  }
}
