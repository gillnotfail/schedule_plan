import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:schedule_plan/core/constants/app_constants.dart';
import 'package:schedule_plan/core/l10n/l10n_extensions.dart';
import 'package:schedule_plan/core/widgets/app_card.dart';
import 'package:schedule_plan/core/widgets/pulse_loading.dart';
import 'package:schedule_plan/core/widgets/scale_tap.dart';
import 'package:schedule_plan/data/models/note.dart';
import 'package:schedule_plan/data/repositories/note_repository.dart';
import 'package:schedule_plan/features/toolbox/note_editor_page.dart';

/// 快速笔记列表（模块五 5.2）。
class NoteListPage extends StatefulWidget {
  const NoteListPage({super.key});

  @override
  State<NoteListPage> createState() => _NoteListPageState();
}

class _NoteListPageState extends State<NoteListPage> {
  late Future<List<Note>> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _future = context.read<NoteRepository>().listNotes();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.noteTitle)),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final id = await context.read<NoteRepository>().createNote('');
          if (!mounted || id <= 0) {
            return;
          }
          if (!context.mounted) {
            return;
          }
          await Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (_) => NoteEditorPage(noteId: id),
            ),
          );
          _reload();
        },
        child: const Icon(Icons.add),
      ),
      body: FutureBuilder<List<Note>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return PulseLoading(message: l10n.loading);
          }
          final notes = snapshot.data ?? const <Note>[];
          if (notes.isEmpty) {
            return Center(child: Text(l10n.noData));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(AppConstants.spaceL),
            itemCount: notes.length,
            itemBuilder: (context, index) {
              final note = notes[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: AppConstants.spaceM),
                child: ScaleTap(
                  onTap: () async {
                    await Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => NoteEditorPage(noteId: note.id!),
                      ),
                    );
                    _reload();
                  },
                  child: AppCard(
                    child: Text(
                      note.content.isEmpty ? l10n.noteEmpty : note.content,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                    ),
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
