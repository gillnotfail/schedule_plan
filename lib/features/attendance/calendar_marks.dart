import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:schedule_plan/core/constants/app_constants.dart';
import 'package:schedule_plan/data/models/china_holiday.dart';

/// 考勤日历格子上的标记语义 —— **唯一口径**（用户规格，第 18 轮定稿）。
///
/// 日历上共有四样东西，一眼可辨 —— 日历下方的 [AttendanceCalendarLegend]
/// 就是这四条的说明书：
/// - **放假日** → 一个**红点**；
/// - **调休上班日** → 一个**紫点**；
/// - **有课但还没点名** → 日期外一圈**淡圈**；
/// - **点过名** → **红弧**按出勤率填充（全勤 = 整圈，缺一半 = 半圈）。
///
/// 前两样是「日历安排」（[ChinaHolidayCalendar] 的静态口径），后两样是「点名进度」
/// （见 `features/attendance/day_attendance_ring.dart`），两组互不干扰。
///
/// 工具箱日历是「红底 = 放假、橙底 = 调休上班」并配「休 / 班」文字，
/// 那页有文字兜底、老师已经认过，所以保持原样；只有小点的考勤页按这里的口径来。
class CalendarMark {
  const CalendarMark._();

  /// 放假的标记色（红）。格子和 [AttendanceCalendarLegend] 共用同一个色号，
  /// 免得"图例上看到的红"和"格子里的红"是两个色。
  static Color holidayColor(ColorScheme scheme) => scheme.error;

  /// 调休上班的标记色（紫）。与放假的红必须**明显不同色**，
  /// 否则又回到"满屏红点分不清"的老问题。
  static Color makeupColor(ColorScheme scheme) => scheme.tertiary;

  /// 这一天该画什么颜色的点；返回 `null` = 这个格子一个点都不画。
  static Color? colorOf(CalendarDayKind? kind, ColorScheme scheme) {
    return switch (kind) {
      CalendarDayKind.holiday => holidayColor(scheme),
      CalendarDayKind.makeupWorkday => makeupColor(scheme),
      _ => null,
    };
  }
}

/// 图例里一个符号画成什么样。
enum CalendarLegendGlyph {
  /// 实心小圆点：放假 / 调休上班
  dot,

  /// 淡色空心圈：有课但还没点名
  ring,

  /// 只画四分之三圈的红弧：出勤率
  arc,
}

/// 图例里的一项：一个符号 + 一句说明。
class CalendarLegendItem {
  const CalendarLegendItem({
    required this.glyph,
    required this.color,
    required this.label,
  });

  final CalendarLegendGlyph glyph;
  final Color color;
  final String label;
}

/// 考勤日历底部的一行图例。
///
/// 日历上的四样标记 —— 放假红点、调休紫点、未点名淡圈、出勤红弧 ——
/// 全写在日历下面，老师不用猜，也不用去长按试探（长按命中率低，第 18 轮已去掉）。
class AttendanceCalendarLegend extends StatelessWidget {
  const AttendanceCalendarLegend({super.key, required this.items});

  final List<CalendarLegendItem> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontSize: 10.5,
    );
    // 用 Wrap 而不是 Row：四条说明横着排，中文勉强够、英文（"Make-up workday"）
    // 一定放不下，宁可换行也不要溢出。
    return Wrap(
      spacing: AppConstants.spaceM,
      runSpacing: 2,
      children: <Widget>[
        for (final item in items)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _LegendGlyph(glyph: item.glyph, color: item.color),
              const SizedBox(width: 3),
              Text(item.label, style: style),
            ],
          ),
      ],
    );
  }
}

/// 图例里的符号：一个实心点 / 一个空心圈 / 一段红弧。
class _LegendGlyph extends StatelessWidget {
  const _LegendGlyph({required this.glyph, required this.color});

  final CalendarLegendGlyph glyph;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return switch (glyph) {
      CalendarLegendGlyph.dot => Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      CalendarLegendGlyph.ring => Container(
        width: 11,
        height: 11,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: color, width: 1.6),
        ),
      ),
      CalendarLegendGlyph.arc => SizedBox(
        width: 11,
        height: 11,
        child: CustomPaint(painter: _LegendArcPainter(color: color)),
      ),
    };
  }
}

/// 图例里表示「出勤率」的那一小段红弧：淡淡一整圈打底 + 四分之三圈的红。
class _LegendArcPainter extends CustomPainter {
  const _LegendArcPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.shortestSide - 1.6) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = color.withValues(alpha: 0.22),
    );
    canvas.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi * 0.75,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_LegendArcPainter old) => old.color != color;
}
