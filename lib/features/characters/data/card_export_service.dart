import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../domain/character_card.dart';
import 'png_codec.dart';

/// 角色卡导出。
///
/// JSON 导出为 Character Card V2；
/// PNG 导出会把 JSON 以 base64 写回 tEXt(chara)，可直接被 SillyTavern 读取。
class CardExportService {
  const CardExportService();

  Future<Directory> _exportDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'exports'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  String toJsonString(CharacterCard card) =>
      const JsonEncoder.withIndent('  ').convert(card.toTavernJson());

  Future<File> exportJson(CharacterCard card) async {
    final dir = await _exportDir();
    final file = File(p.join(dir.path, '${_safeName(card.name)}.json'));
    await file.writeAsString(toJsonString(card), encoding: utf8);
    return file;
  }

  /// 把卡片数据嵌入 PNG（若没有头像则生成一张纯色占位图不可行，直接抛错由调用方降级为 JSON）
  Future<File?> exportPng(CharacterCard card, Uint8List? avatarBytes) async {
    if (avatarBytes == null || !PngCodec.isPng(avatarBytes)) return null;
    final payload = base64.encode(utf8.encode(jsonEncode(card.toTavernJson())));
    final embedded = PngCodec.embedText(avatarBytes, 'chara', payload);
    final dir = await _exportDir();
    final file = File(p.join(dir.path, '${_safeName(card.name)}.png'));
    await file.writeAsBytes(embedded);
    return file;
  }

  /// 导出全部角色卡为一个 JSON 文件
  Future<File> exportAll(List<CharacterCard> cards) async {
    final dir = await _exportDir();
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    final file = File(p.join(dir.path, 'characters_$stamp.json'));
    final payload = cards.map((c) => c.toTavernJson()).toList();
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(payload),
      encoding: utf8,
    );
    return file;
  }

  static String _safeName(String name) {
    final cleaned = name.replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '_').trim();
    return cleaned.isEmpty ? 'character' : cleaned;
  }
}
