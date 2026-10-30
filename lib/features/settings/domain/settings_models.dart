import 'dart:convert';

class ApiConfig {
  const ApiConfig({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.model,
    this.isOpenAiCompatible = true,
    required this.keyRef,
    this.extraHeaders = const <String, String>{},
    this.maxTokens,
    this.temperature,
    this.topP,
    this.stream = true,
    this.isDefault = false,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;

  /// 例如 https://api.openai.com/v1（不带 /chat/completions）
  final String baseUrl;
  final String model;
  final bool isOpenAiCompatible;

  /// 指向安全存储中的键名，明文 Key 永不入库
  final String keyRef;
  final Map<String, String> extraHeaders;
  final int? maxTokens;
  final double? temperature;
  final double? topP;
  final bool stream;
  final bool isDefault;
  final int createdAt;
  final int updatedAt;

  String get chatCompletionsUrl {
    final base = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (base.endsWith('/chat/completions')) return base;
    return '$base/chat/completions';
  }

  factory ApiConfig.fromRow(Map<String, Object?> row) {
    Map<String, String> headers = const <String, String>{};
    final rawHeaders = row['extra_headers'] as String?;
    if (rawHeaders != null && rawHeaders.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawHeaders);
        if (decoded is Map) {
          headers = decoded.map(
            (k, v) => MapEntry(k.toString(), v.toString()),
          );
        }
      } catch (_) {
        // 非法 JSON 视为无额外头
      }
    }
    return ApiConfig(
      id: row['id']! as String,
      name: (row['name'] as String?) ?? '',
      baseUrl: (row['base_url'] as String?) ?? '',
      model: (row['model'] as String?) ?? '',
      isOpenAiCompatible: ((row['is_openai_compatible'] as int?) ?? 1) == 1,
      keyRef: (row['key_ref'] as String?) ?? '',
      extraHeaders: headers,
      maxTokens: row['max_tokens'] as int?,
      temperature: (row['temperature'] as num?)?.toDouble(),
      topP: (row['top_p'] as num?)?.toDouble(),
      stream: ((row['stream'] as int?) ?? 1) == 1,
      isDefault: ((row['is_default'] as int?) ?? 0) == 1,
      createdAt: (row['created_at'] as int?) ?? 0,
      updatedAt: (row['updated_at'] as int?) ?? 0,
    );
  }

  Map<String, Object?> toRow() => <String, Object?>{
        'id': id,
        'name': name,
        'base_url': baseUrl,
        'model': model,
        'is_openai_compatible': isOpenAiCompatible ? 1 : 0,
        'key_ref': keyRef,
        'extra_headers': jsonEncode(extraHeaders),
        'max_tokens': maxTokens,
        'temperature': temperature,
        'top_p': topP,
        'stream': stream ? 1 : 0,
        'is_default': isDefault ? 1 : 0,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  ApiConfig copyWith({
    String? name,
    String? baseUrl,
    String? model,
    bool? isOpenAiCompatible,
    String? keyRef,
    Map<String, String>? extraHeaders,
    int? maxTokens,
    double? temperature,
    double? topP,
    bool? stream,
    bool? isDefault,
    int? updatedAt,
  }) =>
      ApiConfig(
        id: id,
        name: name ?? this.name,
        baseUrl: baseUrl ?? this.baseUrl,
        model: model ?? this.model,
        isOpenAiCompatible: isOpenAiCompatible ?? this.isOpenAiCompatible,
        keyRef: keyRef ?? this.keyRef,
        extraHeaders: extraHeaders ?? this.extraHeaders,
        maxTokens: maxTokens ?? this.maxTokens,
        temperature: temperature ?? this.temperature,
        topP: topP ?? this.topP,
        stream: stream ?? this.stream,
        isDefault: isDefault ?? this.isDefault,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}

class ModelPricing {
  const ModelPricing({
    required this.id,
    required this.modelPattern,
    required this.inputPer1M,
    required this.outputPer1M,
    this.currency = 'USD',
    required this.updatedAt,
  });

  final String id;

  /// 支持通配：`gpt-4o*`、`*mini*`
  final String modelPattern;

  /// 微单位 / 1M token
  final int inputPer1M;
  final int outputPer1M;
  final String currency;
  final int updatedAt;

  bool matches(String model) {
    final pattern = modelPattern.trim().toLowerCase();
    if (pattern.isEmpty) return false;
    final target = model.trim().toLowerCase();
    if (!pattern.contains('*')) return pattern == target;
    final regex = RegExp(
      '^${pattern.split('*').map(RegExp.escape).join('.*')}\$',
    );
    return regex.hasMatch(target);
  }

  factory ModelPricing.fromRow(Map<String, Object?> row) => ModelPricing(
        id: row['id']! as String,
        modelPattern: (row['model_pattern'] as String?) ?? '',
        inputPer1M: (row['input_per_1m'] as int?) ?? 0,
        outputPer1M: (row['output_per_1m'] as int?) ?? 0,
        currency: (row['currency'] as String?) ?? 'USD',
        updatedAt: (row['updated_at'] as int?) ?? 0,
      );

  Map<String, Object?> toRow() => <String, Object?>{
        'id': id,
        'model_pattern': modelPattern,
        'input_per_1m': inputPer1M,
        'output_per_1m': outputPer1M,
        'currency': currency,
        'updated_at': updatedAt,
      };
}

/// 设置项 key 常量，避免字符串散落
class SettingKeys {
  static const themeMode = 'theme_mode';
  static const themeAccent = 'theme_accent';
  static const themeSpot = 'theme_spot';
  static const navOrder = 'nav_order';
  static const defaultApiConfigId = 'default_api_config_id';
  static const contextLimit = 'context_limit';
  static const temperature = 'temperature';
  static const topP = 'top_p';
  static const streamEnabled = 'stream_enabled';
  static const charsPerToken = 'chars_per_token';
  static const outputRatio = 'output_ratio';
  static const editorDraft = 'editor_draft';
  static const libraryViewMode = 'library_view_mode';

  /// 全局系统提示词（回复风格层）。空串 = 使用内置默认风格。
  static const systemPrompt = 'system_prompt';

  /// 是否已通过「关于页连点软件名」解锁成人向设置分区。
  static const nsfwUnlocked = 'nsfw_unlocked';

  /// 成人向提示词是否启用（仅在已解锁时可改）。
  static const nsfwEnabled = 'nsfw_enabled';

  /// 单次回复的总字数上限（0 = 不限制）。
  static const maxReplyLength = 'max_reply_length';

  /// 叙述视角：character（角色扮演第一人称）/ author（作者第三人称全知）。
  static const narrativeMode = 'narrative_mode';
}

class AppSettings {
  const AppSettings({
    this.themeMode = 'system',
    this.themeAccent = '',
    this.themeSpot = '',
    this.navOrder = const <String>['characters', 'stats', 'editor', 'settings'],
    this.defaultApiConfigId,
    this.contextLimit = 4096,
    this.temperature = 0.9,
    this.topP = 1.0,
    this.streamEnabled = true,
    this.charsPerToken = 3.0,
    this.outputRatio = 1.0,
    this.libraryViewMode = 'grid',
    this.systemPrompt = '',
    this.nsfwUnlocked = false,
    this.nsfwEnabled = false,
    this.maxReplyLength = 300,
    this.narrativeMode = 'character',
  });

  final String themeMode;

  /// 主题色（十六进制，如 #7FBEE8）；空串 = 默认淡蓝
  final String themeAccent;

  /// 点缀色（十六进制，如 #E879A9）；空串 = 默认粉红
  final String themeSpot;

  final List<String> navOrder;
  final String? defaultApiConfigId;
  final int contextLimit;
  final double temperature;
  final double topP;
  final bool streamEnabled;

  /// 估算规则：平均多少字符 ≈ 1 token（中英混排经验值 2.5~4）
  final double charsPerToken;

  /// 无 usage 时按输入 token × 该比例估算输出
  final double outputRatio;
  final String libraryViewMode;

  /// 全局系统提示词（回复风格层）。空串 = 用内置默认风格；
  /// 卡片自己的 system_prompt 优先于这里。
  final String systemPrompt;

  /// 是否已解锁成人向分区（关于页连点软件名后置 true）
  final bool nsfwUnlocked;

  /// 成人向提示词是否启用
  final bool nsfwEnabled;

  /// 单次回复的总字数上限（0 = 不限制）
  final int maxReplyLength;

  /// 叙述视角：'character' = 角色扮演第一人称；'author' = 作者第三人称全知
  final String narrativeMode;

  AppSettings copyWith({
    String? themeMode,
    String? themeAccent,
    String? themeSpot,
    List<String>? navOrder,
    String? defaultApiConfigId,
    int? contextLimit,
    double? temperature,
    double? topP,
    bool? streamEnabled,
    double? charsPerToken,
    double? outputRatio,
    String? libraryViewMode,
    String? systemPrompt,
    bool? nsfwUnlocked,
    bool? nsfwEnabled,
    int? maxReplyLength,
    String? narrativeMode,
  }) =>
      AppSettings(
        themeMode: themeMode ?? this.themeMode,
        themeAccent: themeAccent ?? this.themeAccent,
        themeSpot: themeSpot ?? this.themeSpot,
        navOrder: navOrder ?? this.navOrder,
        defaultApiConfigId: defaultApiConfigId ?? this.defaultApiConfigId,
        contextLimit: contextLimit ?? this.contextLimit,
        temperature: temperature ?? this.temperature,
        topP: topP ?? this.topP,
        streamEnabled: streamEnabled ?? this.streamEnabled,
        charsPerToken: charsPerToken ?? this.charsPerToken,
        outputRatio: outputRatio ?? this.outputRatio,
        libraryViewMode: libraryViewMode ?? this.libraryViewMode,
        systemPrompt: systemPrompt ?? this.systemPrompt,
        nsfwUnlocked: nsfwUnlocked ?? this.nsfwUnlocked,
        nsfwEnabled: nsfwEnabled ?? this.nsfwEnabled,
        maxReplyLength: maxReplyLength ?? this.maxReplyLength,
        narrativeMode: narrativeMode ?? this.narrativeMode,
      );
}
