import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_plan/core/constants/app_constants.dart';
import 'package:schedule_plan/data/models/lesson.dart';
import 'package:schedule_plan/features/schedule/time_axis.dart';

LessonWithTime _lessonAt(String start, String end) => LessonWithTime(
      lesson: const Lesson(
        courseId: 1,
        classId: 1,
        teacherId: 1,
        weekday: 1,
        periodIndex: 1,
      ),
      startTime: start,
      endTime: end,
      periodType: 'normal',
      courseName: '语文',
      className: '一年级一班',
      classColor: '#2196F3',
      templateId: 1,
    );

void main() {
  group('TimeAxis.compute', () {
    test('无课程时回落到 08:00-18:00 默认跨度', () {
      final axis = TimeAxis.compute(<LessonWithTime>[]);
      expect(axis.startMinute, 8 * 60);
      expect(axis.endMinute, 18 * 60);
      expect(axis.pxPerMinute, AppConstants.pxPerMinuteDefault);
      expect(axis.height, 720.0);
    });

    test('上下界取整到半点并各预留 30 分钟余量', () {
      final axis = TimeAxis.compute(<LessonWithTime>[
        _lessonAt('08:00', '08:45'),
        _lessonAt('09:00', '09:45'),
      ]);
      // 480 - 30 = 450 → 07:30；585 + 30 = 615 → 向上取整到 10:30
      expect(axis.startMinute, 7 * 60 + 30);
      expect(axis.endMinute, 10 * 60 + 30);
    });

    test('跨度较小时使用默认像素密度', () {
      final axis = TimeAxis.compute(<LessonWithTime>[_lessonAt('08:00', '08:45')]);
      expect(axis.pxPerMinute, AppConstants.pxPerMinuteDefault);
    });

    test('跨度极大时自适应缩小但不低于下限', () {
      final axis = TimeAxis.compute(<LessonWithTime>[_lessonAt('06:00', '22:00')]);
      expect(axis.pxPerMinute, lessThanOrEqualTo(AppConstants.pxPerMinuteDefault));
      expect(axis.pxPerMinute, greaterThanOrEqualTo(AppConstants.pxPerMinuteMin));
      expect(axis.height, lessThanOrEqualTo(AppConstants.timeAxisMaxHeight + 0.001));
    });

    test('结束时间不合法（早于起始）时按 45 分钟兜底', () {
      final axis = TimeAxis.compute(<LessonWithTime>[_lessonAt('08:00', '07:00')]);
      expect(axis.endMinute, greaterThan(axis.startMinute));
    });

    test('结束时间不会超过当日 24:00', () {
      final axis = TimeAxis.compute(<LessonWithTime>[_lessonAt('23:00', '23:55')]);
      expect(axis.endMinute, 24 * 60);
    });
  });

  group('TimeAxis 几何换算', () {
    final axis = const TimeAxis(startMinute: 480, endMinute: 600, pxPerMinute: 1.5);

    test('offsetOf / heightOf', () {
      expect(axis.offsetOf(480), 0.0);
      expect(axis.offsetOf(510), 45.0);
      expect(axis.heightOf(480, 525), 67.5);
      expect(axis.totalMinutes, 120);
    });

    test('hourTicks 只落在实际跨度内的整点', () {
      expect(axis.hourTicks, <int>[480, 540, 600]);
    });
  });
}
