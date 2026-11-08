import 'dart:convert';

import 'world_entry.dart';

/// 状态栏输出格式：[statusFormatJson] 为旧的 JSON 协议，
/// [statusFormatTemplate] 为「幻梦」式的文本块（模型按行输出 `键：值`）。
const String statusFormatJson = 'json';
const String statusFormatTemplate = 'template';

/// 角色卡领域模型。字段命名对齐 SillyTavern Character Card V2 规范。
class CharacterCard {
  const CharacterCard({
    required this.id,
    required this.name,
    this.summary = '',
    this.description = '',
    this.personality = '',
    this.scenario = '',
    this.firstMes = '',
    this.mesExample = '',
    this.systemPrompt = '',
    this.postHistoryInstructions = '',
    this.creator = '',
    this.cardVersion = '',
    this.avatarPath,
    this.source = 'manual',
    this.spec = 'v2',
    this.rawJson,
    required this.createdAt,
    required this.updatedAt,
    this.lastChatAt,
    this.tags = const <String>[],
    this.alternateGreetings = const <String>[],
    this.statusEnabled = false,
    this.statusInitial = const <String, dynamic>{},
    this.statusRules = '',
    this.statusTemplate = '',
    this.statusFormat = statusFormatTemplate,
    this.worldBook = const <WorldEntry>[],
  });

  final String id;
  final String name;

  /// 列表/卡库展示用的简介，与 [description]（人设正文）分开
  final String summary;
  final String description;
  final String personality;
  final String scenario;
  final String firstMes;
  final String mesExample;
  final String systemPrompt;
  final String postHistoryInstructions;
  final String creator;
  final String cardVersion;

  /// 相对路径，如 `avatars/<id>.png`。绝对路径在 iOS 沙盒迁移后会失效，故不存。
  final String? avatarPath;
  final String source;
  final String spec;

  /// 原始 JSON 里未被识别的扩展字段，导出时回填，保证 round-trip 不丢数据。
  final String? rawJson;
  final int createdAt;
  final int updatedAt;
  final int? lastChatAt;

  final List<String> tags;
  final List<String> alternateGreetings;

  /// ── 状态栏 ──
  /// 是否启用状态栏（启用后会在提示词里注入协议，并在对话页展示面板）
  final bool statusEnabled;

  /// 初始状态键值，如 {"好感度": 0, "时间": "清晨"}
  final Map<String, dynamic> statusInitial;

  /// 状态更新规则（自然语言，交给模型遵守）
  final String statusRules;

  /// 展示模板，支持 {{键}} 占位符；留空则自动按键值列表展示
  final String statusTemplate;

  /// 状态栏输出格式：json / template
  final String statusFormat;

  /// 世界书：常驻 + 关键词条目
  final List<WorldEntry> worldBook;


  /// 开场白总数（含主开场白）
  int get greetingCount => (firstMes.isEmpty ? 0 : 1) + alternateGreetings.length;

  /// index 0 为主开场白，其余对应 alternate_greetings
  String greetingAt(int index) {
    if (index <= 0) return firstMes;
    final i = index - 1;
    if (i < alternateGreetings.length) return alternateGreetings[i];
    return firstMes;
  }

  List<String> get allGreetings => <String>[
        if (firstMes.isNotEmpty) firstMes,
        ...alternateGreetings,
      ];

  /// 列表页简介：优先简介字段，退化为 description，再退化为 personality
  String get previewText {
    final text = summary.trim().isNotEmpty
        ? summary
        : (description.trim().isNotEmpty ? description : personality);
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static Map<String, dynamic> _decodeMap(Object? raw) {
    if (raw is! String || raw.trim().isEmpty) return const <String, dynamic>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return <String, dynamic>{
          for (final e in decoded.entries) e.key.toString(): e.value,
        };
      }
    } catch (_) {
      // 数据损坏时按空处理，不影响卡片可用
    }
    return const <String, dynamic>{};
  }

  /// 序列化为 JSON 字符串（写库用）
  static String encodeMap(Map<String, dynamic> map) => jsonEncode(map);

  factory CharacterCard.fromRow(
    Map<String, Object?> row, {
    List<String> tags = const <String>[],
    List<String> alternateGreetings = const <String>[],
  }) {
    return CharacterCard(
      id: row['id']! as String,
      name: (row['name'] as String?) ?? '',
      summary: (row['summary'] as String?) ?? '',
      description: (row['description'] as String?) ?? '',
      personality: (row['personality'] as String?) ?? '',
      scenario: (row['scenario'] as String?) ?? '',
      firstMes: (row['first_mes'] as String?) ?? '',
      mesExample: (row['mes_example'] as String?) ?? '',
      systemPrompt: (row['system_prompt'] as String?) ?? '',
      postHistoryInstructions:
          (row['post_history_instructions'] as String?) ?? '',
      creator: (row['creator'] as String?) ?? '',
      cardVersion: (row['card_version'] as String?) ?? '',
      avatarPath: row['avatar_path'] as String?,
      source: (row['source'] as String?) ?? 'manual',
      spec: (row['spec'] as String?) ?? 'v2',
      rawJson: row['raw_json'] as String?,
      createdAt: (row['created_at'] as int?) ?? 0,
      updatedAt: (row['updated_at'] as int?) ?? 0,
      lastChatAt: row['last_chat_at'] as int?,
      tags: tags,
      alternateGreetings: alternateGreetings,
      statusEnabled: ((row['status_enabled'] as int?) ?? 0) == 1,
      statusInitial: _decodeMap(row['status_initial']),
      statusRules: (row['status_rules'] as String?) ?? '',
      statusTemplate: (row['status_template'] as String?) ?? '',
      statusFormat: (row['status_format'] as String?) ?? statusFormatTemplate,
      worldBook: WorldEntry.decodeList(row['world_book']),
    );
  }

  Map<String, Object?> toRow() => <String, Object?>{
        'id': id,
        'name': name,
        'summary': summary,
        'description': description,
        'personality': personality,
        'scenario': scenario,
        'first_mes': firstMes,
        'mes_example': mesExample,
        'system_prompt': systemPrompt,
        'post_history_instructions': postHistoryInstructions,
        'creator': creator,
        'card_version': cardVersion,
        'avatar_path': avatarPath,
        'source': source,
        'spec': spec,
        'raw_json': rawJson,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'last_chat_at': lastChatAt,
        'status_format': statusFormat,
        'world_book': WorldEntry.encodeList(worldBook),
      };

  /// 导出为 Character Card V2 结构
  /// [extraExtensions] 用于导出时临时塞入不属于角色设定的数据
  /// （比如每张卡的生成参数 `silas_generation`），不改卡片结构。
  Map<String, dynamic> toTavernJson({Map<String, dynamic>? extraExtensions}) {
    Map<String, dynamic> extensions = <String, dynamic>{};
    if (rawJson != null && rawJson!.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawJson!);
        // v2 文档是 {spec, data:{extensions}}，v1 是扁平的 {extensions}
        if (decoded is Map) {
          final nested = decoded['data'];
          final raw = (nested is Map && nested['extensions'] is Map)
              ? nested['extensions']
              : decoded['extensions'];
          if (raw is Map) {
            extensions = Map<String, dynamic>.from(raw);
          }
        }
      } catch (_) {
        // 原始 JSON 损坏时忽略，不影响导出
      }
    }
    if (worldBook.isNotEmpty) {
      extensions['world_book'] = worldBook.map((e) => e.toJson()).toList();
    }
    if (statusEnabled) {
      extensions['dsh_status'] = <String, dynamic>{
        'format': statusFormat,
        'initial': statusInitial,
        'rules': statusRules,
        'template': statusTemplate,
      };
    }
    if (summary.trim().isNotEmpty) {
      extensions['dsh_summary'] = summary;
    }
    if (extraExtensions != null && extraExtensions.isNotEmpty) {
      extensions.addAll(extraExtensions);
    }
    return <String, dynamic>{
      'spec': 'chara_card_v2',
      'spec_version': '2.0',
      'data': <String, dynamic>{
        'name': name,
        'description': description,
        'personality': personality,
        'scenario': scenario,
        'first_mes': firstMes,
        'mes_example': mesExample,
        'system_prompt': systemPrompt,
        'post_history_instructions': postHistoryInstructions,
        'creator': creator,
        'character_version': cardVersion,
        'alternate_greetings': alternateGreetings,
        'tags': tags,
        'extensions': extensions,
      },
    };
  }

  CharacterCard copyWith({
    String? id,
    String? name,
    String? summary,
    String? description,
    String? personality,
    String? scenario,
    String? firstMes,
    String? mesExample,
    String? systemPrompt,
    String? postHistoryInstructions,
    String? creator,
    String? cardVersion,
    String? avatarPath,
    String? source,
    String? spec,
    String? rawJson,
    int? createdAt,
    int? updatedAt,
    int? lastChatAt,
    List<String>? tags,
    List<String>? alternateGreetings,
    bool? statusEnabled,
    Map<String, dynamic>? statusInitial,
    String? statusRules,
    String? statusTemplate,
    String? statusFormat,
    List<WorldEntry>? worldBook,
  }) {
    return CharacterCard(
      id: id ?? this.id,
      name: name ?? this.name,
      summary: summary ?? this.summary,
      description: description ?? this.description,
      personality: personality ?? this.personality,
      scenario: scenario ?? this.scenario,
      firstMes: firstMes ?? this.firstMes,
      mesExample: mesExample ?? this.mesExample,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      postHistoryInstructions:
          postHistoryInstructions ?? this.postHistoryInstructions,
      creator: creator ?? this.creator,
      cardVersion: cardVersion ?? this.cardVersion,
      avatarPath: avatarPath ?? this.avatarPath,
      source: source ?? this.source,
      spec: spec ?? this.spec,
      rawJson: rawJson ?? this.rawJson,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastChatAt: lastChatAt ?? this.lastChatAt,
      tags: tags ?? this.tags,
      alternateGreetings: alternateGreetings ?? this.alternateGreetings,
      statusEnabled: statusEnabled ?? this.statusEnabled,
      statusInitial: statusInitial ?? this.statusInitial,
      statusRules: statusRules ?? this.statusRules,
      statusTemplate: statusTemplate ?? this.statusTemplate,
      statusFormat: statusFormat ?? this.statusFormat,
      worldBook: worldBook ?? this.worldBook,
    );
  }
}

