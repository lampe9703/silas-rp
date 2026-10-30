import 'dart:typed_data';

import '../../../core/utils/ids.dart';
import '../../../core/utils/time_utils.dart';
import '../domain/character_card.dart';
import 'avatar_storage.dart';
import 'card_export_service.dart';
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
    CardImportService importer = const CardImportService(),
    CardExportService exporter = const CardExportService(),
  })  : _dao = dao,
        _avatars = avatars,
        _importer = importer,
        _exporter = exporter;

  final CharacterDao _dao;
  final AvatarStorage _avatars;
  final CardImportService _importer;
  final CardExportService _exporter;

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

  Future<void> toggleFavorite(CharacterCard card) async {
    _dao.toggleFavorite(card.id, !card.isFavorite);
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
      return const ImportOutcome(imported: 1);
    }
    _dao.importAll(list.map((e) => e.card).toList());
    return ImportOutcome(imported: list.length);
  }

  Future<String> exportJson(CharacterCard card) async {
    final file = await _exporter.exportJson(card);
    return file.path;
  }

  Future<String?> exportPng(CharacterCard card) async {
    final bytes = await _avatars.readBytes(card.avatarPath);
    final file = await _exporter.exportPng(card, bytes);
    return file?.path;
  }

  Future<String> exportAll() async {
    final all = _dao.list(limit: 100000);
    final file = await _exporter.exportAll(all);
    return file.path;
  }
}

