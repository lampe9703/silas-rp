import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app_providers.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/network/openai_client.dart';
import '../../../../core/prompt/prompt_builder.dart';
import '../../../../core/prompt/status_parser.dart';
import '../../../../core/prompt/token_estimator.dart';
import '../../../../core/prompt/world_book_engine.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/ids.dart';
import '../../../../core/utils/time_utils.dart';
import '../../../characters/domain/character_card.dart';
import '../../../settings/data/settings_repository.dart';
import '../../../settings/domain/settings_models.dart';
import '../../../stats/domain/usage_models.dart';
import '../../data/message_dao.dart';
import '../../data/session_dao.dart';
import '../../domain/chat_models.dart';

class ChatState {
  const ChatState({
    this.card,
    this.sessions = const <ChatSession>[],
    this.session,
    this.messages = const <ChatMessage>[],
    this.isLoading = true,
    this.isStreaming = false,
    this.error,
    this.hasMoreHistory = false,
  });

  final CharacterCard? card;
  final List<ChatSession> sessions;
  final ChatSession? session;

  /// 按 seq 升序
  final List<ChatMessage> messages;
  final bool isLoading;
  final bool isStreaming;
  final String? error;
  final bool hasMoreHistory;

  bool get isEmptyConversation => messages.isEmpty;

  ChatState copyWith({
    CharacterCard? card,
    List<ChatSession>? sessions,
    ChatSession? session,
    List<ChatMessage>? messages,
    bool? isLoading,
    bool? isStreaming,
    String? error,
    bool clearError = false,
    bool? hasMoreHistory,
  }) =>
      ChatState(
        card: card ?? this.card,
        sessions: sessions ?? this.sessions,
        session: session ?? this.session,
        messages: messages ?? this.messages,
        isLoading: isLoading ?? this.isLoading,
        isStreaming: isStreaming ?? this.isStreaming,
        error: clearError ? null : (error ?? this.error),
        hasMoreHistory: hasMoreHistory ?? this.hasMoreHistory,
      );
}

/// 对话控制器。family 参数为角色卡 id，一个角色卡下可管理多个会话。
class ChatController extends FamilyNotifier<ChatState, String> {
  static const int pageSize = 40;

  CancelToken? _cancelToken;

  SessionDao get _sessionDao => ref.read(sessionDaoProvider);
  MessageDao get _messageDao => ref.read(messageDaoProvider);

  @override
  ChatState build(String arg) {
    final card = ref.read(characterRepositoryProvider).byId(arg);
    if (card == null) {
      return const ChatState(isLoading: false, error: '角色卡不存在或已删除');
    }
    final sessions = _sessionDao.listByCard(arg);
    ChatSession session;
    if (sessions.isEmpty) {
      session = _createSession(card, sessions.length);
      // 开场白写入后计数已变化，必须重新读一次，否则界面显示 0 条消息
      session = _sessionDao.byId(session.id) ?? session;
      sessions.insert(0, session);
    } else {
      session = sessions.first;
      // 老会话可能因为创建时没填初始状态而没有状态，这里补一次模板种子，
      // 否则状态栏永远不显示，解析也拿不到 knownKeys。
      if (card.statusEnabled && session.statusState.isEmpty) {
        final seed = card.statusInitial.isNotEmpty
            ? card.statusInitial
            : StatusParser.seedFromTemplate(card.statusTemplate);
        if (seed.isNotEmpty) {
          _sessionDao.setStatusState(session.id, seed);
          session = _sessionDao.byId(session.id) ?? session;
        }
      }
    }
    final messages = _loadPage(session.id);
    return ChatState(
      card: card,
      sessions: sessions,
      session: session,
      messages: messages,
      isLoading: false,
      hasMoreHistory: messages.length >= pageSize,
    );
  }

  List<ChatMessage> _loadPage(String sessionId, {int? beforeSeq}) {
    final desc = _messageDao.page(sessionId, beforeSeq: beforeSeq, limit: pageSize);
    return desc.reversed.toList();
  }

  /// 新建会话。
  ///
  /// [greetingIndex] 决定用哪一段开场白：0 = 主开场白，1..n = 第 n 段备选。
  ChatSession _createSession(
    CharacterCard card,
    int existingCount, {
    int greetingIndex = 0,
  }) {
    final session = _sessionDao.create(
      cardId: card.id,
      title: existingCount == 0 ? card.name : '${card.name} #${existingCount + 1}',
    );
    _seedGreeting(card, session, greetingIndex);
    if (card.statusEnabled) {
      // 初始状态为空时用「状态栏模板」兜底：新会话也能显示状态栏，
      // 且后续解析有 knownKeys 可用（模型漏写围栏也能从正文尾部提取）。
      final seed = card.statusInitial.isNotEmpty
          ? card.statusInitial
          : StatusParser.seedFromTemplate(card.statusTemplate);
      if (seed.isNotEmpty) {
        _sessionDao.setStatusState(session.id, seed);
      }
    }
    return session;
  }

  /// 开场白作为第一条 assistant 消息写入。
  ///
  /// 显式传入 card：build() 阶段还不能访问 state，只能走参数。
  void _seedGreeting(CharacterCard card, ChatSession session, int greetingIndex) {
    final content = card.greetingAt(greetingIndex);
    if (content.trim().isEmpty) return;
    _messageDao.append(
      sessionId: session.id,
      role: ChatRole.assistant,
      content: content,
      seq: 1,
    );
    _sessionDao.setGreetingSeq(session.id, greetingIndex);
  }

  // ───────────────────────────── 会话管理 ─────────────────────────────

  void newSession() {
    final card = state.card;
    if (card == null) return;
    // 新会话沿用「你此刻正在聊的这个会话」用的开场白：
    // 作者写了多段备选开场白时，「再开一个」通常是拿同一段重新开始，
    // 而不是每次都被拽回第一段。
    final greetingIndex = state.session?.greetingSeq ?? 0;
    var session = _createSession(
      card,
      state.sessions.length,
      greetingIndex: greetingIndex,
    );
    session = _sessionDao.byId(session.id) ?? session;
    final sessions = _sessionDao.listByCard(card.id);
    final messages = _loadPage(session.id);
    state = state.copyWith(
      sessions: sessions,
      session: session,
      messages: messages,
      hasMoreHistory: messages.length >= pageSize,
      clearError: true,
    );
  }

  void switchSession(String sessionId) {
    final session = _sessionDao.byId(sessionId);
    if (session == null) return;
    final messages = _loadPage(sessionId);
    state = state.copyWith(
      session: session,
      messages: messages,
      hasMoreHistory: messages.length >= pageSize,
      clearError: true,
    );
  }

  void deleteSession(String sessionId) {
    _sessionDao.delete(sessionId);
    final card = state.card;
    if (card == null) return;
    var sessions = _sessionDao.listByCard(card.id);
    ChatSession session;
    if (sessions.isEmpty) {
      session = _createSession(card, 0);
      sessions = _sessionDao.listByCard(card.id);
    } else {
      session = sessions.first;
      // 老会话可能因为创建时没填初始状态而没有状态，这里补一次模板种子，
      // 否则状态栏永远不显示，解析也拿不到 knownKeys。
      if (card.statusEnabled && session.statusState.isEmpty) {
        final seed = card.statusInitial.isNotEmpty
            ? card.statusInitial
            : StatusParser.seedFromTemplate(card.statusTemplate);
        if (seed.isNotEmpty) {
          _sessionDao.setStatusState(session.id, seed);
          session = _sessionDao.byId(session.id) ?? session;
        }
      }
    }
    final messages = _loadPage(session.id);
    state = state.copyWith(
      sessions: sessions,
      session: session,
      messages: messages,
      hasMoreHistory: messages.length >= pageSize,
    );
  }

  /// 批量删除会话（多选管理用）
  void deleteSessions(List<String> sessionIds) {
    if (sessionIds.isEmpty) return;
    for (final id in sessionIds) {
      _sessionDao.delete(id);
    }
    final card = state.card;
    if (card == null) return;
    var sessions = _sessionDao.listByCard(card.id);
    ChatSession session;
    if (sessions.isEmpty) {
      session = _createSession(card, 0);
      sessions = _sessionDao.listByCard(card.id);
    } else {
      session = sessions.first;
      if (card.statusEnabled && session.statusState.isEmpty) {
        final seed = card.statusInitial.isNotEmpty
            ? card.statusInitial
            : StatusParser.seedFromTemplate(card.statusTemplate);
        if (seed.isNotEmpty) {
          _sessionDao.setStatusState(session.id, seed);
          session = _sessionDao.byId(session.id) ?? session;
        }
      }
    }
    final messages = _loadPage(session.id);
    state = state.copyWith(
      sessions: sessions,
      session: session,
      messages: messages,
      hasMoreHistory: messages.length >= pageSize,
    );
  }

  void clearMessages() {
    final session = state.session;
    final card = state.card;
    if (session == null || card == null) return;
    _sessionDao.clearMessages(session.id);
    final refreshed = _sessionDao.byId(session.id)!;
    _seedGreeting(card, refreshed, refreshed.greetingSeq);
    final messages = _loadPage(session.id);
    state = state.copyWith(
      session: _sessionDao.byId(session.id),
      messages: messages,
      hasMoreHistory: false,
      clearError: true,
    );
  }

  /// 切换开场白：会清空当前会话并重新开场（UI 层需二次确认）
  void switchGreeting(int index) {
    final session = state.session;
    final card = state.card;
    if (session == null || card == null) return;
    _sessionDao.clearMessages(session.id);
    _sessionDao.setGreetingSeq(session.id, index);
    _seedGreeting(card, _sessionDao.byId(session.id)!, index);
    final messages = _loadPage(session.id);
    state = state.copyWith(
      session: _sessionDao.byId(session.id),
      messages: messages,
      hasMoreHistory: false,
    );
  }

  void loadMoreHistory() {
    final session = state.session;
    if (session == null || state.messages.isEmpty || !state.hasMoreHistory) return;
    final oldestSeq = state.messages.first.seq;
    final older = _loadPage(session.id, beforeSeq: oldestSeq);
    state = state.copyWith(
      messages: <ChatMessage>[...older, ...state.messages],
      hasMoreHistory: older.length >= pageSize,
    );
  }

  // ───────────────────────────── 发送 / 生成 ─────────────────────────────

  Future<void> send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || state.isStreaming) return;
    final session = state.session;
    if (session == null) return;

    final userMessage = _messageDao.append(
      sessionId: session.id,
      role: ChatRole.user,
      content: trimmed,
    );
    state = state.copyWith(
      messages: <ChatMessage>[...state.messages, userMessage],
      clearError: true,
    );
    // 用户消息已落库，立即刷新会话计数（生成提前返回时也不会留下过期数字）
    _refreshSessionMeta();
    await _generateReply();
  }

  /// 重新生成最后一条 assistant 回复
  Future<void> regenerateLast() async {
    if (state.isStreaming) return;
    final target = state.messages.lastWhere(
      (m) => m.role == ChatRole.assistant,
      orElse: () => throw StateError('没有可重新生成的消息'),
    );
    await _regenerate(target);
  }

  Future<void> _regenerate(ChatMessage target) async {
    final session = state.session;
    if (session == null) return;
    // 同 seq 插入新变体：先把旧变体置为非激活，避免唯一索引冲突
    _messageDao
      ..deactivateVariant(target.id)
      ..deleteFrom(session.id, target.seq + 1);
    final remaining =
        state.messages.where((m) => m.seq < target.seq).toList(growable: false);
    state = state.copyWith(messages: remaining, clearError: true);
    await _generateReply(
      variantGroup: target.variantGroup ?? target.id,
      variantIndex: target.variantIndex + 1,
      seq: target.seq,
    );
  }

  void stop() {
    _cancelToken?.cancel('user_cancelled');
  }

  void clearError() => state = state.copyWith(clearError: true);

  Future<void> _generateReply({
    String? variantGroup,
    int variantIndex = 0,
    int? seq,
  }) async {
    final card = state.card;
    final session = state.session;
    if (card == null || session == null) return;

    final settings = ref.read(appSettingsProvider);
    final settingsRepo = ref.read(settingsRepositoryProvider);
    final apiConfig = settingsRepo.defaultApiConfig();
    if (apiConfig == null) {
      state = state.copyWith(error: '还没有可用的 API 配置，请先到「设置 → API 配置」添加。');
      _refreshSessionMeta();
      return;
    }
    // Key 允许为空：Ollama / LM Studio / LocalAI 等自建端点通常不校验鉴权。
    // 真需要鉴权时，服务端会返回 401，走统一错误提示。
    final apiKey = await settingsRepo.apiKey(apiConfig);

    // 组装提示词
    final history = _messageDao.contextWindow(session.id);
    String userInput = '';
    final historyForPrompt = <ChatMessage>[];
    if (history.isNotEmpty) {
      final last = history.last;
      if (last.role == ChatRole.user) {
        userInput = last.content;
        historyForPrompt.addAll(history.sublist(0, history.length - 1));
      } else {
        historyForPrompt.addAll(history);
        userInput = '（继续）';
      }
    }

    final builder = PromptBuilder(
      estimator: TokenEstimator(charsPerToken: settings.charsPerToken),
    );
    // 状态栏：会话里有快照就用快照，否则回落到角色卡的初始状态。
    // 必须在世界书激活之前算出来：状态值里的 P3 / X2 这类编号本身就是世界书关键词。
    final statusState = session.statusState.isNotEmpty
        ? session.statusState
        : card.statusInitial;

    // 世界书：拿最近 8 条对话 + 本轮输入 + 状态栏的值做关键词扫描，
    // 概率按会话种子固定。带上状态值是为了让「人格 / 阶段」条目能被编号命中。
    final recentText = WorldBookEngine.scanText(
      recentLines: historyForPrompt.map((m) => m.content).toList(),
      userInput: userInput,
      statusState: statusState,
    );
    final world = WorldBookEngine(estimator: builder.estimator).activate(
      entries: card.worldBook,
      recentText: recentText,
      seed: session.id.hashCode,
    );
    // 被状态值触发的那几条（人格 / 阶段）单独拎出来：
    // 它们要和普通设定分开注入，并且放到 system 末尾，才压得住通用风格约束。
    final statusHint = statusState.values.map((v) => '$v').join(' ');
    final personaEntries = world.included
        .where((e) => WorldBookEngine.drivenByStatus(e, statusHint))
        .toList();
    final personaIds = personaEntries.map((e) => e.id).toSet();
    final worldText = WorldBookEngine.render(
      world.included.where((e) => !personaIds.contains(e.id)),
    );
    final personaText = WorldBookEngine.render(personaEntries);

    final payload = builder.build(
      card: card,
      history: historyForPrompt,
      userInput: userInput,
      contextLimit: settings.contextLimit,
      reservedForReply: apiConfig.maxTokens ?? 512,
      statusState: statusState,
      worldText: worldText,
      personaText: personaText,
      // 设置页里的全局系统提示词（回复风格层）；卡片自己写了则优先卡片
      globalStylePrompt: settings.systemPrompt,
      // 成人向尺度：仅在设置里主动开启时注入
      nsfwEnabled: settings.nsfwEnabled,
      // 单句对话字数上限（0 = 不限）
      maxReplyLength: settings.maxReplyLength,
      narrativeMode: settings.narrativeMode,
    );

    // 占位行：流式期间只更新 content 单列
    final placeholder = _messageDao.append(
      sessionId: session.id,
      role: ChatRole.assistant,
      content: '',
      status: MessageStatus.streaming,
      seq: seq,
      variantGroup: variantGroup,
      variantIndex: variantIndex,
      model: apiConfig.model,
      apiConfigId: apiConfig.id,
    );

    state = state.copyWith(
      messages: <ChatMessage>[...state.messages, placeholder],
      isStreaming: true,
      clearError: true,
    );

    final cancelToken = CancelToken();
    _cancelToken = cancelToken;
    final buffer = StringBuffer();
    // 思考过程单独累积：只存下来给「查看思考过程」看，不参与任何提示词
    final reasoningBuffer = StringBuffer();
    final stopwatch = Stopwatch()..start();
    int lastFlushMs = 0;
    int? ttftMs;
    TokenUsage? usage;
    String? finishReason;

    try {
      final stream = ref.read(openAiClientProvider).streamChat(
            config: apiConfig,
            apiKey: apiKey,
            messages: payload,
            cancelToken: cancelToken,
            maxTokens: apiConfig.maxTokens,
            temperature: apiConfig.temperature ?? settings.temperature,
            topP: apiConfig.topP ?? settings.topP,
          );

      await for (final event in stream) {
        if (event.reasoningDelta != null) {
          reasoningBuffer.write(event.reasoningDelta);
        }
        if (event.contentDelta != null) {
          ttftMs ??= stopwatch.elapsedMilliseconds;
          buffer.write(event.contentDelta);
        }
        // 节流：每 250ms 落盘一次（正文与思考一起），避免每个 token 一次事务
        final now = DateTime.now().millisecondsSinceEpoch;
        if (now - lastFlushMs >= 250) {
          lastFlushMs = now;
          if (buffer.isNotEmpty) {
            // 状态块不该出现在气泡里，流式阶段就要剥掉
            final visible = StatusParser.stripForDisplay(buffer.toString());
            _messageDao.updateContent(placeholder.id, visible);
            _patchMessage(placeholder.id, content: visible);
          }
          if (reasoningBuffer.isNotEmpty) {
            final thinking = reasoningBuffer.toString();
            _messageDao.updateReasoning(placeholder.id, thinking);
            _patchMessage(placeholder.id, reasoning: thinking);
          }
        }
        if (event.usage != null) usage = event.usage;
        if (event.finishReason != null) finishReason = event.finishReason;
        if (event.isDone) break;
      }

      final elapsed = stopwatch.elapsedMilliseconds;
      // 已知键 = 当前状态 + 模板条目。作者为省 token 常只写部分初始状态，
      // 模板里的其余条目也要能被尾部「键：值」提取识别。
      final knownKeys = <String>{
        ...statusState.keys,
        ...StatusParser.seedFromTemplate(card.statusTemplate).keys,
      };
      final parsed = StatusParser.parse(
        buffer.toString(),
        knownKeys: knownKeys,
      );
      // 入库前把中文引号统一成英文引号。
      // 只靠渲染层转换是「治标」：DB 里仍是中文引号，历史消息喂回模型时
      // 模型看到的还是中文引号，会一直沿用。入库就替换，模型才能学会英文引号。
      final text = parsed.visibleText
          .replaceAll('\u201c', '"')
          .replaceAll('\u201d', '"');
      final promptTokens =
          usage?.promptTokens ?? builder.estimator.estimateMessages(payload.map((e) => e['content'] ?? ''));
      final completionTokens = usage?.completionTokens ?? builder.estimator.estimate(text);
      final isEstimated = usage == null;

      _messageDao.finalize(
        placeholder.id,
        status: MessageStatus.done,
        content: text,
        reasoning: reasoningBuffer.isEmpty ? null : reasoningBuffer.toString(),
        tokenCount: promptTokens + completionTokens,
        finishReason: finishReason,
        latencyMs: elapsed,
      );
      _patchMessage(
        placeholder.id,
        content: text,
        status: MessageStatus.done,
        reasoning: reasoningBuffer.isEmpty ? null : reasoningBuffer.toString(),
      );

      // 合并模型给出的状态更新
      if (parsed.status != null && parsed.status!.isNotEmpty) {
        final merged = <String, dynamic>{...statusState, ...parsed.status!};
        _sessionDao.setStatusState(session.id, merged);
      }
      _recordUsage(
        apiConfig: apiConfig,
        card: card,
        session: session,
        messageId: placeholder.id,
        promptTokens: promptTokens,
        completionTokens: completionTokens,
        isEstimated: isEstimated,
        costMicros: _cost(apiConfig.model, promptTokens, completionTokens, settingsRepo),
        latencyMs: elapsed,
        ttftMs: ttftMs,
        status: 'success',
      );
      _refreshSessionMeta();
    } on ApiException catch (e) {
      final elapsed = stopwatch.elapsedMilliseconds;
      final text = StatusParser.stripForDisplay(buffer.toString());
      final cancelled = e.kind == ApiErrorKind.cancelled;
      final promptTokens = usage?.promptTokens ??
          builder.estimator.estimateMessages(payload.map((x) => x['content'] ?? ''));
      final completionTokens =
          usage?.completionTokens ?? builder.estimator.estimate(text);

      _messageDao.finalize(
        placeholder.id,
        status: cancelled ? MessageStatus.cancelled : MessageStatus.error,
        content: text,
        reasoning: reasoningBuffer.isEmpty ? null : reasoningBuffer.toString(),
        tokenCount: promptTokens + completionTokens,
        latencyMs: elapsed,
        errorMessage: cancelled ? null : e.userMessage,
      );
      _patchMessage(
        placeholder.id,
        content: text,
        status: cancelled ? MessageStatus.cancelled : MessageStatus.error,
        errorMessage: cancelled ? null : e.userMessage,
      );

      // 失败/取消的请求同样计入统计（按实际已消耗 token），状态可区分
      _recordUsage(
        apiConfig: apiConfig,
        card: card,
        session: session,
        messageId: placeholder.id,
        promptTokens: promptTokens,
        completionTokens: completionTokens,
        isEstimated: usage == null,
        costMicros: _cost(apiConfig.model, promptTokens, completionTokens, settingsRepo),
        latencyMs: elapsed,
        ttftMs: ttftMs,
        status: cancelled ? 'cancelled' : 'error',
        errorCode: e.kind.name,
        httpStatus: e.statusCode,
      );

      if (!cancelled) {
        state = state.copyWith(error: e.userMessage);
      }
      _refreshSessionMeta();
    } catch (e) {
      final visible = StatusParser.stripForDisplay(buffer.toString());
      _messageDao.finalize(
        placeholder.id,
        status: MessageStatus.error,
        content: visible,
        errorMessage: '$e',
      );
      _patchMessage(
        placeholder.id,
        content: visible,
        status: MessageStatus.error,
        errorMessage: '$e',
      );
      state = state.copyWith(error: '生成失败：$e');
    } finally {
      _cancelToken = null;
      state = state.copyWith(isStreaming: false);
    }
  }

  int _cost(
    String model,
    int promptTokens,
    int completionTokens,
    SettingsRepository settingsRepo,
  ) {
    final pricing = settingsRepo.resolvePricing(model);
    if (pricing == null) return 0;
    return CostCalculator.costMicros(
      promptTokens: promptTokens,
      completionTokens: completionTokens,
      inputPer1M: pricing.inputPer1M,
      outputPer1M: pricing.outputPer1M,
    );
  }

  void _recordUsage({
    required ApiConfig apiConfig,
    required CharacterCard card,
    required ChatSession session,
    required String messageId,
    required int promptTokens,
    required int completionTokens,
    required bool isEstimated,
    required int costMicros,
    required int latencyMs,
    int? ttftMs,
    required String status,
    String? errorCode,
    int? httpStatus,
  }) {
    ref.read(usageDaoProvider).record(
          ApiCallLog(
            id: newId(),
            requestAt: nowMs(),
            sessionId: session.id,
            messageId: messageId,
            cardId: card.id,
            cardName: card.name,
            apiConfigId: apiConfig.id,
            model: apiConfig.model,
            status: status,
            httpStatus: httpStatus,
            promptTokens: promptTokens,
            completionTokens: completionTokens,
            totalTokens: promptTokens + completionTokens,
            isEstimated: isEstimated,
            costMicros: costMicros,
            latencyMs: latencyMs,
            ttftMs: ttftMs,
            errorCode: errorCode,
          ),
        );
    ref.read(characterRepositoryProvider).touchLastChat(card.id);
  }

  void _refreshSessionMeta() {
    final session = state.session;
    if (session == null) return;
    final refreshed = _sessionDao.byId(session.id);
    final sessions = state.card == null
        ? state.sessions
        : _sessionDao.listByCard(state.card!.id);
    state = state.copyWith(session: refreshed, sessions: sessions);
  }

  // ───────────────────────────── 消息操作 ─────────────────────────────

  void editMessage(ChatMessage message, String content) {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return;
    _messageDao.updateContentById(message.id, trimmed, null);
    _patchMessage(message.id, content: trimmed);
    _refreshSessionMeta();
  }

  /// 编辑用户消息后重新生成：删除该条之后的全部消息并重发
  Future<void> editAndResend(ChatMessage message, String content) async {
    final session = state.session;
    if (session == null || message.role != ChatRole.user) return;
    final trimmed = content.trim();
    if (trimmed.isEmpty) return;
    _messageDao.updateContentById(message.id, trimmed, null);
    _messageDao.deleteFrom(session.id, message.seq + 1);
    final kept = state.messages.where((m) => m.seq <= message.seq).toList();
    final updated = kept.map((m) {
      if (m.id == message.id) return m.copyWith(content: trimmed);
      return m;
    }).toList();
    state = state.copyWith(messages: updated);
    await _generateReply();
  }

  void deleteMessage(ChatMessage message) {
    _messageDao.delete(message.id);
    state = state.copyWith(
      messages: state.messages.where((m) => m.id != message.id).toList(),
    );
    _refreshSessionMeta();
  }

  void _patchMessage(
    String id, {
    String? content,
    String? reasoning,
    MessageStatus? status,
    String? errorMessage,
  }) {
    final updated = state.messages.map((m) {
      if (m.id != id) return m;
      return m.copyWith(
        content: content ?? m.content,
        reasoning: reasoning ?? m.reasoning,
        status: status ?? m.status,
        errorMessage: errorMessage ?? m.errorMessage,
        updatedAt: nowMs(),
      );
    }).toList();
    state = state.copyWith(messages: updated);
  }

  /// 供 UI 展示的提示：当前会话 token 粗略占用
  String get contextUsageHint {
    final total = state.messages
        .where((m) => !m.isBusy)
        .fold<int>(0, (sum, m) => sum + (m.tokenCount ?? 0));
    if (total == 0) return '';
    return '≈${formatTokens(total)} tokens';
  }
}

final chatControllerProvider =
    NotifierProvider.family<ChatController, ChatState, String>(
  ChatController.new,
);
