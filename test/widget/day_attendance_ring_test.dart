import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:schedule_plan/data/models/attendance.dart';
import 'package:schedule_plan/features/attendance/day_attendance_ring.dart';

/// 日历「考勤进度圆环」测试。
///
/// 用户规格（本轮第 3 点）：红点换成圆圈，用进度表示当天考勤的百分比 ——
/// 1. 当天无课 → 什么都不画；
/// 2. 有课但没考勤记录 → 只有一圈透明描边；
/// 3. 有记录 → 红色圆弧按百分比填充。
///
/// 这里不靠"看截图"判断，而是**真的把圆环画进一张位图**再数像素：
/// 透明、淡描边、红色圆弧三种状态在位图上是可区分的。
void main() {
  group('AttendanceDayStat 口径', () {
    test('没课 / 没有应点名人数时出勤率为 0', () {
      expect(AttendanceDayStat.none.rate, 0);
      expect(AttendanceDayStat.none.hasRecord, isFalse);
      expect(
        const AttendanceDayStat(
          hasLesson: true,
          expected: 0,
          marked: 3,
          present: 2,
        ).rate,
        0,
      );
    });

    test('出勤率 = 出勤人次 / 应点名人次，并夹在 0~1', () {
      const stat = AttendanceDayStat(
        hasLesson: true,
        expected: 40,
        marked: 40,
        present: 38,
      );
      expect(stat.rate, closeTo(0.95, 1e-9));
      expect(stat.hasRecord, isTrue);

      // 记录比应到还多（改了班级人数等边界）：不能超过一整圈
      const overflow = AttendanceDayStat(
        hasLesson: true,
        expected: 10,
        marked: 12,
        present: 12,
      );
      expect(overflow.rate, 1);
    });
  });

  group('圆环绘制', () {
    test('无课时不画任何东西', () {
      final painter = _painter(progress: null, hasLesson: false, hasRecord: false);
      expect(painter.visible, isFalse);
    });

    testWidgets('三种状态在位图上可区分：全透明 / 淡描边 / 红色圆弧', (tester) async {
      // 位图必须走 runAsync：`Picture.toImage` 依赖真正的光栅化，
      // 在默认的伪异步时钟下会一直挂着（表现为测试 10 分钟超时）。
      final none = await tester.runAsync(
        () => _paint(_painter(progress: null, hasLesson: false, hasRecord: false)),
      );
      expect(none!.opaquePixels, 0, reason: '没课的日子不该有任何标记');

      // 2) 有课没记录：只有一圈淡淡的描边，没有红色
      final unmarked = await tester.runAsync(
        () => _paint(_painter(progress: 0, hasLesson: true, hasRecord: false)),
      );
      expect(unmarked!.opaquePixels, greaterThan(0), reason: '要看得见"今天有课"');
      expect(unmarked.redPixels, 0, reason: '没点名不该出现红色进度');

      // 3) 点过名、全勤：整圈红色
      final full = await tester.runAsync(
        () => _paint(_painter(progress: 1, hasLesson: true, hasRecord: true)),
      );
      expect(full!.redPixels, greaterThan(unmarked.redPixels));

      // 4) 半勤：红色像素明显少于全勤
      final half = await tester.runAsync(
        () => _paint(_painter(progress: 0.5, hasLesson: true, hasRecord: true)),
      );
      expect(half!.redPixels, greaterThan(0));
      expect(
        half.redPixels,
        lessThan(full.redPixels * 0.75),
        reason: '50% 的弧长必须明显短于整圈',
      );
    });

    test('参数不变时不重绘', () {
      final painter = _painter(progress: 0.5, hasLesson: true, hasRecord: true);
      expect(painter.shouldRepaint(painter), isFalse);
      expect(
        painter.shouldRepaint(
          _painter(progress: 0.6, hasLesson: true, hasRecord: true),
        ),
        isTrue,
      );
    });
  });

  testWidgets('圆环套在日期数字外面，数字照常渲染', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: DayAttendanceRing(
              stat: const AttendanceDayStat(
                hasLesson: true,
                expected: 40,
                marked: 40,
                present: 38,
              ),
              progressColor: const Color(0xFFE23B3B),
              trackColor: const Color(0xFFDCE9E6),
              child: const Text('21'),
            ),
          ),
        ),
      ),
    );

    expect(find.text('21'), findsOneWidget);
    final ring = tester.getRect(find.byType(DayAttendanceRing));
    final day = tester.getRect(find.text('21'));
    expect(
      ring.width,
      greaterThan(day.width + 4),
      reason: '圆环要套在日期外面，比数字占的地方大',
    );
  });
}

AttendanceRingPainter _painter({
  required double? progress,
  required bool hasLesson,
  required bool hasRecord,
}) {
  return AttendanceRingPainter(
    progress: progress,
    hasLesson: hasLesson,
    hasRecord: hasRecord,
    progressColor: const Color(0xFFE23B3B),
    trackColor: const Color(0xFFDCE9E6),
    strokeWidth: 2.6,
  );
}

class _Pixels {
  const _Pixels({required this.opaquePixels, required this.redPixels});

  /// 非全透明像素数（画了东西就有）
  final int opaquePixels;

  /// 红色像素数（进度弧）
  final int redPixels;
}

/// 把圆环画进位图并统计像素。
Future<_Pixels> _paint(AttendanceRingPainter painter) async {
  const size = 48;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  painter.paint(canvas, Size.square(size.toDouble()));
  final image = await recorder.endRecording().toImage(size, size);
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  expect(data, isNotNull);

  var opaque = 0;
  var red = 0;
  final bytes = data!.buffer.asUint8List();
  for (var i = 0; i < bytes.length; i += 4) {
    final r = bytes[i];
    final g = bytes[i + 1];
    final b = bytes[i + 2];
    final a = bytes[i + 3];
    if (a < 16) {
      continue;
    }
    opaque++;
    // 圆环的进度色是纯红系（#E23B3B）：红通道远高于蓝通道
    if (r > 140 && r > b + 60 && g < r) {
      red++;
    }
  }
  image.dispose();
  return _Pixels(opaquePixels: opaque, redPixels: red);
}
