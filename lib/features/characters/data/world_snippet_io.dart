import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app_providers.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../domain/world_snippet.dart';

/// 世界书收藏的导入 / 导出（入口在「设置 → 数据管理」）。
///
/// 收藏是全局的，不随角色卡导出，所以要单独备份成一个 JSON 文件。
Future<void> exportWorldSnippets(BuildContext context, WidgetRef ref) async {
  final all = ref.read(worldSnippetDaoProvider).list();
  if (all.isEmpty) {
    showToast(context, '世界书收藏是空的，没有可导出的内容');
    return;
  }
  final payload = const JsonEncoder.withIndent('  ').convert(<String, dynamic>{
    'spec': 'silas_world_snippets',
    'version': 1,
    'snippets': all.map((s) => s.toJson()).toList(),
  });
  try {
    final path = await FilePicker.platform.saveFile(
      dialogTitle: '导出世界书收藏',
      fileName: 'silas_snippets.json',
      type: FileType.custom,
      allowedExtensions: const <String>['json'],
      bytes: Uint8List.fromList(utf8.encode(payload)),
    );
    if (!context.mounted || path == null) return;
    showToast(context, '已导出 ${all.length} 条世界书');
  } catch (e) {
    if (context.mounted) showToast(context, '导出失败：$e');
  }
}

Future<void> importWorldSnippets(BuildContext context, WidgetRef ref) async {
  try {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const <String>['json'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;
    final bytes = picked.files.first.bytes;
    if (bytes == null) return;

    final decoded = jsonDecode(utf8.decode(bytes));
    final rawList = decoded is Map
        ? (decoded['snippets'] as List?)
        : (decoded is List ? decoded : null);
    if (rawList == null) {
      if (context.mounted) showToast(context, '这个文件里没有世界书数据');
      return;
    }

    final dao = ref.read(worldSnippetDaoProvider);
    final existing = dao.list().map((s) => s.title).toSet();
    var added = 0;
    var skipped = 0;
    for (final raw in rawList) {
      if (raw is! Map) continue;
      final snippet = WorldSnippet.fromJson(Map<String, dynamic>.from(raw));
      if (snippet == null) continue;
      if (existing.contains(snippet.title)) {
        skipped++;
        continue;
      }
      dao.save(snippet);
      added++;
    }
    if (!context.mounted) return;
    showToast(
      context,
      skipped > 0 ? '导入 $added 条，跳过 $skipped 条（重名）' : '导入 $added 条世界书',
    );
  } catch (e) {
    if (context.mounted) showToast(context, '导入失败：$e');
  }
}
