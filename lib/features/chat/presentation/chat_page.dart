import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app_providers.dart';
import '../../../core/theme/glass_theme.dart';
import '../../../core/utils/time_utils.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../domain/chat_models.dart';
import 'controllers/chat_controller.dart';
import 'widgets/chat_input_bar.dart';
import 'widgets/message_bubble.dart';
import 'widgets/status_panel.dart';

class ChatPage extends ConsumerStatefulWidget {
  const ChatPage({super.key, required this.cardId});

  final String cardId;

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage> {
  final _inputController = TextEditingController();
  final _focusNode = FocusNode();
  final _scrollController = ScrollController();
  int _lastMessageCount = 0;

  /// 返回拦截去重：收键盘的短暂延迟期间连按返回不会重入
  bool _popping = false;

  @override
  void dispose() {
    _inputController.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom({bool animate = true}) {
    if (!_scrollController.hasClients) return;
    if (animate) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    } else {
      _scrollController.jumpTo(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = chatControllerProvider(widget.cardId);
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);

    // 新消息到达时贴底（列表为 reverse，offset 0 即底部）
    ref.listen<ChatState>(provider, (previous, next) {
      if (next.messages.length > _lastMessageCount) {
        _lastMessageCount = next.messages.length;
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
      }
    });
    _lastMessageCount = state.messages.length;

    final card = state.card;
    if (card == null) {
      return Scaffold(
        appBar: AppBar(),
        body: EmptyState(
          icon: Icons.error_outline_rounded,
          title: state.error ?? '角色卡不存在',
          description: '它可能已被删除，返回角色卡仓库看看。',
        ),
      );
    }

    final avatarFile = ref.watch(avatarStorageProvider).file(card.avatarPath);

    return PopScope(
      // 拦截返回（AppBar 返回键与系统返回键都走 maybePop）。
      // 「键盘已下沉但焦点还在输入框」时直接 pop：退场过程中的焦点移交
      // 会把输入法重新唤出、盖在主页上——在上个版本里是 pop 完才补 unfocus，
      // 时机太晚。现在先收起 IME 并释放焦点，确认生效后再真正离开。
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || _popping) return;
        _popping = true;
        final navigator = Navigator.of(context);
        try {
          // 1) 释放输入焦点：关闭 TextInputConnection，之后不会再有 show 请求
          FocusManager.instance.primaryFocus?.unfocus();
          // 2) 平台通道强制收起 IME 窗口——无论焦点/连接处于什么状态都能收
          await SystemChannels.textInput.invokeMethod('TextInput.hide');
          // 3) 留出消息生效时间，避免退场动画中途 IME 又被唤起
          await Future<void>.delayed(const Duration(milliseconds: 60));
        } finally {
          _popping = false;
        }
        if (mounted) navigator.pop();
      },
      child: Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: InkWell(
          onTap: () {
            // 打开任何弹窗前先释放输入焦点，防止弹窗关闭时焦点还原唤出输入法
            parkKeyboard(context);
            _showSessions(context, state, controller);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                CharacterAvatar(file: avatarFile, name: card.name, size: 34),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        card.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '${state.session?.messageCount ?? 0} 条消息'
                        '${controller.contextUsageHint.isEmpty ? '' : ' · ${controller.contextUsageHint}'}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w400,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.unfold_more_rounded, size: 16),
                const SizedBox(width: 6),
              ],
            ),
          ),
        ),
        actions: [
          // 在菜单**打开前**就释放输入焦点：菜单路由会抢走焦点，关闭时把焦点
          // 还原给输入框——那正是「点空白处关弹窗却唤出输入法」的根源。
          // onTapDown 在指针按下的瞬间触发，早于菜单打开。
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (_) => parkKeyboard(context),
            child: PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded),
              onCanceled: () => parkKeyboard(context),
              onSelected: (value) => _onMenuAction(value, state, controller),
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'new', child: Text('新建会话')),
                PopupMenuItem(
                    value: 'greeting', child: Text('切换开场白')),
                PopupMenuItem(value: 'params', child: Text('生成参数')),
                PopupMenuItem(value: 'reasoning', child: Text('查看思考过程')),
                PopupMenuItem(value: 'clear', child: Text('清空当前对话')),
                PopupMenuItem(value: 'delete', child: Text('删除当前会话')),
              ],
            ),
          ),
        ],
      ),
      body: Stack(
        children: <Widget>[
          // 有封面的卡：用封面极度模糊后做背景（iris music 那种氛围感）
          if (avatarFile != null)
            Positioned.fill(child: _CoverBackdrop(file: avatarFile)),
          Column(
            children: [
          Expanded(
            child: state.messages.isEmpty
                ? const EmptyState(
                    icon: Icons.chat_bubble_outline_rounded,
                    title: '还没有对话',
                    description: '在下方输入框说点什么，开始这段角色扮演。',
                  )
                : state.messages.length == 1 && !state.messages.first.isUser
                    // 只有开场白时贴顶显示。
                    // reverse 列表在内容不足一屏时会贴底排列，表现为开场白挤在
                    // 输入框上方；这里单独渲染成顶部的普通滚动内容，符合「开场白
                    // 在聊天区顶部」的预期。开始对话（≥2 条）后回到正常反向列表，
                    // 开场白自然成为最上面那条。用户首条发言仍走正常贴底逻辑。
                    ? SingleChildScrollView(
                        padding: const EdgeInsets.only(top: 8, bottom: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            MessageBubble(
                              message: state.messages.first,
                              card: card,
                              cardAvatar: avatarFile,
                              onLongPress: () => _showMessageActions(
                                context,
                                state.messages.first,
                                state,
                                controller,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        reverse: true,
                        padding: const EdgeInsets.only(top: 8, bottom: 8),
                        itemCount: state.messages.length + 1,
                        itemBuilder: (context, index) {
                          if (index == state.messages.length) {
                            return _buildTopLoader(state, controller);
                          }
                          final message =
                              state.messages[state.messages.length - 1 - index];
                          return MessageBubble(
                            message: message,
                            card: card,
                            cardAvatar: avatarFile,
                            onLongPress: () => _showMessageActions(
                              context,
                              message,
                              state,
                              controller,
                            ),
                          );
                        },
                      ),
          ),
          if (state.error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
              child: GlassSurface(
                radius: 14,
                blur: 14,
                lift: 0.5,
                tint: const Color(0xFFD9636B).withOpacity(0.10),
                padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                child: Row(
                  children: <Widget>[
                    const Icon(Icons.info_outline_rounded,
                        size: 15, color: Color(0xFFD9636B)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        state.error!,
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.45,
                          color: GlassPalette.inkOf(
                            Theme.of(context).brightness,
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 16),
                      visualDensity: VisualDensity.compact,
                      onPressed: controller.clearError,
                    ),
                  ],
                ),
              ),
            ),
          // 只要卡片开了状态栏就渲染面板。
          //
          // 以前这里还要求 statusState 非空，于是下面几种情况整块面板直接消失，
          // 看起来就是「状态栏时不时不见」：
          //   · 作者只写了状态栏模板、没写初始状态（种子为空）
          //   · 老会话的 status_state 是 '{}'，且卡片的初始状态/模板都空
          //   · 本次回复没有可解析的状态块，状态一直没被写进去
          // 没数据时面板自己会给占位（模板骨架 / 未设定），不会误导成「已关闭」。
          if (card.statusEnabled)
            StatusPanel(
              status: state.session?.statusState ?? const <String, dynamic>{},
              template: card.statusTemplate,
            ),
              ChatInputBar(
                controller: _inputController,
                focusNode: _focusNode,
                isStreaming: state.isStreaming,
                onStop: controller.stop,
                onSend: () async {
                  final text = _inputController.text;
                  if (text.trim().isEmpty) return;
                  _inputController.clear();
                  await controller.send(text);
                },
              ),
            ],
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildTopLoader(ChatState state, ChatController controller) {
    if (!state.hasMoreHistory) {
      return const SizedBox(height: 12);
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: TextButton(
          onPressed: controller.loadMoreHistory,
          child: const Text('加载更早的消息'),
        ),
      ),
    );
  }

  /// 「查看思考过程」：把最近一条带 reasoning 的回复的思考过程展示出来。
  ///
  /// 只读、不参与任何提示词；模型不返回 reasoning 时给一句明确提示，
  /// 而不是弹一个空面板。
  Future<void> _showReasoning(ChatState state) async {
    ChatMessage? target;
    for (final m in state.messages.reversed) {
      if (m.role == ChatRole.assistant && m.reasoning.trim().isNotEmpty) {
        target = m;
        break;
      }
    }
    if (target == null) {
      showToast(context, '当前会话没有可查看的思考内容：这个模型可能不返回 reasoning');
      return;
    }

    final reasoning = target.reasoning.trim();
    final preview = target.content.replaceAll(RegExp(r'\s+'), ' ').trim();
    final model = target.model;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        final brightness = Theme.of(sheetContext).brightness;
        final faint = GlassPalette.inkFaintOf(brightness);
        final soft = GlassPalette.inkSoftOf(brightness);
        return FractionallySizedBox(
          heightFactor: 0.78,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
                child: Row(
                  children: <Widget>[
                    Text(
                      '思考过程',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: GlassPalette.inkOf(brightness),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${reasoning.runes.length} 字'
                        '${model == null || model.isEmpty ? '' : ' · $model'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11.5, color: faint),
                      ),
                    ),
                  ],
                ),
              ),
              if (preview.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                  child: Text(
                    '对应回复：$preview',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, height: 1.5, color: soft),
                  ),
                ),
              const Divider(height: 1),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
                  child: SelectableText(
                    reasoning,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.75,
                      color: soft,
                    ),
                  ),
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
                child: Text(
                  '思考内容不会进入上下文，只在这里查看。',
                  style: TextStyle(fontSize: 11, color: faint),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _onMenuAction(
    String value,
    ChatState state,
    ChatController controller,
  ) async {
    switch (value) {
      case 'new':
        controller.newSession();
        break;
      case 'greeting':
        await _showGreetings(state, controller);
        break;
      case 'params':
        await _showGenerationParams();
        break;
      case 'reasoning':
        await _showReasoning(state);
        break;
      case 'clear':
        final ok = await showConfirmDialog(
          context,
          title: '清空当前对话',
          message: '当前会话的所有消息会被删除（角色卡本身不受影响）。',
          confirmText: '清空',
          danger: true,
        );
        if (ok) controller.clearMessages();
        break;
      case 'delete':
        final session = state.session;
        if (session == null) return;
        final ok = await showConfirmDialog(
          context,
          title: '删除会话',
          message: '该会话的全部消息将被永久删除。',
          confirmText: '删除',
          danger: true,
        );
        if (ok) controller.deleteSession(session.id);
        break;
    }
  }

  Future<void> _showMessageActions(
    BuildContext context,
    ChatMessage message,
    ChatState state,
    ChatController controller,
  ) async {
    parkKeyboard(context);
    final isLastAssistant = message.role == ChatRole.assistant &&
        state.messages.isNotEmpty &&
        state.messages.last.id == message.id;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.copy_rounded),
              title: const Text('复制内容'),
              onTap: () async {
                Navigator.of(sheetContext).pop();
                await Clipboard.setData(ClipboardData(text: message.content));
                if (context.mounted) showToast(context, '已复制');
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: Text(message.isUser ? '编辑并重新生成' : '编辑内容'),
              onTap: () async {
                Navigator.of(sheetContext).pop();
                await _editMessage(message, controller);
              },
            ),
            if (isLastAssistant)
              ListTile(
                leading: const Icon(Icons.refresh_rounded),
                title: const Text('重新生成'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  controller.regenerateLast();
                },
              ),
            ListTile(
              leading: Icon(
                Icons.delete_outline_rounded,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(
                '删除这条消息',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                controller.deleteMessage(message);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _editMessage(ChatMessage message, ChatController controller) async {
    parkKeyboard(context);
    final textController = TextEditingController(text: message.content);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(message.isUser ? '编辑消息并重新生成' : '编辑消息'),
        content: SizedBox(
          width: double.maxFinite,
          child: TextField(
            controller: textController,
            maxLines: 10,
            minLines: 4,
            autofocus: true,
            style: const TextStyle(fontSize: 14, height: 1.5),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(textController.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (result == null || result.trim().isEmpty) return;
    if (message.isUser) {
      await controller.editAndResend(message, result);
    } else {
      controller.editMessage(message, result);
    }
  }

  Future<void> _showSessions(
    BuildContext context,
    ChatState state,
    ChatController controller,
  ) async {
    parkKeyboard(context);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _SessionsSheet(state: state, controller: controller),
    );
  }

  Future<void> _showGreetings(ChatState state, ChatController controller) async {
    parkKeyboard(context);
    final card = state.card;
    if (card == null) return;
    final greetings = card.allGreetings;
    if (greetings.isEmpty) {
      showToast(context, '这张角色卡没有开场白');
      return;
    }

    final selected = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 420),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: greetings.length,
            itemBuilder: (context, index) => ListTile(
              leading: Icon(
                index == state.session?.greetingSeq
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 20,
              ),
              title: Text(
                index == 0 ? '主开场白' : '备选开场白 $index',
                style: const TextStyle(fontSize: 14),
              ),
              subtitle: Text(
                greetings[index],
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, height: 1.4),
              ),
              onTap: () => Navigator.of(sheetContext).pop(index),
            ),
          ),
        ),
      ),
    );

    if (selected == null) return;
    if (selected == state.session?.greetingSeq) return;
    if (!mounted) return;
    final ok = await showConfirmDialog(
      context,
      title: '切换开场白',
      message: '切换会用新的开场白重置当前会话，已有消息将被删除。',
      confirmText: '切换',
      danger: true,
    );
    if (ok) controller.switchGreeting(selected);
  }

  Future<void> _showGenerationParams() async {
    parkKeyboard(context);
    final settings = ref.read(appSettingsProvider);
    var temperature = settings.temperature;
    var contextLimit = settings.contextLimit;
    final apiConfig = ref.read(settingsRepositoryProvider).defaultApiConfig();

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '生成参数',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  '当前模型：${apiConfig?.model ?? '未配置'}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                _SliderRow(
                  label: '温度',
                  value: temperature,
                  min: 0,
                  max: 2,
                  divisions: 40,
                  display: temperature.toStringAsFixed(2),
                  onChanged: (v) => setSheetState(() => temperature = v),
                ),
                _SliderRow(
                  label: '上下文上限',
                  value: contextLimit.toDouble(),
                  min: 1024,
                  max: 16384,
                  divisions: 30,
                  display: '$contextLimit tokens',
                  onChanged: (v) =>
                      setSheetState(() => contextLimit = v.round()),
                ),
                const SizedBox(height: 8),
                Text(
                  '更长的上下文意味着更高的费用。修改后对后续请求生效。',
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.5,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () {
                      ref
                          .read(appSettingsProvider.notifier)
                          .setTemperature(temperature);
                      ref
                          .read(appSettingsProvider.notifier)
                          .setContextLimit(contextLimit);
                      Navigator.of(sheetContext).pop();
                    },
                    child: const Text('保存'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.display,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String display;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontSize: 13)),
            Text(
              display,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ],
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

/// 角色卡封面模糊背景
class _CoverBackdrop extends StatelessWidget {
  const _CoverBackdrop({required this.file});

  final File file;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        // 先降到 160px 再放大模糊：视觉一致，代价极低
        ImageFiltered(
          imageFilter: ImageFilter.blur(
            sigmaX: 70,
            sigmaY: 70,
            tileMode: TileMode.decal,
          ),
          child: Image.file(
            file,
            fit: BoxFit.cover,
            cacheWidth: 160,
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),
        ),
        // 压一层浅色/深色蒙版，保证文字可读
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: isDark
                  ? <Color>[
                      Colors.black.withOpacity(0.42),
                      Colors.black.withOpacity(0.62),
                    ]
                  : <Color>[
                      Colors.white.withOpacity(0.34),
                      Colors.white.withOpacity(0.56),
                    ],
            ),
          ),
        ),
      ],
    );
  }
}

/// 会话记录面板：普通态点选切换，管理态多选批量删除
class _SessionsSheet extends StatefulWidget {
  const _SessionsSheet({required this.state, required this.controller});

  final ChatState state;
  final ChatController controller;

  @override
  State<_SessionsSheet> createState() => _SessionsSheetState();
}

class _SessionsSheetState extends State<_SessionsSheet> {
  bool _managing = false;
  final Set<String> _selected = <String>{};

  Future<void> _deleteSelected() async {
    if (_selected.isEmpty) return;
    final ok = await showConfirmDialog(
      context,
      title: '删除会话',
      message: '选中的 ${_selected.length} 个会话及其全部消息将被永久删除。',
      confirmText: '删除',
      danger: true,
    );
    if (!ok) return;
    final ids = _selected.toList();
    if (mounted) Navigator.of(context).pop();
    widget.controller.deleteSessions(ids);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sessions = widget.state.sessions;

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 8, 4),
            child: Row(
              children: <Widget>[
                Text(
                  '会话记录',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: GlassPalette.inkOf(Theme.of(context).brightness),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${sessions.length} 个',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: GlassPalette.inkFaintOf(Theme.of(context).brightness),
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => setState(() {
                    _managing = !_managing;
                    _selected.clear();
                  }),
                  child: Text(_managing ? '完成' : '管理'),
                ),
              ],
            ),
          ),
          if (!_managing) ...<Widget>[
            ListTile(
              leading: const Icon(Icons.add_comment_outlined),
              title: const Text('新建会话'),
              onTap: () {
                Navigator.of(context).pop();
                widget.controller.newSession();
              },
            ),
            const Divider(height: 1),
          ],
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 380),
            child: ListView(
              shrinkWrap: true,
              children: sessions.map((session) {
                final active = session.id == widget.state.session?.id;
                final checked = _selected.contains(session.id);
                return ListTile(
                  leading: _managing
                      ? Checkbox(
                          value: checked,
                          onChanged: (_) => setState(() {
                            if (checked) {
                              _selected.remove(session.id);
                            } else {
                              _selected.add(session.id);
                            }
                          }),
                        )
                      : Icon(
                          active
                              ? Icons.radio_button_checked_rounded
                              : Icons.radio_button_unchecked_rounded,
                          size: 20,
                          color: active ? scheme.primary : scheme.outline,
                        ),
                  title: Text(
                    session.title.isEmpty ? '未命名会话' : session.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14),
                  ),
                  subtitle: Text(
                    '${session.messageCount} 条 · '
                    '${session.lastMessageAt == null ? '尚无消息' : formatRelative(session.lastMessageAt!)}',
                    style: const TextStyle(fontSize: 11.5),
                  ),
                  trailing: _managing
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.delete_outline_rounded, size: 18),
                          onPressed: () {
                            Navigator.of(context).pop();
                            widget.controller.deleteSession(session.id);
                          },
                        ),
                  onTap: _managing
                      ? () => setState(() {
                            if (checked) {
                              _selected.remove(session.id);
                            } else {
                              _selected.add(session.id);
                            }
                          })
                      : () {
                          Navigator.of(context).pop();
                          widget.controller.switchSession(session.id);
                        },
                );
              }).toList(),
            ),
          ),
          if (_managing)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: FilledButton.icon(
                onPressed: _selected.isEmpty ? null : _deleteSelected,
                icon: const Icon(Icons.delete_sweep_rounded, size: 18),
                label: Text(
                  _selected.isEmpty ? '选择要删除的会话' : '删除所选（${_selected.length}）',
                ),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(44),
                  backgroundColor: scheme.error,
                ),
              ),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
