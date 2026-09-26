import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:schedule_plan/core/constants/app_constants.dart';
import 'package:schedule_plan/core/error/app_exceptions.dart';
import 'package:schedule_plan/core/l10n/l10n_extensions.dart';
import 'package:schedule_plan/core/logging/app_logger.dart';
import 'package:schedule_plan/core/widgets/app_card.dart';
import 'package:schedule_plan/data/models/class_course.dart';
import 'package:schedule_plan/data/models/lesson.dart';
import 'package:schedule_plan/data/models/schedule_template.dart';
import 'package:schedule_plan/data/repositories/class_repository.dart';
import 'package:schedule_plan/data/repositories/course_repository.dart';
import 'package:schedule_plan/data/repositories/lesson_repository.dart';
import 'package:schedule_plan/data/repositories/template_repository.dart';

/// 一键新增课表（模块一 1.5）。
///
/// 底部半屏弹层（约占屏幕高度 60%，可上滑展开至 90%），
/// 内部以「Depth Stack 候选卡片」形式层层递进：
/// 选班级 -> 选课程 -> 选周几和节次，每层都可返回上一层重新选择。
Future<bool> showLessonQuickAddSheet(BuildContext context) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(AppConstants.radius),
      ),
    ),
    builder: (sheetContext) {
      return SizedBox(
        height: MediaQuery.of(sheetContext).size.height *
            AppConstants.bottomSheetExpandedFraction,
        child: DraggableScrollableSheet(
          initialChildSize: AppConstants.bottomSheetInitialFraction,
          minChildSize: 0.35,
          maxChildSize: AppConstants.bottomSheetExpandedFraction,
          expand: false,
          builder: (context, controller) {
            return _LessonQuickAddBody(scrollController: controller);
          },
        ),
      );
    },
  ).then((value) => value ?? false);
}

class _LessonQuickAddBody extends StatefulWidget {
  const _LessonQuickAddBody({required this.scrollController});

  final ScrollController scrollController;

  @override
  State<_LessonQuickAddBody> createState() => _LessonQuickAddBodyState();
}

class _LessonQuickAddBodyState extends State<_LessonQuickAddBody> {
  int _step = 0;
  ClassInfo? _classInfo;
  Course? _course;
  int _weekday = DateTime.now().weekday;
  int? _periodIndex;
  List<TemplatePeriod> _periods = <TemplatePeriod>[];
  String? _errorMessage;
  bool _saving = false;

  void _selectClass(ClassInfo info) async {
    final courses =
        await context.read<CourseRepository>().listCourses(classId: info.id);
    if (!mounted) {
      return;
    }
    setState(() {
      _classInfo = info;
      _step = 1;
    });
    _courses = courses;
  }

  List<Course> _courses = <Course>[];

  Future<void> _selectCourse(Course course) async {
    final periods = await context
        .read<TemplateRepository>()
        .periodsForWeekday(_classInfo!.templateId, _weekday);
    if (!mounted) {
      return;
    }
    setState(() {
      _course = course;
      _periods = periods;
      _periodIndex = periods.isEmpty ? null : periods.first.periodIndex;
      _step = 2;
    });
  }

  Future<void> _loadPeriods(int weekday) async {
    final periods = await context
        .read<TemplateRepository>()
        .periodsForWeekday(_classInfo!.templateId, weekday);
    if (!mounted) {
      return;
    }
    setState(() {
      _weekday = weekday;
      _periods = periods;
      _periodIndex = periods.isEmpty ? null : periods.first.periodIndex;
    });
  }

  Future<void> _save() async {
    final l10n = context.l10n;
    final selectedClass = _classInfo;
    final selectedCourse = _course;
    final periodIndex = _periodIndex;
    if (selectedClass == null || selectedCourse == null || periodIndex == null) {
      setState(() => _errorMessage = l10n.requiredField);
      return;
    }
    setState(() {
      _saving = true;
      _errorMessage = null;
    });
    try {
      await context.read<LessonRepository>().addLesson(
            Lesson(
              courseId: selectedCourse.id!,
              classId: selectedClass.id!,
              teacherId: AppConstants.currentTeacherId,
              weekday: _weekday,
              periodIndex: periodIndex,
            ),
          );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
    } on ConflictException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _saving = false;
        _errorMessage = error.message;
      });
    } on AppException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _saving = false;
        _errorMessage = error.message;
      });
    } catch (error, stack) {
      AppLogger.e('新增课表失败', error: error, stack: stack);
      if (!mounted) {
        return;
      }
      setState(() {
        _saving = false;
        _errorMessage = l10n.unexpectedError;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ListView(
      controller: widget.scrollController,
      padding: const EdgeInsets.all(AppConstants.spaceL),
      children: <Widget>[
        Row(
          children: <Widget>[
            if (_step > 0)
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() => _step = _step - 1),
              ),
            Expanded(
              child: Text(
                l10n.addLesson,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Text(
              '${_step + 1}/3',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        const SizedBox(height: AppConstants.spaceM),
        if (_step == 0) _buildClassStep(l10n.selectClass),
        if (_step == 1) _buildCourseStep(),
        if (_step == 2) _buildSlotStep(),
        if (_errorMessage != null) ...<Widget>[
          const SizedBox(height: AppConstants.spaceM),
          // 校验/冲突错误内联提示在对应字段下方，不用弹窗打断填写流程（规范 11）
          Text(
            _errorMessage!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: AppConstants.spaceL),
        if (_step == 2)
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? l10n.loading : l10n.save),
          ),
      ],
    );
  }

  Widget _buildClassStep(String title) {
    final repository = context.read<ClassRepository>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(title),
        const SizedBox(height: AppConstants.spaceM),
        FutureBuilder<List<ClassInfo>>(
          future: repository.listClasses(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const LinearProgressIndicator();
            }
            final classes = snapshot.data!;
            if (classes.isEmpty) {
              return Text(context.l10n.noData);
            }
            return Column(
              children: <Widget>[
                for (final item in classes)
                  AppCard(
                    onTap: () => _selectClass(item),
                    child: Row(
                      children: <Widget>[
                        Expanded(child: Text(item.name)),
                        Text(item.grade),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildCourseStep() {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(_classInfo?.name ?? ''),
        const SizedBox(height: AppConstants.spaceM),
        if (_courses.isEmpty)
          Text(context.l10n.noData, style: theme.textTheme.bodyMedium)
        else
          for (final course in _courses)
            AppCard(
              onTap: () => _selectCourse(course),
              child: Row(
                children: <Widget>[
                  Expanded(child: Text(course.name)),
                  Text(course.room ?? ''),
                ],
              ),
            ),
      ],
    );
  }

  Widget _buildSlotStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(_course?.name ?? ''),
        const SizedBox(height: AppConstants.spaceM),
        Wrap(
          spacing: AppConstants.spaceS,
          children: <Widget>[
            for (var weekday = 1; weekday <= AppConstants.weekdayCount; weekday++)
              ChoiceChip(
                label: Text(context.l10n.weekdayShort(weekday)),
                selected: _weekday == weekday,
                onSelected: (_) => _loadPeriods(weekday),
              ),
          ],
        ),
        const SizedBox(height: AppConstants.spaceM),
        if (_periods.isEmpty)
          Text(context.l10n.noTemplatePeriod)
        else
          Wrap(
            spacing: AppConstants.spaceS,
            children: <Widget>[
              for (final period in _periods)
                ChoiceChip(
                  label: Text(context.l10n.periodIndexLabel(period.periodIndex)),
                  selected: _periodIndex == period.periodIndex,
                  onSelected: (_) =>
                      setState(() => _periodIndex = period.periodIndex),
                ),
            ],
          ),
      ],
    );
  }

}
