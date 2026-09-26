import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:schedule_plan/core/error/app_exceptions.dart';
import 'package:schedule_plan/core/logging/app_logger.dart';
import 'package:schedule_plan/data/models/llm_provider_config.dart';
import 'package:schedule_plan/data/models/note.dart';

/// LLM 调用（readme 模块五 5.2 / 依赖清单 http 或 dio）。
///
/// 支持 OpenAI 兼容接口与 Anthropic 接口，API Key 由用户在设置中填写并混淆存储。
class LlmService {
  LlmService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const Duration _timeout = Duration(seconds: 60);

  /// 根据指令对选中文本做扩写 / 润色 / 总结，返回模型输出。
  Future<String> write({
    required LlmProviderConfig provider,
    required AiWritingAction action,
    required String text,
  }) async {
    if (provider.apiKey.isEmpty) {
      throw const AppException('未配置 API Key，请先在设置中填写');
    }
    final instruction = _instructionOf(action);
    try {
      if (_isAnthropic(provider)) {
        return await _callAnthropic(provider, instruction, text);
      }
      return await _callOpenAiCompatible(provider, instruction, text);
    } catch (error, stack) {
      AppLogger.e('调用 LLM 失败', error: error, stack: stack);
      if (error is AppException) {
        rethrow;
      }
      throw AppException('调用大模型接口失败：$error', cause: error);
    }
  }

  bool _isAnthropic(LlmProviderConfig provider) =>
      provider.baseUrl.toLowerCase().contains('anthropic') ||
      provider.name.toLowerCase().contains('anthropic');

  String _instructionOf(AiWritingAction action) => switch (action) {
        AiWritingAction.expand => '请对下面的内容进行扩写，保持原意并补充细节：',
        AiWritingAction.polish => '请对下面的内容进行润色，使表达更通顺专业，不要改变事实：',
        AiWritingAction.summarize => '请对下面的内容进行总结，输出要点列表：',
      };

  Future<String> _callOpenAiCompatible(
    LlmProviderConfig provider,
    String instruction,
    String text,
  ) async {
    final uri = _buildUri(provider, 'chat/completions');
    final response = await _client
        .post(
          uri,
          headers: <String, String>{
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${provider.apiKey}',
          },
          body: jsonEncode(<String, Object?>{
            'model': provider.modelName,
            'messages': <Map<String, String>>[
              <String, String>{'role': 'system', 'content': instruction},
              <String, String>{'role': 'user', 'content': text},
            ],
            'temperature': 0.7,
          }),
        )
        .timeout(_timeout);
    _checkStatus(response);
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final choices = decoded['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty) {
      throw const AppException('大模型返回内容为空');
    }
    final message = (choices.first as Map<String, dynamic>)['message']
        as Map<String, dynamic>?;
    final content = message?['content'] as String?;
    if (content == null) {
      throw const AppException('大模型返回内容格式异常');
    }
    return content.trim();
  }

  Future<String> _callAnthropic(
    LlmProviderConfig provider,
    String instruction,
    String text,
  ) async {
    final uri = _buildUri(provider, 'messages');
    final response = await _client
        .post(
          uri,
          headers: <String, String>{
            'Content-Type': 'application/json',
            'x-api-key': provider.apiKey,
            'anthropic-version': '2023-06-01',
          },
          body: jsonEncode(<String, Object?>{
            'model': provider.modelName,
            'max_tokens': 2048,
            'system': instruction,
            'messages': <Map<String, String>>[
              <String, String>{'role': 'user', 'content': text},
            ],
          }),
        )
        .timeout(_timeout);
    _checkStatus(response);
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final contentList = decoded['content'] as List<dynamic>?;
    if (contentList == null || contentList.isEmpty) {
      throw const AppException('大模型返回内容为空');
    }
    final first = contentList.first as Map<String, dynamic>;
    final text0 = first['text'] as String?;
    if (text0 == null) {
      throw const AppException('大模型返回内容格式异常');
    }
    return text0.trim();
  }

  Uri _buildUri(LlmProviderConfig provider, String path) {
    var base = provider.baseUrl.trim();
    if (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    if (!base.startsWith('http')) {
      base = 'https://$base';
    }
    if (base.endsWith(path)) {
      return Uri.parse(base);
    }
    return Uri.parse('$base/$path');
  }

  void _checkStatus(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AppException(
        '大模型接口返回 ${response.statusCode}：${response.body}',
      );
    }
  }

  void dispose() => _client.close();
}
