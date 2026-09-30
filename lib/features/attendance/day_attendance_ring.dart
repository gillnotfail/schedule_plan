import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:schedule_plan/data/models/attendance.dart';

/// 日历上围绕日期数字的「考勤进度圆环」（用户规格，第 18 轮定稿）。
///
/// 三种状态，一眼可辨：
/// 1. **当天无课** → 完全不画（[stat] 为 null 或 `hasLesson == false` 且没记录）；
/// 2. **有课但一条考勤记录都没有** → 只有一圈**淡圈**，表示"这天有课、还没点名"；
/// 3. **点过名** → 红色圆弧按**出勤率**填充：全勤 = 整圈，缺一半 = 半圈。
///
/// 与日历格子上另外两样标记（放假红点、调休紫点，见 `CalendarMark`）互不干扰：
/// 点表示"日历安排"，圈表示"点名进度"。四种标记的含义统一写在日历下方的
/// `AttendanceCalendarLegend` 里，老师不用猜。
///
/// 之所以是"出勤率"而不是"点名完成度"：老师扫月历想看的是"哪天班上出勤不正常"，
/// "哪天没点名"从状态 2 的淡圈就已经能看出来（口径详见 [AttendanceDayStat]）。
///
/// 圆环**套在日期数字外面**（不是另起一行），所以不占额外高度，
/// 周视图和月视图能共用同一套版式。
class DayAttendanceRing extends StatelessWidget {
  const DayAttendanceRing({
    super.key,
    required this.stat,
    required this.child,
    required this.progressColor,
    required this.trackColor,
    this.dayDiameter = 34,
    this.strokeWidth = 2.6,
    this.gap = 2,
  });

  /// 当天的考勤概览；null 或"没课也没记录"时只画日期本身
  final AttendanceDayStat? stat;

  /// 日期数字（外圈尺寸由 [dayDiameter] + 环宽推导）
  final Widget child;

  /// 进度色：用户指定用红色（异常醒目，与"今天"的强调色区分开）
  final Color progressColor;

  /// 轨道色：进度环的底 —— 缺的那一段露出它，一眼看出没出全勤
  final Color trackColor;

  /// 日期圆的直径
  final double dayDiameter;

  /// 环宽
  final double strokeWidth;

  /// 日期圆与环之间的空隙
  final double gap;

  double get _diameter => dayDiameter + (strokeWidth + gap) * 2;

  @override
  Widget build(BuildContext context) {
    final value = stat;
    return SizedBox(
      width: _diameter,
      height: _diameter,
      child: CustomPaint(
        painter: AttendanceRingPainter(
          progress: value?.rate,
          hasLesson: value?.hasLesson ?? false,
          hasRecord: value?.hasRecord ?? false,
          progressColor: progressColor,
          trackColor: trackColor,
          strokeWidth: strokeWidth,
        ),
        child: Center(
          child: SizedBox(width: dayDiameter, height: dayDiameter, child: child),
        ),
      ),
    );
  }
}

/// 纯绘制逻辑，抽成独立类方便单测直接验算弧长。
class AttendanceRingPainter extends CustomPainter {
  AttendanceRingPainter({
    required this.progress,
    required this.hasLesson,
    required this.hasRecord,
    required this.progressColor,
    required this.trackColor,
    required this.strokeWidth,
  });

  /// 0~1；为 null 表示当天无课（不画环）
  final double? progress;

  /// 当天排了课 —— 决定"有课没点名"那天画不画淡圈
  final bool hasLesson;
  final bool hasRecord;
  final Color progressColor;
  final Color trackColor;
  final double strokeWidth;

  /// 环是否可见：当天有课（或当天留下过记录）才画，无课的日子保持日历清爽
  bool get visible => hasLesson || hasRecord;

  @override
  void paint(Canvas canvas, Size size) {
    if (!visible) {
      return;
    }
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (math.min(size.width, size.height) - strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    // 底：一条淡淡的整圈。没点过名时它就是"淡圈"的全部内容；
    // 点过名时它托住进度弧，缺的那一段才看得出来。
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = hasRecord ? trackColor : trackColor.withValues(alpha: 0.55);
    canvas.drawCircle(center, radius, track);

    if (!hasRecord || progress == null || progress! <= 0) {
      return;
    }
    final sweep = 2 * math.pi * progress!.clamp(0.0, 1.0);
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = progressColor;
    // 从 12 点方向顺时针填充：和所有进度环的认知一致
    canvas.drawArc(rect, -math.pi / 2, sweep, false, arc);
  }

  @override
  bool shouldRepaint(AttendanceRingPainter old) =>
      old.progress != progress ||
      old.hasLesson != hasLesson ||
      old.hasRecord != hasRecord ||
      old.progressColor != progressColor ||
      old.trackColor != trackColor ||
      old.strokeWidth != strokeWidth;
}
