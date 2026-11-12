import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../shared/widgets/app_widgets.dart';
import '../../characters/domain/character_card.dart';
import '../domain/chat_models.dart';

/// 会话导出格式。
enum ChatExportFormat {
  /// 可读文本：直接打开就能看，适合分享 / 存档
  markdown('Markdown', 'md'),

  /// 完整数据：保留角色、模型、时间戳、状态，适合二次处理
  json('JSON', 'json');

  const ChatExportFormat(this.label, this.extension);

  final String label;
  final String extension;
}

/// 把**当前这一个会话**导出成文件。
///
/// 只导出会话本身（消息 + 时间 + 模型），不含角色卡定义 ——
/// 卡是另一份数据，要带走请用卡库的导出。
Future<void> exportSession(
  BuildContext context, {
  required CharacterCard card,
  required ChatSession session,
  required List<ChatMessage> messages,
  required ChatExportFormat format,
  bool includeReasoning = false,
}) async {
  if (messages.isEmpty) {
    showToast(context, '当前会话还没有消息，没有可导出的内容');
    return;
  }

  final payload = format == ChatExportFormat.markdown
      ? buildSessionMarkdown(
          card: card,
          session: session,
          messages: messages,
          includeReasoning: includeReasoning,
        )
      : buildSessionJson(
          card: card,
          session: session,
          messages: messages,
          includeReasoning: includeReasoning,
        );

  final fileName = '${_safeName(card.name)}-${_stamp(DateTime.now())}'
      '.${format.extension}';

  try {
    final path = await FilePicker.platform.saveFile(
      dialogTitle: '导出聊天记录',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: <String>[format.extension],
      bytes: Uint8List.fromList(utf8.encode(payload)),
    );
    if (!context.mounted || path == null) return;
    showToast(context, '已导出 ${messages.length} 条消息');
  } catch (e) {
    if (context.mounted) showToast(context, '导出失败：$e');
  }
}

/// Markdown 版本：按时间顺序排版，`我` / 角色名 作为小标题。
String buildSessionMarkdown({
  required CharacterCard card,
  required ChatSession session,
  required List<ChatMessage> messages,
  bool includeReasoning = false,
}) {
  final buffer = StringBuffer();
  final title = session.title.trim().isEmpty ? card.name : session.title.trim();

  buffer.writeln('# $title');
  buffer.writeln();
  buffer.writeln('> 角色卡：${card.name}');
  buffer.writeln('> 消息：${messages.length} 条');
  buffer.writeln('> 导出：${_fullTime(DateTime.now())}');
  final models = <String>{
    for (final m in messages)
      if ((m.model ?? '').trim().isNotEmpty) m.model!.trim(),
  };
  if (models.isNotEmpty) {
    buffer.writeln('> 模型：${models.join('、')}');
  }
  buffer.writeln();
  buffer.writeln('---');
  buffer.writeln();

  for (final m in messages) {
    final who = m.isUser ? '我' : card.name;
    final clock = _hm(m.createdAt);
    final model = (!m.isUser && (m.model ?? '').trim().isNotEmpty)
        ? ' · ${m.model!.trim()}'
        : '';
    buffer.writeln('### $who · $clock$model');
    buffer.writeln();

    final body = m.content.trim();
    buffer.writeln(body.isEmpty ? '_（空）_' : body);
    buffer.writeln();

    // 中断 / 出错的消息要标出来，否则读起来像是模型只写了一半
    if (m.status == MessageStatus.cancelled) {
      buffer.writeln('_（已中断）_');
      buffer.writeln();
    } else if (m.status == MessageStatus.error) {
      final reason = (m.errorMessage ?? '').trim();
      buffer.writeln(reason.isEmpty ? '_（出错）_' : '_（出错：$reason）_');
      buffer.writeln();
    }

    if (includeReasoning && m.reasoning.trim().isNotEmpty) {
      buffer.writeln('> **思考过程**');
      for (final line in m.reasoning.trim().split('\n')) {
        buffer.writeln('> $line');
      }
      buffer.writeln();
    }
  }

  return buffer.toString();
}

/// JSON 版本：保留原始字段，便于以后做统计或再导入。
String buildSessionJson({
  required CharacterCard card,
  required ChatSession session,
  required List<ChatMessage> messages,
  bool includeReasoning = false,
}) {
  final payload = <String, dynamic>{
    'spec': 'silas_chat_log',
    'version': 1,
    'exported_at': DateTime.now().millisecondsSinceEpoch,
    'card': <String, dynamic>{
      'id': card.id,
      'name': card.name,
    },
    'session': <String, dynamic>{
      'id': session.id,
      'title': session.title,
      'created_at': session.createdAt,
      'updated_at': session.updatedAt,
      'message_count': messages.length,
      if (session.apiConfigId != null) 'api_config_id': session.apiConfigId,
      'status_state': session.statusState,
    },
    'messages': <Map<String, dynamic>>[
      for (final m in messages)
        <String, dynamic>{
          'seq': m.seq,
          'role': m.role.name,
          'created_at': m.createdAt,
          'content': m.content,
          'status': m.status.name,
          if ((m.model ?? '').isNotEmpty) 'model': m.model,
          if ((m.finishReason ?? '').isNotEmpty) 'finish_reason': m.finishReason,
          if (m.tokenCount != null) 'token_count': m.tokenCount,
          if (m.latencyMs != null) 'latency_ms': m.latencyMs,
          if ((m.errorMessage ?? '').isNotEmpty) 'error_message': m.errorMessage,
          if (includeReasoning && m.reasoning.trim().isNotEmpty)
            'reasoning': m.reasoning,
        },
    ],
  };
  return const JsonEncoder.withIndent('  ').convert(payload);
}

String _two(int v) => v.toString().padLeft(2, '0');

String _hm(int ms) {
  final t = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${_two(t.hour)}:${_two(t.minute)}';
}

String _fullTime(DateTime t) =>
    '${t.year}-${_two(t.month)}-${_two(t.day)} ${_two(t.hour)}:${_two(t.minute)}';

String _stamp(DateTime t) =>
    '${t.year}${_two(t.month)}${_two(t.day)}-${_two(t.hour)}${_two(t.minute)}';

/// 文件名安全化：去掉路径分隔符与常见非法字符
String _safeName(String name) {
  final cleaned = name
      .replaceAll(RegExp(r'[\\/:*?"<>|\n\r\t]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (cleaned.isEmpty) return 'chat';
  return cleaned.length > 40 ? cleaned.substring(0, 40) : cleaned;
}
