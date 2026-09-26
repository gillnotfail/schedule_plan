import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_plan/data/models/lesson.dart';

Lesson _lesson({
  int? id,
  int courseId = 1,
  int classId = 1,
  int teacherId = 1,
  int weekday = 1,
  int periodIndex = 1,
}) =>
    Lesson(
      id: id,
      courseId: courseId,
      classId: classId,
      teacherId: teacherId,
      weekday: weekday,
      periodIndex: periodIndex,
    );

LessonWithTime _withTime(
  Lesson lesson, {
  required String start,
  required String end,
  int templateId = 1,
}) =>
    LessonWithTime(
      lesson: lesson,
      startTime: start,
      endTime: end,
      periodType: 'normal',
      courseName: '语文',
      className: '一年级一班',
      classColor: '#2196F3',
      templateId: templateId,
    );

void main() {
  group('LessonWithTime.overlapsWith', () {
    test('同一天时间重叠 → true', () {
      final a = _withTime(_lesson(weekday: 1), start: '08:00', end: '08:45');
      final b = _withTime(_lesson(weekday: 1), start: '08:30', end: '09:15');
      expect(a.overlapsWith(b), isTrue);
    });

    test('不同星期即使时间相同也不冲突', () {
      final a = _withTime(_lesson(weekday: 1), start: '08:00', end: '08:45');
      final b = _withTime(_lesson(weekday: 2), start: '08:00', end: '08:45');
      expect(a.overlapsWith(b), isFalse);
    });

    test('首尾相接不算冲突', () {
      final a = _withTime(_lesson(weekday: 1), start: '08:00', end: '08:45');
      final b = _withTime(_lesson(weekday: 1), start: '08:45', end: '09:30');
      expect(a.overlapsWith(b), isFalse);
    });
  });

  group('LessonConflictDetector.findConflicts', () {
    test('period_index 相同但真实时间不同 → 不误判为冲突', () {
      // 多作息模板聚合场景的核心用例：不同模板的 period_index 语义不同，
      // 同一节次编号可能对应完全不同的真实时间，禁止直接比较 period_index。
      final candidate = _withTime(
        _lesson(periodIndex: 3, classId: 2),
        start: '10:00',
        end: '10:45',
        templateId: 2,
      );
      final existing = <LessonWithTime>[
        _withTime(_lesson(id: 10, periodIndex: 3), start: '08:00', end: '08:45'),
      ];
      expect(
        LessonConflictDetector.findConflicts(candidate: candidate, existing: existing),
        isEmpty,
      );
    });

    test('period_index 不同但真实时间重叠 → 必须判为冲突', () {
      final candidate = _withTime(
        _lesson(periodIndex: 5, classId: 2),
        start: '08:15',
        end: '09:00',
        templateId: 2,
      );
      final existing = <LessonWithTime>[
        _withTime(_lesson(id: 10, periodIndex: 2), start: '08:00', end: '08:45'),
      ];
      final conflicts =
          LessonConflictDetector.findConflicts(candidate: candidate, existing: existing);
      expect(conflicts.length, 1);
      expect(conflicts.first.lesson.id, 10);
    });

    test('编辑自身时通过 ignoreLessonId 排除自身', () {
      final candidate = _withTime(
        _lesson(id: 10, periodIndex: 1),
        start: '08:00',
        end: '08:45',
      );
      final existing = <LessonWithTime>[
        _withTime(_lesson(id: 10, periodIndex: 1), start: '08:00', end: '08:45'),
      ];
      expect(
        LessonConflictDetector.findConflicts(
          candidate: candidate,
          existing: existing,
          ignoreLessonId: 10,
        ),
        isEmpty,
      );
    });

    test('多个冲突一次性全部返回', () {
      final candidate = _withTime(_lesson(periodIndex: 9), start: '08:00', end: '12:00');
      final existing = <LessonWithTime>[
        _withTime(_lesson(id: 1), start: '08:00', end: '08:45'),
        _withTime(_lesson(id: 2), start: '09:00', end: '09:45'),
        _withTime(_lesson(id: 3), start: '13:00', end: '13:45'),
      ];
      final conflicts =
          LessonConflictDetector.findConflicts(candidate: candidate, existing: existing);
      expect(conflicts.map((item) => item.lesson.id).toList(), <int>[1, 2]);
    });
  });

  group('LessonConflictDetector.hasSameSlot', () {
    test('同班级同星期同节次 → 已占用', () {
      final candidate = _lesson(classId: 1, weekday: 1, periodIndex: 2);
      final existing = <Lesson>[_lesson(id: 7, classId: 1, weekday: 1, periodIndex: 2)];
      expect(
        LessonConflictDetector.hasSameSlot(candidate: candidate, existing: existing),
        isTrue,
      );
    });

    test('不同班级同节次 → 不占用', () {
      final candidate = _lesson(classId: 2, weekday: 1, periodIndex: 2);
      final existing = <Lesson>[_lesson(id: 7, classId: 1, weekday: 1, periodIndex: 2)];
      expect(
        LessonConflictDetector.hasSameSlot(candidate: candidate, existing: existing),
        isFalse,
      );
    });

    test('编辑自身时排除自身', () {
      final candidate = _lesson(id: 7, classId: 1, weekday: 1, periodIndex: 2);
      final existing = <Lesson>[_lesson(id: 7, classId: 1, weekday: 1, periodIndex: 2)];
      expect(
        LessonConflictDetector.hasSameSlot(
          candidate: candidate,
          existing: existing,
          ignoreLessonId: 7,
        ),
        isFalse,
      );
    });
  });

  group('LessonConflictDetector.canSwap', () {
    test('同班级同模板可交换', () {
      final a = _withTime(_lesson(id: 1, classId: 1, periodIndex: 1), start: '08:00', end: '08:45');
      final b = _withTime(_lesson(id: 2, classId: 1, periodIndex: 2), start: '08:55', end: '09:40');
      expect(LessonConflictDetector.canSwap(source: a, target: b), isTrue);
    });

    test('跨班级禁止交换', () {
      final a = _withTime(_lesson(id: 1, classId: 1), start: '08:00', end: '08:45');
      final b = _withTime(_lesson(id: 2, classId: 2), start: '08:55', end: '09:40');
      expect(LessonConflictDetector.canSwap(source: a, target: b), isFalse);
    });

    test('跨模板（同班级不同模板）禁止交换', () {
      final a = _withTime(_lesson(id: 1, classId: 1), start: '08:00', end: '08:45', templateId: 1);
      final b = _withTime(_lesson(id: 2, classId: 1), start: '08:55', end: '09:40', templateId: 2);
      expect(LessonConflictDetector.canSwap(source: a, target: b), isFalse);
    });
  });

  group('Lesson 序列化', () {
    test('toMap / fromMap 往返一致', () {
      final lesson = _lesson(id: 3, courseId: 4, classId: 5, teacherId: 6, weekday: 2, periodIndex: 7);
      final restored = Lesson.fromMap(lesson.toMap());
      expect(restored.id, lesson.id);
      expect(restored.courseId, lesson.courseId);
      expect(restored.classId, lesson.classId);
      expect(restored.teacherId, lesson.teacherId);
      expect(restored.weekday, lesson.weekday);
      expect(restored.periodIndex, lesson.periodIndex);
    });

    test('新增（id 为空）时不写入 id 字段', () {
      expect(_lesson().toMap().containsKey('id'), isFalse);
    });
  });
}
