import 'dart:convert';

enum ChatRole { system, user, assistant }

enum MessageStatus { pending, streaming, done, error, cancelled }

extension ChatRoleX on ChatRole {
  String get wire => name;
  static ChatRole parse(String? value) => ChatRole.values.firstWhere(
        (r) => r.name == value,
        orElse: () => ChatRole.assistant,
      );
}

extension MessageStatusX on MessageStatus {
  static MessageStatus parse(String? value) => MessageStatus.values.firstWhere(
        (s) => s.name == value,
        orElse: () => MessageStatus.done,
      );
  bool get isTerminal => this != MessageStatus.pending && this != MessageStatus.streaming;
}

class ChatSession {
  const ChatSession({
    required this.id,
    required this.cardId,
    this.title = '',
    this.greetingSeq = 0,
    this.messageCount = 0,
    this.previewText = '',
    this.lastMessageAt,
    this.lastMessageRole,
    this.isArchived = false,
    this.statusState = const <String, dynamic>{},
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String cardId;
  final String title;
  final int greetingSeq;
  final int messageCount;
  final String previewText;
  final int? lastMessageAt;
  final String? lastMessageRole;
  final bool isArchived;

  /// 状态栏当前值（随对话推进，由模型输出的状态块更新）
  final Map<String, dynamic> statusState;
  final int createdAt;
  final int updatedAt;

  factory ChatSession.fromRow(Map<String, Object?> row) => ChatSession(
        id: row['id']! as String,
        cardId: row['card_id']! as String,
        title: (row['title'] as String?) ?? '',
        greetingSeq: (row['greeting_seq'] as int?) ?? 0,
        messageCount: (row['message_count'] as int?) ?? 0,
        previewText: (row['preview_text'] as String?) ?? '',
        lastMessageAt: row['last_message_at'] as int?,
        lastMessageRole: row['last_message_role'] as String?,
        isArchived: ((row['is_archived'] as int?) ?? 0) == 1,
        statusState: _decodeStatus(row['status_state']),
        createdAt: (row['created_at'] as int?) ?? 0,
        updatedAt: (row['updated_at'] as int?) ?? 0,
      );

  static Map<String, dynamic> _decodeStatus(Object? raw) {
    if (raw is! String || raw.trim().isEmpty) return const <String, dynamic>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return <String, dynamic>{
          for (final e in decoded.entries) e.key.toString(): e.value,
        };
      }
    } catch (_) {
      // 忽略损坏的状态数据
    }
    return const <String, dynamic>{};
  }

  ChatSession copyWith({
    String? title,
    int? greetingSeq,
    int? messageCount,
    String? previewText,
    int? lastMessageAt,
    String? lastMessageRole,
    bool? isArchived,
    Map<String, dynamic>? statusState,
    int? updatedAt,
  }) =>
      ChatSession(
        id: id,
        cardId: cardId,
        title: title ?? this.title,
        greetingSeq: greetingSeq ?? this.greetingSeq,
        messageCount: messageCount ?? this.messageCount,
        previewText: previewText ?? this.previewText,
        lastMessageAt: lastMessageAt ?? this.lastMessageAt,
        lastMessageRole: lastMessageRole ?? this.lastMessageRole,
        isArchived: isArchived ?? this.isArchived,
        statusState: statusState ?? this.statusState,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.sessionId,
    required this.seq,
    required this.role,
    this.content = '',
    this.reasoning = '',
    this.status = MessageStatus.done,
    this.variantGroup,
    this.variantIndex = 0,
    this.isActiveVariant = true,
    this.excludedFromContext = false,
    this.tokenCount,
    this.model,
    this.apiConfigId,
    this.errorMessage,
    this.finishReason,
    this.latencyMs,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String sessionId;
  final int seq;
  final ChatRole role;
  final String content;

  /// 模型的思考过程（reasoning_content）。
  ///
  /// 只用于「查看思考过程」，**绝不进入上下文**：喂回模型会污染后续输出。
  /// 不是所有模型都返回，没有时为空串。
  final String reasoning;
  final MessageStatus status;
  final String? variantGroup;
  final int variantIndex;
  final bool isActiveVariant;
  final bool excludedFromContext;
  final int? tokenCount;
  final String? model;
  final String? apiConfigId;
  final String? errorMessage;
  final String? finishReason;
  final int? latencyMs;
  final int createdAt;
  final int updatedAt;

  bool get isUser => role == ChatRole.user;
  bool get isAssistant => role == ChatRole.assistant;
  bool get isBusy => status == MessageStatus.pending || status == MessageStatus.streaming;

  factory ChatMessage.fromRow(Map<String, Object?> row) => ChatMessage(
        id: row['id']! as String,
        sessionId: row['session_id']! as String,
        seq: (row['seq'] as int?) ?? 0,
        role: ChatRoleX.parse(row['role'] as String?),
        content: (row['content'] as String?) ?? '',
        reasoning: (row['reasoning'] as String?) ?? '',
        status: MessageStatusX.parse(row['status'] as String?),
        variantGroup: row['variant_group'] as String?,
        variantIndex: (row['variant_index'] as int?) ?? 0,
        isActiveVariant: ((row['is_active_variant'] as int?) ?? 1) == 1,
        excludedFromContext: ((row['excluded_from_context'] as int?) ?? 0) == 1,
        tokenCount: row['token_count'] as int?,
        model: row['model'] as String?,
        apiConfigId: row['api_config_id'] as String?,
        errorMessage: row['error_message'] as String?,
        finishReason: row['finish_reason'] as String?,
        latencyMs: row['latency_ms'] as int?,
        createdAt: (row['created_at'] as int?) ?? 0,
        updatedAt: (row['updated_at'] as int?) ?? 0,
      );

  Map<String, Object?> toRow() => <String, Object?>{
        'id': id,
        'session_id': sessionId,
        'seq': seq,
        'role': role.name,
        'content': content,
        'status': status.name,
        'variant_group': variantGroup,
        'variant_index': variantIndex,
        'is_active_variant': isActiveVariant ? 1 : 0,
        'excluded_from_context': excludedFromContext ? 1 : 0,
        'token_count': tokenCount,
        'model': model,
        'api_config_id': apiConfigId,
        'error_message': errorMessage,
        'finish_reason': finishReason,
        'latency_ms': latencyMs,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  ChatMessage copyWith({
    String? content,
    String? reasoning,
    MessageStatus? status,
    bool? isActiveVariant,
    bool? excludedFromContext,
    int? tokenCount,
    String? model,
    String? apiConfigId,
    String? errorMessage,
    String? finishReason,
    int? latencyMs,
    int? updatedAt,
  }) =>
      ChatMessage(
        id: id,
        sessionId: sessionId,
        seq: seq,
        role: role,
        content: content ?? this.content,
      reasoning: reasoning ?? this.reasoning,
        status: status ?? this.status,
        variantGroup: variantGroup,
        variantIndex: variantIndex,
        isActiveVariant: isActiveVariant ?? this.isActiveVariant,
        excludedFromContext: excludedFromContext ?? this.excludedFromContext,
        tokenCount: tokenCount ?? this.tokenCount,
        model: model ?? this.model,
        apiConfigId: apiConfigId ?? this.apiConfigId,
        errorMessage: errorMessage ?? this.errorMessage,
        finishReason: finishReason ?? this.finishReason,
        latencyMs: latencyMs ?? this.latencyMs,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}
