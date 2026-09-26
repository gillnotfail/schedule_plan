import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:schedule_plan/core/constants/app_constants.dart';
import 'package:schedule_plan/core/l10n/l10n_extensions.dart';
import 'package:schedule_plan/core/logging/app_logger.dart';
import 'package:schedule_plan/core/theme/app_motion.dart';
import 'package:schedule_plan/core/theme/app_page_route.dart';
import 'package:schedule_plan/core/utils/color_utils.dart';
import 'package:schedule_plan/core/utils/pinyin_utils.dart';
import 'package:schedule_plan/core/widgets/app_card.dart';
import 'package:schedule_plan/core/widgets/app_snackbar.dart';
import 'package:schedule_plan/core/widgets/confirm_dialog.dart';
import 'package:schedule_plan/core/widgets/pulse_loading.dart';
import 'package:schedule_plan/core/widgets/settings_tile.dart';
import 'package:schedule_plan/data/models/class_course.dart';
import 'package:schedule_plan/data/models/schedule_template.dart';
import 'package:schedule_plan/data/models/student.dart';
import 'package:schedule_plan/data/repositories/class_repository.dart';
import 'package:schedule_plan/data/repositories/student_repository.dart';
import 'package:schedule_plan/data/repositories/template_repository.dart';
import 'package:schedule_plan/features/management/class_form_sheet.dart';
import 'package:schedule_plan/features/management/course_list_page.dart';
import 'package:schedule_plan/features/management/student_form_sheet.dart';
import 'package:schedule_plan/features/management/student_import_page.dart';
import 'package:schedule_plan/l10n/generated/app_localizations.dart';

/// 班级详情（用户规格）。
///
/// 「班级管理」是根据导入的学生名单**归集**出来的，点某个班就该进这个页面：
/// 上半部分是这个班的基本信息（多少人、班主任、男生女生各多少、用哪套作息），
/// 下半部分直接就是**这个班的学生名单**，可以随手增删改。
///
/// 学生名单既可以由 Excel 导入批量生成，也可以在这里一个个补；
/// 两种来源写的是同一张 student 表，不存在「导入的看不见」这种情况。
class ClassDetailPage extends StatefulWidget {
  const ClassDetailPage({super.key, required this.classId});

  final int classId;

  @override
  State<ClassDetailPage> createState() => _ClassDetailPageState();
}

class _ClassDetailPageState extends State<ClassDetailPage> {
  late Future<_ClassDetailData> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() => _future = _load());
  }

  Future<_ClassDetailData> _load() async {
    // 仓储在 await 之前取好，避免跨异步间隙使用 context
    final classRepo = context.read<ClassRepository>();
    final studentRepo = context.read<StudentRepository>();
    final templateRepo = context.read<TemplateRepository>();

    final info = await classRepo.getClass(widget.classId);
    final students = await studentRepo.listByClass(widget.classId);
    final classes = await classRepo.listClasses();
    final templates = await templateRepo.listTemplates();
    final defaultTemplateId = templates.isEmpty
        ? null
        : templates
            .firstWhere(
              (item) => item.isDefault,
              orElse: () => templates.first,
            )
            .id;

    // 学生按拼音排序，和考勤页保持一致的口径
    students.sort((a, b) => PinyinUtils.compareByName(a.name, b.name));

    return _ClassDetailData(
      info: info,
      students: students,
      classes: classes,
      templates: templates,
      defaultTemplateId: defaultTemplateId,
    );
  }

  Future<void> _editClass(_ClassDetailData data) async {
    final info = data.info;
    if (info == null) {
      return;
    }
    final result = await showClassFormSheet(
      context,
      existing: info,
      templates: data.templates,
      defaultTemplateId: data.defaultTemplateId,
    );
    if (result == null || !mounted) {
      return;
    }
    try {
      await context.read<ClassRepository>().updateClass(result);
      if (!mounted) {
        return;
      }
      showAppSnackBar(context, context.l10n.classSaved);
      _reload();
    } catch (error, stack) {
      AppLogger.e('保存班级失败', error: error, stack: stack);
      if (!mounted) {
        return;
      }
      showAppSnackBar(context, context.l10n.operationFailed('$error'));
    }
  }

  Future<void> _editStudent(_ClassDetailData data, {Student? existing}) async {
    if (data.classes.isEmpty) {
      showAppSnackBar(context, context.l10n.classManagementDesc);
      return;
    }
    final result = await showStudentFormSheet(
      context,
      classes: data.classes,
      existing: existing,
      defaultClassId: widget.classId,
    );
    if (result == null || !mounted) {
      return;
    }
    try {
      final repo = context.read<StudentRepository>();
      if (existing == null) {
        await repo.createStudent(result);
      } else {
        await repo.updateStudent(result);
      }
      if (!mounted) {
        return;
      }
      showAppSnackBar(context, context.l10n.studentSaved);
      _reload();
    } catch (error, stack) {
      AppLogger.e('保存学生失败', error: error, stack: stack);
      if (!mounted) {
        return;
      }
      showAppSnackBar(context, context.l10n.operationFailed('$error'));
    }
  }

  Future<void> _deleteStudent(Student student) async {
    final l10n = context.l10n;
    final repo = context.read<StudentRepository>();
    final confirmed = await showAppConfirm(
      context: context,
      title: l10n.deleteStudent,
      body: l10n.deleteStudentConfirmBody,
      danger: true,
    );
    if (!confirmed) {
      return;
    }
    try {
      await repo.deleteStudent(student.id!);
      if (!mounted) {
        return;
      }
      _reload();
    } catch (error, stack) {
      AppLogger.e('删除学生失败', error: error, stack: stack);
      if (!mounted) {
        return;
      }
      showAppSnackBar(context, l10n.operationFailed('$error'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return FutureBuilder<_ClassDetailData>(
      future: _future,
      builder: (context, snapshot) {
        final data = snapshot.data;
        final info = data?.info;
        final title = info == null
            ? l10n.classDetailTitle
            : '${info.name} · ${l10n.classDetailTitle}';
        return Scaffold(
          appBar: AppBar(
            title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
            actions: <Widget>[
              IconButton(
                tooltip: l10n.edit,
                icon: const Icon(Icons.edit_outlined),
                onPressed: data == null ? null : () => _editClass(data),
              ),
            ],
          ),
          floatingActionButton: data == null
              ? null
              : FloatingActionButton.extended(
                  onPressed: () {
                    AppMotion.tap();
                    _editStudent(data);
                  },
                  icon: const Icon(Icons.person_add_alt_1_outlined),
                  label: Text(l10n.addStudent),
                ),
          body: _buildBody(l10n, snapshot),
        );
      },
    );
  }

  Widget _buildBody(
    AppLocalizations l10n,
    AsyncSnapshot<_ClassDetailData> snapshot,
  ) {
    if (snapshot.connectionState == ConnectionState.waiting &&
        !snapshot.hasData) {
      return PulseLoading(message: l10n.loading);
    }
    final data = snapshot.data;
    if (data == null || data.info == null) {
      return Center(child: Text(l10n.noData));
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.spaceL,
        AppConstants.spaceL,
        AppConstants.spaceL,
        AppConstants.spaceL * 4,
      ),
      children: <Widget>[
        _ClassHeader(data: data),
        const SizedBox(height: AppConstants.spaceM),
        _buildStats(data),
        const SizedBox(height: AppConstants.spaceM),
        SettingsGroup(
          children: <Widget>[
            SettingsTile(
              icon: Icons.menu_book_outlined,
              title: l10n.classDetailCourses,
              subtitle: l10n.classDetailCoursesDesc,
              gradient: const <Color>[Color(0xFFFFA94D), Color(0xFFE8710A)],
              onTap: () async {
                await pushAppPage<void>(
                  context,
                  CourseListPage(
                    classId: widget.classId,
                    className: data.info!.name,
                  ),
                );
                _reload();
              },
            ),
            SettingsTile(
              icon: Icons.upload_file_outlined,
              title: l10n.importStudents,
              subtitle: l10n.importFormatLine4,
              gradient: const <Color>[Color(0xFF81C784), Color(0xFF2E7D32)],
              onTap: () async {
                await pushAppPage<void>(context, const StudentImportPage());
                _reload();
              },
            ),
          ],
        ),
        const SizedBox(height: AppConstants.spaceL),
        _buildRosterHeader(l10n),
        const SizedBox(height: AppConstants.spaceS),
        if (data.students.isEmpty)
          _buildEmptyRoster(l10n)
        else
          for (final student in data.students) _buildStudentRow(data, student),
      ],
    );
  }

  Widget _buildRosterHeader(AppLocalizations l10n) {
    return Row(
      children: <Widget>[
        Icon(
          Icons.people_outline,
          size: 17,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            l10n.classDetailStudents,
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
        Text(
          l10n.classDetailStudentsDesc,
          style: Theme.of(context).textTheme.labelSmall,
        ),
      ],
    );
  }

  Widget _buildEmptyRoster(AppLocalizations l10n) {
    return AppCard(
      padding: const EdgeInsets.all(AppConstants.spaceL),
      child: Column(
        children: <Widget>[
          Icon(
            Icons.person_search_outlined,
            size: 30,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: AppConstants.spaceS),
          Text(
            l10n.classDetailNoStudents,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: AppConstants.spaceXs),
          Text(
            l10n.rosterEmptyGuide,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelSmall,
          ),
          const SizedBox(height: AppConstants.spaceM),
          FilledButton.tonalIcon(
            onPressed: () async {
              await pushAppPage<void>(context, const StudentImportPage());
              _reload();
            },
            icon: const Icon(Icons.upload_file_outlined, size: 18),
            label: Text(l10n.goImportRoster),
          ),
        ],
      ),
    );
  }

  Widget _buildStudentRow(_ClassDetailData data, Student student) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final color = parseHexColor(data.info?.color, scheme.primary);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppConstants.spaceS),
      child: AppCard(
        padding: const EdgeInsets.symmetric(
          horizontal: AppConstants.spaceM,
          vertical: AppConstants.spaceS,
        ),
        onTap: () => _editStudent(data, existing: student),
        child: Row(
          children: <Widget>[
            StudentAvatar(name: student.name, color: color),
            const SizedBox(width: AppConstants.spaceM),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    student.name,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  Text(
                    <String>[
                      if (student.studentNo != null &&
                          student.studentNo!.isNotEmpty)
                        '${l10n.studentNo} ${student.studentNo}',
                      switch (student.gender) {
                        StudentGender.male => l10n.genderMale,
                        StudentGender.female => l10n.genderFemale,
                        null => l10n.genderUnset,
                      },
                    ].join(' · '),
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: l10n.delete,
              icon: const Icon(Icons.delete_outline, size: 20),
              onPressed: () => _deleteStudent(student),
            ),
          ],
        ),
      ),
    );
  }

  /// 人数与男女构成：导入完最想看的就是这几个数字。
  Widget _buildStats(_ClassDetailData data) {
    final l10n = context.l10n;
    final stats = ClassRosterStats.of(data.students);
    return Row(
      children: <Widget>[
        Expanded(
          child: _StatTile(
            label: l10n.classStatStudents,
            value: '${stats.total}',
            icon: Icons.groups_2_outlined,
          ),
        ),
        const SizedBox(width: AppConstants.spaceS),
        Expanded(
          child: _StatTile(
            label: l10n.classStatMale,
            value: '${stats.male}',
            icon: Icons.male_rounded,
          ),
        ),
        const SizedBox(width: AppConstants.spaceS),
        Expanded(
          child: _StatTile(
            label: l10n.classStatFemale,
            value: '${stats.female}',
            icon: Icons.female_rounded,
          ),
        ),
        if (stats.unset > 0) ...<Widget>[
          const SizedBox(width: AppConstants.spaceS),
          Expanded(
            child: _StatTile(
              label: l10n.classStatUnset,
              value: '${stats.unset}',
              icon: Icons.help_outline_rounded,
            ),
          ),
        ],
      ],
    );
  }
}

/// 班级抬头卡：名称 + 年级 + 班主任 + 绑定作息。
class _ClassHeader extends StatelessWidget {
  const _ClassHeader({required this.data});

  final _ClassDetailData data;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final info = data.info!;
    final color = parseHexColor(info.color, scheme.primary);
    final teacher = (info.headTeacher ?? '').trim();
    return AppCard(
      padding: const EdgeInsets.all(AppConstants.spaceL),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.16),
                  borderRadius: AppRadii.innerAll,
                ),
                child: Icon(Icons.school_outlined, color: color, size: 22),
              ),
              const SizedBox(width: AppConstants.spaceM),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      info.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                    Text(
                      info.grade,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppConstants.spaceM),
          _InfoLine(
            icon: Icons.person_outline,
            label: l10n.headTeacher,
            value: teacher.isEmpty ? l10n.teacherUnset : teacher,
          ),
          const SizedBox(height: AppConstants.spaceXs),
          _InfoLine(
            icon: Icons.schedule_outlined,
            label: l10n.templateBinding,
            value: data.templateName,
          ),
        ],
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      children: <Widget>[
        Icon(icon, size: 15, color: scheme.onSurfaceVariant),
        const SizedBox(width: 6),
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: AppConstants.spaceS),
        Expanded(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.spaceS,
        vertical: AppConstants.spaceM,
      ),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: AppRadii.tileAll,
      ),
      child: Column(
        children: <Widget>[
          Icon(icon, size: 17, color: scheme.primary),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            softWrap: false,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: scheme.primary,
              letterSpacing: -0.5,
            ),
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall,
          ),
        ],
      ),
    );
  }
}

/// 班级人数与男女构成。
///
/// 抽成纯函数是为了能直接单测：这几个数字是「导入完到底进没进对」的第一眼证据，
/// 算错了比页面画错更严重。
@immutable
class ClassRosterStats {
  const ClassRosterStats({
    required this.total,
    required this.male,
    required this.female,
    required this.unset,
  });

  factory ClassRosterStats.of(List<Student> students) {
    var male = 0;
    var female = 0;
    for (final student in students) {
      switch (student.gender) {
        case StudentGender.male:
          male++;
        case StudentGender.female:
          female++;
        case null:
          break;
      }
    }
    return ClassRosterStats(
      total: students.length,
      male: male,
      female: female,
      unset: students.length - male - female,
    );
  }

  final int total;
  final int male;
  final int female;

  /// 没填性别的（导入的表格里这一列常留空）
  final int unset;
}

class _ClassDetailData {
  const _ClassDetailData({
    required this.info,
    required this.students,
    required this.classes,
    required this.templates,
    required this.defaultTemplateId,
  });

  final ClassInfo? info;
  final List<Student> students;
  final List<ClassInfo> classes;
  final List<ScheduleTemplate> templates;
  final int? defaultTemplateId;

  /// 这个班绑定的作息名称。
  String get templateName {
    final id = info?.templateId;
    if (id == null) {
      return '';
    }
    for (final template in templates) {
      if (template.id == id) {
        return template.name;
      }
    }
    return '';
  }
}
