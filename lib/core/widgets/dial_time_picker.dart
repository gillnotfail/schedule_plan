import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:schedule_plan/core/constants/app_constants.dart';
import 'package:schedule_plan/core/l10n/l10n_extensions.dart';
import 'package:schedule_plan/core/theme/app_motion.dart';
import 'package:schedule_plan/core/utils/time_utils.dart';

/// 12 小时表盘 ↔ 24 小时制的换算。
///
/// 抽成纯函数便于单测：表盘上只有 1~12，而库里存的是 24 小时制 "HH:mm"，
/// 两者来回换算如果写错，会出现「下午 3 点存成凌晨 3 点」这种静默错位。
abstract final class DialTimeMath {
  /// 表盘上的小时数字（1~12）。0 点与 12 点都落在「12」上。
  static int hour12Of(int hour24) {
    final value = hour24 % 12;
    return value == 0 ? 12 : value;
  }

  /// 是否下午（>= 12:00）。
  static bool isPm(int hour24) => hour24 >= 12;

  /// 12 点方向为 0 号位，顺时针到 11 号位。
  static int hourIndexOf(int hour24) => hour24 % 12;

  /// (1~12 的小时, 上午/下午, 分钟) → 24 小时制小时。
  static int combine({
    required int hour12,
    required bool pm,
    required int minute,
  }) {
    final safe = hour12.clamp(1, 12);
    final base = safe == 12 ? 0 : safe;
    final hour = pm ? base + 12 : base;
    return hour.clamp(0, 23);
  }

  /// 把当前时针换算成「切换上午/下午之后」的新小时（12 小时读数保持不变）。
  static int withPm(int hour24, bool pm) {
    return combine(
      hour12: hour12Of(hour24),
      pm: pm,
      minute: 0,
    );
  }

  /// 表盘角度：12 点方向（-90°）为 0 号位，每格 30°。
  static double angleForIndex(int index) =>
      -math.pi / 2 + index * (2 * math.pi / 12);

  /// 由点击位置的角度反推 0~11 的格子号（就近吸附）。
  static int indexFromAngle(double angle) {
    final slot = (angle + math.pi / 2) / (2 * math.pi / 12);
    final rounded = slot.round() % 12;
    return rounded < 0 ? rounded + 12 : rounded;
  }
}

/// 机械表盘时间选择器（用户规格）。
///
/// 一块**双环表盘**，两圈同时可点，不需要先切「时 / 分」模式：
/// - **内圈**：1~12 的小时数字（12 在正上方），点一下就定小时；
/// - **外圈**：00 / 05 / … / 55 的分钟刻度，点一下就定分钟；
/// - 点完内圈后焦点自动落到外圈，所以「先点时针、再点分针」两步就能收工；
/// - 短针指小时、长针指分钟，两根针各自以 Spatial Spring 旋转到位；
/// - 中心区留白，读数提到表盘上方，配 上午 / 下午 切换（12 小时表盘必须区分）。
class DialTimePicker extends StatefulWidget {
  const DialTimePicker({
    super.key,
    required this.initialTime,
    required this.onChanged,
    this.size = 292,
  });

  /// 初始值，格式 "HH:mm"
  final String initialTime;
  final ValueChanged<String> onChanged;
  final double size;

  @override
  State<DialTimePicker> createState() => _DialTimePickerState();
}

class _DialTimePickerState extends State<DialTimePicker> {
  late int _hour;
  late int _minute;

  /// 焦点是否在「分」上：只影响高亮，两圈任何时候都能点。
  /// 初始在「时」上——用户点开表盘多半是先调小时。
  bool _focusMinute = false;

  @override
  void initState() {
    super.initState();
    final minutes = TimeUtils.tryParseMinutes(widget.initialTime) ?? 0;
    _hour = (minutes ~/ 60).clamp(0, 23);
    // 分钟按 5 分钟粒度吸附，与滚轮选择器、后续校验保持同一精度
    _minute = TimeUtils.snapToStep(minutes % 60);
  }

  int get _hourIndex => DialTimeMath.hourIndexOf(_hour);
  bool get _isPm => DialTimeMath.isPm(_hour);

  void _selectHourIndex(int index) {
    // 内圈 0 号位就是「12 点」
    final hour12 = index == 0 ? 12 : index;
    final next = DialTimeMath.combine(
      hour12: hour12,
      pm: _isPm,
      minute: _minute,
    );
    AppMotion.select();
    setState(() {
      _hour = next;
      // 定完小时，焦点顺势交给分钟：下一次点击外圈就是选分
      _focusMinute = true;
    });
    _emit();
  }

  void _selectMinuteSlot(int slot) {
    final minute = slot * AppConstants.wheelSnapMinutes;
    AppMotion.select();
    setState(() {
      _minute = minute;
      _focusMinute = true;
    });
    _emit();
  }

  void _selectPm(bool pm) {
    if (pm == _isPm) {
      return;
    }
    AppMotion.select();
    setState(() {
      _hour = DialTimeMath.withPm(_hour, pm);
      _focusMinute = true;
    });
    _emit();
  }

  void _emit() {
    widget.onChanged(TimeUtils.formatMinutes(_hour * 60 + _minute));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        // 读数提到表盘上方：表盘中心留白给两根指针，读数也更大更清楚
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              _hour.toString().padLeft(2, '0'),
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: _focusMinute ? scheme.onSurface : scheme.primary,
                letterSpacing: 1,
              ),
            ),
            Text(
              ':',
              style: theme.textTheme.headlineMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            Text(
              _minute.toString().padLeft(2, '0'),
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: _focusMinute ? scheme.tertiary : scheme.onSurface,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(width: AppConstants.spaceL),
            SegmentedButton<bool>(
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              segments: <ButtonSegment<bool>>[
                ButtonSegment<bool>(value: false, label: Text(l10n.dialAmLabel)),
                ButtonSegment<bool>(value: true, label: Text(l10n.dialPmLabel)),
              ],
              selected: <bool>{_isPm},
              onSelectionChanged: (selection) => _selectPm(selection.first),
            ),
          ],
        ),
        const SizedBox(height: AppConstants.spaceM),
        _DialFace(
          size: widget.size,
          hourIndex: _hourIndex,
          minuteSlot: _minute ~/ AppConstants.wheelSnapMinutes,
          focusMinute: _focusMinute,
          onPickHourIndex: _selectHourIndex,
          onPickMinuteSlot: _selectMinuteSlot,
        ),
        const SizedBox(height: AppConstants.spaceS),
        Text(
          l10n.dialTwoRingHint,
          style: theme.textTheme.labelMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _DialFace extends StatelessWidget {
  const _DialFace({
    required this.size,
    required this.hourIndex,
    required this.minuteSlot,
    required this.focusMinute,
    required this.onPickHourIndex,
    required this.onPickMinuteSlot,
  });

  final double size;
  final int hourIndex;
  final int minuteSlot;
  final bool focusMinute;
  final ValueChanged<int> onPickHourIndex;
  final ValueChanged<int> onPickMinuteSlot;

  double get _radius => size / 2;

  /// 外圈（分钟）数字所在半径
  double get _outerRadius => _radius * 0.78;

  /// 内圈（小时）数字所在半径
  double get _innerRadius => _radius * 0.515;

  /// 内外两圈的分界半径：点击落在这条线以内算「选小时」
  double get _bandSplit => (_outerRadius + _innerRadius) / 2;

  /// 数字触控区边长（M3E 无障碍要求 >= 48，这里取 44 + InkWell 的水波纹外扩）
  static const double _hitSize = 40;

  void _handleTapUp(TapUpDetails details) {
    final center = Offset(_radius, _radius);
    final delta = details.localPosition - center;
    final distance = delta.distance;
    // 中心圆点和最外圈留白不响应，避免误触
    if (distance < _radius * 0.22 || distance > _radius - 4) {
      return;
    }
    final index = DialTimeMath.indexFromAngle(
      math.atan2(delta.dy, delta.dx),
    );
    if (distance < _bandSplit) {
      onPickHourIndex(index);
    } else {
      onPickMinuteSlot(index);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: _handleTapUp,
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            // 表盘底盘：外圈轨道 + 内圈轨道 + 十二条分区射线
            CustomPaint(
              size: Size.square(size),
              painter: _DialPlatePainter(
                ringColor: scheme.surfaceContainerHighest,
                innerColor: scheme.surfaceContainer,
                tickColor: scheme.outline.withValues(alpha: 0.45),
                bandSplit: _bandSplit,
                outerRadius: _outerRadius,
                innerRadius: _innerRadius,
                radius: _radius,
              ),
            ),
            // 时针（短）
            _DialHand(
              size: size,
              angle: DialTimeMath.angleForIndex(hourIndex),
              color: scheme.primary,
              knobColor: scheme.primary,
              from: _radius * 0.09,
              to: _innerRadius - 22,
              strokeWidth: 5.5,
              dimmed: focusMinute,
            ),
            // 分针（长）
            _DialHand(
              size: size,
              angle: DialTimeMath.angleForIndex(minuteSlot),
              color: scheme.tertiary,
              knobColor: scheme.tertiary,
              from: _radius * 0.09,
              to: _outerRadius - 20,
              strokeWidth: 3.6,
              dimmed: !focusMinute,
            ),
            // 内圈：小时 1~12
            for (var i = 0; i < 12; i++)
              _positionedNumber(
                index: i,
                radius: _innerRadius,
                label: i == 0 ? '12' : '$i',
                active: i == hourIndex,
                focused: !focusMinute,
                accent: scheme.primary,
                onAccent: scheme.onPrimary,
                theme: theme,
                scheme: scheme,
                onTap: () => onPickHourIndex(i),
              ),
            // 外圈：分钟 00~55
            for (var i = 0; i < 12; i++)
              _positionedNumber(
                index: i,
                radius: _outerRadius,
                label: (i * AppConstants.wheelSnapMinutes)
                    .toString()
                    .padLeft(2, '0'),
                active: i == minuteSlot,
                focused: focusMinute,
                accent: scheme.tertiary,
                onAccent: scheme.onTertiary,
                theme: theme,
                scheme: scheme,
                onTap: () => onPickMinuteSlot(i),
              ),
          ],
        ),
      ),
    );
  }

  Widget _positionedNumber({
    required int index,
    required double radius,
    required String label,
    required bool active,
    required bool focused,
    required Color accent,
    required Color onAccent,
    required ThemeData theme,
    required ColorScheme scheme,
    required VoidCallback onTap,
  }) {
    final angle = DialTimeMath.angleForIndex(index);
    return Positioned(
      left: _radius + radius * math.cos(angle) - _hitSize / 2,
      top: _radius + radius * math.sin(angle) - _hitSize / 2,
      child: SizedBox(
        width: _hitSize,
        height: _hitSize,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: AnimatedScale(
              scale: active ? 1.0 : (focused ? 0.94 : 0.86),
              duration: AppMotion.springMedium,
              curve: AppMotion.expressive,
              child: AnimatedContainer(
                duration: AppMotion.quick,
                curve: AppMotion.effects,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: active ? accent : Colors.transparent,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  label,
                  maxLines: 1,
                  softWrap: false,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontSize: active ? 15 : (focused ? 14 : 12.5),
                    fontWeight:
                        active || focused ? FontWeight.w800 : FontWeight.w600,
                    color: active
                        ? onAccent
                        : (focused
                            ? scheme.onSurface
                            : scheme.onSurfaceVariant),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 单根指针：从 `from` 半径指向 `to` 半径，配合 TweenAnimationBuilder 做弹性旋转。
class _DialHand extends StatelessWidget {
  const _DialHand({
    required this.size,
    required this.angle,
    required this.color,
    required this.knobColor,
    required this.from,
    required this.to,
    required this.strokeWidth,
    required this.dimmed,
  });

  final double size;
  final double angle;
  final Color color;
  final Color knobColor;
  final double from;
  final double to;
  final double strokeWidth;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: angle, end: angle),
      duration: AppMotion.dialPointer,
      curve: AppMotion.expressive,
      builder: (context, value, _) => CustomPaint(
        size: Size.square(size),
        painter: _DialHandPainter(
          angle: value,
          color: color.withValues(alpha: dimmed ? 0.38 : 1),
          knobColor: knobColor.withValues(alpha: dimmed ? 0.30 : 1),
          from: from,
          to: to,
          strokeWidth: strokeWidth,
        ),
      ),
    );
  }
}

class _DialHandPainter extends CustomPainter {
  const _DialHandPainter({
    required this.angle,
    required this.color,
    required this.knobColor,
    required this.from,
    required this.to,
    required this.strokeWidth,
  });

  final double angle;
  final Color color;
  final Color knobColor;
  final double from;
  final double to;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final direction = Offset(math.cos(angle), math.sin(angle));
    canvas.drawLine(
      center + direction * from,
      center + direction * to,
      Paint()
        ..color = color
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round,
    );
    // 中心圆帽：两根指针共用一个，视觉上像真实的表轴
    canvas.drawCircle(center, size.width * 0.022, Paint()..color = knobColor);
  }

  @override
  bool shouldRepaint(covariant _DialHandPainter oldDelegate) =>
      oldDelegate.angle != angle ||
      oldDelegate.color != color ||
      oldDelegate.knobColor != knobColor ||
      oldDelegate.from != from ||
      oldDelegate.to != to ||
      oldDelegate.strokeWidth != strokeWidth;
}

class _DialPlatePainter extends CustomPainter {
  const _DialPlatePainter({
    required this.ringColor,
    required this.innerColor,
    required this.tickColor,
    required this.radius,
    required this.bandSplit,
    required this.outerRadius,
    required this.innerRadius,
  });

  final Color ringColor;
  final Color innerColor;
  final Color tickColor;
  final double radius;
  final double bandSplit;
  final double outerRadius;
  final double innerRadius;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);

    // 外层轨道（分钟环）
    canvas.drawCircle(
      center,
      radius - 2,
      Paint()..color = ringColor.withValues(alpha: 0.55),
    );
    // 内层轨道（小时环）
    canvas.drawCircle(center, bandSplit, Paint()..color = innerColor);

    // 两圈之间的分界圈：提示「点里面是时、点外面是分」
    canvas.drawCircle(
      center,
      bandSplit,
      Paint()
        ..color = tickColor.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );

    // 十二条分区射线：让 12 格在视觉上站得住
    final rayPaint = Paint()
      ..color = tickColor.withValues(alpha: 0.18)
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 12; i++) {
      final angle = DialTimeMath.angleForIndex(i);
      final direction = Offset(math.cos(angle), math.sin(angle));
      canvas.drawLine(
        center + direction * (innerRadius * 0.42),
        center + direction * (radius - 6),
        rayPaint,
      );
    }

    // 数字轨道的淡淡底圈，避免数字浮在空气里
    canvas.drawCircle(
      center,
      innerRadius,
      Paint()
        ..color = tickColor.withValues(alpha: 0.10)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _DialPlatePainter oldDelegate) =>
      oldDelegate.ringColor != ringColor ||
      oldDelegate.innerColor != innerColor ||
      oldDelegate.tickColor != tickColor ||
      oldDelegate.radius != radius ||
      oldDelegate.bandSplit != bandSplit;
}

/// 弹出机械表盘时间选择器，返回 "HH:mm"；取消时返回 null。
Future<String?> showDialTimePicker(
  BuildContext context, {
  required String initialTime,
  required String title,
}) {
  final l10n = context.l10n;
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: RoundedRectangleBorder(borderRadius: AppRadii.sheetTop),
    builder: (sheetContext) {
      var value = initialTime;
      return SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            AppConstants.spaceL,
            AppConstants.spaceS,
            AppConstants.spaceL,
            AppConstants.spaceL +
                MediaQuery.of(sheetContext).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Center(
                child: Text(
                  title,
                  style: Theme.of(sheetContext).textTheme.titleLarge,
                ),
              ),
              const SizedBox(height: AppConstants.spaceM),
              DialTimePicker(
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
        ),
      );
    },
  );
}
