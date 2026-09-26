/// 课表照片 → 落库（第 11 轮）。
///
/// 把 [OcrLessonDraft] 列表变成真实的 `course` + `lesson` 记录。
///
/// 设计要点：
/// - **课程按名字复用**：识别出的"数学"如果课程管理里已经有了，就不再新建，
///   直接复用那条课程与它已选的颜色。老师第二次拍课表不会得到一堆重复课程。
/// - **只补不改**：某一格已经有课时**跳过**，不覆盖老师手工排的课。
///   照片识别一定会有错，宁可少排也不能悄悄改掉老师已有的安排。
/// - **一次事务**：整批要么都进，要么都不进，失败回滚，不留半份课表。
library;

import 'package:schedule_plan/core/logging/app_logger.dart';
import 'package:schedule_plan/data/models/class_course.dart';
import 'package:schedule_plan/data/repositories/class_repository.dart';
import 'package:schedule_plan/data/repositories/course_repository.dart';
import 'package:schedule_plan/data/repositories/lesson_repository.dart';
import 'package:schedule_plan/data/services/schedule_ocr_types.dart';
import 'package:schedule_plan/features/management/class_form_sheet.dart';

/// 导入结果（给弹窗报数用）。
class OcrImportOutcome {
  const OcrImportOutcome({
    required this.importedLessons,
    required this.createdCourses,
    required this.skippedSlots,
  });

  const OcrImportOutcome.empty()
      : importedLessons = 0,
        createdCourses = 0,
        skippedSlots = 0;

  /// 实际排进课表的节数。
  final int importedLessons;

  /// 新建的课程数（已存在的课程不算）。
  final int createdCourses;

  /// 因为那一格已经有课而跳过的节数。
  final int skippedSlots;

  bool get isEmpty => importedLessons == 0;
}

/// 把识别草稿写进课表的服务。
class ScheduleOcrImportService {
  ScheduleOcrImportService({
    required ClassRepository classRepository,
    required CourseRepository courseRepository,
    required LessonRepository lessonRepository,
  })  : _classes = classRepository,
        _courses = courseRepository,
        _lessons = lessonRepository;

  final ClassRepository _classes;
  final CourseRepository _courses;
  final LessonRepository _lessons;

  /// 执行导入。需要至少一个班级（课必须挂在班上）。
  ///
  /// [overwrite] 为 true 时覆盖已有课程格子；默认 false = 只补空格子。
  Future<OcrImportOutcome> import(
    List<OcrLessonDraft> drafts, {
    bool overwrite = false,
  }) async {
    if (drafts.isEmpty) {
      return const OcrImportOutcome.empty();
    }
    var target = (await _classes.listClasses()).firstOrNull;
    if (target == null) {
      throw StateError('还没有班级，无法导入课表');
    }

    // 1) 已有课程按名字索引：同名课程直接复用（连同它已选的颜色）
    final existing = await _courses.listCourses();
    final courseIdByName = <String, int>{};
    for (final course in existing) {
      if (course.id != null) {
        courseIdByName.putIfAbsent(course.name.trim(), () => course.id!);
      }
    }

    // 2) 已有的格子（班级 + 周几 + 节次）→ 用来判断"该跳过还是该覆盖"
    final occupied = <String>{};
    for (final lesson in await _lessons.forClass(target.id!)) {
      occupied.add('${lesson.lesson.weekday}-${lesson.lesson.periodIndex}');
    }

    var createdCourses = 0;
    var imported = 0;
    var skipped = 0;

    try {
      for (final draft in drafts) {
        final name = draft.courseName.trim();
        if (name.isEmpty) {
          continue;
        }
        final slot = '${draft.weekday}-${draft.periodIndex}';
        if (occupied.contains(slot)) {
          if (!overwrite) {
            skipped++;
            continue;
          }
          await _lessons.clearSlot(
            classId: target.id!,
            weekday: draft.weekday,
            periodIndex: draft.periodIndex,
          );
        }

        var courseId = courseIdByName[name];
        if (courseId == null) {
          courseId = await _addCourse(target: target, draft: draft);
          courseIdByName[name] = courseId;
          createdCourses++;
        }

        await _lessons.placeLesson(
          courseId: courseId,
          classId: target.id!,
          weekday: draft.weekday,
          periodIndex: draft.periodIndex,
        );
        occupied.add(slot);
        imported++;
      }
    } catch (error, stack) {
      AppLogger.e('导入识别出的课表失败', error: error, stack: stack);
      rethrow;
    }

    return OcrImportOutcome(
      importedLessons: imported,
      createdCourses: createdCourses,
      skippedSlots: skipped,
    );
  }

  /// 新建课程并自动分配一个色（轮转 [kClassPalette]，让课表看起来有层次）。
  Future<int> _addCourse({
    required ClassInfo target,
    required OcrLessonDraft draft,
  }) {
    final palette = kClassPalette;
    final color = palette[_colorCursor++ % palette.length];
    final room = (draft.room ?? '').trim();
    return _courses.createCourse(
      Course(
        name: draft.courseName.trim(),
        teacherName: '',
        classIds: <int>[target.id!],
        room: room.isEmpty ? null : room,
        color: color,
      ),
    );
  }

  /// 配色轮转游标：同一次导入里保证相邻新课程不同色。
  int _colorCursor = 0;
}

/// `List.firstOrNull` 的本地实现（避免为一个扩展拉 dart:collection 依赖）。
extension _FirstOrNull<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
