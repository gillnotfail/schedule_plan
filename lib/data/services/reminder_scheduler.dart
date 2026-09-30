import 'package:schedule_plan/core/constants/app_constants.dart';
import 'package:schedule_plan/core/logging/app_logger.dart';
import 'package:schedule_plan/core/utils/date_utils.dart';
import 'package:schedule_plan/data/repositories/lesson_repository.dart';
import 'package:schedule_plan/data/repositories/schedule_event_repository.dart';
import 'package:schedule_plan/data/services/notification_service.dart';

/// 课前提醒与日程提醒的调度器（readme 模块七 7.1 / 7.2）。
///
/// **关键约束**：提醒触发时间不得在排课时固化为绝对时间戳。
/// 每次生成提醒时都必须重新联查当前生效的作息模板，按模板解析出的真实时间
/// 计算触发时刻，避免学校中途调整作息后提醒时间过时。
class ReminderScheduler {
  ReminderScheduler({
    required LessonRepository lessonRepository,
    required ScheduleEventRepository eventRepository,
    NotificationService? notificationService,
  })  : _lessons = lessonRepository,
        _events = eventRepository,
        _notifications = notificationService ?? NotificationService.instance;

  final LessonRepository _lessons;
  final ScheduleEventRepository _events;
  final NotificationService _notifications;

  /// 重新生成某一天的课前提醒。
  ///
  /// 返回实际安排的提醒条数。
  Future<int> regenerateLessonReminders({
    required DateTime date,
    required int minutesBefore,
    int teacherId = AppConstants.currentTeacherId,
  }) async {
    try {
      final weekday = DateUtils.isoWeekday(date);
      final lessons = await _lessons.queryWithTime(teacherId: teacherId, weekday: weekday);
      var scheduled = 0;
      var index = 0;
      for (final item in lessons) {
        final id = AppConstants.lessonReminderIdBase + (item.lesson.id ?? index);
        await _notifications.cancel(id);
        final trigger = DateUtils.atMinutes(date, item.startMinutes - minutesBefore);
        if (!trigger.isAfter(DateTime.now())) {
          index++;
          continue;
        }
        await _notifications.schedule(
          id: id,
          title: item.courseName,
          body: '${item.className} ${item.timeRangeText}',
          when: trigger,
          payload: 'lesson:${item.lesson.id}',
        );
        scheduled++;
        index++;
      }
      AppLogger.i('已重新生成 ${DateUtils.formatDate(date)} 的课前提醒：$scheduled 条');
      return scheduled;
    } catch (error, stack) {
      AppLogger.e('重新生成课前提醒失败', error: error, stack: stack);
      return 0;
    }
  }

  /// 日程事件提醒（模块七 7.2）：按事件设置的提醒开关和提前量生成。
  Future<int> regenerateEventReminders() async {
    try {
      final events = await _events.listEvents();
      var scheduled = 0;
      for (final event in events) {
        final id = AppConstants.eventReminderIdBase + (event.id ?? 0);
        await _notifications.cancel(id);
        if (!event.reminderEnabled) {
          continue;
        }
        final minutesBefore = event.reminderMinutesBefore ?? AppConstants.reminderMinutesBefore;
        final trigger = DateTime.fromMillisecondsSinceEpoch(event.startAt)
            .subtract(Duration(minutes: minutesBefore));
        if (!trigger.isAfter(DateTime.now())) {
          continue;
        }
        await _notifications.schedule(
          id: id,
          title: event.title,
          body: event.location ?? '',
          when: trigger,
          payload: 'event:${event.id}',
        );
        scheduled++;
      }
      AppLogger.i('已重新生成日程提醒：$scheduled 条');
      return scheduled;
    } catch (error, stack) {
      AppLogger.e('重新生成日程提醒失败', error: error, stack: stack);
      return 0;
    }
  }

  /// 一次性刷新：今天 + 明天 + 日程事件。
  Future<int> refreshAll({
    required int minutesBefore,
    int teacherId = AppConstants.currentTeacherId,
  }) async {
    final now = DateTime.now();
    final today = await regenerateLessonReminders(
      date: now,
      minutesBefore: minutesBefore,
      teacherId: teacherId,
    );
    final tomorrow = await regenerateLessonReminders(
      date: now.add(const Duration(days: 1)),
      minutesBefore: minutesBefore,
      teacherId: teacherId,
    );
    final events = await regenerateEventReminders();
    return today + tomorrow + events;
  }
}
