import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:schedule_plan/core/constants/app_constants.dart';
import 'package:schedule_plan/core/l10n/l10n_extensions.dart';
import 'package:schedule_plan/core/logging/app_logger.dart';
import 'package:schedule_plan/core/theme/app_motion.dart';
import 'package:schedule_plan/core/utils/color_utils.dart';
import 'package:schedule_plan/core/theme/app_page_route.dart';
import 'package:schedule_plan/core/widgets/app_card.dart';
import 'package:schedule_plan/core/widgets/app_snackbar.dart';
import 'package:schedule_plan/core/widgets/confirm_dialog.dart';
import 'package:schedule_plan/core/widgets/pulse_loading.dart';
import 'package:schedule_plan/data/models/class_course.dart';
import 'package:schedule_plan/data/models/schedule_template.dart';
import 'package:schedule_plan/data/repositories/class_repository.dart';
import 'package:schedule_plan/data/repositories/template_repository.dart';
import 'package:schedule_plan/features/management/class_detail_page.dart';
import 'package:schedule_plan/features/management/class_form_sheet.dart';
import 'package:schedule_plan/features/management/student_list_page.dart';

/// 班级管理（模块六 6.4：支持多班级 + 拖拽调整展示顺序）。
///
/// 用户规格：班级是**按导入的学生名单归集**出来的（Excel 里出现过的班级自动建档），
/// 点某个班就进 [ClassDetailPage]——先看这个班的基本信息与人数构成，
/// 下面直接是这个班的学生名单。这里保留的是「批量视角」：排序、批量改作息、删除。
class ClassListPage extends StatefulWidget {
  const ClassListPage({super.key});

  @override
  State<ClassListPage> createState() => _ClassListPageState();
}

class _ClassListPageState extends State<ClassListPage> {
  late Future<_ClassPageData> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _future = _load();
    });
  }

  Future<_ClassPageData> _load() async {
    // 仓储在 await 之前取好，避免跨异步间隙使用 context
    final classRepo = context.read<ClassRepository>();
    final templateRepo = context.read<TemplateRepository>();
    final classes = await classRepo.listClasses();
    final templates = await templateRepo.listTemplates();
    final defaultTemplate = templates.firstWhere(
      (item) => item.isDefault,
      orElse: () => templates.isEmpty
          ? const ScheduleTemplate(
              name: '', createdAt: 0, updatedAt: 0)
          : templates.first,
    );
    final grades = await classRepo.listGrades();
    return _ClassPageData(
      classes: classes,
      templates: templates,
      defaultTemplateId: defaultTemplate.id,
      grades: grades,
    );
  }

  Future<void> _edit(ClassInfo? info, _ClassPageData data) async {
    final result = await showClassFormSheet(
      context,
      existing: info,
      templates: data.templates,
      defaultTemplateId: data.defaultTemplateId,
    );
    if (result == null || !mounted) {
      return;
    }
    final l10n = context.l10n;
    try {
      final repository = context.read<ClassRepository>();
      if (info == null) {
        final newId = await repository.createClass(result);
        if (!mounted) {
          return;
        }
        _reload();
        // 新班级一定是空名单：直接把老师送去加学生（用户规格）
        showAppSnackBar(
          context,
          l10n.classCreatedNextStep,
          long: true,
          onRetry: () => pushAppPage<void>(
            context,
            StudentListPage(classId: newId, className: result.name),
          ).then((_) => _reload()),
          retryLabel: l10n.goAddStudents,
        );
        return;
      }
      await repository.updateClass(result);
      if (!mounted) {
        return;
      }
      showAppSnackBar(context, l10n.classSaved);
      _reload();
    } catch (error, stack) {
      AppLogger.e('保存班级失败', error: error, stack: stack);
      if (!mounted) {
        return;
      }
      showAppSnackBar(context, l10n.operationFailed('$error'));
    }
  }

  /// 进班级详情：基本信息 + 男女构成 + 这个班的学生名单（用户规格）。
  Future<void> _openDetail(ClassInfo info) async {
    await pushAppPage<void>(context, ClassDetailPage(classId: info.id!));
    if (!mounted) {
      return;
    }
    _reload();
  }

  /// 删除班级。**涉及学生时必须二次确认**（用户规格），
  /// 并且要在确认文案里写清「这个班下还有多少人会被一起删掉」。
  Future<void> _delete(ClassInfo info) async {
    final l10n = context.l10n;
    final classRepo = context.read<ClassRepository>();
    final confirmed = await showAppConfirm(
      context: context,
      title: l10n.deleteClass,
      body: info.studentCount > 0
          ? l10n.classDeleteConfirmWithStudents(info.studentCount)
          : l10n.classDeleteConfirmBody,
      danger: true,
    );
    if (!confirmed) {
      return;
    }
    await classRepo.deleteClass(info.id!);
    _reload();
  }

  Future<void> _batchUpdateTemplate(_ClassPageData data) async {
    final l10n = context.l10n;
    if (data.grades.isEmpty) {
      return;
    }
    var grade = data.grades.first;
    var templateId = data.defaultTemplateId;
    final confirmed = await showAppSheet<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setSheetState) {
          final affected = data.classes
              .where((item) => item.grade == grade)
              .map((item) => item.name)
              .toList();
          return AppCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(l10n.batchUpdateTemplate,
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: AppConstants.spaceM),
                DropdownButtonFormField<String>(
                  initialValue: grade,
                  decoration: InputDecoration(labelText: l10n.gradeName),
                  items: <DropdownMenuItem<String>>[
                    for (final item in data.grades)
                      DropdownMenuItem<String>(value: item, child: Text(item)),
                  ],
                  onChanged: (value) =>
                      setSheetState(() => grade = value ?? grade),
                ),
                const SizedBox(height: AppConstants.spaceM),
                DropdownButtonFormField<int>(
                  initialValue: templateId,
                  decoration: InputDecoration(labelText: l10n.templateBinding),
                  items: <DropdownMenuItem<int>>[
                    for (final template in data.templates)
                      if (template.id != null)
                        DropdownMenuItem<int>(
                          value: template.id,
                          child: Text(template.name),
                        ),
                  ],
                  onChanged: (value) =>
                      setSheetState(() => templateId = value ?? templateId),
                ),
                const SizedBox(height: AppConstants.spaceM),
                // 操作前必须展示将被影响的班级清单并二次确认
                Text(l10n.batchUpdateTemplateConfirm(affected.join('、'))),
                const SizedBox(height: AppConstants.spaceL),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: Text(l10n.confirm),
                ),
              ],
            ),
          );
        },
      ),
    );
    if (confirmed != true || templateId == null || !mounted) {
      return;
    }
    await context
        .read<ClassRepository>()
        .updateTemplateForGrade(grade, templateId!);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.manageClasses),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.swap_vert),
            tooltip: l10n.batchUpdateTemplate,
            onPressed: () async {
              final data = await _future;
              await _batchUpdateTemplate(data);
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final data = await _future;
          await _edit(null, data);
        },
        child: const Icon(Icons.add),
      ),
      body: FutureBuilder<_ClassPageData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return PulseLoading(message: l10n.loading);
          }
          final data = snapshot.data;
          if (data == null || data.classes.isEmpty) {
            return Center(child: Text(l10n.noData));
          }
          final classes = [...data.classes];
          return ReorderableListView.builder(
            padding: const EdgeInsets.all(AppConstants.spaceL),
            header: Padding(
              padding: const EdgeInsets.only(bottom: AppConstants.spaceM),
              child: Row(
                children: <Widget>[
                  Icon(
                    Icons.info_outline,
                    size: 15,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          l10n.classManagementDesc,
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                        Text(
                          l10n.classDetailTapHint,
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            itemCount: classes.length,
            onReorder: (oldIndex, newIndex) async {
              if (newIndex > oldIndex) {
                newIndex -= 1;
              }
              final item = classes.removeAt(oldIndex);
              classes.insert(newIndex, item);
              // 拖拽排序结果本地持久化
              await context
                  .read<ClassRepository>()
                  .reorderClasses(classes.map((e) => e.id!).toList());
              _reload();
            },
            itemBuilder: (context, index) {
              final item = classes[index];
              final teacher = (item.headTeacher ?? '').trim();
              final subtitle = <String>[
                item.grade,
                l10n.studentCountLabel(item.studentCount),
                if (teacher.isNotEmpty) '${l10n.headTeacher} $teacher',
              ].join(' · ');
              return Padding(
                key: ValueKey<int>(item.id!),
                padding: const EdgeInsets.only(bottom: AppConstants.spaceM),
                child: AppCard(
                  onTap: () {
                    AppMotion.tap();
                    _openDetail(item);
                  },
                  child: Row(
                    children: <Widget>[
                      Container(
                        width: 12,
                        height: 40,
                        decoration: BoxDecoration(
                          color: parseHexColor(
                            item.color,
                            Theme.of(context).colorScheme.primary,
                          ),
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      const SizedBox(width: AppConstants.spaceM),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              item.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyLarge
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            Text(
                              subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 20,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                      PopupMenuButton<String>(
                        tooltip: l10n.edit,
                        icon: const Icon(Icons.more_vert, size: 20),
                        onSelected: (value) {
                          if (value == 'edit') {
                            _edit(item, data);
                          } else {
                            _delete(item);
                          }
                        },
                        itemBuilder: (context) => <PopupMenuEntry<String>>[
                          PopupMenuItem<String>(
                            value: 'edit',
                            child: ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.edit_outlined, size: 18),
                              title: Text(l10n.edit),
                            ),
                          ),
                          PopupMenuItem<String>(
                            value: 'delete',
                            child: ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(
                                Icons.delete_outline,
                                size: 18,
                                color: Theme.of(context).colorScheme.error,
                              ),
                              title: Text(
                                l10n.delete,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _ClassPageData {
  const _ClassPageData({
    required this.classes,
    required this.templates,
    required this.defaultTemplateId,
    required this.grades,
  });

  final List<ClassInfo> classes;
  final List<ScheduleTemplate> templates;
  final int? defaultTemplateId;
  final List<String> grades;
}
