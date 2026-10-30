import 'dart:convert';
import 'dart:typed_data';

import '../../../core/utils/ids.dart';
import '../../../core/utils/time_utils.dart';
import '../domain/character_card.dart';
import '../domain/world_entry.dart';
import 'png_codec.dart';

class ImportedCard {
  const ImportedCard({required this.card, this.avatarBytes});
  final CharacterCard card;
  final Uint8List? avatarBytes;
}

/// 导入来源：普通模式走通用（酒馆）卡，高级模式走幻梦卡
enum CardImportFlavor {
  /// 自动：幻梦字段优先，缺失的用通用字段补齐（数据管理页的通用导入用）
  auto,

  /// 通用卡：Character Card V1/V2/V3，只看标准字段
  tavern,

  /// 幻梦卡：优先读 cus_data / role 里的私有配置
  huanmeng,
}

/// SillyTavern 角色卡导入。
///
/// 支持三种来源：
/// 1. PNG 内嵌 tEXt（keyword = `chara` / `ccv3`，内容为 base64 JSON）
/// 2. Character Card V2 / V3 JSON
/// 3. 更早的扁平 JSON（char_name / char_persona 等）
///
/// 幻梦导出的卡同样放在 PNG 里，但真正的设定在 `cus_data`；
/// 用 [CardImportFlavor.huanmeng] 时优先按幻梦字段解析。
class CardImportService {
  const CardImportService();

  ImportedCard? fromBytes(
    Uint8List bytes, {
    CardImportFlavor flavor = CardImportFlavor.auto,
  }) {
    if (PngCodec.isPng(bytes)) return fromPng(bytes, flavor: flavor);
    try {
      return fromJsonString(utf8.decode(bytes, allowMalformed: true),
          flavor: flavor);
    } catch (_) {
      return null;
    }
  }

  ImportedCard? fromPng(
    Uint8List bytes, {
    CardImportFlavor flavor = CardImportFlavor.auto,
  }) {
    final texts = PngCodec.readTextChunks(bytes);
    for (final key in const <String>['ccv3', 'chara', 'Chara']) {
      final raw = texts[key];
      if (raw == null || raw.trim().isEmpty) continue;
      final json = _decodeEmbedded(raw);
      if (json == null) continue;
      return ImportedCard(
        card: _build(json, source: 'png', hasAvatar: true, flavor: flavor),
        avatarBytes: bytes,
      );
    }
    return null;
  }

  ImportedCard? fromJsonString(
    String text, {
    CardImportFlavor flavor = CardImportFlavor.auto,
  }) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    Object? decoded;
    try {
      decoded = jsonDecode(trimmed);
    } catch (_) {
      // 有些导出把 JSON 又 base64 了一层
      decoded = _decodeEmbedded(trimmed);
    }
    if (decoded is List) return null;
    if (decoded is! Map) return null;
    return ImportedCard(
      card: _build(
        Map<String, dynamic>.from(decoded),
        source: 'json',
        flavor: flavor,
      ),
    );
  }

  /// 一次导入多个：JSON 数组或单个对象都兼容
  List<ImportedCard> fromJsonArrayString(
    String text, {
    CardImportFlavor flavor = CardImportFlavor.auto,
  }) {
    final trimmed = text.trim();
    Object? decoded;
    try {
      decoded = jsonDecode(trimmed);
    } catch (_) {
      return const <ImportedCard>[];
    }
    if (decoded is List) {
      final result = <ImportedCard>[];
      for (final item in decoded) {
        if (item is Map) {
          result.add(ImportedCard(
            card: _build(
              Map<String, dynamic>.from(item),
              source: 'json',
              flavor: flavor,
            ),
          ));
        }
      }
      return result;
    }
    if (decoded is Map) {
      final single = fromJsonString(trimmed, flavor: flavor);
      return single == null ? const <ImportedCard>[] : <ImportedCard>[single];
    }
    return const <ImportedCard>[];
  }

  Map<String, dynamic>? _decodeEmbedded(String raw) {
    final text = raw.trim();
    // 先当作纯 JSON
    if (text.startsWith('{')) {
      try {
        final decoded = jsonDecode(text);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {
        // 继续尝试 base64
      }
    }
    try {
      var normalized = text.replaceAll(RegExp(r'\s'), '');
      normalized = normalized.replaceAll('-', '+').replaceAll('_', '/');
      final padding = normalized.length % 4;
      if (padding != 0) normalized = normalized.padRight(normalized.length + 4 - padding, '=');
      final bytes = base64.decode(normalized);
      final decoded = jsonDecode(utf8.decode(bytes, allowMalformed: true));
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      return null;
    }
    return null;
  }

  CharacterCard _build(
    Map<String, dynamic> json, {
    required String source,
    bool hasAvatar = false,
    CardImportFlavor flavor = CardImportFlavor.auto,
  }) {
    final spec = (json['spec'] as String?) ?? '';
    final data = (json['data'] is Map)
        ? Map<String, dynamic>.from(json['data'] as Map)
        : json;
    final isV2 = spec.contains('v2') || spec.contains('v3') || json['data'] is Map;

    // 幻梦的私有配置：PNG/JSON 里塞在 cus_data，接口导出时包在 role/role_data 里。
    // 通用卡模式刻意忽略它，只认标准字段。
    final conf = flavor != CardImportFlavor.tavern
        ? _huanmengConfig(json, data)
        : const <String, dynamic>{};

    final name = _firstNonEmpty(<String>[
      _firstString(data, const ['name', 'char_name', 'charName']),
      _firstString(conf, const ['name', 'role_name']),
    ]).trim();
    final now = nowMs();

    final extensions = (data['extensions'] is Map)
        ? Map<String, dynamic>.from(data['extensions'] as Map)
        : const <String, dynamic>{};
    final status = (extensions['dsh_status'] is Map)
        ? Map<String, dynamic>.from(extensions['dsh_status'] as Map)
        : const <String, dynamic>{};
    final statusInitial = (status['initial'] is Map)
        ? <String, dynamic>{
            for (final e in (status['initial'] as Map).entries)
              e.key.toString(): e.value,
          }
        : const <String, dynamic>{};

    final statusFromHuanmeng = conf['statusBlockEnable'] == true;
    var statusEnabled = status.isNotEmpty || statusFromHuanmeng;
    var statusFormat = (status['format'] as String?) ?? statusFormatTemplate;
    var statusRules = (status['rules'] as String?) ?? '';
    var statusTemplate = (status['template'] as String?) ?? '';
    var initial = statusInitial;
    if (status.isEmpty && statusFromHuanmeng) {
      initial = _parseStatusLines(_firstString(conf, const ['status_block_init']));
      statusTemplate = _braceTemplate(_firstString(conf, const ['status_block']));
      statusRules = _firstString(conf, const ['status_block_rule']);
    }

    final firstMes = _firstNonEmpty(<String>[
      _firstSceneMessage(conf),
      _firstString(conf, const ['first_message']),
      _firstString(data, const ['first_mes', 'char_greeting', 'greeting']),
    ]);
    final alternateGreetings = <String>[
      ..._extraSceneMessages(conf),
      ..._stringList(data['alternate_greetings']),
    ];

    final card = CharacterCard(
      id: newId(),
      name: name.isEmpty ? '未命名角色' : name,
      summary: _firstNonEmpty(<String>[
        (extensions['dsh_summary'] as String?) ?? '',
        _firstString(conf, const ['introduction', 'simple_intro']),
      ]),
      description: _firstNonEmpty(<String>[
        _firstString(data, const ['description', 'char_persona', 'persona']),
        _firstString(conf, const ['description']),
      ]),
      personality: _firstNonEmpty(<String>[
        _firstString(data, const ['personality', 'char_personality']),
        _firstString(conf, const ['personality']),
      ]),
      scenario: _firstNonEmpty(<String>[
        _firstString(data, const ['scenario', 'world_scenario']),
        _firstString(conf, const ['scenario']),
      ]),
      firstMes: firstMes,
      mesExample: _firstNonEmpty(<String>[
        _firstString(data, const ['mes_example', 'example_dialogue']),
        _firstString(conf, const ['example_dialog']),
        _examplesFromPairs(conf),
      ]),
      systemPrompt: _firstString(data, const ['system_prompt', 'systemPrompt']),
      postHistoryInstructions: _firstString(
        data,
        const ['post_history_instructions', 'postHistoryInstructions'],
      ),
      creator: _firstString(data, const ['creator', 'created_by']),
      cardVersion: _firstString(data, const ['character_version', 'characterVersion']),
      source: source,
      spec: isV2 ? 'v2' : 'v1',
      rawJson: jsonEncode(json),
      createdAt: now,
      updatedAt: now,
      tags: <String>{
        ..._stringList(data['tags']),
        ..._stringList(conf['sub_tags']),
        ..._stringList(conf['tags']),
      }.toList(),
      alternateGreetings: alternateGreetings
          .where((e) => e.trim().isNotEmpty)
          .toSet()
          .toList(),
      worldBook: _worldEntriesFrom(conf, data, extensions),
      statusEnabled: statusEnabled,
      statusFormat: statusFormat,
      statusInitial: initial,
      statusRules: statusRules,
      statusTemplate: statusTemplate,
    );
    return card;
  }

  /// 幻梦配置块：优先 cus_data，其次接口导出的 role / role_data
  static Map<String, dynamic> _huanmengConfig(
    Map<String, dynamic> json,
    Map<String, dynamic> data,
  ) {
    for (final candidate in <Object?>[
      data['cus_data'],
      json['cus_data'],
      json['role'],
      json['role_data'],
      data['role'],
    ]) {
      if (candidate is Map) {
        return Map<String, dynamic>.from(candidate);
      }
    }
    return const <String, dynamic>{};
  }

  static List<WorldEntry> _worldEntriesFrom(
    Map<String, dynamic> conf,
    Map<String, dynamic> data,
    Map<String, dynamic> extensions,
  ) {
    final own = WorldEntry.decodeList(extensions['world_book']);
    if (own.isNotEmpty) return own;

    List<dynamic>? entries;
    final book = conf['role_book'];
    if (book is Map && book['entries'] is List) {
      entries = book['entries'] as List<dynamic>;
    } else if (data['character_book'] is Map &&
        (data['character_book'] as Map)['entries'] is List) {
      entries = (data['character_book'] as Map)['entries'] as List<dynamic>;
    }
    if (entries == null) return const <WorldEntry>[];

    final result = <WorldEntry>[];
    for (var i = 0; i < entries.length; i++) {
      final raw = entries[i];
      if (raw is! Map) continue;
      final entry = Map<String, dynamic>.from(raw);
      final ext = entry['extensions'] is Map
          ? Map<String, dynamic>.from(entry['extensions'] as Map)
          : const <String, dynamic>{};
      final keys = entry['keys'] ?? entry['key'] ?? entry['keywords'];
      final keywords = keys is List
          ? keys.map((e) => e.toString()).join(',')
          : (keys?.toString() ?? '');
      final content = _firstString(entry, const ['content']);
      if (content.trim().isEmpty) continue;
      result.add(
        WorldEntry(
          id: 'import_${DateTime.now().microsecondsSinceEpoch}_$i',
          enabled: entry['enabled'] != false,
          kind: entry['constant'] == true
              ? WorldEntryKind.constant
              : WorldEntryKind.keyword,
          comment: _firstString(entry, const ['comment', 'name']),
          keywords: keywords,
          insertionOrder: (entry['insertion_order'] as num?)?.toInt() ?? 100,
          probability:
              ((ext['probability'] ?? entry['probability']) as num?)?.toInt() ??
                  100,
          content: content,
        ),
      );
    }
    return result;
  }

  /// 场景数组里的第一条开场白
  static String _firstSceneMessage(Map<String, dynamic> conf) {
    final scenes = conf['muilte_scenes'];
    if (scenes is List) {
      for (final scene in scenes) {
        if (scene is Map) {
          final text = _firstString(
            Map<String, dynamic>.from(scene),
            const ['first_message'],
          );
          if (text.trim().isNotEmpty) return text;
        }
      }
    }
    return '';
  }

  /// 其余场景的开场白 → 备选开场白
  static List<String> _extraSceneMessages(Map<String, dynamic> conf) {
    final scenes = conf['muilte_scenes'];
    if (scenes is! List) return const <String>[];
    final all = <String>[];
    for (final scene in scenes) {
      if (scene is Map) {
        final text = _firstString(
          Map<String, dynamic>.from(scene),
          const ['first_message'],
        );
        if (text.trim().isNotEmpty) all.add(text);
      }
    }
    return all.length <= 1 ? const <String>[] : all.sublist(1);
  }

  /// 幻梦的对话示例是 user/char 成对的数组
  static String _examplesFromPairs(Map<String, dynamic> conf) {
    final list = conf['muilte_examples'] ?? conf['muilte_exapmles'];
    if (list is! List || list.isEmpty) return '';
    final buffer = StringBuffer();
    for (final item in list) {
      if (item is! Map) continue;
      final user = _firstString(Map<String, dynamic>.from(item), const ['user']);
      final char = _firstString(Map<String, dynamic>.from(item), const ['char']);
      if (user.trim().isEmpty && char.trim().isEmpty) continue;
      if (buffer.isNotEmpty) buffer.writeln('<START>');
      if (user.trim().isNotEmpty) buffer.writeln('{{user}}: $user');
      if (char.trim().isNotEmpty) buffer.writeln('{{char}}: $char');
    }
    return buffer.toString().trim();
  }

  /// `键：值` 纯文本 → 状态初始值（允许值为空）
  static Map<String, dynamic> _parseStatusLines(String text) {
    final result = <String, dynamic>{};
    for (final raw in text.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      final idx = line.indexOf(RegExp(r'[：:]'));
      if (idx <= 0) continue;
      final key = line.substring(0, idx).trim();
      final value = line.substring(idx + 1).trim();
      if (key.isEmpty) continue;
      result[key] = value;
    }
    return result;
  }

  /// 幻梦状态模板用单花括号 `{键}`，这里转成本地渲染器的 `{{键}}`
  static String _braceTemplate(String text) {
    if (text.trim().isEmpty) return '';
    return text.replaceAllMapped(
      RegExp(r'\{([^{}\n]{1,24})\}'),
      (m) => '{{${m.group(1)}}}',
    );
  }

  static String _firstNonEmpty(List<String> values) {
    for (final value in values) {
      if (value.trim().isNotEmpty) return value;
    }
    return values.isEmpty ? '' : values.first;
  }

  static String _firstString(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value is String && value.trim().isNotEmpty) return value;
    }
    return '';
  }

  static List<String> _stringList(Object? value) {
    if (value is List) {
      return value
          .whereType<Object>()
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    if (value is String && value.trim().isNotEmpty) {
      return value
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    return const <String>[];
  }
}

