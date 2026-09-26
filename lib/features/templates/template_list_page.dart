import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:schedule_plan/core/constants/app_constants.dart';
import 'package:schedule_plan/core/l10n/l10n_extensions.dart';
import 'package:schedule_plan/core/logging/app_logger.dart';
import 'package:schedule_plan/core/widgets/app_card.dart';
import 'package:schedule_plan/core/widgets/app_snackbar.dart';
import 'package:schedule_plan/core/widgets/confirm_dialog.dart';
import 'package:schedule_plan/core/widgets/pulse_loading.dart';
import 'package:schedule_plan/core/widgets/scale_tap.dart';
import 'package:schedule_plan/data/models/schedule_template.dart';
import 'package:schedule_plan/data/repositories/template_repository.dart';
import 'package:schedule_plan/features/templates/template_editor_page.dart';

/// 作息模板管理列表（模块一 1.2）。
class TemplateListPage extends StatefulWidget {
  const TemplateListPage({super.key});

  @override
  State<TemplateListPage> createState() => _TemplateListPageState();
}

class _TemplateListPageState extends State<TemplateListPage> {
  late Future<List<ScheduleTemplate>> _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<TemplateRepository>().listTemplates();
  }

  Future<void> _reload() async {
    final future = context.read<TemplateRepository>().listTemplates();
    setState(() => _future = future);
    await future;
  }

  Future<void> _create() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => const TemplateEditorPage()),
    );
    if (result == true) {
      await _reload();
    }
  }

  Future<void> _open(ScheduleTemplate template) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => TemplateEditorPage(templateId: template.id),
      ),
    );
    if (result == true) {
      await _reload();
    }
  }

  Future<void> _setDefault(ScheduleTemplate template) async {
    final l10n = context.l10n;
    final repo = context.read<TemplateRepository>();
    final confirmed = await showAppConfirm(
      context: context,
      title: l10n.templateSetDefault,
      body: l10n.templateSetDefaultConfirm,
    );
    if (!confirmed) {
      return;
    }
    try {
      await repo.setDefaultTemplate(template.id!);
      await _reload();
    } catch (error, stack) {
      AppLogger.e('设置默认模板失败', error: error, stack: stack);
      if (!mounted) {
        return;
      }
      showAppSnackBar(context, l10n.operationFailed('$error'));
    }
  }

  Future<void> _delete(ScheduleTemplate template) async {
    final l10n = context.l10n;
    final repository = context.read<TemplateRepository>();
    try {
      // 删除前必须校验：仍有班级绑定则禁止删除，并列出受影响班级名单
      final confirmed = await showAppConfirm(
        context: context,
        title: l10n.templateDelete,
        body: l10n.templateEditAffectClasses(template.boundClassCount),
        danger: true,
      );
      if (!confirmed) {
        return;
      }
      await repository.deleteTemplate(template.id!);
      await _reload();
    } on TemplateInUseException catch (error) {
      if (!mounted) {
        return;
      }
      await showAppConfirm(
        context: context,
        title: l10n.templateDeleteBlocked,
        body: l10n.templateDeleteBlockedBody(error.classNames.join('、')),
      );
    } catch (error, stack) {
      AppLogger.e('删除模板失败', error: error, stack: stack);
      if (!mounted) {
        return;
      }
      showAppSnackBar(context, l10n.operationFailed('$error'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.templateTitle)),
      floatingActionButton: FloatingActionButton(
        onPressed: _create,
        child: const Icon(Icons.add),
      ),
      body: FutureBuilder<List<ScheduleTemplate>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return PulseLoading(message: l10n.loading);
          }
          final templates = snapshot.data ?? const <ScheduleTemplate>[];
          if (templates.isEmpty) {
            return EmptyView(message: l10n.noData, icon: Icons.tune_outlined);
          }
          return ListView.builder(
            padding: const EdgeInsets.all(AppConstants.spaceL),
            itemCount: templates.length,
            itemBuilder: (context, index) {
              final template = templates[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: AppConstants.spaceM),
                child: ScaleTap(
                  onTap: () => _open(template),
                  child: AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                template.name,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            if (template.isDefault)
                              Chip(
                                label: Text(l10n.templateIsDefault),
                                visualDensity: VisualDensity.compact,
                              ),
                          ],
                        ),
                        const SizedBox(height: AppConstants.spaceS),
                        Text(
                          l10n.templateBoundClasses(template.boundClassCount),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: AppConstants.spaceS),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: <Widget>[
                            TextButton(
                              onPressed: () => _setDefault(template),
                              child: Text(l10n.templateSetDefault),
                            ),
                            TextButton(
                              onPressed: () => _delete(template),
                              child: Text(l10n.delete),
                            ),
                          ],
                        ),
                      ],
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
