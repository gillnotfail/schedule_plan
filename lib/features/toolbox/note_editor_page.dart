import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:schedule_plan/core/constants/app_constants.dart';
import 'package:schedule_plan/core/error/app_exceptions.dart';
import 'package:schedule_plan/core/l10n/l10n_extensions.dart';
import 'package:schedule_plan/core/logging/app_logger.dart';
import 'package:schedule_plan/core/widgets/app_card.dart';
import 'package:schedule_plan/core/widgets/app_snackbar.dart';
import 'package:schedule_plan/core/widgets/confirm_dialog.dart';
import 'package:schedule_plan/data/models/note.dart';
import 'package:schedule_plan/data/repositories/llm_repository.dart';
import 'package:schedule_plan/data/repositories/note_repository.dart';
import 'package:schedule_plan/data/services/llm_service.dart';

/// 快速笔记编辑器 + AI 拓写（模块五 5.2）。
///
/// 选中一段文字后调用已配置的 LLM 进行「扩写/润色/总结」，
/// 结果以 Diff 对比形式展示，用户确认后才替换原文。
class NoteEditorPage extends StatefulWidget {
  const NoteEditorPage({super.key, required this.noteId});

  final int noteId;

  @override
  State<NoteEditorPage> createState() => _NoteEditorPageState();
}

class _NoteEditorPageState extends State<NoteEditorPage> {
  final TextEditingController _controller = TextEditingController();
  bool _loading = true;
  bool _aiBusy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final notes = await context.read<NoteRepository>().listNotes();
    final note = notes.firstWhere(
      (item) => item.id == widget.noteId,
      orElse: () => Note(content: '', createdAt: 0, updatedAt: 0),
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _controller.text = note.content;
      _loading = false;
    });
  }

  Future<void> _save() async {
    final l10n = context.l10n;
    final noteRepo = context.read<NoteRepository>();
    try {
      final notes = await noteRepo.listNotes();
      final note = notes.firstWhere(
        (item) => item.id == widget.noteId,
        orElse: () => Note(content: '', createdAt: 0, updatedAt: 0),
      );
      await noteRepo.updateNote(
            note.copyWith(content: _controller.text),
          );
      if (!mounted) {
        return;
      }
      showAppSnackBar(context, l10n.noteSaved);
    } catch (error, stack) {
      AppLogger.e('保存笔记失败', error: error, stack: stack);
      if (!mounted) {
        return;
      }
      showAppSnackBar(context, l10n.operationFailed('$error'));
    }
  }

  Future<void> _runAi(AiWritingAction action) async {
    final l10n = context.l10n;
    final llmRepo = context.read<LlmProviderRepository>();
    final llmService = context.read<LlmService>();
    final selection = _controller.selection;
    if (selection.isCollapsed) {
      showAppSnackBar(context, l10n.aiSelectTextFirst);
      return;
    }
    final selected = _controller.text.substring(selection.start, selection.end);
    final provider = await llmRepo.getDefaultProvider();
    if (provider == null) {
      if (!mounted) {
        return;
      }
      showAppSnackBar(context, l10n.aiNoProvider);
      return;
    }
    setState(() => _aiBusy = true);
    try {
      final result = await llmService.write(
            provider: provider,
            action: action,
            text: selected,
          );
      if (!mounted) {
        return;
      }
      setState(() => _aiBusy = false);
      final apply = await showAppSheet<bool>(
        context: context,
        builder: (_) => _DiffSheet(
          title: l10n.aiDiffTitle,
          original: selected,
          result: result,
        ),
      );
      if (apply != true) {
        return;
      }
      final text = _controller.text;
      _controller.text = text.replaceRange(selection.start, selection.end, result);
      await _save();
    } on AppException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _aiBusy = false);
      showAppSnackBar(context, error.message);
    } catch (error, stack) {
      AppLogger.e('AI 拓写失败', error: error, stack: stack);
      if (!mounted) {
        return;
      }
      setState(() => _aiBusy = false);
      showAppSnackBar(context, l10n.unexpectedError);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.noteTitle)),
        body: const LinearProgressIndicator(),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.noteTitle),
        actions: <Widget>[
          IconButton(icon: const Icon(Icons.save_outlined), onPressed: _save),
        ],
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(AppConstants.spaceL),
            child: Wrap(
              spacing: AppConstants.spaceS,
              children: <Widget>[
                for (final action in AiWritingAction.values)
                  OutlinedButton(
                    onPressed: _aiBusy ? null : () => _runAi(action),
                    child: Text(_actionLabel(action)),
                  ),
              ],
            ),
          ),
          if (_aiBusy) const LinearProgressIndicator(),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(AppConstants.spaceL),
              child: TextField(
                controller: _controller,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                decoration: InputDecoration(
                  hintText: l10n.noteEmpty,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppConstants.radius),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _actionLabel(AiWritingAction action) {
    final l10n = context.l10n;
    return switch (action) {
      AiWritingAction.expand => l10n.aiExpand,
      AiWritingAction.polish => l10n.aiPolish,
      AiWritingAction.summarize => l10n.aiSummarize,
    };
  }
}

/// AI 结果 Diff 对比（原文 vs 结果），确认后才替换。
class _DiffSheet extends StatelessWidget {
  const _DiffSheet({
    required this.title,
    required this.original,
    required this.result,
  });

  final String title;
  final String original;
  final String result;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return AppCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: AppConstants.spaceM),
          Text(l10n.aiOriginal, style: theme.textTheme.labelLarge),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.all(AppConstants.spaceM),
            decoration: BoxDecoration(
              color: theme.colorScheme.error.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(AppConstants.radius),
            ),
            child: Text(original),
          ),
          const SizedBox(height: AppConstants.spaceM),
          Text(l10n.aiResult, style: theme.textTheme.labelLarge),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.all(AppConstants.spaceM),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(AppConstants.radius),
            ),
            child: Text(result),
          ),
          const SizedBox(height: AppConstants.spaceL),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(l10n.aiDiscard),
                ),
              ),
              const SizedBox(width: AppConstants.spaceM),
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: Text(l10n.aiApply),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
