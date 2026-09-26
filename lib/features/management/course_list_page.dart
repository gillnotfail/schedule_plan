import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:schedule_plan/core/constants/app_constants.dart';
import 'package:schedule_plan/core/l10n/l10n_extensions.dart';
import 'package:schedule_plan/core/logging/app_logger.dart';
import 'package:schedule_plan/core/theme/app_motion.dart';
import 'package:schedule_plan/core/theme/app_page_route.dart';
import 'package:schedule_plan/core/utils/color_utils.dart';
import 'package:schedule_plan/core/widgets/app_card.dart';
import 'package:schedule_plan/core/widgets/app_snackbar.dart';
import 'package:schedule_plan/core/widgets/confirm_dialog.dart';
import 'package:schedule_plan/core/widgets/pulse_loading.dart';
import 'package:schedule_plan/data/models/class_course.dart';
import 'package:schedule_plan/data/repositories/class_repository.dart';
import 'package:schedule_plan/data/repositories/course_repository.dart';
import 'package:schedule_plan/features/management/class_form_sheet.dart'
    show kClassPalette;
import 'package:schedule_plan/features/management/course_ocr_page.dart';

/// 课程管理（模块六 6.1 + 用户规格）。
///
/// 用户规格：课程名称与上课教室手动输入；上课班级从已导入/添加的班级中**多选**
/// （支持合班 / 大课），人数按所选班级自动汇总；备注可选。
class CourseListPage extends StatefulWidget {
  const CourseListPage({super.key, this.classId, this.className});

  final int? classId;
  final String? className;

  @override
  State<CourseListPage> createState() => _CourseListPageState();
}

class _CourseListPageState extends State<CourseListPage> {
  late Future<_CourseData> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() => _future = _load());
  }

  Future<_CourseData> _load() async {
    // 仓储在 await 之前取好，避免跨异步间隙使用 context
    final classRepo = context.read<ClassRepository>();
    final courseRepo = context.read<CourseRepository>();
    final classes = await classRepo.listClasses();
    final courses = await courseRepo.listCourses(classId: widget.classId);
    final counts = await courseRepo.studentCountByCourse();
    return _CourseData(
      classes: classes,
      courses: courses,
      counts: counts,
    );
  }

  /// 课程卡片配色：课程自选色 > 挂载班级里第一个的颜色 > null（用主题渐变）。
  ///
  /// 与 `CourseDetail.color` / 课表格子的取色口径保持一致，
  /// 这样"课程管理里看到的颜色"和"课表格子里的颜色"永远是同一个。
  Color? _cardColorOf(Course course, _CourseData data) {
    final fallback = Theme.of(context).colorScheme.primary;
    final own = (course.color ?? '').trim();
    if (own.isNotEmpty) {
      return parseHexColor(own, fallback);
    }
    for (final item in data.classes) {
      final id = item.id;
      if (id != null && course.hasClass(id)) {
        return parseHexColor(item.color, fallback);
      }
    }
    return null;
  }

  Future<void> _edit(_CourseData data, Course? course) async {
    if (data.classes.isEmpty) {
      showAppSnackBar(context, context.l10n.classManagementDesc);
      return;
    }
    final result = await showModalBottomSheet<_CourseFormResult>(
      context: context,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(borderRadius: AppRadii.sheetTop),
      builder: (_) => _CourseForm(
        existing: course,
        classes: data.classes,
        defaultClassId: widget.classId,
      ),
    );
    if (result == null || !mounted) {
      return;
    }
    try {
      final repository = context.read<CourseRepository>();
      final course2 = result.toCourse(existing: course);
      if (course == null) {
        await repository.createCourse(course2);
      } else {
        await repository.updateCourse(course2);
      }
      if (!mounted) {
        return;
      }
      showAppSnackBar(context, context.l10n.courseSaved);
      _reload();
    } catch (error, stack) {
      AppLogger.e('保存课程失败', error: error, stack: stack);
      if (!mounted) {
        return;
      }
      showAppSnackBar(context, context.l10n.operationFailed('$error'));
    }
  }

  Future<void> _delete(Course course) async {
    final l10n = context.l10n;
    final repo = context.read<CourseRepository>();
    final confirmed = await showAppConfirm(
      context: context,
      title: l10n.deleteCourse,
      body: l10n.clearAllDataConfirm,
      danger: true,
    );
    if (!confirmed) {
      return;
    }
    try {
      await repo.deleteCourse(course.id!);
      if (!mounted) {
        return;
      }
      _reload();
    } catch (error, stack) {
      AppLogger.e('删除课程失败', error: error, stack: stack);
      if (!mounted) {
        return;
      }
      showAppSnackBar(context, l10n.operationFailed('$error'));
    }
  }

  Future<void> _clearAll() async {
    final l10n = context.l10n;
    final repo = context.read<CourseRepository>();
    final confirmed = await showAppConfirm(
      context: context,
      title: l10n.courseClearAll,
      body: l10n.courseClearAllConfirm,
      danger: true,
    );
    if (!confirmed) {
      return;
    }
    try {
      await repo.clearAllCourses();
      if (!mounted) {
        return;
      }
      showAppSnackBar(context, l10n.courseCleared);
      _reload();
    } catch (error, stack) {
      AppLogger.e('清空课程失败', error: error, stack: stack);
      if (!mounted) {
        return;
      }
      showAppSnackBar(context, l10n.operationFailed('$error'));
    }
  }

  /// 去拍照识别课表（第 11 轮）。回来时若真的导入了课程就重载列表。
  Future<void> _openOcr() async {
    final imported = await pushAppPage<bool>(
      context,
      const CourseOcrPage(),
    );
    if (imported == true && mounted) {
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final title = widget.className == null
        ? l10n.courseManagement
        : '${widget.className} · ${l10n.manageCourses}';
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: <Widget>[
          IconButton(
            tooltip: l10n.ocrEntryTitle,
            icon: const Icon(Icons.document_scanner_outlined),
            onPressed: _openOcr,
          ),
          IconButton(
            tooltip: l10n.courseClearAll,
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: _clearAll,
          ),
        ],
      ),
      floatingActionButton: FutureBuilder<_CourseData>(
        future: _future,
        builder: (context, snapshot) {
          final data = snapshot.data;
          if (data == null) {
            return const SizedBox.shrink();
          }
          return FloatingActionButton.extended(
            onPressed: () => _edit(data, null),
            icon: const Icon(Icons.add),
            label: Text(l10n.addCourse),
          );
        },
      ),
      body: FutureBuilder<_CourseData>(
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
          if (data.courses.isEmpty) {
            return EmptyView(
              message: l10n.noData,
              icon: Icons.menu_book_outlined,
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(
              AppConstants.spaceL,
              AppConstants.spaceL,
              AppConstants.spaceL,
              AppConstants.spaceL * 4,
            ),
            itemCount: data.courses.length,
            itemBuilder: (context, index) {
              final course = data.courses[index];
              final names = data.classes
                  .where((item) => course.hasClass(item.id!))
                  .map((item) => item.name)
                  .toList();
              final count = data.counts[course.id] ?? 0;
              // 配色口径与课表格子**完全一致**（即 CourseDetail.color）：
              // 课程自选色优先，没选过回落成挂载班级里第一个的颜色；
              // 连班级色都拿不到时才退回主题渐变。
              // 用户规格："添加课程时给课程锁定的颜色，课表单元格里要一致"。
              final cardColor = _cardColorOf(course, data);
              return Padding(
                padding: const EdgeInsets.only(bottom: AppConstants.spaceM),
                child: AppCard(
                  padding: const EdgeInsets.all(AppConstants.spaceM),
                  onTap: () => _edit(data, course),
                  child: Row(
                    children: <Widget>[
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          gradient: cardColor == null
                              ? LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: <Color>[
                                    Theme.of(context).colorScheme.primary,
                                    Theme.of(context).colorScheme.tertiary,
                                  ],
                                )
                              : null,
                          color: cardColor,
                          borderRadius: AppRadii.smallAll,
                        ),
                        child: const Icon(
                          Icons.menu_book_outlined,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: AppConstants.spaceM),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Row(
                              children: <Widget>[
                                Expanded(
                                  child: Text(
                                    course.name,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyLarge
                                        ?.copyWith(
                                          fontWeight: FontWeight.w800,
                                        ),
                                  ),
                                ),
                                Text(
                                  '${l10n.courseCountLabel} $count',
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelMedium
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                        fontWeight: FontWeight.w800,
                                      ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              <String>[
                                if (course.room != null &&
                                    course.room!.isNotEmpty)
                                  '${l10n.courseRoomLabel} ${course.room}',
                                if (names.isNotEmpty) names.join('、'),
                                if (course.description != null &&
                                    course.description!.isNotEmpty)
                                  course.description!,
                              ].join(' · '),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: l10n.delete,
                        icon: const Icon(Icons.delete_outline, size: 20),
                        onPressed: () => _delete(course),
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

/// 课程表单结果（拆成独立类型，避免把「人数」这类派生值塞进 Course）。
class _CourseFormResult {
  const _CourseFormResult({
    required this.name,
    required this.room,
    required this.classIds,
    required this.description,
    this.color,
  });

  final String name;
  final String? room;
  final List<int> classIds;
  final String? description;

  /// 课程标记色；null 表示跟随班级色。
  final String? color;

  Course toCourse({Course? existing}) => Course(
        id: existing?.id,
        name: name,
        teacherName: existing?.teacherName ?? '',
        classIds: classIds,
        room: room,
        description: description,
        color: color,
      );
}

class _CourseForm extends StatefulWidget {
  const _CourseForm({
    required this.classes,
    this.existing,
    this.defaultClassId,
  });

  final List<ClassInfo> classes;
  final Course? existing;
  final int? defaultClassId;

  @override
  State<_CourseForm> createState() => _CourseFormState();
}

class _CourseFormState extends State<_CourseForm> {
  late final TextEditingController _name;
  late final TextEditingController _room;
  late final TextEditingController _description;
  late Set<int> _classIds;
  String? _nameError;
  String? _classError;

  /// 课程标记色；null = 跟随班级色（用户规格：可给课程单独选颜色）。
  String? _color;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _name = TextEditingController(text: existing?.name ?? '');
    _room = TextEditingController(text: existing?.room ?? '');
    _description = TextEditingController(text: existing?.description ?? '');
    _color = existing?.color;
    _classIds = <int>{
      if (existing != null && existing.classIds.isNotEmpty)
        ...existing.classIds
      else if (widget.defaultClassId != null)
        widget.defaultClassId!,
    };
  }

  @override
  void dispose() {
    _name.dispose();
    _room.dispose();
    _description.dispose();
    super.dispose();
  }

  /// 人数 = 所选班级人数之和（班级之间学生不重复）。
  int get _studentCount {
    var sum = 0;
    for (final item in widget.classes) {
      if (_classIds.contains(item.id)) {
        sum += item.studentCount;
      }
    }
    return sum;
  }

  /// 班主任（去重）——与颜色一样取**所属班级**，用户规格不往 course 加列。
  String get _headTeachers {
    final names = <String>[];
    for (final item in widget.classes) {
      if (!_classIds.contains(item.id)) {
        continue;
      }
      final name = (item.headTeacher ?? '').trim();
      if (name.isNotEmpty && !names.contains(name)) {
        names.add(name);
      }
    }
    return names.isEmpty ? '—' : names.join('、');
  }

  /// 当前生效的配色：课程自选色优先，否则取所选班级里第一个的颜色。
  ///
  /// 只用于表单里的色块预览，让老师在还没保存时就看到这一课会长什么样。
  String get _effectiveColorHex {
    final own = _color;
    if (own != null && own.isNotEmpty) {
      return own;
    }
    for (final item in widget.classes) {
      if (_classIds.contains(item.id)) {
        return item.color;
      }
    }
    return '';
  }

  /// 弹出多选面板挑上课班级。
  ///
  /// 用弹层而不是内联 Chip，是因为班级列表本身就是「班级管理」里那份名单，
  /// 弹层可以带上班主任和各班人数，选起来更像「从名单里挑」。
  Future<void> _pickClasses() async {
    final l10n = context.l10n;
    final picked = await showModalBottomSheet<Set<int>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: AppRadii.sheetTop),
      builder: (_) => _ClassPickSheet(
        classes: widget.classes,
        selected: _classIds,
        title: l10n.coursePickClassTitle,
      ),
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() {
      _classIds = picked;
      _classError = null;
    });
  }

  void _submit() {
    final l10n = context.l10n;
    var valid = true;
    if (_name.text.trim().isEmpty) {
      setState(() => _nameError = l10n.requiredField);
      valid = false;
    }
    if (_classIds.isEmpty) {
      setState(() => _classError = l10n.courseClassRequired);
      valid = false;
    }
    if (!valid) {
      return;
    }
    Navigator.of(context).pop(
      _CourseFormResult(
        name: _name.text.trim(),
        room: _room.text.trim().isEmpty ? null : _room.text.trim(),
        classIds: _classIds.toList()..sort(),
        description:
            _description.text.trim().isEmpty ? null : _description.text.trim(),
        color: _color,
      ),
    );
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
                l10n.courseFormTitle,
                style: theme.textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppConstants.spaceL),
              TextField(
                controller: _name,
                decoration: InputDecoration(
                  labelText: l10n.courseNameLabel,
                  errorText: _nameError,
                  prefixIcon: const Icon(Icons.menu_book_outlined, size: 20),
                ),
              ),
              const SizedBox(height: AppConstants.spaceM),
              TextField(
                controller: _room,
                decoration: InputDecoration(
                  labelText: l10n.courseRoomLabel,
                  prefixIcon: const Icon(Icons.meeting_room_outlined, size: 20),
                ),
              ),
              const SizedBox(height: AppConstants.spaceL),
              Row(
                children: <Widget>[
                  Icon(
                    Icons.groups_outlined,
                    size: 17,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      l10n.courseClassLabel,
                      style: theme.textTheme.labelLarge,
                    ),
                  ),
                  Text(
                    '${l10n.courseCountLabel} $_studentCount',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                l10n.courseMultiClassHint,
                style: theme.textTheme.labelSmall,
              ),
              const SizedBox(height: AppConstants.spaceS),
              // 班级多选走**弹层挑选**（用户规格）：班级可能是十几个，
              // 平铺一堆 Chip 会把表单撑得很长，也不好在里面看清每个班有多少人
              OutlinedButton.icon(
                onPressed: _pickClasses,
                icon: const Icon(Icons.checklist_rounded, size: 18),
                label: Text(l10n.pickClass),
              ),
              const SizedBox(height: AppConstants.spaceS),
              if (_classIds.isEmpty)
                Text(
                  l10n.courseClassRequired,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.outline,
                  ),
                )
              else
                Wrap(
                  spacing: AppConstants.spaceS,
                  runSpacing: AppConstants.spaceS,
                  children: <Widget>[
                    for (final item in widget.classes)
                      if (_classIds.contains(item.id))
                        Chip(
                          avatar: CircleAvatar(
                            radius: 7,
                            backgroundColor:
                                parseHexColor(item.color, scheme.primary),
                          ),
                          label: Text('${item.name} (${item.studentCount})'),
                          onDeleted: () => setState(() {
                            _classIds.remove(item.id);
                            _classError = null;
                          }),
                        ),
                  ],
                ),
              if (_classError != null)
                Padding(
                  padding: const EdgeInsets.only(top: AppConstants.spaceS),
                  child: Text(
                    _classError!,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: AppConstants.spaceS),
              // 班主任：只读展示，取所选班级的班主任（用户规格：
              // 颜色与班主任都跟着班级走，不往 course 表加列）
              Row(
                children: <Widget>[
                  Icon(
                    Icons.person_outline,
                    size: 16,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      l10n.classHeadTeacherFromClass,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Flexible(
                    child: Text(
                      _headTeachers,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppConstants.spaceM),
              // 课程标记色（用户规格：新增课程时可以给这门课挑个颜色）
              Row(
                children: <Widget>[
                  Icon(
                    Icons.palette_outlined,
                    size: 17,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      l10n.courseColorLabel,
                      style: theme.textTheme.labelLarge,
                    ),
                  ),
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: parseHexColor(
                        _effectiveColorHex,
                        scheme.outlineVariant,
                      ),
                      borderRadius: AppRadii.smallAll,
                      border: Border.all(color: scheme.outlineVariant),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(l10n.courseColorHint, style: theme.textTheme.labelSmall),
              const SizedBox(height: AppConstants.spaceS),
              Wrap(
                spacing: AppConstants.spaceS,
                runSpacing: AppConstants.spaceS,
                children: <Widget>[
                  ChoiceChip(
                    label: Text(l10n.courseColorAuto),
                    selected: _color == null,
                    onSelected: (_) {
                      AppMotion.select();
                      setState(() => _color = null);
                    },
                  ),
                  for (final hex in kClassPalette)
                    ChoiceChip(
                      label: const SizedBox(width: 22, height: 12),
                      selected: _color == hex,
                      backgroundColor: Color(int.parse(hex, radix: 16)),
                      selectedColor: Color(int.parse(hex, radix: 16)),
                      onSelected: (_) {
                        AppMotion.select();
                        setState(() => _color = hex);
                      },
                    ),
                ],
              ),
              const SizedBox(height: AppConstants.spaceM),
              Text(
                l10n.courseAutoCountHint,
                style: theme.textTheme.labelSmall,
              ),
              const SizedBox(height: AppConstants.spaceM),
              TextField(
                controller: _description,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: l10n.courseRemarkLabel,
                  prefixIcon: const Icon(Icons.notes_outlined, size: 20),
                ),
              ),
              const SizedBox(height: AppConstants.spaceXl),
              FilledButton(onPressed: _submit, child: Text(l10n.save)),
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

class _CourseData {
  const _CourseData({
    required this.classes,
    required this.courses,
    required this.counts,
  });

  final List<ClassInfo> classes;
  final List<Course> courses;
  final Map<int, int> counts;
}

/// 「选择上课班级」多选弹层。
///
/// 列出「班级管理」里那份名单（名称 + 人数 + 班主任），勾选后确认回填。
class _ClassPickSheet extends StatefulWidget {
  const _ClassPickSheet({
    required this.classes,
    required this.selected,
    required this.title,
  });

  final List<ClassInfo> classes;
  final Set<int> selected;
  final String title;

  @override
  State<_ClassPickSheet> createState() => _ClassPickSheetState();
}

class _ClassPickSheetState extends State<_ClassPickSheet> {
  late Set<int> _draft;

  @override
  void initState() {
    super.initState();
    _draft = <int>{...widget.selected};
  }

  int get _draftStudentCount {
    var sum = 0;
    for (final item in widget.classes) {
      if (_draft.contains(item.id)) {
        sum += item.studentCount;
      }
    }
    return sum;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppConstants.spaceL,
          AppConstants.spaceS,
          AppConstants.spaceL,
          AppConstants.spaceL,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.8,
          ),
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
                  Expanded(
                    child: Text(
                      widget.title,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    '${l10n.courseCountLabel} $_draftStudentCount',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              Text(
                l10n.coursePickClassHint,
                style: theme.textTheme.labelSmall,
              ),
              const SizedBox(height: AppConstants.spaceM),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: widget.classes.length,
                  itemBuilder: (context, index) {
                    final item = widget.classes[index];
                    final teacher = (item.headTeacher ?? '').trim();
                    return CheckboxListTile(
                      value: _draft.contains(item.id),
                      onChanged: (checked) {
                        AppMotion.select();
                        setState(() {
                          if (checked == true) {
                            _draft.add(item.id!);
                          } else {
                            _draft.remove(item.id);
                          }
                        });
                      },
                      controlAffinity: ListTileControlAffinity.leading,
                      secondary: CircleAvatar(
                        radius: 9,
                        backgroundColor:
                            parseHexColor(item.color, scheme.primary),
                      ),
                      title: Text(
                        item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        <String>[
                          l10n.studentCountLabel(item.studentCount),
                          if (teacher.isNotEmpty)
                            '${l10n.headTeacher} $teacher',
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: AppConstants.spaceM),
              FilledButton(
                onPressed: () {
                  AppMotion.confirm();
                  Navigator.of(context).pop(_draft);
                },
                child: Text(l10n.confirm),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
