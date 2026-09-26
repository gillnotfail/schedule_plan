import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:schedule_plan/core/constants/app_constants.dart';
import 'package:schedule_plan/core/l10n/l10n_extensions.dart';
import 'package:schedule_plan/core/logging/app_logger.dart';
import 'package:schedule_plan/core/utils/date_utils.dart' as app_dates;
import 'package:schedule_plan/core/widgets/app_card.dart';
import 'package:schedule_plan/core/widgets/app_snackbar.dart';
import 'package:schedule_plan/core/widgets/confirm_dialog.dart';
import 'package:schedule_plan/data/models/china_holiday.dart';
import 'package:schedule_plan/data/models/schedule_event.dart';
import 'package:schedule_plan/data/repositories/note_repository.dart';
import 'package:schedule_plan/data/services/holiday_service.dart';
import 'package:schedule_plan/data/services/holiday_sync_service.dart';
import 'package:schedule_plan/data/services/reminder_scheduler.dart';
import 'package:schedule_plan/features/toolbox/holiday_shift_sheet.dart';
import 'package:schedule_plan/l10n/generated/app_localizations.dart';

/// 日程安排（模块五 5.3）：独立日历视图 + 事件管理。
///
/// 第 13 轮接入中国节假日与调休：
/// - 日历格子按官方安排着色（**红=放假、橙=调休上班**），旁边给图例；
/// - 点调休上班日可以直接选"这天上周几的课"，落库后课时结算会跟着变；
/// - 有日程的日子在角上点一个小圆点（重复日程也认，判定与错峰课表同一套）。
///
/// 节假日数据分两层：**联网取回的年度缓存优先，内置常量表兜底**
/// （见 `china_holiday_calendar.dart` 头部）。后台取回新数据后本页会跟着重画。
class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  final HolidayService _holidays = HolidayService();

  /// 当前显示的是哪个月的日历（永远取该月 1 号，避免 31 号翻月溢出）。
  late DateTime _month;
  DateTime _selected = app_dates.DateUtils.dateOnly(DateTime.now());

  List<ScheduleEvent> _events = const <ScheduleEvent>[];
  bool _loading = true;

  /// 选中的调休日"上周几的课"（null = 还没确认）。
  int? _shiftOfSelected;
  bool _loadingShift = false;

  @override
  void initState() {
    super.initState();
    _month = DateTime(_selected.year, _selected.month, 1);
    _reload();
  }

  Future<void> _reload() async {
    if (!mounted) {
      return;
    }
    setState(() => _loading = true);
    try {
      final events = await context.read<ScheduleEventRepository>().listEvents();
      if (!mounted) {
        return;
      }
      setState(() {
        _events = events;
        _loading = false;
      });
    } catch (error, stack) {
      AppLogger.e('加载日程失败', error: error, stack: stack);
      if (!mounted) {
        return;
      }
      setState(() => _loading = false);
    }
    await _loadShift();
  }

  Future<void> _loadShift() async {
    if (!HolidayService.isMakeupWorkday(_selected)) {
      if (mounted) {
        setState(() => _shiftOfSelected = null);
      }
      return;
    }
    setState(() => _loadingShift = true);
    final shift = await _holidays.shiftOf(_selected);
    if (!mounted) {
      return;
    }
    setState(() {
      _shiftOfSelected = shift;
      _loadingShift = false;
    });
  }

  /// 某个日期当天的日程（重复日程按 `occursOnWeek` 判定，与错峰课表同一口径）。
  List<ScheduleEvent> _eventsOn(DateTime day) {
    final weekStart = app_dates.DateUtils.startOfWeek(day);
    return _events.where((event) {
      if (!event.occursOnWeek(weekStart)) {
        return false;
      }
      final start = DateTime.fromMillisecondsSinceEpoch(event.startAt);
      return start.weekday == day.weekday;
    }).toList(growable: false);
  }

  void _select(DateTime day) {
    setState(() => _selected = app_dates.DateUtils.dateOnly(day));
    _loadShift();
  }

  void _shiftMonth(int delta) {
    // 必须走 DateUtils.shiftMonth：直接 DateTime(y, m ± 1, d) 会在
    // 3 月 31 日往前翻时溢出成 3 月 3 日（Dart 的日期进位）。
    final shifted = app_dates.DateUtils.shiftMonth(_month, delta);
    setState(() => _month = DateTime(shifted.year, shifted.month, 1));
  }

  @override
  Widget build(BuildContext context) {
    // 后台取回新的年度安排后会 notify。格子里的「休 / 班」是同步查内存表画的，
    // 所以只要重建一次就等于刷新了——不用再去读库。
    context.watch<HolidaySyncService>();
    final l10n = context.l10n;
    final first = DateTime(_month.year, _month.month, 1);
    final gridStart = first.subtract(Duration(days: first.weekday - 1));
    return Scaffold(
      appBar: AppBar(title: Text(l10n.scheduleCalendar)),
      floatingActionButton: FloatingActionButton(
        onPressed: _addEvent,
        child: const Icon(Icons.add),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: <Widget>[
          _buildCalendarCard(context, gridStart),
          const SizedBox(height: AppConstants.spaceM),
          _buildDayPanel(context),
          const SizedBox(height: AppConstants.spaceM),
          _buildEventList(context),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 日历
  // ---------------------------------------------------------------------------

  Widget _buildCalendarCard(BuildContext context, DateTime gridStart) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.spaceL,
        AppConstants.spaceS,
        AppConstants.spaceL,
        0,
      ),
      child: AppCard(
        padding: const EdgeInsets.all(AppConstants.spaceM),
        child: Column(
          children: <Widget>[
            Row(
              children: <Widget>[
                IconButton(
                  tooltip: l10n.previousMonth,
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => _shiftMonth(-1),
                ),
                Expanded(
                  child: Text(
                    l10n.yearMonth(_month.year, _month.month),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: l10n.nextMonth,
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () => _shiftMonth(1),
                ),
              ],
            ),
            const SizedBox(height: AppConstants.spaceS),
            Row(
              children: <Widget>[
                for (var weekday = 1; weekday <= 7; weekday++)
                  Expanded(
                    child: Text(
                      l10n.weekdayShort(weekday),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppConstants.spaceXs),
            GridView.count(
              crossAxisCount: 7,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 2,
              crossAxisSpacing: 2,
              childAspectRatio: AppConstants.calendarCellAspectRatio,
              children: <Widget>[
                for (var i = 0; i < AppConstants.calendarGridDays; i++)
                  _buildCell(gridStart.add(Duration(days: i))),
              ],
            ),
            const SizedBox(height: AppConstants.spaceS),
            Row(
              children: <Widget>[
                _LegendDot(color: scheme.error, label: l10n.holidayKindHoliday),
                const SizedBox(width: AppConstants.spaceM),
                _LegendDot(
                  color: scheme.tertiary,
                  label: l10n.holidayKindMakeup,
                ),
                const SizedBox(width: AppConstants.spaceM),
                Expanded(
                  child: Text(
                    l10n.holidayLegend,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCell(DateTime day) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final kind = HolidayService.kindOf(day);
    final inMonth = day.month == _month.month;
    final selected = app_dates.DateUtils.isSameDay(day, _selected);
    final isToday = app_dates.DateUtils.isSameDay(day, DateTime.now());
    final holiday = kind == CalendarDayKind.holiday;
    final makeup = kind == CalendarDayKind.makeupWorkday;

    final Color? background;
    if (holiday) {
      background = scheme.error.withValues(alpha: selected ? 0.26 : 0.13);
    } else if (makeup) {
      background = scheme.tertiary.withValues(alpha: selected ? 0.30 : 0.16);
    } else if (selected) {
      background = scheme.primaryContainer;
    } else {
      background = null;
    }

    final numberColor = holiday
        ? scheme.error
        : makeup
            ? scheme.tertiary
            : (inMonth ? scheme.onSurface : scheme.onSurfaceVariant.withValues(alpha: 0.45));

    return GestureDetector(
      onTap: () => _select(day),
      child: Container(
        decoration: BoxDecoration(
          color: background,
          borderRadius: AppRadii.smallAll,
          border: isToday && !selected
              ? Border.all(color: scheme.primary.withValues(alpha: 0.6))
              : null,
        ),
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              '${day.day}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: numberColor,
                fontWeight: holiday || makeup || isToday
                    ? FontWeight.w800
                    : FontWeight.w500,
              ),
            ),
            if (holiday || makeup)
              Text(
                holiday ? context.l10n.holidayKindHoliday : context.l10n.holidayKindMakeup,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontSize: 8,
                  height: 1.0,
                  fontWeight: FontWeight.w800,
                  color: holiday ? scheme.error : scheme.tertiary,
                ),
              )
            else if (_eventsOn(day).isNotEmpty)
              Container(
                width: 4,
                height: 4,
                margin: const EdgeInsets.only(top: 2),
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: inMonth ? 0.8 : 0.35),
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 选中那天的说明（放假 / 调休）
  // ---------------------------------------------------------------------------

  Widget _buildDayPanel(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final info = HolidayService.infoOf(_selected);
    if (info == null) {
      return const SizedBox.shrink();
    }
    final holiday = info.kind == CalendarDayKind.holiday;
    final accent = holiday ? scheme.error : scheme.tertiary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppConstants.spaceL),
      child: AppCard(
        color: accent.withValues(alpha: 0.10),
        borderColor: accent.withValues(alpha: 0.28),
        elevated: false,
        padding: const EdgeInsets.all(AppConstants.spaceM),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  holiday
                      ? Icons.beach_access_outlined
                      : Icons.swap_horiz_rounded,
                  size: 18,
                  color: accent,
                ),
                const SizedBox(width: AppConstants.spaceS),
                Expanded(
                  child: Text(
                    holiday
                        ? '${_holidayName(context, info.name)} · '
                            '${l10n.holidayKindHoliday}'
                        : '${_holidayName(context, info.name)} · '
                            '${l10n.holidayKindMakeup}',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: accent,
                    ),
                  ),
                ),
              ],
            ),
            if (!holiday) ...<Widget>[
              const SizedBox(height: AppConstants.spaceS),
              Text(
                _loadingShift
                    ? l10n.loading
                    : (_shiftOfSelected == null
                        ? l10n.holidayMakeupNotSet
                        : l10n.holidayMakeupResolved(
                            l10n.weekdayShort(_shiftOfSelected!),
                          )),
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: AppConstants.spaceS),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _editShift,
                  child: Text(
                    _shiftOfSelected == null
                        ? l10n.holidayMakeupSet
                        : l10n.edit,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _editShift() async {
    // 先读"上次选过的星期几"再弹层：写进参数里会让 await 与 context
    // 落在同一个表达式，触发 use_build_context_synchronously。
    final suggest = await _holidays.lastShift();
    if (!mounted) {
      return;
    }
    final choice = await showHolidayShiftSheet(
      context,
      date: _selected,
      currentWeekday: _shiftOfSelected,
      suggestWeekday: suggest,
    );
    if (choice == null || !mounted) {
      return;
    }
    await _holidays.setShift(_selected, choice.weekday);
    await _loadShift();
    if (!mounted) {
      return;
    }
    showAppSnackBar(
      context,
      choice.weekday == null
          ? context.l10n.holidayShiftCleared
          : context.l10n.holidayShiftSaved(
              context.l10n.weekdayShort(choice.weekday!),
            ),
    );
  }

  // ---------------------------------------------------------------------------
  // 当天日程列表
  // ---------------------------------------------------------------------------

  Widget _buildEventList(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final events = _eventsOn(_selected);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppConstants.spaceL),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SectionHeader(
            title: l10n.eventDayTitle,
            icon: Icons.event_note_outlined,
            description: '${_selected.month} 月 ${_selected.day} 日 · '
                '${l10n.weekdayShort(_selected.weekday)}',
          ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(AppConstants.spaceL),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (events.isEmpty)
            AppCard(
              child: Text(
                l10n.noData,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            )
          else
            for (final event in events)
              Padding(
                padding: const EdgeInsets.only(bottom: AppConstants.spaceS),
                child: AppCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppConstants.spaceM,
                    vertical: AppConstants.spaceS,
                  ),
                  child: _EventTile(
                    event: event,
                    onDelete: () => _delete(event),
                  ),
                ),
              ),
        ],
      ),
    );
  }

  Future<void> _delete(ScheduleEvent event) async {
    final id = event.id;
    if (id == null) {
      return;
    }
    await context.read<ScheduleEventRepository>().deleteEvent(id);
    if (!mounted) {
      return;
    }
    showAppSnackBar(context, context.l10n.delete);
    await _reload();
  }

  Future<void> _addEvent() async {
    final result = await showAppSheet<ScheduleEvent>(
      context: context,
      builder: (_) => _EventForm(day: _selected),
    );
    if (result == null || !mounted) {
      return;
    }
    final eventRepo = context.read<ScheduleEventRepository>();
    final scheduler = context.read<ReminderScheduler>();
    try {
      await eventRepo.createEvent(result);
      // 模块七 7.2：日程提醒与事件联动，按提醒开关和提前量生成本地通知
      await scheduler.regenerateEventReminders();
      if (!mounted) {
        return;
      }
      showAppSnackBar(context, context.l10n.eventSaved);
      await _reload();
    } catch (error, stack) {
      AppLogger.e('新增日程失败', error: error, stack: stack);
      if (!mounted) {
        return;
      }
      showAppSnackBar(context, context.l10n.operationFailed('$error'));
    }
  }
}

/// 一天里的一条日程：时间 + 标题 + 地点 + 删除。
class _EventTile extends StatelessWidget {
  const _EventTile({required this.event, required this.onDelete});

  final ScheduleEvent event;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final start = DateTime.fromMillisecondsSinceEpoch(event.startAt);
    final location = event.location;
    return Row(
      children: <Widget>[
        Container(
          width: 52,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            color: scheme.primaryContainer.withValues(alpha: 0.7),
            borderRadius: AppRadii.smallAll,
          ),
          child: Text(
            '${start.hour.toString().padLeft(2, '0')}:'
            '${start.minute.toString().padLeft(2, '0')}',
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: scheme.onPrimaryContainer,
            ),
          ),
        ),
        const SizedBox(width: AppConstants.spaceM),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                event.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                <String>[
                  _recurrenceLabel(l10n, event.recurrence),
                  if (location != null && location.isNotEmpty) location,
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: l10n.delete,
          icon: const Icon(Icons.delete_outline),
          onPressed: onDelete,
        ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: <Widget>[
        Container(
          width: 10,
          height: 10,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.18),
            borderRadius: AppRadii.smallAll,
          ),
          child: Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              fontSize: 7,
              height: 1.0,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

/// 重复周期的中文说法。
///
/// 直接复用日程表单里的那四个键，不另建一套——同一个 `EventRecurrence`
/// 在两个页面必须叫同一个名字。
String _recurrenceLabel(AppLocalizations l10n, EventRecurrence recurrence) =>
    switch (recurrence) {
      EventRecurrence.once => l10n.eventRecurrenceOnce,
      EventRecurrence.weekly => l10n.eventRecurrenceWeekly,
      EventRecurrence.biweekly => l10n.eventRecurrenceBiweekly,
      EventRecurrence.monthly => l10n.eventRecurrenceMonthly,
    };

/// 节日名的本地化。
String _holidayName(BuildContext context, HolidayName? name) {
  final l10n = context.l10n;
  return switch (name) {
    HolidayName.newYear => l10n.holidayNameNewYear,
    HolidayName.springFestival => l10n.holidayNameSpringFestival,
    HolidayName.qingming => l10n.holidayNameQingming,
    HolidayName.labourDay => l10n.holidayNameLabourDay,
    HolidayName.dragonBoat => l10n.holidayNameDragonBoat,
    HolidayName.midAutumn => l10n.holidayNameMidAutumn,
    HolidayName.nationalDay => l10n.holidayNameNationalDay,
    HolidayName.nationalDayMidAutumn => l10n.holidayNameNationalDayMidAutumn,
    null => '',
  };
}

class _EventForm extends StatefulWidget {
  const _EventForm({required this.day});

  final DateTime day;

  @override
  State<_EventForm> createState() => _EventFormState();
}

class _EventFormState extends State<_EventForm> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _location = TextEditingController();
  TimeOfDay _time = TimeOfDay.now();
  bool _reminder = true;
  int _minutesBefore = AppConstants.reminderMinutesBefore;
  EventRecurrence _recurrence = EventRecurrence.once;

  @override
  void dispose() {
    _title.dispose();
    _location.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AppCard(
      radius: AppRadii.sheet,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(l10n.eventFormTitle,
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppConstants.spaceM),
          TextField(
            controller: _title,
            decoration: InputDecoration(labelText: l10n.eventTitle),
          ),
          const SizedBox(height: AppConstants.spaceM),
          TextField(
            controller: _location,
            decoration: InputDecoration(labelText: l10n.eventLocation),
          ),
          const SizedBox(height: AppConstants.spaceM),
          OutlinedButton.icon(
            icon: const Icon(Icons.access_time),
            label: Text(_time.format(context)),
            onPressed: () async {
              final picked = await showTimePicker(
                context: context,
                initialTime: _time,
              );
              if (picked != null) {
                setState(() => _time = picked);
              }
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.eventReminder),
            value: _reminder,
            onChanged: (value) => setState(() => _reminder = value),
          ),
          const SizedBox(height: AppConstants.spaceM),
          Text(l10n.eventRecurrence,
              style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: AppConstants.spaceS),
          SegmentedButton<EventRecurrence>(
            segments: <ButtonSegment<EventRecurrence>>[
              ButtonSegment<EventRecurrence>(
                value: EventRecurrence.once,
                label: Text(l10n.eventRecurrenceOnce),
              ),
              ButtonSegment<EventRecurrence>(
                value: EventRecurrence.weekly,
                label: Text(l10n.eventRecurrenceWeekly),
              ),
              ButtonSegment<EventRecurrence>(
                value: EventRecurrence.biweekly,
                label: Text(l10n.eventRecurrenceBiweekly),
              ),
              ButtonSegment<EventRecurrence>(
                value: EventRecurrence.monthly,
                label: Text(l10n.eventRecurrenceMonthly),
              ),
            ],
            selected: <EventRecurrence>{_recurrence},
            onSelectionChanged: (selection) =>
                setState(() => _recurrence = selection.first),
          ),
          if (_reminder)
            TextField(
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: l10n.eventReminderBefore,
              ),
              controller: TextEditingController(text: '$_minutesBefore'),
              onChanged: (value) =>
                  _minutesBefore = int.tryParse(value) ?? _minutesBefore,
            ),
          const SizedBox(height: AppConstants.spaceL),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
            onPressed: () {
              if (_title.text.trim().isEmpty) {
                return;
              }
              final start = DateTime(
                widget.day.year,
                widget.day.month,
                widget.day.day,
                _time.hour,
                _time.minute,
              );
              Navigator.of(context).pop(
                ScheduleEvent(
                  title: _title.text.trim(),
                  startAt: start.millisecondsSinceEpoch,
                  location:
                      _location.text.trim().isEmpty ? null : _location.text.trim(),
                  reminderEnabled: _reminder,
                  reminderMinutesBefore: _reminder ? _minutesBefore : null,
                  recurrence: _recurrence,
                ),
              );
            },
            child: Text(l10n.save),
          ),
        ],
      ),
    );
  }
}
