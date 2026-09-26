import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:schedule_plan/core/constants/app_constants.dart';
import 'package:schedule_plan/core/error/app_exceptions.dart';
import 'package:schedule_plan/core/l10n/l10n_extensions.dart';
import 'package:schedule_plan/core/logging/app_logger.dart';
import 'package:schedule_plan/core/widgets/app_card.dart';
import 'package:schedule_plan/core/widgets/app_snackbar.dart';
import 'package:schedule_plan/core/widgets/pulse_loading.dart';
import 'package:schedule_plan/core/widgets/wheel_time_picker.dart';
import 'package:schedule_plan/data/models/schedule_template.dart';
import 'package:schedule_plan/data/repositories/template_repository.dart';
import 'package:schedule_plan/data/validators/template_period_validator.dart';

/// 作息模板编辑页（模块一 1.2）。
///
/// 以「周一~周日」横向 Tab 切换，每个 Tab 内是可增删行的节次列表；
/// 保存前执行节次校验，校验失败在**对应行内联提示**具体原因。
class TemplateEditorPage extends StatefulWidget {
  const TemplateEditorPage({super.key, this.templateId});

  /// 为空表示新建模板。
  final int? templateId;

  @override
  State<TemplateEditorPage> createState() => _TemplateEditorPageState();
}

class _TemplateEditorPageState extends State<TemplateEditorPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _nameController = TextEditingController();
  final Map<int, List<TemplatePeriod>> _draft = <int, List<TemplatePeriod>>{};
  Map<int, List<PeriodIssue>> _issues = <int, List<PeriodIssue>>{};
  String? _nameError;
  bool _loading = true;
  bool _saving = false;
  int _boundClassCount = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: AppConstants.weekdayCount, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final repository = context.read<TemplateRepository>();
    if (widget.templateId == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final template = await repository.getTemplate(widget.templateId!);
      final periods = await repository.allPeriods(widget.templateId!);
      _nameController.text = template?.name ?? '';
      for (final period in periods) {
        _draft.putIfAbsent(period.weekday, () => <TemplatePeriod>[]).add(period);
      }
      _boundClassCount = await repository.countBoundClasses(widget.templateId!);
    } catch (error, stack) {
      AppLogger.e('加载作息模板失败', error: error, stack: stack);
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  List<TemplatePeriod> get _currentPeriods =>
      _draft[_tabController.index + 1] ?? <TemplatePeriod>[];

  void _updateCurrent(List<TemplatePeriod> next) {
    setState(() => _draft[_tabController.index + 1] = next);
  }

  void _addPeriod() {
    final list = [..._currentPeriods];
    final last = list.isEmpty ? null : list.last;
    final startMinutes = last?.endMinutes ?? 8 * 60;
    final endMinutes = (startMinutes + 45).clamp(0, 23 * 60 + 59);
    list.add(
      TemplatePeriod(
        templateId: widget.templateId ?? 0,
        weekday: _tabController.index + 1,
        periodIndex: list.length + 1,
        startTime: _format(startMinutes),
        endTime: _format(endMinutes),
      ),
    );
    _updateCurrent(list);
  }

  void _removePeriod(int index) {
    final list = [..._currentPeriods]..removeAt(index);
    // 节次序号自动重排：增删行后自动重排，不允许出现空洞
    _updateCurrent(_renumber(list));
  }

  List<TemplatePeriod> _renumber(List<TemplatePeriod> list) {
    final result = <TemplatePeriod>[];
    for (var i = 0; i < list.length; i++) {
      result.add(list[i].copyWith(periodIndex: i + 1));
    }
    return result;
  }

  String _format(int minutes) {
    final hour = (minutes ~/ 60).toString().padLeft(2, '0');
    final minute = (minutes % 60).toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  Future<void> _pickTime(int index, bool isStart) async {
    final period = _currentPeriods[index];
    final picked = await showWheelTimePicker(
      context,
      initialTime: isStart ? period.startTime : period.endTime,
      title: isStart ? context.l10n.periodStart : context.l10n.periodEnd,
    );
    if (picked == null) {
      return;
    }
    final list = [..._currentPeriods];
    list[index] = isStart
        ? period.copyWith(startTime: picked)
        : period.copyWith(endTime: picked);
    _updateCurrent(list);
  }

  Future<void> _copyToOtherDays() async {
    final l10n = context.l10n;
    final from = _tabController.index + 1;
    final targets = <int>{};
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: const EdgeInsets.all(AppConstants.spaceL),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(l10n.copyToTargets,
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: AppConstants.spaceM),
                  Wrap(
                    spacing: AppConstants.spaceS,
                    children: <Widget>[
                      for (var weekday = 1;
                          weekday <= AppConstants.weekdayCount;
                          weekday++)
                        FilterChip(
                          label: Text(context.l10n.weekdayShort(weekday)),
                          selected: targets.contains(weekday),
                          onSelected: weekday == from
                              ? null
                              : (selected) => setSheetState(() {
                                    if (selected) {
                                      targets.add(weekday);
                                    } else {
                                      targets.remove(weekday);
                                    }
                                  }),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppConstants.spaceL),
                  FilledButton(
                    onPressed: () => Navigator.of(sheetContext).pop(true),
                    child: Text(l10n.confirm),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    if (confirmed != true ||
        targets.isEmpty ||
        widget.templateId == null ||
        !mounted) {
      return;
    }
    try {
      await context.read<TemplateRepository>().copyWeekdayTo(
            widget.templateId!,
            fromWeekday: from,
            targetWeekdays: targets.toList(),
          );
      if (!mounted) {
        return;
      }
      showAppSnackBar(context, l10n.copyDone);
      await _reloadPeriods();
    } catch (error, stack) {
      AppLogger.e('复制作息节次失败', error: error, stack: stack);
      if (!mounted) {
        return;
      }
      showAppSnackBar(context, l10n.operationFailed('$error'));
    }
  }

  Future<void> _reloadPeriods() async {
    if (widget.templateId == null) {
      return;
    }
    final periods =
        await context.read<TemplateRepository>().allPeriods(widget.templateId!);
    if (!mounted) {
      return;
    }
    setState(() {
      _draft.clear();
      for (final period in periods) {
        _draft.putIfAbsent(period.weekday, () => <TemplatePeriod>[]).add(period);
      }
    });
  }

  Future<void> _save() async {
    final l10n = context.l10n;
    final repository = context.read<TemplateRepository>();
    final name = _nameController.text.trim();
    final issues = <int, List<PeriodIssue>>{};
    for (var weekday = 1; weekday <= AppConstants.weekdayCount; weekday++) {
      final periods = _draft[weekday] ?? const <TemplatePeriod>[];
      if (periods.isEmpty) {
        continue;
      }
      final result = TemplatePeriodValidator.validate(periods);
      if (result.isNotEmpty) {
        issues[weekday] = result;
      }
    }
    setState(() {
      _nameError = name.isEmpty ? l10n.templateNameRequired : null;
      _issues = issues;
    });
    if (name.isEmpty || issues.isNotEmpty) {
      if (issues.isNotEmpty) {
        _tabController.animateTo(issues.keys.first - 1);
      }
      return;
    }

    setState(() => _saving = true);
    try {
      final templateId = widget.templateId ?? await repository.createTemplate(name);
      if (widget.templateId != null) {
        await repository.renameTemplate(templateId, name);
      }
      for (var weekday = 1; weekday <= AppConstants.weekdayCount; weekday++) {
        final periods = _draft[weekday];
        if (periods == null || periods.isEmpty) {
          continue;
        }
        await repository.saveWeekdayPeriods(templateId, weekday, periods);
      }
      if (!mounted) {
        return;
      }
      showAppSnackBar(context, l10n.templateSaved);
      Navigator.of(context).pop(true);
    } on AppException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _saving = false);
      showAppSnackBar(context, error.message);
    } catch (error, stack) {
      AppLogger.e('保存作息模板失败', error: error, stack: stack);
      if (!mounted) {
        return;
      }
      setState(() => _saving = false);
      showAppSnackBar(context, l10n.unexpectedError);
    } finally {
      if (mounted && _saving) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.templateTitle)),
        body: PulseLoading(message: l10n.loading),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.templateId == null ? l10n.templateNew : l10n.templateTitle),
        actions: <Widget>[
          if (widget.templateId != null)
            IconButton(
              icon: const Icon(Icons.content_copy_outlined),
              tooltip: l10n.copyFromOtherDay,
              onPressed: _copyToOtherDays,
            ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(AppConstants.spaceL),
            child: TextField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: l10n.templateName,
                errorText: _nameError,
              ),
            ),
          ),
          if (_boundClassCount > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppConstants.spaceL),
              child: AppCard(
                color: Theme.of(context).colorScheme.primaryContainer,
                padding: const EdgeInsets.all(AppConstants.spaceM),
                child: Text(
                  l10n.templateEditAffectClasses(_boundClassCount),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
          TabBar(
            controller: _tabController,
            isScrollable: true,
            tabs: <Tab>[
              for (var weekday = 1; weekday <= AppConstants.weekdayCount; weekday++)
                Tab(text: context.l10n.weekdayShort(weekday)),
            ],
          ),
          Expanded(
            child: AnimatedBuilder(
              animation: _tabController,
              builder: (context, _) => _buildPeriodList(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppConstants.spaceL),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _addPeriod,
                    icon: const Icon(Icons.add),
                    label: Text(l10n.addPeriod),
                  ),
                ),
                const SizedBox(width: AppConstants.spaceM),
                Expanded(
                  child: FilledButton(
                    onPressed: _saving ? null : _save,
                    child: Text(_saving ? l10n.loading : l10n.save),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPeriodList() {
    final l10n = context.l10n;
    final periods = _currentPeriods;
    final issues = _issues[_tabController.index + 1] ?? const <PeriodIssue>[];
    if (periods.isEmpty) {
      return Center(child: Text(l10n.noData));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(AppConstants.spaceL),
      itemCount: periods.length,
      itemBuilder: (context, index) {
        final period = periods[index];
        final rowIssues = issues
            .where((issue) => issue.periodIndex == period.periodIndex)
            .toList();
        return Padding(
          padding: const EdgeInsets.only(bottom: AppConstants.spaceM),
          child: AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Text(l10n.periodIndexLabel(period.periodIndex)),
                    const SizedBox(width: AppConstants.spaceM),
                    Expanded(
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<PeriodType>(
                          isExpanded: true,
                          value: period.periodType,
                          items: <DropdownMenuItem<PeriodType>>[
                            for (final type in PeriodType.values)
                              DropdownMenuItem<PeriodType>(
                                value: type,
                                child: Text(_typeLabel(type)),
                              ),
                          ],
                          onChanged: (type) {
                            if (type == null) {
                              return;
                            }
                            final list = [..._currentPeriods];
                            list[index] = period.copyWith(periodType: type);
                            _updateCurrent(list);
                          },
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      tooltip: l10n.removePeriod,
                      onPressed: () => _removePeriod(index),
                    ),
                  ],
                ),
                const SizedBox(height: AppConstants.spaceS),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _pickTime(index, true),
                        child: Text(period.startTime),
                      ),
                    ),
                    const SizedBox(width: AppConstants.spaceS),
                    const Icon(Icons.arrow_forward, size: 16),
                    const SizedBox(width: AppConstants.spaceS),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _pickTime(index, false),
                        child: Text(period.endTime),
                      ),
                    ),
                  ],
                ),
                // 校验错误内联提示在对应行下方（规范 11）
                for (final issue in rowIssues) ...<Widget>[
                  const SizedBox(height: AppConstants.spaceS),
                  Text(
                    _issueText(issue.type),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  String _issueText(PeriodIssueType type) {
    final l10n = context.l10n;
    return switch (type) {
      PeriodIssueType.invalidFormat => l10n.periodErrorInvalidFormat,
      PeriodIssueType.endBeforeStart => l10n.periodErrorEndBeforeStart,
      PeriodIssueType.overlap => l10n.periodErrorOverlap,
      PeriodIssueType.notAscending => l10n.periodErrorNotAscending,
    };
  }

  String _typeLabel(PeriodType type) {
    final l10n = context.l10n;
    return switch (type) {
      PeriodType.normal => l10n.periodTypeNormal,
      PeriodType.lunchBreak => l10n.periodTypeLunch,
      PeriodType.recess => l10n.periodTypeRecess,
      PeriodType.selfStudy => l10n.periodTypeSelfStudy,
      PeriodType.other => l10n.periodTypeOther,
    };
  }

}
