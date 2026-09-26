import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:schedule_plan/core/constants/app_constants.dart';
import 'package:schedule_plan/core/l10n/l10n_extensions.dart';
import 'package:schedule_plan/core/logging/app_logger.dart';
import 'package:schedule_plan/core/widgets/app_card.dart';
import 'package:schedule_plan/core/widgets/app_snackbar.dart';
import 'package:schedule_plan/core/widgets/confirm_dialog.dart';
import 'package:schedule_plan/core/widgets/pulse_loading.dart';
import 'package:schedule_plan/data/models/llm_provider_config.dart';
import 'package:schedule_plan/data/repositories/llm_repository.dart';

/// LLM 提供商配置（模块五 5.2）。
///
/// API Key 由用户自行填写并加密（混淆）存储在本地。
class LlmProviderPage extends StatefulWidget {
  const LlmProviderPage({super.key});

  @override
  State<LlmProviderPage> createState() => _LlmProviderPageState();
}

class _LlmProviderPageState extends State<LlmProviderPage> {
  late Future<List<LlmProviderConfig>> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _future = context.read<LlmProviderRepository>().listProviders();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.llmProviders)),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _edit(null),
        child: const Icon(Icons.add),
      ),
      body: FutureBuilder<List<LlmProviderConfig>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return PulseLoading(message: l10n.loading);
          }
          final providers = snapshot.data ?? const <LlmProviderConfig>[];
          if (providers.isEmpty) {
            return Center(child: Text(l10n.aiNoProvider));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(AppConstants.spaceL),
            itemCount: providers.length,
            itemBuilder: (context, index) {
              final provider = providers[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: AppConstants.spaceM),
                child: AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(provider.name,
                                style: Theme.of(context).textTheme.titleSmall),
                          ),
                          if (provider.isDefault)
                            Chip(label: Text(l10n.llmSetDefault)),
                        ],
                      ),
                      Text(provider.baseUrl,
                          style: Theme.of(context).textTheme.bodySmall),
                      Text(provider.modelName,
                          style: Theme.of(context).textTheme.bodySmall),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: <Widget>[
                          TextButton(
                            onPressed: () async {
                              await context
                                  .read<LlmProviderRepository>()
                                  .setDefaultProvider(provider.id!);
                              _reload();
                            },
                            child: Text(l10n.llmSetDefault),
                          ),
                          TextButton(
                            onPressed: () => _edit(provider),
                            child: Text(l10n.edit),
                          ),
                          TextButton(
                            onPressed: () async {
                              await context
                                  .read<LlmProviderRepository>()
                                  .deleteProvider(provider.id!);
                              _reload();
                            },
                            child: Text(l10n.delete),
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

  Future<void> _edit(LlmProviderConfig? provider) async {
    final result = await showAppSheet<LlmProviderConfig>(
      context: context,
      builder: (_) => _ProviderForm(existing: provider),
    );
    if (result == null || !mounted) {
      return;
    }
    try {
      final repository = context.read<LlmProviderRepository>();
      if (provider == null) {
        await repository.createProvider(result);
      } else {
        await repository.updateProvider(result);
      }
      _reload();
    } catch (error, stack) {
      AppLogger.e('保存 LLM 提供商失败', error: error, stack: stack);
      if (!mounted) {
        return;
      }
      showAppSnackBar(context, context.l10n.operationFailed('$error'));
    }
  }
}

class _ProviderForm extends StatefulWidget {
  const _ProviderForm({this.existing});

  final LlmProviderConfig? existing;

  @override
  State<_ProviderForm> createState() => _ProviderFormState();
}

class _ProviderFormState extends State<_ProviderForm> {
  late final TextEditingController _name;
  late final TextEditingController _baseUrl;
  late final TextEditingController _apiKey;
  late final TextEditingController _model;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _name = TextEditingController(text: existing?.name ?? '');
    _baseUrl = TextEditingController(
      text: existing?.baseUrl ?? 'https://api.openai.com/v1',
    );
    _apiKey = TextEditingController(
      text: existing == null ? '' : existing.apiKey,
    );
    _model = TextEditingController(text: existing?.modelName ?? 'gpt-4o-mini');
  }

  @override
  void dispose() {
    _name.dispose();
    _baseUrl.dispose();
    _apiKey.dispose();
    _model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AppCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(l10n.llmProviders, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppConstants.spaceM),
          TextField(
            controller: _name,
            decoration: InputDecoration(labelText: l10n.llmProviderName),
          ),
          const SizedBox(height: AppConstants.spaceM),
          TextField(
            controller: _baseUrl,
            decoration: InputDecoration(labelText: l10n.llmBaseUrl),
          ),
          const SizedBox(height: AppConstants.spaceM),
          TextField(
            controller: _apiKey,
            obscureText: true,
            decoration: InputDecoration(labelText: l10n.llmApiKey),
          ),
          const SizedBox(height: AppConstants.spaceM),
          TextField(
            controller: _model,
            decoration: InputDecoration(labelText: l10n.llmModelName),
          ),
          const SizedBox(height: AppConstants.spaceL),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop(
                LlmProviderConfig.withPlainKey(
                  id: widget.existing?.id,
                  name: _name.text.trim().isEmpty ? 'LLM' : _name.text.trim(),
                  baseUrl: _baseUrl.text.trim(),
                  plainApiKey: _apiKey.text.trim(),
                  modelName: _model.text.trim(),
                  isDefault: widget.existing?.isDefault ?? false,
                ),
              );
            },
            child: Text(l10n.save),
          ),
        ],
      ),
    );
  }
}
