import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app_providers.dart';
import '../../characters/data/world_snippet_io.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../../characters/presentation/controllers/character_list_controller.dart';
import '../presentation/settings_page.dart';
import '../../stats/presentation/controllers/stats_controller.dart';

class DataManagePage extends ConsumerStatefulWidget {
  const DataManagePage({super.key});

  @override
  ConsumerState<DataManagePage> createState() => _DataManagePageState();
}

class _DataManagePageState extends ConsumerState<DataManagePage> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cardCount = ref.watch(characterRepositoryProvider).count();
    final logCount = ref.watch(usageDaoProvider).countLogs();

    return Scaffold(
      appBar: AppBar(title: const Text('数据管理')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          SectionCard(
            title: '当前数据量',
            padding: EdgeInsets.zero,
            children: [
              ListTile(
                title: const Text('角色卡', style: TextStyle(fontSize: 14)),
                trailing: Text('$cardCount', style: const TextStyle(fontSize: 14)),
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              ListTile(
                title: const Text('调用记录', style: TextStyle(fontSize: 14)),
                trailing: Text('$logCount', style: const TextStyle(fontSize: 14)),
              ),
            ],
          ),
          const SizedBox(height: 18),
          SectionCard(
            title: '角色卡备份',
            padding: EdgeInsets.zero,
            children: [
              ListTile(
                leading: const Icon(Icons.upload_file_rounded, size: 20),
                title: const Text('导出全部角色卡', style: TextStyle(fontSize: 14)),
                subtitle: const Text(
                  '生成一个 JSON 文件，可在其它设备导入',
                  style: TextStyle(fontSize: 11.5),
                ),
                onTap: _busy ? null : _exportAll,
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              ListTile(
                leading: const Icon(Icons.file_download_outlined, size: 20),
                title: const Text('导入角色卡', style: TextStyle(fontSize: 14)),
                subtitle: const Text(
                  '支持 PNG 角色卡与 JSON（含批量文件）',
                  style: TextStyle(fontSize: 11.5),
                ),
                onTap: _busy ? null : _import,
              ),
            ],
          ),
          const SizedBox(height: 18),
          SectionCard(
            title: '世界书收藏',
            padding: EdgeInsets.zero,
            children: [
              ListTile(
                leading: const Icon(Icons.ios_share_rounded, size: 20),
                title: const Text('导出世界书收藏', style: TextStyle(fontSize: 14)),
                subtitle: const Text(
                  '跨角色卡复用的通用条目，单独备份成 JSON',
                  style: TextStyle(fontSize: 11.5),
                ),
                onTap: _busy
                    ? null
                    : () => exportWorldSnippets(context, ref),
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              ListTile(
                leading: const Icon(Icons.file_download_outlined, size: 20),
                title: const Text('导入世界书收藏', style: TextStyle(fontSize: 14)),
                subtitle: const Text(
                  '同名条目会自动跳过；不影响已有角色卡',
                  style: TextStyle(fontSize: 11.5),
                ),
                onTap: _busy
                    ? null
                    : () => importWorldSnippets(context, ref),
              ),
            ],
          ),
          const SizedBox(height: 18),
          SectionCard(
            title: '清理',
            padding: EdgeInsets.zero,
            children: [
              ListTile(
                leading: const Icon(Icons.cleaning_services_outlined, size: 20),
                title: const Text('清空统计数据', style: TextStyle(fontSize: 14)),
                subtitle: const Text(
                  '删除全部调用明细与汇总，角色卡与会话保留',
                  style: TextStyle(fontSize: 11.5),
                ),
                onTap: _clearStats,
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              ListTile(
                leading: Icon(Icons.delete_forever_rounded,
                    size: 20, color: scheme.error),
                title: Text(
                  '清空全部数据',
                  style: TextStyle(fontSize: 14, color: scheme.error),
                ),
                subtitle: const Text(
                  '角色卡、会话、消息、统计、API 配置全部删除',
                  style: TextStyle(fontSize: 11.5),
                ),
                onTap: _wipeAll,
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            '所有数据都保存在设备本地，卸载应用会一并删除。建议定期导出角色卡备份。',
            style: TextStyle(
              fontSize: 11.5,
              height: 1.6,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _exportAll() async {
    setState(() => _busy = true);
    try {
      final path = await ref.read(characterRepositoryProvider).exportAll();
      await shareExportedFile(path);
      if (!mounted) return;
      showToast(context, '已导出到：$path');
    } catch (e) {
      if (mounted) showToast(context, '导出失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    setState(() => _busy = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: const ['png', 'json'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final repo = ref.read(characterRepositoryProvider);
      var imported = 0;
      for (final file in result.files) {
        final bytes = file.bytes;
        if (bytes == null) continue;
        if (file.name.toLowerCase().endsWith('.json')) {
          final outcome = await repo.importJsonPayload(
            utf8.decode(bytes, allowMalformed: true),
            fileName: file.name,
          );
          imported += outcome.imported;
        } else {
          final outcome = await repo.importFile(bytes, fileName: file.name);
          imported += outcome.imported;
        }
      }
      ref.read(characterListProvider.notifier).refresh();
      if (mounted) showToast(context, '成功导入 $imported 张角色卡');
    } catch (e) {
      if (mounted) showToast(context, '导入失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clearStats() async {
    final ok = await showConfirmDialog(
      context,
      title: '清空统计数据',
      message: '全部调用明细与汇总数据将被永久删除。',
      confirmText: '清空',
      danger: true,
    );
    if (!ok) return;
    ref.read(statsProvider.notifier).clearAll();
    if (mounted) {
      setState(() {});
      showToast(context, '统计已清空');
    }
  }

  Future<void> _wipeAll() async {
    final ok = await showConfirmDialog(
      context,
      title: '清空全部数据',
      message: '角色卡、会话消息、统计数据、API 配置与保存的 Key 都会被永久删除，无法恢复。',
      confirmText: '全部删除',
      danger: true,
    );
    if (!ok) return;

    setState(() => _busy = true);
    try {
      await ref.read(settingsRepositoryProvider).clearAllSecrets();
      ref.read(databaseProvider).wipeAll();
      ref.invalidate(characterListProvider);
      ref.invalidate(statsProvider);
      ref.invalidate(apiConfigsProvider);
      ref.invalidate(appSettingsProvider);
      if (mounted) {
        setState(() {});
        showToast(context, '已清空全部数据');
      }
    } catch (e) {
      if (mounted) showToast(context, '清空失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
