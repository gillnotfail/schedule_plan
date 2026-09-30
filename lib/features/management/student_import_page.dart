import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:schedule_plan/core/constants/app_constants.dart';
import 'package:schedule_plan/core/l10n/l10n_extensions.dart';
import 'package:schedule_plan/core/logging/app_logger.dart';
import 'package:schedule_plan/core/theme/app_motion.dart';
import 'package:schedule_plan/core/theme/app_page_route.dart';
import 'package:schedule_plan/core/widgets/app_card.dart';
import 'package:schedule_plan/core/widgets/app_snackbar.dart';
import 'package:schedule_plan/core/widgets/pulse_loading.dart';
import 'package:schedule_plan/core/widgets/settings_tile.dart';
import 'package:schedule_plan/data/models/import_log.dart';
import 'package:schedule_plan/data/models/student.dart';
import 'package:schedule_plan/data/repositories/class_repository.dart';
import 'package:schedule_plan/data/repositories/import_log_repository.dart';
import 'package:schedule_plan/data/repositories/student_repository.dart';
import 'package:schedule_plan/data/services/excel_service.dart';
import 'package:schedule_plan/data/services/share_service.dart';
import 'package:schedule_plan/features/management/student_list_page.dart';
import 'package:schedule_plan/l10n/generated/app_localizations.dart';

/// Excel 批量导入学生名单（模块六 6.3 + 用户规格）。
///
/// 与旧版的关键差异：
/// 1. **以 Excel 里的「班级」列为准**，未匹配到的班级自动建档；
/// 2. **不需要二次确认**——选完文件就解析并直接入库，然后把人送到学生名单页。
///    老版本把"导入"按钮放在几百行预览的最下面，等于逼着老师一路拉到底，
///    这也是本次返工最主要的一条（"很多用户不会有耐心下拉到最后"）；
/// 3. 明细预览改成**可折叠**，需要核对时再展开；
/// 4. 只有**存在失败行**时才留在本页，并把失败原因摊开，方便回去改表格。
class StudentImportPage extends StatefulWidget {
  const StudentImportPage({super.key});

  @override
  State<StudentImportPage> createState() => _StudentImportPageState();
}

class _StudentImportPageState extends State<StudentImportPage> {
  static const List<String> _palette = <String>[
    'FF26A69A',
    'FF5C6BC0',
    'FFEF6C00',
    'FF8E24AA',
    'FF0288D1',
    'FF43A047',
    'FFE53935',
    'FF795548',
  ];

  List<ImportPreviewRow> _rows = const <ImportPreviewRow>[];
  List<ImportRowResult> _results = const <ImportRowResult>[];
  Set<String> _existingClassNames = <String>{};
  List<String> _classesToCreate = const <String>[];
  String? _fileName;

  /// 解析 + 入库整个过程（对用户来说就是一个"正在处理"）
  bool _busy = false;
  bool _showFormat = true;
  bool _showDetails = false;

  /// 选文件 → 解析 → 直接入库。
  ///
  /// 用户规格：导入**不做二次确认**，选完文件就进名单。
  /// 因此这里没有"确认导入"这一步：只有"全是错误行"或"一行都没读到"才中断。
  Future<void> _pickFile() async {
    final l10n = context.l10n;
    final classRepo = context.read<ClassRepository>();
    setState(() {
      _busy = true;
      _results = const <ImportRowResult>[];
      _showDetails = false;
    });
    try {
      final picked = await ShareService.pickExcel();
      if (picked == null) {
        if (mounted) {
          setState(() => _busy = false);
        }
        return;
      }
      final parsed = ExcelService().parseStudentRows(picked.bytes);
      final classes = await classRepo.listClasses();
      final names = classes.map((item) => item.name).toSet();
      final toCreate = <String>{
        for (final row in parsed)
          if ((row.className ?? '').trim().isNotEmpty &&
              !names.contains(row.className!.trim()))
            row.className!.trim(),
      }.toList()
        ..sort();

      final rows = <ImportPreviewRow>[
        for (final row in parsed)
          row.copyWith(
            errorKey: row.name.trim().isEmpty
                ? 'importReasonMissingName'
                : ((row.className ?? '').trim().isEmpty
                    ? 'importReasonMissingClass'
                    : null),
          ),
      ];
      if (!mounted) {
        return;
      }
      final allBroken = rows.every((row) => row.hasError);
      setState(() {
        _rows = rows;
        _fileName = picked.name;
        _existingClassNames = names;
        _classesToCreate = toCreate;
        // 有文件之后就把格式说明收起来，版面让给"导了多少行"
        _showFormat = false;
        // 一行都导不进去时，明细直接摊开让老师看见每一行的原因
        _showDetails = allBroken;
      });
      if (rows.isEmpty) {
        setState(() => _busy = false);
        showAppSnackBar(context, l10n.importEmptyFile);
        return;
      }
      if (allBroken) {
        setState(() => _busy = false);
        showAppSnackBar(context, l10n.importFileUnreadable);
        return;
      }
      await _import();
    } on ExcelParseException catch (error, stack) {
      // 技术细节只进日志；给用户看的是「这份表格读不出来」+ 自查建议
      AppLogger.e('解析 Excel 失败', error: error, stack: stack);
      if (!mounted) {
        return;
      }
      setState(() => _busy = false);
      showAppSnackBar(context, l10n.importFileUnreadable);
    } catch (error, stack) {
      AppLogger.e('解析 Excel 失败', error: error, stack: stack);
      if (!mounted) {
        return;
      }
      setState(() => _busy = false);
      showAppSnackBar(context, l10n.operationFailed('$error'));
    }
  }

  /// 落库，并决定下一步：全成功就直接进学生名单，有失败行就留在本页看原因。
  Future<void> _import() async {
    final l10n = context.l10n;
    final classRepository = context.read<ClassRepository>();
    final studentRepository = context.read<StudentRepository>();
    final importRepo = context.read<ImportLogRepository>();
    final results = <ImportRowResult>[];
    var success = 0;
    var fail = 0;
    var skip = 0;
    var createdClasses = 0;

    try {
      // 1) 先把 Excel 里出现过的班级全部建档（用户规格：导入即生成班级）
      final classIdByName = <String, int>{};
      final existing = await classRepository.listClasses();
      for (final item in existing) {
        classIdByName[item.name] = item.id!;
      }
      var paletteIndex = 0;
      for (final name in _classesToCreate) {
        final info = await classRepository.ensureClass(
          name,
          color: _palette[paletteIndex % _palette.length],
        );
        paletteIndex++;
        classIdByName[name] = info.id!;
        createdClasses++;
      }

      // 2) 重复保护：同一个班里已经有同名学生的行直接跳过。
      //    现在没有"确认导入"这一步，误选同一个文件两次是非常容易发生的，
      //    不拦的话名单会整份翻倍。同一个文件里重复的行也只进第一个。
      final seen = await studentRepository.existingRosterKeys();

      // 3) 逐行组装学生；失败行保留具体原因
      final students = <Student>[];
      for (final row in _rows) {
        if (row.hasError) {
          results.add(
            ImportRowResult(
              rowIndex: row.rowIndex,
              status: 'fail',
              reason: row.errorKey,
              studentName: row.name,
            ),
          );
          fail++;
          continue;
        }
        final classId = classIdByName[row.className!.trim()];
        if (classId == null) {
          results.add(
            ImportRowResult(
              rowIndex: row.rowIndex,
              status: 'fail',
              reason: 'importReasonClassNotFound',
              studentName: row.name,
            ),
          );
          fail++;
          continue;
        }
        final key = StudentRepository.rosterKey(classId, row.name);
        if (seen.contains(key)) {
          results.add(
            ImportRowResult(
              rowIndex: row.rowIndex,
              status: 'skip',
              reason: 'importReasonDuplicate',
              studentName: row.name,
            ),
          );
          skip++;
          continue;
        }
        seen.add(key);
        students.add(
          Student(
            name: row.name.trim(),
            studentNo: row.studentNo,
            gender: row.gender,
            classId: classId,
          ),
        );
        results.add(
          ImportRowResult(
            rowIndex: row.rowIndex,
            status: 'success',
            studentName: row.name,
          ),
        );
        success++;
      }

      if (students.isNotEmpty) {
        await studentRepository.insertMany(students);
      }
      await importRepo.saveLog(
        ImportLog(
          fileName: _fileName ?? '',
          importedAt: DateTime.now().millisecondsSinceEpoch,
          successCount: success,
          failCount: fail,
          detailJson: jsonEncode(
            results.map((item) => item.toMap()).toList(),
          ),
        ),
      );
      if (!mounted) {
        return;
      }
      final classRepo = context.read<ClassRepository>();
      final classes = await classRepo.listClasses();
      if (!mounted) {
        return;
      }
      setState(() {
        _results = results;
        _busy = false;
        _existingClassNames = classes.map((item) => item.name).toSet();
        _classesToCreate = const <String>[];
        // 有失败行才需要看明细；全成功就直接去名单页
        _showDetails = fail > 0;
      });
      final summary = createdClasses > 0
          ? '${l10n.importResult(success, fail, skip)} · '
              '${l10n.importAutoCreated(createdClasses)}'
          : l10n.importResult(success, fail, skip);
      showAppSnackBar(context, summary);
      if (fail == 0 && success > 0) {
        await _goRoster();
      }
    } catch (error, stack) {
      AppLogger.e('导入学生失败', error: error, stack: stack);
      if (!mounted) {
        return;
      }
      setState(() => _busy = false);
      showAppSnackBar(context, l10n.operationFailed('$error'));
    }
  }

  /// 直接进学生名单。
  ///
  /// 用 `pushReplacement` 而不是 `push`：从名单返回时应该回到进入导入页之前的
  /// 那个页面（设置页 / 班级详情页），而不是回到一个已经导完的导入页。
  Future<void> _goRoster() async {
    if (!mounted) {
      return;
    }
    AppMotion.confirm();
    await Navigator.of(context).pushReplacement(
      AppPageRoute<void>(child: const StudentListPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.importStudents)),
      body: _busy
          ? PulseLoading(message: l10n.loading)
          : ListView(
              padding: const EdgeInsets.only(bottom: AppConstants.spaceXl),
              children: <Widget>[
                _buildFormatCard(theme),
                // 主操作固定在**顶部**：老师选完文件就能立刻看到结果，
                // 不需要滑过几百行预览去找按钮
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppConstants.spaceL,
                  ),
                  child: FilledButton.icon(
                    onPressed: _pickFile,
                    icon: const Icon(Icons.folder_open_outlined, size: 18),
                    label: Text(l10n.importChooseFile),
                  ),
                ),
                // 选文件之前先把话说明白：这里没有"确认导入"这一步
                if (_fileName == null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppConstants.spaceL,
                      AppConstants.spaceS,
                      AppConstants.spaceL,
                      0,
                    ),
                    child: Text(
                      l10n.importAutoHint,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                if (_fileName != null) ...<Widget>[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppConstants.spaceL,
                      AppConstants.spaceM,
                      AppConstants.spaceL,
                      0,
                    ),
                    child: Row(
                      children: <Widget>[
                        Icon(
                          Icons.description_outlined,
                          size: 15,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _fileName!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_rows.isNotEmpty) _buildSummaryCard(theme, l10n),
                  if (_rows.isNotEmpty) _buildDetailToggle(l10n),
                  if (_showDetails)
                    for (final row in _rows) _buildPreviewRow(row),
                  if (_results.isNotEmpty) _buildRosterAction(l10n),
                ],
              ],
            ),
    );
  }

  /// 导入结果概览：几行、建了几个班、成没成功，一屏之内全部可见。
  ///
  /// 还没入库（全是错误行）时也要给出"成功 0 行、失败 N 行"的读数，
  /// 否则老师只看到一片红字明细，不知道整体算什么结果。
  Widget _buildSummaryCard(ThemeData theme, AppLocalizations l10n) {
    final scheme = theme.colorScheme;
    final succeeded =
        _results.where((item) => item.status == 'success').length;
    final failed = _results.isNotEmpty
        ? _results.where((item) => item.status == 'fail').length
        : _rows.where((row) => row.hasError).length;
    final skipped =
        _results.where((item) => item.status == 'skip').length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.spaceL,
        AppConstants.spaceM,
        AppConstants.spaceL,
        0,
      ),
      child: AppCard(
        padding: const EdgeInsets.all(AppConstants.spaceM),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              l10n.importRowsTotal(_rows.length),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            if (_classesToCreate.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: AppConstants.spaceXs),
                child: Text(
                  l10n.importAutoCreated(_classesToCreate.length),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.primary,
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(top: AppConstants.spaceXs),
              child: Text(
                l10n.importResult(succeeded, failed, skipped),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: failed > 0 ? scheme.error : scheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 明细折叠开关：默认收起，需要核对时再展开（几百行不再挡路）。
  Widget _buildDetailToggle(AppLocalizations l10n) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.spaceL,
        AppConstants.spaceS,
        AppConstants.spaceL,
        0,
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () {
            AppMotion.tap();
            setState(() => _showDetails = !_showDetails);
          },
          icon: Icon(
            _showDetails
                ? Icons.expand_less_rounded
                : Icons.expand_more_rounded,
            size: 18,
          ),
          label: Text(
            _showDetails
                ? l10n.importDetailHide
                : l10n.importDetailToggle(_rows.length),
          ),
          style: TextButton.styleFrom(
            visualDensity: VisualDensity.compact,
            textStyle: theme.textTheme.labelMedium,
          ),
        ),
      ),
    );
  }

  /// 有失败行时会停在本页：给一个"去学生名单"的出口，成功的那部分已经进去了。
  Widget _buildRosterAction(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.spaceL,
        AppConstants.spaceM,
        AppConstants.spaceL,
        0,
      ),
      child: OutlinedButton.icon(
        onPressed: _goRoster,
        icon: const Icon(Icons.people_outline, size: 18),
        label: Text(l10n.importGoRoster),
      ),
    );
  }

  Widget _buildFormatCard(ThemeData theme) {
    final l10n = context.l10n;
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.spaceL,
        AppConstants.spaceL,
        AppConstants.spaceL,
        AppConstants.spaceM,
      ),
      child: AppCard(
        padding: EdgeInsets.zero,
        child: Column(
          children: <Widget>[
            SettingsTile(
              icon: Icons.description_outlined,
              title: l10n.importFormatTitle,
              subtitle: l10n.importFormatLine1,
              showChevron: false,
              trailing: IconButton(
                icon: Icon(
                  _showFormat
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                ),
                onPressed: () {
                  AppMotion.tap();
                  setState(() => _showFormat = !_showFormat);
                },
              ),
            ),
            AnimatedCrossFade(
              duration: AppMotion.standard,
              crossFadeState: _showFormat
                  ? CrossFadeState.showFirst
                  : CrossFadeState.showSecond,
              firstChild: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppConstants.spaceL,
                  0,
                  AppConstants.spaceL,
                  AppConstants.spaceL,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _bullet(theme, l10n.importFormatLine2, required: true),
                    _bullet(theme, l10n.importFormatLine3),
                    _bullet(theme, l10n.importFormatLine4),
                    const SizedBox(height: AppConstants.spaceM),
                    Text(
                      l10n.importFormatExample,
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: AppConstants.spaceXs),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(AppConstants.spaceM),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHigh,
                        borderRadius: AppRadii.smallAll,
                      ),
                      child: Text(
                        '| 姓名 | 班级 | 学号 | 性别 |\n'
                        '| 张三 | 高一(3)班 | 2026001 | 男 |\n'
                        '| 李四 | 高一(3)班 | 2026002 | 女 |\n'
                        '| 王五 | 马原班 |  |  |',
                        style: theme.textTheme.labelSmall?.copyWith(
                          height: 1.6,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              secondChild: const SizedBox(width: double.infinity),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bullet(ThemeData theme, String text, {bool required = false}) {
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppConstants.spaceXs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                color: required ? scheme.primary : scheme.outline,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: AppConstants.spaceS),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: required ? FontWeight.w700 : FontWeight.w400,
                color: required ? scheme.onSurface : scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewRow(ImportPreviewRow row) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final result = _results.isEmpty
        ? null
        : _results.firstWhere(
            (item) => item.rowIndex == row.rowIndex,
            orElse: () => ImportRowResult(rowIndex: row.rowIndex, status: 'skip'),
          );
    final isNewClass = row.className != null &&
        !_existingClassNames.contains(row.className);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.spaceL,
        AppConstants.spaceXs,
        AppConstants.spaceL,
        AppConstants.spaceXs,
      ),
      child: AppCard(
        padding: const EdgeInsets.symmetric(
          horizontal: AppConstants.spaceM,
          vertical: AppConstants.spaceS,
        ),
        elevated: false,
        child: Row(
          children: <Widget>[
            Text(
              '${row.rowIndex}',
              style: theme.textTheme.labelSmall,
            ),
            const SizedBox(width: AppConstants.spaceM),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Text(
                        row.name,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: AppConstants.spaceS),
                      if (row.studentNo != null)
                        Text(
                          row.studentNo!,
                          style: theme.textTheme.labelSmall,
                        ),
                    ],
                  ),
                  Text(
                    <String>[
                      row.className ?? '-',
                      if (isNewClass) l10n.importFormatLine4,
                      if (row.gender != null)
                        row.gender == StudentGender.male
                            ? l10n.genderMale
                            : l10n.genderFemale,
                    ].join(' · '),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: isNewClass ? scheme.primary : null,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              _statusText(result, row),
              style: theme.textTheme.labelSmall?.copyWith(
                color: row.hasError ? scheme.error : scheme.onSurfaceVariant,
                fontWeight: row.hasError ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _statusText(ImportRowResult? result, ImportPreviewRow row) {
    final l10n = context.l10n;
    if (result == null) {
      return row.hasError ? _reasonText(row.errorKey!) : '';
    }
    return switch (result.status) {
      'success' => l10n.importDone,
      // 失败和跳过都要给出原因：跳过＝这个班里已经有同名学生
      'fail' || 'skip' => _reasonText(result.reason),
      _ => l10n.all,
    };
  }

  String _reasonText(String? key) {
    final l10n = context.l10n;
    return switch (key) {
      'importReasonMissingName' => l10n.importReasonMissingName,
      'importReasonMissingClass' => l10n.importReasonMissingClass,
      'importReasonClassNotFound' => l10n.importReasonClassNotFound,
      'importReasonDuplicate' => l10n.importReasonDuplicate,
      _ => l10n.noData,
    };
  }
}
