import 'dart:convert';
import 'dart:typed_data';

import '../../../core/utils/ids.dart';
import '../../../core/utils/time_utils.dart';
import '../domain/character_card.dart';
import 'avatar_storage.dart';
import 'card_export_service.dart';
import 'card_generation_dao.dart';
import 'card_import_service.dart';
import 'character_dao.dart';

class ImportOutcome {
  const ImportOutcome({
    this.imported = 0,
    this.failed = 0,
    this.failures = const <String>[],
  });

  final int imported;
  final int failed;
  final List<String> failures;

  String get summary {
    if (imported == 0 && failed == 0) return '没有可导入的角色卡';
    if (failed == 0) return '成功导入 $imported 张角色卡';
    return '成功 $imported 张，失败 $failed 张';
  }
}

class CharacterRepository {
  CharacterRepository({
    required CharacterDao dao,
    required AvatarStorage avatars,
    CardGenerationDao? generation,
    CardImportService importer = const CardImportService(),
    CardExportService exporter = const CardExportService(),
  })  : _dao = dao,
        _avatars = avatars,
        _generation = generation,
        _importer = importer,
        _exporter = exporter;

  final CharacterDao _dao;
  final AvatarStorage _avatars;
  final CardGenerationDao? _generation;
  final CardImportService _importer;
  final CardExportService _exporter;

  /// 导出时把这张卡的生成参数塞进 extensions（不写进卡片结构，只在这里附加）
  Map<String, dynamic>? _generationExtension(CharacterCard card) {
    final gen = _generation?.byCard(card.id);
    if (gen == null || gen.isEmpty) return null;
    return <String, dynamic>{
      'silas_generation': <String, dynamic>{
        if (gen.temperature != null) 'temperature': gen.temperature,
        if (gen.contextLimit != null) 'context_limit': gen.contextLimit,
        if (gen.narrativeMode != null) 'narrative_mode': gen.narrativeMode,
        if (gen.maxReplyLength != null) 'max_reply_length': gen.maxReplyLength,
      },
    };
  }

  /// 导入后把 extensions 里的生成参数还原到 card_generation 表
  void _restoreGeneration(CharacterCard card) {
    final gen = _generation;
    if (gen == null) return;
    final raw = card.rawJson;
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final nested = decoded['data'];
      final extensions = (nested is Map && nested['extensions'] is Map)
          ? nested['extensions']
          : decoded['extensions'];
      final payload = extensions is Map ? extensions['silas_generation'] : null;
      if (payload is! Map) return;
      final temperature = (payload['temperature'] as num?)?.toDouble();
      final contextLimit = (payload['context_limit'] as num?)?.toInt();
      final narrativeMode = payload['narrative_mode'] as String?;
      final maxReplyLength = (payload['max_reply_length'] as num?)?.toInt();
      if (temperature == null &&
          contextLimit == null &&
          narrativeMode == null &&
          maxReplyLength == null) {
        return;
      }
      gen.save(
        card.id,
        temperature: temperature,
        contextLimit: contextLimit,
        narrativeMode: narrativeMode,
        maxReplyLength: maxReplyLength,
      );
    } catch (_) {
      // 参数块坏了就忽略，不影响卡片本身
    }
  }

  List<CharacterCard> list({
    String? query,
    List<String> tags = const <String>[],
    CardSort sort = CardSort.updated,
    CardCursor? cursor,
    int limit = 30,
  }) =>
      _dao.list(query: query, tags: tags, sort: sort, cursor: cursor, limit: limit);

  CharacterCard? byId(String id) => _dao.byId(id);

  List<({String tag, int count})> tagStats() => _dao.tagStats();

  int count() => _dao.count();

  Future<CharacterCard> save(CharacterCard card) async {
    final normalized = card.copyWith(
      updatedAt: nowMs(),
      createdAt: card.createdAt == 0 ? nowMs() : card.createdAt,
    );
    _dao.save(normalized);
    return normalized;
  }

  /// 复制角色卡（不含会话）
  Future<CharacterCard?> duplicate(String id) async {
    final source = _dao.byId(id);
    if (source == null) return null;
    final now = nowMs();
    final copy = source.copyWith(
      id: newId(),
      name: '${source.name} 副本',
      avatarPath: null,
      createdAt: now,
      updatedAt: now,
      lastChatAt: null,
    );
    final avatarBytes = await _avatars.readBytes(source.avatarPath);
    if (avatarBytes != null) {
      final rel = await _avatars.save(copy.id, avatarBytes);
      _dao.save(copy.copyWith(avatarPath: rel));
      return copy.copyWith(avatarPath: rel);
    }
    _dao.save(copy);
    return copy;
  }

  Future<void> delete(CharacterCard card) async {
    _dao.delete(card.id);
    await _avatars.remove(card.avatarPath);
  }


  /// 记录最近聊天时间（对话页发送消息后调用，用于「按最近聊天」排序）
  void touchLastChat(String cardId) {
    _dao.touchLastChat(cardId, nowMs());
  }

  /// 设置自定义头像（本地图片选择）
  Future<String> saveAvatar(String cardId, Uint8List bytes) =>
      _avatars.save(cardId, bytes);

  Future<Uint8List?> avatarBytes(CharacterCard card) =>
      _avatars.readBytes(card.avatarPath);

  /// 导入单个文件（PNG 或 JSON）
  Future<ImportOutcome> importFile(
    Uint8List bytes, {
    String? fileName,
    CardImportFlavor flavor = CardImportFlavor.auto,
  }) async {
    try {
      final imported = _importer.fromBytes(bytes, flavor: flavor);
      if (imported == null) {
        return ImportOutcome(
          failed: 1,
          failures: <String>[fileName ?? '未知文件'],
        );
      }
      var card = imported.card;
      if (imported.avatarBytes != null) {
        final rel = await _avatars.save(card.id, imported.avatarBytes!);
        card = card.copyWith(avatarPath: rel);
      }
      _dao.save(card);
      return const ImportOutcome(imported: 1);
    } catch (e) {
      return ImportOutcome(failed: 1, failures: <String>[fileName ?? '$e']);
    }
  }

  /// 导入 JSON（可能是数组，即批量导出文件）
  Future<ImportOutcome> importJsonPayload(
    String text, {
    String? fileName,
    CardImportFlavor flavor = CardImportFlavor.auto,
  }) async {
    final list = _importer.fromJsonArrayString(text, flavor: flavor);
    if (list.isEmpty) {
      final single = _importer.fromJsonString(text, flavor: flavor);
      if (single == null) {
        return ImportOutcome(failed: 1, failures: <String>[fileName ?? 'JSON']);
      }
      _dao.save(single.card);
      _restoreGeneration(single.card);
      return const ImportOutcome(imported: 1);
    }
    final cards = list.map((e) => e.card).toList();
    _dao.importAll(cards);
    for (final card in cards) {
      _restoreGeneration(card);
    }
    return ImportOutcome(imported: cards.length);
  }

  /// 导出前一律按 id 回库重读一次。
  ///
  /// 调用方手里的 card 可能来自列表快照（长按菜单持有的是构建时的对象），
  /// 卡片刚在编辑页改完、列表还没重建时，直接拿快照导出会得到改动前的内容。
  Future<String> exportJson(CharacterCard card) async {
    final fresh = _dao.byId(card.id) ?? card;
    final file = await _exporter.exportJson(
      fresh,
      extraExtensions: _generationExtension(fresh),
    );
    return file.path;
  }

  Future<String?> exportPng(CharacterCard card) async {
    final fresh = _dao.byId(card.id) ?? card;
    final bytes = await _avatars.readBytes(fresh.avatarPath);
    final file = await _exporter.exportPng(
      fresh,
      bytes,
      extraExtensions: _generationExtension(fresh),
    );
    return file?.path;
  }

  Future<String> exportAll() async {
    final all = _dao.list(limit: 100000);
    final file = await _exporter.exportAll(all);
    return file.path;
  }
}

