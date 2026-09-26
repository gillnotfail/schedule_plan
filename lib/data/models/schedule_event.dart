/// 日程安排事件（readme 3.11 表 schedule_event，模块五 5.3）。
///
/// 用户规格（第 9 轮）：日程要能**联动到课表/作息表**——单次活动这周有、下周就没了；
/// 隔周/隔月活动不用单独打开日程，直接在课表上就能看到。所以新增 [recurrence]
/// 描述重复周期，[occursOnWeek] 判定某个活动在给定的一周里到底发不发生。
class ScheduleEvent {
  const ScheduleEvent({
    this.id,
    required this.title,
    required this.startAt,
    this.endAt,
    this.location,
    this.reminderEnabled = false,
    this.reminderMinutesBefore,
    this.recurrence = EventRecurrence.once,
  });

  final int? id;
  final String title;

  /// 毫秒时间戳
  final int startAt;
  final int? endAt;
  final String? location;
  final bool reminderEnabled;
  final int? reminderMinutesBefore;

  /// 重复周期：单次 / 每周 / 隔周 / 每月。
  final EventRecurrence recurrence;

  ScheduleEvent copyWith({
    int? id,
    String? title,
    int? startAt,
    int? endAt,
    String? location,
    bool? reminderEnabled,
    int? reminderMinutesBefore,
    EventRecurrence? recurrence,
  }) {
    return ScheduleEvent(
      id: id ?? this.id,
      title: title ?? this.title,
      startAt: startAt ?? this.startAt,
      endAt: endAt ?? this.endAt,
      location: location ?? this.location,
      reminderEnabled: reminderEnabled ?? this.reminderEnabled,
      reminderMinutesBefore: reminderMinutesBefore ?? this.reminderMinutesBefore,
      recurrence: recurrence ?? this.recurrence,
    );
  }

  /// 这个活动在 [weekStart]（周一 00:00）开头的那一周里发不发生。
  ///
  /// - 单次：只在它自己那一周发生（下周就没了）；
  /// - 每周：每周都发生；
  /// - 隔周：从它自己那周起，隔着周发生（第 0、2、4… 周）；
  /// - 每月：在「和开始日同一天号」的那周发生（每月固定那天）。
  bool occursOnWeek(DateTime weekStart) {
    final start = DateTime.fromMillisecondsSinceEpoch(startAt);
    final ws = DateTime(weekStart.year, weekStart.month, weekStart.day);
    switch (recurrence) {
      case EventRecurrence.once:
        final end = ws.add(const Duration(days: 7));
        return !start.isBefore(ws) && start.isBefore(end);
      case EventRecurrence.weekly:
        return true;
      case EventRecurrence.biweekly:
        final anchor = _startOfWeek(start);
        final weeks = ws.difference(anchor).inDays ~/ 7;
        return weeks.isEven;
      case EventRecurrence.monthly:
        // 每月固定那"一天号"：这一周的 7 天里只要有那天号就算发生
        for (var i = 0; i < 7; i++) {
          if (ws.add(Duration(days: i)).day == start.day) {
            return true;
          }
        }
        return false;
    }
  }

  /// 事件落在 [weekday]（1=周一…7=周日）这一天的毫秒起点，供课表按列定位。
  /// 只在 `occursOnWeek` 为真后调用，否则返回的日期可能不在那一周里。
  int startAtOn(DateTime weekStart, int weekday) {
    final start = DateTime.fromMillisecondsSinceEpoch(startAt);
    final ws = DateTime(weekStart.year, weekStart.month, weekStart.day);
    final day = ws.add(Duration(days: weekday - 1));
    return DateTime(day.year, day.month, day.day, start.hour, start.minute)
        .millisecondsSinceEpoch;
  }

  Map<String, Object?> toMap() => <String, Object?>{
        if (id != null) 'id': id,
        'title': title,
        'start_at': startAt,
        'end_at': endAt,
        'location': location,
        'reminder_enabled': reminderEnabled ? 1 : 0,
        'reminder_minutes_before': reminderMinutesBefore,
        'recurrence': recurrence.storageKey,
      };

  static ScheduleEvent fromMap(Map<String, Object?> map) => ScheduleEvent(
        id: map['id'] as int?,
        title: map['title'] as String,
        startAt: map['start_at'] as int,
        endAt: map['end_at'] as int?,
        location: map['location'] as String?,
        reminderEnabled: (map['reminder_enabled'] as int? ?? 0) == 1,
        reminderMinutesBefore: map['reminder_minutes_before'] as int?,
        recurrence: EventRecurrence.fromStorage(map['recurrence'] as String?),
      );

  static DateTime _startOfWeek(DateTime d) =>
      DateTime(d.year, d.month, d.day - (d.weekday - 1));
}

/// 日程重复周期。
enum EventRecurrence {
  once,
  weekly,
  biweekly,
  monthly;

  String get storageKey => name;

  static EventRecurrence fromStorage(String? value) =>
      EventRecurrence.values.firstWhere(
        (item) => item.storageKey == value,
        orElse: () => EventRecurrence.once,
      );
}

/// 专注模式记录（readme 3.12 表 focus_session，模块五 5.1）。
class FocusSession {
  const FocusSession({
    this.id,
    required this.startedAt,
    required this.durationMinutes,
    this.completed = false,
  });

  final int? id;
  final int startedAt;
  final int durationMinutes;
  final bool completed;

  Map<String, Object?> toMap() => <String, Object?>{
        if (id != null) 'id': id,
        'started_at': startedAt,
        'duration_minutes': durationMinutes,
        'completed': completed ? 1 : 0,
      };

  static FocusSession fromMap(Map<String, Object?> map) => FocusSession(
        id: map['id'] as int?,
        startedAt: map['started_at'] as int,
        durationMinutes: map['duration_minutes'] as int,
        completed: (map['completed'] as int? ?? 0) == 1,
      );
}
