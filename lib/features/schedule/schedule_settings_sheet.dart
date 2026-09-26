import 'package:flutter/material.dart';

import 'package:schedule_plan/core/constants/app_constants.dart';
import 'package:schedule_plan/core/l10n/l10n_extensions.dart';
import 'package:schedule_plan/core/theme/app_motion.dart';
import 'package:schedule_plan/core/utils/time_utils.dart';
import 'package:schedule_plan/core/widgets/app_card.dart';
import 'package:schedule_plan/core/widgets/dial_time_picker.dart';
import 'package:schedule_plan/core/widgets/settings_tile.dart';

/// 「课表设置」半屏弹层（用户规格）。
///
/// 一键生成作息 / 默认作息修改 / 作息模板管理 / 一键新增课表 / 一键清空课表 /
/// 拍照导入课表（OCR 占位）。
/// 返回 `true` 表示调用方需要刷新课表。
///
/// 「一键生成作息」的表单初值一律来自**当前正在展示的那套作息**
/// （开始时间 / 时长 / 课间 / 节数 / 已选的星期），
/// 这样打开就能看到真实状态，而不是每次都跳回"周一到周五 8:00"的出厂值。
Future<bool> showScheduleSettingsSheet(
  BuildContext context, {
  required String templateName,
  required int periodCount,
  required void Function({
    required String startTime,
    required int lessonMinutes,
    required int breakMinutes,
    required int count,
    required List<int> weekdays,
  }) onGenerate,
  required Future<void> Function() onEditDefault,
  required Future<void> Function() onClear,
  Future<void> Function()? onImportPhoto,
  Future<void> Function()? onQuickAdd,
  Future<void> Function()? onManageTemplates,
  List<int> initialWeekdays = const <int>[1, 2, 3, 4, 5],
  String initialStartTime = AppConstants.defaultDayStartTime,
  int initialLessonMinutes = AppConstants.defaultLessonMinutes,
  int initialBreakMinutes = AppConstants.defaultBreakMinutes,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: RoundedRectangleBorder(borderRadius: AppRadii.sheetTop),
    builder: (sheetContext) => _ScheduleSettingsSheet(
      templateName: templateName,
      periodCount: periodCount,
      onGenerate: onGenerate,
      onEditDefault: onEditDefault,
      onClear: onClear,
      onImportPhoto: onImportPhoto,
      onQuickAdd: onQuickAdd,
      onManageTemplates: onManageTemplates,
      initialWeekdays: initialWeekdays,
      initialStartTime: initialStartTime,
      initialLessonMinutes: initialLessonMinutes,
      initialBreakMinutes: initialBreakMinutes,
    ),
  );
  return result ?? false;
}

class _ScheduleSettingsSheet extends StatefulWidget {
  const _ScheduleSettingsSheet({
    required this.templateName,
    required this.periodCount,
    required this.onGenerate,
    required this.onEditDefault,
    required this.onClear,
    this.onImportPhoto,
    this.onQuickAdd,
    this.onManageTemplates,
    required this.initialWeekdays,
    required this.initialStartTime,
    required this.initialLessonMinutes,
    required this.initialBreakMinutes,
  });

  final String templateName;
  final int periodCount;
  final void Function({
    required String startTime,
    required int lessonMinutes,
    required int breakMinutes,
    required int count,
    required List<int> weekdays,
  }) onGenerate;
  final Future<void> Function() onEditDefault;
  final Future<void> Function() onClear;
  final Future<void> Function()? onImportPhoto;

  /// 「一键新增课表」向导（按 班级 → 课程 → 周几/节次 三步排课）。
  /// 课表页的右下角主入口已经改成「添加课程」，向导挪到这里保留。
  final Future<void> Function()? onQuickAdd;

  /// 「作息模板」管理入口（新建 / 重命名 / 删除多套作息）。
  ///
  /// 原来挂在设置页，用户规格要求撤掉设置页那一项（"课表页已经有一键生成和
  /// 单独定制了"）；这里保留入口，否则"错峰课表"这类第二套作息就无处可建。
  final Future<void> Function()? onManageTemplates;

  final List<int> initialWeekdays;
  final String initialStartTime;
  final int initialLessonMinutes;
  final int initialBreakMinutes;

  @override
  State<_ScheduleSettingsSheet> createState() => _ScheduleSettingsSheetState();
}

class _ScheduleSettingsSheetState extends State<_ScheduleSettingsSheet> {
  late String _startTime;
  late int _lessonMinutes;
  late int _breakMinutes;
  late int _count;
  late Set<int> _weekdays;
  bool _expanded = true;

  @override
  void initState() {
    super.initState();
    _startTime = widget.initialStartTime;
    _lessonMinutes = widget.initialLessonMinutes;
    _breakMinutes = widget.initialBreakMinutes;
    _count = widget.periodCount > 0
        ? widget.periodCount
        : AppConstants.defaultDayPeriodCount;
    // 已配置的星期优先：打开设置就能看到"现在到底是 5 天还是 7 天"
    _weekdays = widget.initialWeekdays.isEmpty
        ? <int>{1, 2, 3, 4, 5}
        : widget.initialWeekdays.toSet();
  }

  bool get _valid {
    final first = TimeUtils.tryParseMinutes(_startTime) ?? 0;
    final end = first + (_count - 1) * (_lessonMinutes + _breakMinutes) +
        _lessonMinutes;
    return end <= 24 * 60 && _weekdays.isNotEmpty;
  }

  List<(String, String)> get _preview {
    final first = TimeUtils.tryParseMinutes(_startTime) ?? 0;
    final step = _lessonMinutes + _breakMinutes;
    return List<(String, String)>.generate(_count, (index) {
      final start = first + index * step;
      return (
        TimeUtils.formatMinutes(start),
        TimeUtils.formatMinutes(start + _lessonMinutes),
      );
    }, growable: false);
  }

  Future<void> _pickStartTime() async {
    final picked = await showDialTimePicker(
      context,
      initialTime: _startTime,
      title: context.l10n.generateStartTime,
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() => _startTime = picked);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppConstants.spaceL,
          AppConstants.spaceS,
          AppConstants.spaceL,
          AppConstants.spaceL + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.86,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: scheme.outlineVariant,
                      borderRadius: AppRadii.stadiumAll,
                    ),
                  ),
                ),
                const SizedBox(height: AppConstants.spaceM),
                Row(
                  children: <Widget>[
                    Icon(Icons.tune_rounded, color: scheme.primary, size: 20),
                    const SizedBox(width: AppConstants.spaceS),
                    Expanded(
                      child: Text(
                        l10n.scheduleSettings,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ),
                    Text(
                      widget.templateName,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppConstants.spaceL),

                // ---------------- 一键生成作息 ----------------
                AppCard(
                  padding: const EdgeInsets.all(AppConstants.spaceM),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  l10n.quickGenerateTitle,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                Text(
                                  l10n.quickGenerateDesc,
                                  style: theme.textTheme.labelSmall,
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () {
                              AppMotion.tap();
                              setState(() => _expanded = !_expanded);
                            },
                            icon: Icon(
                              _expanded
                                  ? Icons.expand_less_rounded
                                  : Icons.expand_more_rounded,
                            ),
                          ),
                        ],
                      ),
                      AnimatedCrossFade(
                        duration: AppMotion.standard,
                        sizeCurve: AppMotion.expressive,
                        crossFadeState: _expanded
                            ? CrossFadeState.showFirst
                            : CrossFadeState.showSecond,
                        firstChild: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            const SizedBox(height: AppConstants.spaceS),
                            _TimeField(
                              label: l10n.generateStartTime,
                              value: _startTime,
                              onTap: _pickStartTime,
                            ),
                            const SizedBox(height: AppConstants.spaceS),
                            _NumberStepper(
                              label: l10n.generateLessonMinutes,
                              value: _lessonMinutes,
                              min: 20,
                              max: 120,
                              step: 5,
                              onChanged: (value) =>
                                  setState(() => _lessonMinutes = value),
                            ),
                            _NumberStepper(
                              label: l10n.generateBreakMinutes,
                              value: _breakMinutes,
                              min: 0,
                              max: 40,
                              step: 5,
                              onChanged: (value) =>
                                  setState(() => _breakMinutes = value),
                            ),
                            _NumberStepper(
                              label: l10n.generatePeriodCount,
                              value: _count,
                              min: 1,
                              max: 16,
                              step: 1,
                              onChanged: (value) =>
                                  setState(() => _count = value),
                            ),
                            const SizedBox(height: AppConstants.spaceS),
                            Text(
                              l10n.generateWeekdays,
                              style: theme.textTheme.labelLarge,
                            ),
                            const SizedBox(height: AppConstants.spaceXs),
                            Wrap(
                              spacing: AppConstants.spaceS,
                              children: <Widget>[
                                for (var day = 1;
                                    day <= AppConstants.weekdayCount;
                                    day++)
                                  FilterChip(
                                    label: Text(context.l10n.weekdayShort(day)),
                                    selected: _weekdays.contains(day),
                                    onSelected: (selected) {
                                      AppMotion.select();
                                      setState(() {
                                        if (selected) {
                                          _weekdays.add(day);
                                        } else {
                                          _weekdays.remove(day);
                                        }
                                      });
                                    },
                                  ),
                              ],
                            ),
                            const SizedBox(height: AppConstants.spaceXs),
                            // 说明"生成即最高权限"：未选中的星期会被清空，
                            // 避免老师以为"取消勾选"只是不重新生成
                            Text(
                              l10n.generateReplacesHint,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: AppConstants.spaceM),
                            Text(
                              l10n.generatePreview,
                              style: theme.textTheme.labelLarge,
                            ),
                            const SizedBox(height: AppConstants.spaceXs),
                            Container(
                              padding: const EdgeInsets.all(AppConstants.spaceM),
                              decoration: BoxDecoration(
                                color: scheme.surfaceContainerHigh,
                                borderRadius: AppRadii.smallAll,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  for (var i = 0; i < _preview.length; i++)
                                    if (i < 4 || i == _preview.length - 1)
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 1,
                                        ),
                                        child: Text(
                                          l10n.generatePreviewRow(
                                            i + 1,
                                            _preview[i].$1,
                                            _preview[i].$2,
                                          ),
                                          style: theme.textTheme.labelSmall
                                              ?.copyWith(height: 1.5),
                                        ),
                                      )
                                    else if (i == 4)
                                      Text(
                                        '  ...',
                                        style: theme.textTheme.labelSmall,
                                      ),
                                ],
                              ),
                            ),
                            if (!_valid)
                              Padding(
                                padding: const EdgeInsets.only(
                                  top: AppConstants.spaceS,
                                ),
                                child: Text(
                                  _weekdays.isEmpty
                                      ? l10n.generateEmptyWeekdays
                                      : l10n.generateInvalidRange,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: scheme.error,
                                  ),
                                ),
                              ),
                            const SizedBox(height: AppConstants.spaceM),
                            FilledButton.icon(
                              onPressed: _valid
                                  ? () {
                                      AppMotion.confirm();
                                      widget.onGenerate(
                                        startTime: _startTime,
                                        lessonMinutes: _lessonMinutes,
                                        breakMinutes: _breakMinutes,
                                        count: _count,
                                        weekdays: _weekdays.toList()..sort(),
                                      );
                                      Navigator.of(context).pop(true);
                                    }
                                  : null,
                              icon: const Icon(Icons.auto_fix_high_outlined,
                                  size: 18),
                              label: Text(l10n.quickGenerateTitle),
                            ),
                          ],
                        ),
                        secondChild: const SizedBox(width: double.infinity),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppConstants.spaceM),

                SettingsGroup(
                  children: <Widget>[
                    if (widget.onManageTemplates != null)
                      SettingsTile(
                        icon: Icons.layers_outlined,
                        title: l10n.templateTitle,
                        subtitle: l10n.defaultTemplateHint,
                        onTap: () async {
                          Navigator.of(context).pop(false);
                          await widget.onManageTemplates!();
                        },
                      ),
                    SettingsTile(
                      icon: Icons.schedule_outlined,
                      title: l10n.defaultTemplateEdit,
                      subtitle: l10n.defaultTemplateHint,
                      onTap: () async {
                        Navigator.of(context).pop(false);
                        await widget.onEditDefault();
                      },
                    ),
                    if (widget.onQuickAdd != null)
                      SettingsTile(
                        icon: Icons.playlist_add_rounded,
                        title: l10n.addLesson,
                        subtitle: l10n.quickAddLessonHint,
                        onTap: () async {
                          Navigator.of(context).pop(false);
                          await widget.onQuickAdd!();
                        },
                      ),
                    SettingsTile(
                      icon: Icons.photo_camera_outlined,
                      title: l10n.importPhotoSchedule,
                      subtitle: l10n.importPhotoScheduleHint,
                      onTap: () async {
                        // 拍照识别已经跑通（第 11 轮）：直接进三步流程页，
                        // 导入成功后由课表页统一 reload，所以这里先关掉弹层。
                        final handler = widget.onImportPhoto;
                        if (handler == null) {
                          return;
                        }
                        Navigator.of(context).pop(false);
                        await handler();
                      },
                    ),
                    SettingsTile(
                      icon: Icons.delete_sweep_outlined,
                      title: l10n.clearSchedule,
                      subtitle: l10n.clearScheduleConfirm,
                      danger: true,
                      onTap: () async {
                        Navigator.of(context).pop(false);
                        await widget.onClear();
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

}

/// 修改单个节次时间（用户规格：点击第一列的某节课即可自定义修改）。
///
/// 返回 (开始时间, 结束时间, 是否级联顺延, 是否应用到所有上课日)，
/// 取消时返回 null。
Future<({String start, String end, bool cascade, bool allDays})?>
    showPeriodTimeSheet(
  BuildContext context, {
  required int periodIndex,
  required String startTime,
  required String endTime,
  required List<int> availableWeekdays,
  required bool defaultApplyAllDays,
}) async {
  final result = await showModalBottomSheet<({
    String start,
    String end,
    bool cascade,
    bool allDays
  })>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: RoundedRectangleBorder(borderRadius: AppRadii.sheetTop),
    builder: (sheetContext) => _PeriodTimeSheet(
      periodIndex: periodIndex,
      startTime: startTime,
      endTime: endTime,
      availableWeekdays: availableWeekdays,
      defaultApplyAllDays: defaultApplyAllDays,
    ),
  );
  return result;
}

class _PeriodTimeSheet extends StatefulWidget {
  const _PeriodTimeSheet({
    required this.periodIndex,
    required this.startTime,
    required this.endTime,
    required this.availableWeekdays,
    required this.defaultApplyAllDays,
  });

  final int periodIndex;
  final String startTime;
  final String endTime;
  final List<int> availableWeekdays;
  final bool defaultApplyAllDays;

  @override
  State<_PeriodTimeSheet> createState() => _PeriodTimeSheetState();
}

class _PeriodTimeSheetState extends State<_PeriodTimeSheet> {
  late String _start;
  late String _end;
  late bool _cascade;
  late bool _allDays;

  /// 本节的课堂时长。
  ///
  /// 取自**作息模板里这一节自己的起止时间**——早读 20 分钟、晚自习 60 分钟
  /// 这类长短课不能用全局默认的 40 分钟顶替，否则结束时间会算飞。
  late final int _lessonMinutes;

  /// 结束时间是否被用户单独指定过。
  ///
  /// 用户规格：点第一列改时间时**只调开始时间就够了**，结束时间按课堂时长
  /// 自动算；只有特地改过一次结束时间，才脱离自动。
  bool _endManual = false;

  @override
  void initState() {
    super.initState();
    _start = widget.startTime;
    _end = widget.endTime;
    _cascade = true;
    _allDays = widget.defaultApplyAllDays;
    final start = TimeUtils.tryParseMinutes(_start);
    final end = TimeUtils.tryParseMinutes(_end);
    _lessonMinutes = (start != null && end != null && end > start)
        ? end - start
        : AppConstants.defaultLessonMinutes;
  }

  /// 结束时间 = 开始时间 + 本节课堂时长。
  ///
  /// 封顶到 23:55：`formatMinutes` 是按 24 小时取模的，直接传 1440 会绕回
  /// "00:00"，那就变成「结束时间比开始时间还早」了。
  String _autoEndFrom(String start) {
    final total = (TimeUtils.tryParseMinutes(start) ?? 0) + _lessonMinutes;
    final capped = total >= TimeUtils.minutesPerDay
        ? TimeUtils.minutesPerDay - AppConstants.wheelSnapMinutes
        : total;
    return TimeUtils.formatMinutes(capped);
  }

  Future<void> _pickStart() async {
    final picked = await showDialTimePicker(
      context,
      initialTime: _start,
      title: context.l10n.generateStartTime,
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() {
      _start = picked;
      // 默认路径：结束时间跟着开始时间自动走
      if (!_endManual) {
        _end = _autoEndFrom(picked);
      }
    });
  }

  Future<void> _pickEnd() async {
    final picked = await showDialTimePicker(
      context,
      initialTime: _end,
      title: context.l10n.periodCustomEnd,
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() {
      _endManual = true;
      _end = picked;
    });
  }

  void _resetEndToAuto() {
    AppMotion.tap();
    setState(() {
      _endManual = false;
      _end = _autoEndFrom(_start);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final invalid =
        TimeUtils.parseMinutes(_end) <= TimeUtils.parseMinutes(_start);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppConstants.spaceL,
          AppConstants.spaceL,
          AppConstants.spaceL,
          AppConstants.spaceL,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              '${l10n.editPeriodTime} · ${l10n.periodIndexLabel(widget.periodIndex)}',
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppConstants.spaceXs),
            Text(
              l10n.editPeriodTimeDesc,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: AppConstants.spaceL),
            Row(
              children: <Widget>[
                Expanded(
                  child: _TimeField(
                    label: l10n.generateStartTime,
                    value: _start,
                    onTap: _pickStart,
                  ),
                ),
                const SizedBox(width: AppConstants.spaceM),
                Expanded(
                  child: _TimeField(
                    label: l10n.periodEnd,
                    value: _end,
                    badge: _endManual
                        ? l10n.periodCustomEnd
                        : l10n.periodAutoEndBadge,
                    locked: !_endManual,
                    onTap: _pickEnd,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppConstants.spaceS),
            Row(
              children: <Widget>[
                Icon(
                  Icons.auto_awesome_outlined,
                  size: 15,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${l10n.periodDurationMinutes(_lessonMinutes)}'
                    ' · ${l10n.periodAutoEndHint}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                if (_endManual)
                  TextButton(
                    onPressed: _resetEndToAuto,
                    child: Text(l10n.periodRestoreAuto),
                  ),
              ],
            ),
            if (invalid)
              Padding(
                padding: const EdgeInsets.only(top: AppConstants.spaceS),
                child: Text(
                  l10n.periodErrorEndBeforeStart,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.error,
                  ),
                ),
              ),
            const SizedBox(height: AppConstants.spaceM),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.cascadeFollowing),
              value: _cascade,
              onChanged: (value) => setState(() => _cascade = value),
            ),
            if (widget.availableWeekdays.length > 1)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.generateWeekdays),
                subtitle: Text(
                  widget.availableWeekdays.map(context.l10n.weekdayShort).join('、'),
                  style: theme.textTheme.labelSmall,
                ),
                value: _allDays,
                onChanged: (value) => setState(() => _allDays = value),
              ),
            const SizedBox(height: AppConstants.spaceM),
            FilledButton(
              onPressed: invalid
                  ? null
                  : () {
                      AppMotion.confirm();
                      Navigator.of(context).pop((
                        start: _start,
                        end: _end,
                        cascade: _cascade,
                        allDays: _allDays,
                      ));
                    },
              child: Text(l10n.save),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.cancel),
            ),
          ],
        ),
      ),
    );
  }

}

/// 可点击的时间字段（点开机械表盘）。
///
/// [badge] 在右上角标出这一栏的来路（自动 / 自定义）；
/// [locked] 为真时用低调配色表示「这个是算出来的，不是手填的」，
/// 但**仍然可点**——想让结束时间脱离自动，点它一下就切到手动选时间。
class _TimeField extends StatelessWidget {
  const _TimeField({
    required this.label,
    required this.value,
    required this.onTap,
    this.badge,
    this.locked = false,
  });

  final String label;
  final String value;
  final VoidCallback onTap;
  final String? badge;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(label, style: theme.textTheme.labelMedium),
            ),
            if (badge != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: scheme.secondaryContainer.withValues(alpha: 0.75),
                  borderRadius: AppRadii.stadiumAll,
                ),
                child: Text(
                  badge!,
                  maxLines: 1,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSecondaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: AppConstants.spaceXs),
        InkWell(
          borderRadius: AppRadii.tileAll,
          onTap: () {
            AppMotion.tap();
            onTap();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppConstants.spaceM,
              vertical: AppConstants.spaceM,
            ),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: AppRadii.tileAll,
              border: Border.all(
                color: locked
                    ? scheme.outlineVariant.withValues(alpha: 0.8)
                    : scheme.primary.withValues(alpha: 0.5),
                width: locked ? 1 : 1.4,
              ),
            ),
            child: Row(
              children: <Widget>[
                Icon(
                  locked ? Icons.auto_awesome_outlined : Icons.schedule_outlined,
                  size: 17,
                  color: locked ? scheme.onSurfaceVariant : scheme.primary,
                ),
                const SizedBox(width: AppConstants.spaceS),
                Expanded(
                  child: Text(
                    value,
                    maxLines: 1,
                    softWrap: false,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                      color: locked ? scheme.onSurfaceVariant : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// 数值步进器（时长 / 间隔 / 节数）。
class _NumberStepper extends StatelessWidget {
  const _NumberStepper({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final int step;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(label, style: theme.textTheme.bodyMedium),
          ),
          _circleButton(
            context,
            icon: Icons.remove,
            enabled: value - step >= min,
            onTap: () {
              AppMotion.select();
              onChanged((value - step).clamp(min, max));
            },
          ),
          SizedBox(
            width: 46,
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: scheme.primary,
              ),
            ),
          ),
          _circleButton(
            context,
            icon: Icons.add,
            enabled: value + step <= max,
            onTap: () {
              AppMotion.select();
              onChanged((value + step).clamp(min, max));
            },
          ),
        ],
      ),
    );
  }

  Widget _circleButton(
    BuildContext context, {
    required IconData icon,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: enabled
          ? scheme.secondaryContainer.withValues(alpha: 0.75)
          : scheme.surfaceContainerHigh,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: enabled ? onTap : null,
        child: SizedBox(
          width: 34,
          height: 34,
          child: Icon(
            icon,
            size: 17,
            color: enabled ? scheme.onSecondaryContainer : scheme.outline,
          ),
        ),
      ),
    );
  }
}
