import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:schedule_plan/core/constants/app_constants.dart';
import 'package:schedule_plan/core/l10n/l10n_extensions.dart';
import 'package:schedule_plan/core/logging/app_logger.dart';
import 'package:schedule_plan/core/theme/app_motion.dart';
import 'package:schedule_plan/core/utils/color_utils.dart';
import 'package:schedule_plan/core/theme/app_page_route.dart';
import 'package:schedule_plan/core/utils/pinyin_utils.dart';
import 'package:schedule_plan/core/widgets/app_card.dart';
import 'package:schedule_plan/core/widgets/app_snackbar.dart';
import 'package:schedule_plan/core/widgets/confirm_dialog.dart';
import 'package:schedule_plan/core/widgets/pulse_loading.dart';
import 'package:schedule_plan/data/models/class_course.dart';
import 'package:schedule_plan/data/models/student.dart';
import 'package:schedule_plan/data/repositories/class_repository.dart';
import 'package:schedule_plan/data/repositories/student_repository.dart';
import 'package:schedule_plan/features/management/student_form_sheet.dart';
import 'package:schedule_plan/features/management/student_import_page.dart';
import 'package:schedule_plan/l10n/generated/app_localizations.dart';

/// 学生名单（模块六 6.2 / 6.3 + 用户规格）。
///
/// **这里是「导入完看结果」的地方**：不管名单是 Excel 批量导入的还是手工加的，
/// 写进的是同一张 student 表，所以只要库里有，这里就一定看得到——
/// 不再有「导入了却看不到」的自相矛盾。
///
/// [classId] 为空时展示全部学生（设置页入口 / 顶部可再按班级筛），
/// 非空时只展示该班级（班级维度入口）。
class StudentListPage extends StatefulWidget {
  const StudentListPage({super.key, this.classId, this.className});

  final int? classId;
  final String? className;

  @override
  State<StudentListPage> createState() => _StudentListPageState();
}

class _StudentListPageState extends State<StudentListPage> {
  late Future<_RosterData> _future;
  int? _filterClassId;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _filterClassId = widget.classId;
    _reload();
  }

  void _reload() {
    setState(() => _future = _load());
  }

  Future<_RosterData> _load() async {
    // 仓储在 await 之前取好，避免跨异步间隙使用 context
    final classRepo = context.read<ClassRepository>();
    final studentRepo = context.read<StudentRepository>();
    final classes = await classRepo.listClasses();
    final students = await studentRepo.listAll();
    return _RosterData(classes: classes, students: students);
  }

  List<Student> _visible(_RosterData data) {
    final keyword = _query.trim().toLowerCase();
    final list = data.students.where((student) {
      if (_filterClassId != null && student.classId != _filterClassId) {
        return false;
      }
      if (keyword.isEmpty) {
        return true;
      }
      return student.name.toLowerCase().contains(keyword) ||
          (student.studentNo ?? '').toLowerCase().contains(keyword);
    }).toList();
    list.sort((a, b) => PinyinUtils.compareByName(a.name, b.name));
    return list;
  }

  Future<void> _openForm(_RosterData data, {Student? existing}) async {
    if (data.classes.isEmpty) {
      // 学生必须挂在某个班上，没有班级就先引导去建班
      showAppSnackBar(
        context,
        context.l10n.cellNeedsClassBody,
        long: true,
        onRetry: () => pushAppPage<void>(context, const StudentImportPage()),
        retryLabel: context.l10n.goImportRoster,
      );
      return;
    }
    final result = await showStudentFormSheet(
      context,
      classes: data.classes,
      existing: existing,
      defaultClassId: _filterClassId ?? widget.classId,
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

  Future<void> _delete(Student student) async {
    final l10n = context.l10n;
    final studentRepo = context.read<StudentRepository>();
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
      await studentRepo.deleteStudent(student.id!);
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
    final title = widget.className == null
        ? l10n.studentRoster
        : '${widget.className} · ${l10n.studentRoster}';
    return Scaffold(
      appBar: AppBar(
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: <Widget>[
          IconButton(
            tooltip: l10n.goImportRoster,
            icon: const Icon(Icons.upload_file_outlined),
            onPressed: () async {
              await pushAppPage<void>(context, const StudentImportPage());
              _reload();
            },
          ),
        ],
      ),
      floatingActionButton: FutureBuilder<_RosterData>(
        future: _future,
        builder: (context, snapshot) {
          final data = snapshot.data;
          if (data == null) {
            return const SizedBox.shrink();
          }
          return FloatingActionButton.extended(
            onPressed: () => _openForm(data),
            icon: const Icon(Icons.person_add_alt_1_outlined),
            label: Text(l10n.addStudent),
          );
        },
      ),
      body: FutureBuilder<_RosterData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return PulseLoading(message: l10n.loading);
          }
          final data = snapshot.data;
          if (data == null) {
            return Center(child: Text(l10n.noData));
          }
          final students = _visible(data);
          return Column(
            children: <Widget>[
              _buildToolbar(data),
              Expanded(
                child: students.isEmpty
                    ? _buildEmpty(l10n, data)
                    : ListView.builder(
                        cacheExtent: AppConstants.listCacheExtent.toDouble(),
                        padding: const EdgeInsets.fromLTRB(
                          AppConstants.spaceL,
                          AppConstants.spaceS,
                          AppConstants.spaceL,
                          AppConstants.spaceL * 4,
                        ),
                        itemCount: students.length,
                        itemBuilder: (context, index) =>
                            _buildStudentRow(data, students[index]),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildStudentRow(_RosterData data, Student student) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final classInfo = data.classOf(student.classId);
    final color = parseHexColor(classInfo?.color, scheme.primary);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppConstants.spaceS),
      child: AppCard(
        padding: const EdgeInsets.symmetric(
          horizontal: AppConstants.spaceM,
          vertical: AppConstants.spaceS,
        ),
        onTap: () => _openForm(data, existing: student),
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
                      classInfo?.name ?? '--',
                      if (student.studentNo != null &&
                          student.studentNo!.isNotEmpty)
                        '${l10n.studentNo} ${student.studentNo}',
                      _genderLabel(student.gender),
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: l10n.delete,
              icon: const Icon(Icons.delete_outline, size: 20),
              onPressed: () => _delete(student),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty(AppLocalizations l10n, _RosterData data) {
    final noRosterAtAll = data.students.isEmpty;
    return Padding(
      padding: const EdgeInsets.all(AppConstants.spaceL),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(
            Icons.person_search_outlined,
            size: 34,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: AppConstants.spaceM),
          Text(
            noRosterAtAll ? l10n.rosterEmptyGuide : l10n.noStudentsHint,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (noRosterAtAll) ...<Widget>[
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
        ],
      ),
    );
  }

  Widget _buildToolbar(_RosterData data) {
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
      child: Column(
        children: <Widget>[
          // 一进来先给总数：导入完最想确认的就是「到底进来多少人」
          Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppConstants.spaceM,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer.withValues(alpha: 0.7),
                  borderRadius: AppRadii.stadiumAll,
                ),
                child: Text(
                  l10n.rosterSummary(
                    data.students.length,
                    data.classes.length,
                  ),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onPrimaryContainer,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const Spacer(),
              if (_query.isNotEmpty || _filterClassId != null)
                Text(
                  l10n.studentCountLabel(_visible(data).length),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppConstants.spaceS),
          TextField(
            onChanged: (value) => setState(() => _query = value),
            decoration: InputDecoration(
              hintText: l10n.searchHint,
              prefixIcon: const Icon(Icons.search, size: 20),
              isDense: true,
            ),
          ),
          const SizedBox(height: AppConstants.spaceS),
          SizedBox(
            height: 38,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: <Widget>[
                FilterChip(
                  label: Text(l10n.all),
                  selected: _filterClassId == null,
                  onSelected: (_) {
                    AppMotion.select();
                    setState(() => _filterClassId = null);
                  },
                ),
                const SizedBox(width: AppConstants.spaceS),
                for (final item in data.classes)
                  Padding(
                    padding: const EdgeInsets.only(right: AppConstants.spaceS),
                    child: FilterChip(
                      label: Text('${item.name} (${item.studentCount})'),
                      selected: _filterClassId == item.id,
                      onSelected: (_) {
                        AppMotion.select();
                        setState(() => _filterClassId = item.id);
                      },
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _genderLabel(StudentGender? gender) {
    final l10n = context.l10n;
    return switch (gender) {
      StudentGender.male => l10n.genderMale,
      StudentGender.female => l10n.genderFemale,
      null => l10n.genderUnset,
    };
  }
}

class _RosterData {
  const _RosterData({required this.classes, required this.students});

  final List<ClassInfo> classes;
  final List<Student> students;

  ClassInfo? classOf(int id) {
    for (final item in classes) {
      if (item.id == id) {
        return item;
      }
    }
    return null;
  }
}
