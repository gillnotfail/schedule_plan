import 'package:schedule_plan/core/utils/secret_box.dart';

/// LLM 提供商配置（readme 3.14 表 llm_provider_config，模块五 5.2）。
///
/// api_key_encrypted：本地加密存储，不明文落盘。
class LlmProviderConfig {
  const LlmProviderConfig({
    this.id,
    required this.name,
    required this.baseUrl,
    required this.apiKeyEncrypted,
    required this.modelName,
    this.isDefault = false,
  });

  final int? id;

  /// 展示名，如「OpenAI 兼容」「Anthropic」
  final String name;
  final String baseUrl;
  final String apiKeyEncrypted;
  final String modelName;
  final bool isDefault;

  /// 读取明文密钥（仅内存中使用，不落盘）。
  String get apiKey => apiKeyEncrypted.isEmpty ? '' : SecretBox.reveal(apiKeyEncrypted);

  LlmProviderConfig copyWith({
    int? id,
    String? name,
    String? baseUrl,
    String? apiKeyEncrypted,
    String? modelName,
    bool? isDefault,
  }) {
    return LlmProviderConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      baseUrl: baseUrl ?? this.baseUrl,
      apiKeyEncrypted: apiKeyEncrypted ?? this.apiKeyEncrypted,
      modelName: modelName ?? this.modelName,
      isDefault: isDefault ?? this.isDefault,
    );
  }

  Map<String, Object?> toMap() => <String, Object?>{
        if (id != null) 'id': id,
        'name': name,
        'base_url': baseUrl,
        'api_key_encrypted': apiKeyEncrypted,
        'model_name': modelName,
        'is_default': isDefault ? 1 : 0,
      };

  static LlmProviderConfig fromMap(Map<String, Object?> map) => LlmProviderConfig(
        id: map['id'] as int?,
        name: map['name'] as String,
        baseUrl: map['base_url'] as String,
        apiKeyEncrypted: map['api_key_encrypted'] as String? ?? '',
        modelName: map['model_name'] as String,
        isDefault: (map['is_default'] as int? ?? 0) == 1,
      );

  /// 用明文密钥构造（写入前先混淆）。
  factory LlmProviderConfig.withPlainKey({
    int? id,
    required String name,
    required String baseUrl,
    required String plainApiKey,
    required String modelName,
    bool isDefault = false,
  }) {
    return LlmProviderConfig(
      id: id,
      name: name,
      baseUrl: baseUrl,
      apiKeyEncrypted: SecretBox.obfuscate(plainApiKey),
      modelName: modelName,
      isDefault: isDefault,
    );
  }
}
