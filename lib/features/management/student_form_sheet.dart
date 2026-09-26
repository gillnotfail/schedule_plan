import 'package:flutter/material.dart';

import 'package:schedule_plan/core/constants/app_constants.dart';
import 'package:schedule_plan/core/l10n/l10n_extensions.dart';
import 'package:schedule_plan/core/theme/app_motion.dart';
import 'package:schedule_plan/data/models/class_course.dart';
import 'package:schedule_plan/data/models/student.dart';

/// 学生表单弹层（用户规格）。
///
/// 字段口径：**姓名、班级必填；性别、学号选填**；
/// 班主任只读展示并取「所属班级」的值——不往 student 表加列，
/// 否则同一个班里会出现多个班主任的口径。
///
/// 返回填好的 [Student]；取消返回 null。
/// 抽成公共弹层的理由：学生名单页与班级详情页都要用同一份表单，
/// 复制两份迟早会漂。
Future<Student?> showStudentFormSheet(
  BuildContext context, {
  required List<ClassInfo> classes,
  Student? existing,
  int? defaultClassId,
}) {
  if (classes.isEmpty) {
    return Future<Student?>.value();
  }
  return showModalBottomSheet<Student>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: RoundedRectangleBorder(borderRadius: AppRadii.sheetTop),
    builder: (_) => _StudentForm(
      classes: classes,
      existing: existing,
      defaultClassId: defaultClassId,
    ),
  );
}

class _StudentForm extends StatefulWidget {
  const _StudentForm({
    required this.classes,
    required this.defaultClassId,
    this.existing,
  });

  final List<ClassInfo> classes;
  final int? defaultClassId;
  final Student? existing;

  @override
  State<_StudentForm> createState() => _StudentFormState();
}

class _StudentFormState extends State<_StudentForm> {
  late final TextEditingController _name;
  late final TextEditingController _no;
  late int _classId;
  StudentGender? _gender;
  String? _nameError;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.existing?.name ?? '');
    _no = TextEditingController(text: widget.existing?.studentNo ?? '');
    _gender = widget.existing?.gender;
    _classId = widget.existing?.classId ??
        widget.defaultClassId ??
        widget.classes.first.id!;
  }

  @override
  void dispose() {
    _name.dispose();
    _no.dispose();
    super.dispose();
  }

  void _submit() {
    final l10n = context.l10n;
    if (_name.text.trim().isEmpty) {
      setState(() => _nameError = l10n.requiredField);
      return;
    }
    final existing = widget.existing;
    final student = Student(
      id: existing?.id,
      name: _name.text.trim(),
      studentNo: _no.text.trim().isEmpty ? null : _no.text.trim(),
      gender: _gender,
      classId: _classId,
    );
    Navigator.of(context).pop(student);
  }

  /// 班主任取「所属班级」的值（用户规格：不往 student 表加列，
  /// 避免一个班里出现多个班主任的口径）。
  String _headTeacherOf(int classId) {
    final l10n = context.l10n;
    for (final item in widget.classes) {
      if (item.id == classId) {
        final name = (item.headTeacher ?? '').trim();
        return name.isEmpty ? l10n.teacherUnset : name;
      }
    }
    return l10n.teacherUnset;
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                l10n.studentFormTitle,
                style: theme.textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppConstants.spaceXs),
              Text(
                l10n.studentFormDesc,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: AppConstants.spaceL),
              TextField(
                controller: _name,
                decoration: InputDecoration(
                  labelText: l10n.studentNameRequired,
                  errorText: _nameError,
                  prefixIcon: const Icon(Icons.badge_outlined, size: 20),
                ),
              ),
              const SizedBox(height: AppConstants.spaceM),
              DropdownButtonFormField<int>(
                initialValue: _classId,
                decoration: InputDecoration(
                  labelText: l10n.studentClassRequired,
                  prefixIcon: const Icon(Icons.groups_outlined, size: 20),
                ),
                items: <DropdownMenuItem<int>>[
                  for (final item in widget.classes)
                    DropdownMenuItem<int>(
                      value: item.id,
                      child: Text(item.name),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _classId = value);
                  }
                },
              ),
              const SizedBox(height: AppConstants.spaceS),
              // 班主任：只读展示并取自「所属班级」
              Row(
                children: <Widget>[
                  Icon(
                    Icons.person_outline,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      l10n.classHeadTeacherFromClass,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Text(
                    _headTeacherOf(_classId),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppConstants.spaceM),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  l10n.studentGender,
                  style: theme.textTheme.labelLarge,
                ),
              ),
              const SizedBox(height: AppConstants.spaceXs),
              SegmentedButton<int>(
                segments: <ButtonSegment<int>>[
                  ButtonSegment<int>(value: 0, label: Text(l10n.genderUnset)),
                  ButtonSegment<int>(value: 1, label: Text(l10n.genderMale)),
                  ButtonSegment<int>(value: 2, label: Text(l10n.genderFemale)),
                ],
                selected: <int>{
                  switch (_gender) {
                    StudentGender.male => 1,
                    StudentGender.female => 2,
                    null => 0,
                  },
                },
                onSelectionChanged: (selection) {
                  AppMotion.select();
                  setState(() {
                    _gender = switch (selection.first) {
                      1 => StudentGender.male,
                      2 => StudentGender.female,
                      _ => null,
                    };
                  });
                },
              ),
              const SizedBox(height: AppConstants.spaceM),
              TextField(
                controller: _no,
                decoration: InputDecoration(
                  labelText: l10n.studentNoOptional,
                  prefixIcon: const Icon(Icons.numbers, size: 20),
                ),
              ),
              const SizedBox(height: AppConstants.spaceXl),
              FilledButton(
                onPressed: _submit,
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
    );
  }
}

/// 学生头像占位：取姓名首字，空名兜底成 `?`。
///
/// 传 [color]（班级色）时用淡色底 + 同色文字，既不刺眼又能一眼区分班级。
class StudentAvatar extends StatelessWidget {
  const StudentAvatar({super.key, required this.name, this.color});

  final String name;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = color;
    return Container(
      width: 38,
      height: 38,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: accent == null
            ? scheme.secondaryContainer.withValues(alpha: 0.7)
            : accent.withValues(alpha: 0.16),
        borderRadius: AppRadii.smallAll,
      ),
      child: Text(
        name.isEmpty ? '?' : name.substring(0, 1),
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w800,
          color: accent,
        ),
      ),
    );
  }
}
