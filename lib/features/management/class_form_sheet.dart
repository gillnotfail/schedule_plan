import 'package:flutter/material.dart';

import 'package:schedule_plan/core/constants/app_constants.dart';
import 'package:schedule_plan/core/l10n/l10n_extensions.dart';
import 'package:schedule_plan/core/widgets/app_card.dart';
import 'package:schedule_plan/data/models/class_course.dart';
import 'package:schedule_plan/data/models/schedule_template.dart';

/// 班级表单弹层（模块一 1.3 + 用户规格）。
///
/// 班级信息既可以由 Excel 导入自动建档，也可以手工新增 / 修改；
/// 表单里绑定作息模板，因为「这节课几点上」最终由模板决定。
///
/// 返回填好的 [ClassInfo]；取消返回 null。
Future<ClassInfo?> showClassFormSheet(
  BuildContext context, {
  ClassInfo? existing,
  required List<ScheduleTemplate> templates,
  int? defaultTemplateId,
}) {
  if (templates.isEmpty) {
    return Future<ClassInfo?>.value();
  }
  return showModalBottomSheet<ClassInfo>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: RoundedRectangleBorder(borderRadius: AppRadii.sheetTop),
    builder: (_) => _ClassForm(
      existing: existing,
      templates: templates,
      defaultTemplateId: defaultTemplateId,
    ),
  );
}

/// 班级配色候选（导入时按顺序取用，手工新建时供挑选）。
///
/// 用户规格（第 10 轮）："目前能选的课程颜色太少了。最好再多一点，至少10个色。"
/// 课程新建表单与班级新建表单共用这份调色板，扩到 14 个色（环形色相尽量拉开）。
const List<String> kClassPalette = <String>[
  'FF26A69A',
  'FF5C6BC0',
  'FFEF6C00',
  'FF8E24AA',
  'FF0288D1',
  'FF43A047',
  'FFE53935',
  'FF795548',
  'FFEC407A',
  'FF7CB342',
  'FF29B6F6',
  'FFFF7043',
  'FF5E35B1',
  'FF00897B',
];

class _ClassForm extends StatefulWidget {
  const _ClassForm({
    this.existing,
    required this.templates,
    required this.defaultTemplateId,
  });

  final ClassInfo? existing;
  final List<ScheduleTemplate> templates;
  final int? defaultTemplateId;

  @override
  State<_ClassForm> createState() => _ClassFormState();
}

class _ClassFormState extends State<_ClassForm> {
  late final TextEditingController _name;
  late final TextEditingController _grade;
  late final TextEditingController _headTeacher;
  late String _color;
  int? _templateId;
  String? _nameError;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _name = TextEditingController(text: existing?.name ?? '');
    _grade = TextEditingController(text: existing?.grade ?? '');
    _headTeacher = TextEditingController(text: existing?.headTeacher ?? '');
    _color = existing?.color ?? kClassPalette.first;
    // 新建时默认预选当前的默认模板（模块一 1.3）
    _templateId = existing?.templateId ?? widget.defaultTemplateId;
  }

  @override
  void dispose() {
    _name.dispose();
    _grade.dispose();
    _headTeacher.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppConstants.spaceL,
          AppConstants.spaceL,
          AppConstants.spaceL,
          AppConstants.spaceL + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: AppCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  widget.existing == null
                      ? l10n.classFormTitle
                      : '${l10n.edit}${l10n.classFormTitle}',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: AppConstants.spaceM),
                TextField(
                  controller: _name,
                  decoration: InputDecoration(
                    labelText: l10n.className,
                    errorText: _nameError,
                  ),
                ),
                const SizedBox(height: AppConstants.spaceM),
                TextField(
                  controller: _grade,
                  decoration: InputDecoration(labelText: l10n.gradeName),
                ),
                const SizedBox(height: AppConstants.spaceM),
                TextField(
                  controller: _headTeacher,
                  decoration: InputDecoration(labelText: l10n.headTeacher),
                ),
                const SizedBox(height: AppConstants.spaceM),
                DropdownButtonFormField<int>(
                  initialValue: _templateId,
                  decoration: InputDecoration(labelText: l10n.templateBinding),
                  items: <DropdownMenuItem<int>>[
                    for (final template in widget.templates)
                      if (template.id != null)
                        DropdownMenuItem<int>(
                          value: template.id,
                          child: Text(template.name),
                        ),
                  ],
                  onChanged: (value) => setState(() => _templateId = value),
                ),
                const SizedBox(height: AppConstants.spaceM),
                Text(l10n.pickColor),
                const SizedBox(height: AppConstants.spaceS),
                Wrap(
                  spacing: AppConstants.spaceS,
                  children: <Widget>[
                    for (final color in kClassPalette)
                      ChoiceChip(
                        label: const SizedBox(width: 24, height: 12),
                        selected: _color == color,
                        backgroundColor: Color(int.parse(color, radix: 16)),
                        selectedColor: Color(int.parse(color, radix: 16)),
                        onSelected: (_) => setState(() => _color = color),
                      ),
                  ],
                ),
                const SizedBox(height: AppConstants.spaceL),
                FilledButton(
                  onPressed: () {
                    if (_name.text.trim().isEmpty) {
                      setState(() => _nameError = l10n.requiredField);
                      return;
                    }
                    if (_grade.text.trim().isEmpty || _templateId == null) {
                      return;
                    }
                    Navigator.of(context).pop(
                      (widget.existing ??
                              ClassInfo(
                                name: '',
                                grade: '',
                                color: _color,
                                templateId: _templateId!,
                              ))
                          .copyWith(
                        name: _name.text.trim(),
                        grade: _grade.text.trim(),
                        headTeacher: _headTeacher.text.trim().isEmpty
                            ? null
                            : _headTeacher.text.trim(),
                        color: _color,
                        templateId: _templateId,
                      ),
                    );
                  },
                  child: Text(l10n.save),
                ),
                const SizedBox(height: AppConstants.spaceS),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l10n.cancel),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
