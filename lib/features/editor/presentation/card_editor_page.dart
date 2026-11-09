import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app_providers.dart';
import '../../../core/prompt/prompt_builder.dart';
import '../../../core/prompt/status_parser.dart';
import '../../../core/prompt/token_estimator.dart';
import '../../../core/prompt/world_book_engine.dart';
import '../../../core/theme/fonts.dart';
import '../../../core/theme/glass_theme.dart';
import '../../../core/utils/ids.dart';
import '../../../core/utils/time_utils.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../../settings/domain/settings_models.dart';
import '../../characters/domain/character_card.dart';
import '../../characters/domain/world_entry.dart';
import '../../characters/domain/world_snippet.dart';
import '../../characters/presentation/world_snippet_picker.dart';
import '../../characters/presentation/controllers/character_list_controller.dart';
import '../../chat/presentation/controllers/chat_controller.dart';

/// 状态栏推荐模板：一份「完整状态栏应包含什么」的清单。
///
/// 模型本身并不知道这个 App 的状态栏该有哪些条目，只有初始状态时容易漏项、
/// 自造新键或用长句描述。点「填入推荐模板」会写进 statusTemplate 字段，
/// 随后由 PromptBuilder 作为「状态栏条目模板」注入协议里。
const String kDefaultStatusTemplate = '''心情：<当前情绪，两个字以内>
好感度：<0-100 的数字>
时间：<清晨 / 上午 / 午后 / 傍晚 / 深夜>
地点：<当前所在场景>
衣着：<简要描述>
关系：<与对方的关系状态>''';

class CardEditorPage extends ConsumerStatefulWidget {
  const CardEditorPage({super.key, this.cardId, this.embedded = false});

  final String? cardId;

  /// 作为底部导航的 Tab 使用时为 true：不显示返回按钮，保存后不 pop
  final bool embedded;

  @override
  ConsumerState<CardEditorPage> createState() => _CardEditorPageState();
}

class _CardEditorPageState extends ConsumerState<CardEditorPage> {
  final _description = TextEditingController();
  final _personality = TextEditingController();
  final _scenario = TextEditingController();
  final _mesExample = TextEditingController();
  final _firstMes = TextEditingController();
  final _systemPrompt = TextEditingController();
  final _postHistory = TextEditingController();
  final _statusRules = TextEditingController();
  final _statusTemplate = TextEditingController();
  final _statusText = TextEditingController();

  // 普通模式的引导式人设输入
  final _gGender = TextEditingController();
  final _gAge = TextEditingController();
  final _gCharacter = TextEditingController();
  final _gLooks = TextEditingController();
  final _gKinks = TextEditingController();
  final _gExtra = TextEditingController();

  bool _statusEnabled = false;
  String _statusFormat = statusFormatTemplate;
  final List<_StatusEntry> _statusEntries = <_StatusEntry>[];
  final List<_WorldEntryDraft> _worldEntries = <_WorldEntryDraft>[];
  bool _advancedMode = false;

  /// 用户是否真的动过基础模式的引导字段。
  ///
  /// 只有它为 true 时，保存才会用「性别：…/性格：…」这套字段重排人设；
  /// 否则一律以 [_description] 里的原文为准。没有这个开关的话，
  /// 打开一张带段落、空行的卡（默认落在基础模式）随手一存，
  /// 人设就会被压成单行 —— 作者写的换行全部消失。
  bool _guidedDirty = false;

  /// 高级模式下「角色人设」是否收起（方便直接滑到世界书）
  /// 各分区展开状态：id 在集合里表示已收起。默认全展开。
  final Set<String> _collapsedSections = <String>{};

  /// 全部分区 id（顺序仅用于展示与「全部收起」）
  static const List<String> _sectionIds = <String>[
    'persona',
    'system',
    'example',
    'greeting',
    'status',
    'world',
  ];

  bool _isExpanded(String id) => !_collapsedSections.contains(id);

  /// 右侧边滑块的小窗口是否打开
  bool _edgePanelOpen = false;

  final List<TextEditingController> _greetings = <TextEditingController>[];

  String _cardName = '';
  String _cardSummary = '';
  List<String> _cardTags = const <String>[];
  String? _avatarPath;
  Uint8List? _pendingAvatar;
  String? _editingId;
  int _createdAt = 0;
  String? _rawJson;
  String _source = 'manual';

  bool _dirty = false;
  bool _saving = false;
  bool _draftRestored = false;
  Timer? _draftTimer;

  /// 已收藏内容的指纹集合（标题 + 内容），用来判断条目的 ☆ 是否实心。
  ///
  /// 用「标题 + 内容」而不是只比标题：卡里的条目被改动内容后，
  /// 它就是另一本世界书了，星标应当回到空心。
  Set<String> _favoriteKeys = <String>{};

  static String _snippetKey(String title, String content) =>
      '${title.trim()}\u0000${content.trim()}';

  bool _isCollected(String title, String content) =>
      _favoriteKeys.contains(_snippetKey(title, content));

  @override
  void initState() {
    super.initState();
    _refreshFavoriteKeys();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  void _refreshFavoriteKeys() {
    _favoriteKeys = ref
        .read(worldSnippetDaoProvider)
        .list()
        .map((s) => _snippetKey(s.title, s.content))
        .toSet();
  }

  @override
  void dispose() {
    _draftTimer?.cancel();
    for (final c in [
      _description,
      _personality,
      _scenario,
      _mesExample,
      _firstMes,
      _systemPrompt,
      _postHistory,
      _statusRules,
      _statusTemplate,
      _statusText,
      _gGender,
      _gAge,
      _gCharacter,
      _gLooks,
      _gKinks,
      _gExtra,
    ]) {
      c.dispose();
    }
    for (final c in _greetings) {
      c.dispose();
    }
    for (final e in _statusEntries) {
      e.dispose();
    }
    for (final e in _worldEntries) {
      e.dispose();
    }
    super.dispose();
  }

  void _load() {
    final repo = ref.read(characterRepositoryProvider);
    if (widget.cardId != null) {
      final card = repo.byId(widget.cardId!);
      if (card != null) {
        _fillFromCard(card);
        return;
      }
    }
    _restoreDraft();
  }

  void _fillFromCard(CharacterCard card) {
    _editingId = card.id;
    _createdAt = card.createdAt;
    _avatarPath = card.avatarPath;
    _rawJson = card.rawJson;
    _source = card.source;
    _cardName = card.name;
    _cardSummary = card.summary;
    _cardTags = List<String>.from(card.tags);
    _description.text = _mergePersona(
      card.description,
      card.scenario,
      card.personality,
      postHistory: card.postHistoryInstructions,
    );
    // 带段落 / 空行 / 【】小节的卡直接进高级模式：
    // 基础模式那几个字段装不下排版，用户一编辑就会把换行压掉。
    _advancedMode = _needsAdvancedPersona(_description.text);
    _guidedDirty = false;
    _personality.text = '';
    _scenario.text = '';
    _systemPrompt.text = card.systemPrompt;
    _postHistory.text = '';
    _mesExample.text = card.mesExample;
    _firstMes.text = card.firstMes;
    _systemPrompt.text = card.systemPrompt;
    _postHistory.text = card.postHistoryInstructions;
    _fillGuidedFromDescription(card.description);
    for (final c in _greetings) {
      c.dispose();
    }
    _greetings
      ..clear()
      ..addAll(card.alternateGreetings
          .map((g) => TextEditingController(text: g)));

    _statusEnabled = card.statusEnabled;
    _statusFormat = card.statusFormat;
    _statusRules.text = card.statusRules;
    _statusTemplate.text = card.statusTemplate;
    _statusText.text = StatusParser.formatLines(card.statusInitial);
    for (final e in _statusEntries) {
      e.dispose();
    }
    _statusEntries
      ..clear()
      ..addAll(card.statusInitial.entries.map(
        (e) => _StatusEntry(
          key: e.key,
          value: StatusParser.displayValue(e.value),
        ),
      ));
    for (final e in _worldEntries) {
      e.dispose();
    }
    _worldEntries
      ..clear()
      ..addAll(card.worldBook.map(_WorldEntryDraft.fromEntry));
    setState(() {});
  }

  void _restoreDraft() {
    final raw = ref.read(settingsRepositoryProvider).rawSetting(SettingKeys.editorDraft);
    if (raw == null || raw.isEmpty) return;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final name = (map['name'] as String?) ?? '';
      if (name.trim().isEmpty) return;
      _editingId = map['id'] as String?;
      _createdAt = (map['createdAt'] as int?) ?? 0;
      _avatarPath = map['avatarPath'] as String?;
      _cardName = name;
      _cardSummary = (map['summary'] as String?) ?? '';
      _cardTags = ((map['tags'] as List?) ?? const []).whereType<String>().toList();
      _description.text = _mergePersona(
        (map['description'] as String?) ?? '',
        (map['scenario'] as String?) ?? '',
        (map['personality'] as String?) ?? '',
        postHistory: (map['postHistory'] as String?) ?? '',
      );
      _personality.text = '';
      _scenario.text = '';
      _systemPrompt.text = (map['systemPrompt'] as String?) ?? '';
      _postHistory.text = '';
      _mesExample.text = (map['mesExample'] as String?) ?? '';
      _firstMes.text = (map['firstMes'] as String?) ?? '';
      _systemPrompt.text = (map['systemPrompt'] as String?) ?? '';
      _postHistory.text = (map['postHistory'] as String?) ?? '';
      _fillGuidedFromDescription(_description.text);
      for (final c in _greetings) {
        c.dispose();
      }
      _greetings
        ..clear()
        ..addAll(((map['greetings'] as List?) ?? const [])
            .whereType<String>()
            .map((g) => TextEditingController(text: g)));
      _statusEnabled = (map['statusEnabled'] as bool?) ?? false;
      _statusFormat = (map['statusFormat'] as String?) ?? statusFormatTemplate;
      _advancedMode = (map['advancedMode'] as bool?) ?? false;
      _guidedDirty = (map['guidedDirty'] as bool?) ?? false;
      _statusRules.text = (map['statusRules'] as String?) ?? '';
      _statusTemplate.text = (map['statusTemplate'] as String?) ?? '';
      _statusText.text = (map['statusText'] as String?) ?? '';
      for (final e in _statusEntries) {
        e.dispose();
      }
      _statusEntries.clear();
      final initial = map['statusInitial'];
      if (initial is Map) {
        initial.forEach((k, v) {
          _statusEntries.add(
            _StatusEntry(key: k.toString(), value: v.toString()),
          );
        });
      }
      for (final e in _worldEntries) {
        e.dispose();
      }
      _worldEntries.clear();
      final world = map['worldBook'];
      if (world is List) {
        for (final item in world) {
          if (item is Map) {
            _worldEntries.add(
              _WorldEntryDraft.fromEntry(
                WorldEntry.fromJson(Map<String, dynamic>.from(item)),
              ),
            );
          }
        }
      }
      final guided = map['guided'];
      if (guided is Map) {
        _gGender.text = (guided['gender'] as String?) ?? '';
        _gAge.text = (guided['age'] as String?) ?? '';
        _gCharacter.text = (guided['character'] as String?) ?? '';
        _gLooks.text = (guided['looks'] as String?) ?? '';
        _gKinks.text = (guided['kinks'] as String?) ?? '';
        _gExtra.text = (guided['extra'] as String?) ?? '';
      }
      _draftRestored = true;
      setState(() {});
    } catch (_) {
      // 草稿损坏时直接忽略
    }
  }

  void _scheduleDraftSave() {
    _dirty = true;
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 800), _saveDraft);
  }

  void _saveDraft() {
    final map = <String, dynamic>{
      'id': _editingId,
      'createdAt': _createdAt,
      'avatarPath': _avatarPath,
      'name': _cardName,
      'summary': _cardSummary,
      'tags': _cardTags,
      'description': _description.text,
      'personality': _personality.text,
      'scenario': _scenario.text,
      'mesExample': _mesExample.text,
      'firstMes': _firstMes.text,
      'systemPrompt': _systemPrompt.text,
      'postHistory': _postHistory.text,
      'greetings': _greetings.map((c) => c.text).toList(),
      'statusEnabled': _statusEnabled,
      'statusFormat': _statusFormat,
      'advancedMode': _advancedMode,
      'guidedDirty': _guidedDirty,
      'statusRules': _statusRules.text,
      'statusTemplate': _statusTemplate.text,
      'statusText': _statusText.text,
      'statusInitial': <String, String>{
        for (final e in _statusEntries)
          if (e.key.isNotEmpty) e.key: e.rawValue,
      },
      'guided': <String, String>{
        'gender': _gGender.text,
        'age': _gAge.text,
        'character': _gCharacter.text,
        'looks': _gLooks.text,
        'kinks': _gKinks.text,
        'extra': _gExtra.text,
      },
      'worldBook': _worldEntries
          .map((e) => e.toEntry().toJson())
          .toList(),
    };
    ref
        .read(settingsRepositoryProvider)
        .setRaw(SettingKeys.editorDraft, jsonEncode(map));
  }

  void _clearDraft() {
    _draftTimer?.cancel();
    ref.read(settingsRepositoryProvider).removeRaw(SettingKeys.editorDraft);
  }

  CharacterCard _buildCard() {
    final now = nowMs();
    // 基础模式只在「用户真的改过引导字段」时用字段重排人设，否则以原文为准。
    // 这样换行、空行、缩进这些作者用来分段的排版不会被保存动作吃掉。
    final rawDescription = _description.text.trim();
    final description = _advancedMode
        ? rawDescription
        : (_guidedDirty || rawDescription.isEmpty
            ? _descriptionFromGuided()
            : rawDescription);
    return CharacterCard(
      id: _editingId ?? newId(),
      name: _cardName.trim().isEmpty ? '未命名角色' : _cardName.trim(),
      summary: _cardSummary,
      description: description,
      personality: _personality.text.trim(),
      scenario: _scenario.text.trim(),
      firstMes: _firstMes.text.trim(),
      mesExample: _mesExample.text.trim(),
      systemPrompt: _systemPrompt.text.trim(),
      postHistoryInstructions: _postHistory.text.trim(),
      avatarPath: _avatarPath,
      source: _source,
      rawJson: _rawJson,
      createdAt: _createdAt == 0 ? now : _createdAt,
      updatedAt: now,
      tags: _cardTags,
      alternateGreetings: _greetings
          .map((c) => c.text.trim())
          .where((t) => t.isNotEmpty)
          .toList(),
      statusEnabled: _statusEnabled,
      statusInitial: (_advancedMode || _statusFormat == statusFormatTemplate)
          ? (StatusParser.parseLines(_statusText.text) ?? <String, dynamic>{})
          : <String, dynamic>{
              for (final e in _statusEntries)
                if (e.key.isNotEmpty) e.key: e.parsedValue,
            },
      statusRules: _statusRules.text.trim(),
      statusTemplate: _statusTemplate.text.trim(),
      statusFormat: _advancedMode ? statusFormatTemplate : _statusFormat,
      worldBook: _worldEntries
          .map((e) => e.toEntry())
          .where((e) => e.comment.trim().isNotEmpty || e.content.trim().isNotEmpty)
          .toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: widget.embedded,
      onPopInvokedWithResult: widget.embedded
          ? null
          : (didPop, _) async {
              if (didPop) return;
              // 离开页面前先把 debounce 中的草稿立即落盘（<800ms 的尾巴不丢）
              if (_dirty) {
                _draftTimer?.cancel();
                _saveDraft();
              }
              if (!_dirty) {
                Navigator.of(context).pop();
                return;
              }
              final ok = await showConfirmDialog(
                context,
                title: '放弃修改？',
                message: '当前编辑内容尚未保存。草稿已自动保留，下次进入可继续编辑。',
                confirmText: '放弃',
                danger: true,
              );
              if (ok && context.mounted) Navigator.of(context).pop();
            },
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: !widget.embedded,
          title: Text(_editingId == null ? '编写角色卡' : '编辑角色卡'),
          actions: [
            if (widget.embedded)
              IconButton(
                tooltip: '新建一张',
                onPressed: _resetForm,
                icon: const Icon(Icons.note_add_outlined),
              ),
            IconButton(
              tooltip: '预览提示词',
              onPressed: _previewPrompt,
              icon: const Icon(Icons.visibility_outlined),
            ),
            TextButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('保存'),
            ),
            const SizedBox(width: 4),
          ],
        ),
        // 点击任意空白处：收起键盘并立即落盘草稿（=保存）。
        // 再点击原输入框可重新唤起键盘继续编辑；内容一直在 controller 里。
        body: Stack(
          children: <Widget>[
            GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () {
            FocusManager.instance.primaryFocus?.unfocus();
            if (_dirty && (_draftTimer?.isActive ?? false)) {
              _draftTimer?.cancel();
              _saveDraft();
            }
          },
          child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 150),
          children: [
            if (_draftRestored)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.restore_rounded, size: 16),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '已恢复上次未保存的草稿',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            _buildHeader(),
            const SizedBox(height: 12),
            _buildModeToggle(),
            const SizedBox(height: 16),
            _section(
              id: 'persona',
              title: '人设',
              summary: _personaSummary(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _advancedMode
                    ? _buildAdvancedPersona()
                    : _buildGuidedPersona(),
              ),
            ),
            const SizedBox(height: 16),
            _section(
              id: 'example',
              title: '对话示例',
              summary: _mesExample.text.trim().isEmpty
                  ? '未填写'
                  : '${_mesExample.text.runes.length} 字',
              child: _field('示例对话 (mes_example)', _mesExample,
                  hint: '<START>\n{{char}}: …\n{{user}}: …', minLines: 7),
            ),
            const SizedBox(height: 16),
            _section(
              id: 'greeting',
              title: '开场白',
              summary: _greetingSummary(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _field('主开场白 (first_mes)', _firstMes,
                      hint: '对话开始时角色的第一句话', minLines: 5),
                  _buildGreetingsEditor(),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (_advancedMode) ...<Widget>[
              _buildStatusSection(),
              const SizedBox(height: 16),
              _buildWorldBookSection(),
            ],
          ],
          ),
            ),
            // 右侧边缘滑块：点开一个小窗口，收起动作放在窗口里。
            // 不再用悬浮按钮——它会盖住分区点选栏。
            if (_edgePanelOpen)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _edgePanelOpen = false),
                ),
              ),
            Positioned(
              right: 10,
              top: MediaQuery.sizeOf(context).height * 0.30,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _buildEdgePanel(),
                  const SizedBox(width: 8),
                  _buildEdgeButton(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 点击某个分区的点选栏：展开 / 收起该分区
  void _toggleSection(String id) {
    FocusManager.instance.primaryFocus?.unfocus();
    if (_isExpanded(id)) {
      // 收起前先把草稿落盘，避免长文本丢掉最后一段
      _draftTimer?.cancel();
      _saveDraft();
    }
    setState(() {
      if (!_collapsedSections.remove(id)) _collapsedSections.add(id);
    });
  }

  /// 悬浮按钮：只负责收起（不负责展开，展开交给各分区的点选栏）
  void _collapseAllSections() {
    FocusManager.instance.primaryFocus?.unfocus();
    _draftTimer?.cancel();
    _saveDraft();
    setState(() => _collapsedSections.addAll(_sectionIds));
  }

  String _personaSummary() {
    final n = _description.text.runes.length;
    return n == 0 ? '未填写' : '$n 字';
  }

  String _greetingSummary() {
    final parts = <String>[];
    if (_firstMes.text.trim().isNotEmpty) parts.add('主开场白');
    if (_greetings.isNotEmpty) parts.add('${_greetings.length} 条备选');
    return parts.isEmpty ? '未填写' : parts.join(' · ');
  }

  /// 右侧「收起全部」入口。
  ///
  /// 做成圆形按钮而不是贴边竖条：贴边竖条 + 方向箭头在视觉上等于「拖我」，
  /// 但 Android 手势导航把屏幕左右边缘的横滑留给了系统返回，边缘滑块会和
  /// 返回手势抢同一个区域，没法可靠分开。所以这里明确是「点」的语义。
  Widget _buildEdgeButton() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = accentOf(context);
    final fill = isDark
        ? const Color(0xFF1A2431).withOpacity(0.74)
        : Colors.white.withOpacity(0.86);

    return Tooltip(
      message: _edgePanelOpen ? '关闭' : '收起全部分区',
      child: GestureDetector(
        onTap: () => setState(() => _edgePanelOpen = !_edgePanelOpen),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _edgePanelOpen ? accent.withOpacity(0.18) : fill,
            border: Border.all(
              color: accent.withOpacity(_edgePanelOpen ? 0.7 : 0.45),
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: accent.withOpacity(0.20),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Icon(
            _edgePanelOpen
                ? Icons.close_rounded
                : Icons.unfold_less_rounded,
            size: 19,
            color: accent,
          ),
        ),
      ),
    );
  }

  /// 滑块点开的小窗口：收起全部
  Widget _buildEdgePanel() {
    final brightness = Theme.of(context).brightness;
    final expandedCount = _sectionIds.where((id) => _isExpanded(id)).length;

    return IgnorePointer(
      ignoring: !_edgePanelOpen,
      child: AnimatedSlide(
        offset: _edgePanelOpen ? Offset.zero : const Offset(0.3, 0),
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        child: AnimatedOpacity(
          opacity: _edgePanelOpen ? 1 : 0,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          child: Padding(
            padding: const EdgeInsets.only(top: 1),
            child: GlassSurface(
              radius: 16,
              blur: 18,
              padding: EdgeInsets.zero,
              lift: 0.8,
              onTap: expandedCount == 0
                  ? null
                  : () {
                      _collapseAllSections();
                      setState(() => _edgePanelOpen = false);
                    },
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      Icons.unfold_less_rounded,
                      size: 16,
                      color: GlassPalette.inkSoftOf(brightness),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          '收起全部',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: GlassPalette.inkOf(brightness),
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          expandedCount == 0
                              ? '已全部收起'
                              : '$expandedCount 个分区展开中',
                          style: TextStyle(
                            fontSize: 10,
                            color: GlassPalette.inkFaintOf(brightness),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 分区点选栏：点击展开 / 收起。flat=true 时不画底色（用于卡片内部）
  Widget _sectionBar({
    required String id,
    required String title,
    String? summary,
    Widget? trailing,
    bool flat = false,
  }) {
    final brightness = Theme.of(context).brightness;
    final isDark = brightness == Brightness.dark;
    final expanded = _isExpanded(id);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _toggleSection(id),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: flat ? 2 : 12, vertical: 10),
          decoration: flat
              ? null
              : BoxDecoration(
                  color: isDark
                      ? Colors.white.withOpacity(0.06)
                      : Colors.white.withOpacity(0.52),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: GlassPalette.hairline(brightness)),
                ),
          child: Row(
            children: <Widget>[
              Text(
                title,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                  // 分区标题（人设 / 系统提示词 / 状态栏…）统一跟随主题色：
                  // 之前暗色下写死 skySoft，用户换主题色时这里不会变。
                  color: accentOf(context),
                ),
              ),
              if (summary != null) ...<Widget>[
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    summary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.5,
                      color: accentFaintOf(context),
                    ),
                  ),
                ),
              ] else
                const Spacer(),
              AnimatedRotation(
                turns: expanded ? 0.5 : 0,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                child: Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 18,
                  color: GlassPalette.inkFaintOf(brightness),
                ),
              ),
              if (trailing != null) ...<Widget>[
                const SizedBox(width: 4),
                trailing,
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 一个可折叠分区：点选栏 + 内容
  Widget _section({
    required String id,
    required String title,
    String? summary,
    Widget? trailing,
    required Widget child,
  }) {
    final expanded = _isExpanded(id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _sectionBar(id: id, title: title, summary: summary, trailing: trailing),
        ClipRect(
          child: AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: expanded
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(2, 10, 2, 0),
                    child: child,
                  )
                : const SizedBox(width: double.infinity),
          ),
        ),
      ],
    );
  }

  /// 状态栏配置区
  Widget _buildStatusSection() {
    final brightness = Theme.of(context).brightness;
    final faint = GlassPalette.inkFaintOf(brightness);
    final textMode = _advancedMode || _statusFormat == statusFormatTemplate;

    return _section(
      id: 'status',
      title: '状态栏',
      summary: _statusEnabled ? '已开启' : '未开启',
      trailing: _MiniSwitch(
        value: _statusEnabled,
        onChanged: (v) {
          setState(() {
            _statusEnabled = v;
            if (!v) return;
            if (textMode && _statusText.text.trim().isEmpty) {
              _statusText.text = '心情：紧张\n好感度：20';
            } else if (!textMode && _statusEntries.isEmpty) {
              _statusEntries
                ..add(_StatusEntry(key: '好感度', value: '0'))
                ..add(_StatusEntry(key: '时间', value: '清晨'));
            }
          });
          _scheduleDraftSave();
        },
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            textMode
                ? '角色会在每次回复末尾维护一段纯文本状态，像「心情：紧张」这样。'
                : '角色会在每次回复末尾维护一组键值，适合需要进度条的场合。',
            style: TextStyle(fontSize: 11, height: 1.5, color: faint),
          ),
          if (_statusEnabled) ...<Widget>[
            if (!_advancedMode) ...<Widget>[
              const SizedBox(height: 12),
              _statusLabel('输出格式'),
              Row(
                children: <Widget>[
                  Expanded(
                    child: _formatPill(
                      title: '纯文本',
                      subtitle: '键：值 逐行',
                      selected: textMode,
                      onTap: () {
                        setState(() {
                          _statusFormat = statusFormatTemplate;
                          if (_statusText.text.trim().isEmpty) {
                            _statusText.text = _statusTextFromEntries();
                          }
                        });
                        _scheduleDraftSave();
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _formatPill(
                      title: 'JSON',
                      subtitle: '键值对',
                      selected: !textMode,
                      onTap: () {
                        setState(() {
                          final parsed = StatusParser.parseLines(_statusText.text);
                          _statusFormat = statusFormatJson;
                          if (parsed != null && parsed.isNotEmpty) {
                            for (final e in _statusEntries) {
                              e.dispose();
                            }
                            _statusEntries
                              ..clear()
                              ..addAll(parsed.entries.map(
                                (e) => _StatusEntry(
                                  key: e.key,
                                  value: StatusParser.displayValue(e.value),
                                ),
                              ));
                          }
                        });
                        _scheduleDraftSave();
                      },
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            _statusLabel('初始状态'),
            if (textMode)
              TextField(
                controller: _statusText,
                minLines: 4,
                maxLines: null,
                scrollPhysics: const NeverScrollableScrollPhysics(),
                keyboardType: TextInputType.multiline,
                onChanged: (_) {
                  setState(() {});
                  _scheduleDraftSave();
                },
                style: const TextStyle(fontSize: 13.5, height: 1.6),
                decoration: const InputDecoration(
                  hintText: '每行一个「键：值」，例如：\n心情：紧张\n好感度：20\n时间：清晨',
                ),
              )
            else ...<Widget>[
              for (var i = 0; i < _statusEntries.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        flex: 4,
                        child: TextField(
                          controller: _statusEntries[i].keyController,
                          style: const TextStyle(fontSize: 13),
                          onChanged: (_) => _scheduleDraftSave(),
                          decoration: const InputDecoration(
                            hintText: '键，如 好感度',
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 5,
                        child: TextField(
                          controller: _statusEntries[i].valueController,
                          style: const TextStyle(fontSize: 13),
                          onChanged: (_) {
                            setState(() {});
                            _scheduleDraftSave();
                          },
                          decoration: const InputDecoration(
                            hintText: '值，如 0 或 清晨',
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: '删除',
                        visualDensity: VisualDensity.compact,
                        onPressed: () {
                          setState(() {
                            _statusEntries.removeAt(i).dispose();
                          });
                          _scheduleDraftSave();
                        },
                        icon: const Icon(Icons.remove_circle_outline_rounded,
                            size: 18),
                      ),
                    ],
                  ),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () {
                    setState(() => _statusEntries.add(_StatusEntry()));
                    _scheduleDraftSave();
                  },
                  icon: const Icon(Icons.add_rounded, size: 17),
                  label: const Text('添加一项'),
                ),
              ),
            ],
            const SizedBox(height: 12),
            _statusLabel('状态栏模板'),
            Text(
              '告诉模型「一个完整的状态栏应该包含哪些条目」。'
              '留空时模型只能看到上面的初始状态，容易漏项或自造条目。',
              style: TextStyle(fontSize: 10.5, height: 1.5, color: faint),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _statusTemplate,
              minLines: 3,
              maxLines: null,
              scrollPhysics: const NeverScrollableScrollPhysics(),
              keyboardType: TextInputType.multiline,
              onChanged: (_) => _scheduleDraftSave(),
              style: const TextStyle(fontSize: 13, height: 1.5),
              decoration: const InputDecoration(
                hintText: '心情：<当前情绪>\n'
                    '好感度：<0-100>\n'
                    '时间：<时段>\n'
                    '地点：<当前场景>',
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () {
                  setState(() {
                    _statusTemplate.text = kDefaultStatusTemplate;
                  });
                  _scheduleDraftSave();
                },
                icon: const Icon(Icons.auto_awesome_rounded, size: 16),
                label: const Text('填入推荐模板'),
              ),
            ),
            if (_advancedMode) ...<Widget>[
              const SizedBox(height: 6),
              _statusLabel('更新规则'),
              TextField(
                controller: _statusRules,
                minLines: 3,
                maxLines: null,
                scrollPhysics: const NeverScrollableScrollPhysics(),
                keyboardType: TextInputType.multiline,
                onChanged: (_) => _scheduleDraftSave(),
                style: const TextStyle(fontSize: 13, height: 1.5),
                decoration: const InputDecoration(
                  hintText: '告诉模型什么时候、怎么改这些值。例如：\n'
                      '· 好感度随互动变化，每次 +1~3，被冒犯时 -5\n'
                      '· 时间随场景推进，跨度不超过一天',
                ),
              ),
            ],
            const SizedBox(height: 10),
            Text(
              '预览',
              style: TextStyle(
                fontSize: 10.5,
                letterSpacing: 0.8,
                color: faint,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: brightness == Brightness.dark
                    ? Colors.white.withOpacity(0.05)
                    : Colors.white.withOpacity(0.55),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: GlassPalette.hairline(brightness)),
              ),
              child: _buildStatusPreview(brightness),
            ),
          ],
        ],
      ),
    );
  }

  String _statusTextFromEntries() => StatusParser.formatLines(
        <String, dynamic>{
          for (final e in _statusEntries)
            if (e.key.isNotEmpty) e.key: e.parsedValue,
        },
      );

  Map<String, dynamic> _currentStatusValues() {
    if (_advancedMode || _statusFormat == statusFormatTemplate) {
      return StatusParser.parseLines(_statusText.text) ?? <String, dynamic>{};
    }
    return <String, dynamic>{
      for (final e in _statusEntries)
        if (e.key.isNotEmpty) e.key: e.parsedValue,
    };
  }


  Widget _buildStatusPreview(Brightness brightness) {
    final values = _currentStatusValues();
    if (values.isEmpty) {
      return Text(
        _statusFormat == statusFormatTemplate
            ? '先在上面写至少一行「键：值」'
            : '先添加至少一项初始状态',
        style: TextStyle(
          fontSize: 11.5,
          color: GlassPalette.inkFaintOf(brightness),
        ),
      );
    }
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: <Widget>[
        for (final e in values.entries)
          GlassChip(
            label: '${e.key} ${StatusParser.displayValue(e.value)}',
            color: Theme.of(context).colorScheme.primary,
            dense: true,
          ),
      ],
    );
  }

  Widget _formatPill({
    required String title,
    required String subtitle,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final brightness = Theme.of(context).brightness;
    final scheme = Theme.of(context).colorScheme;
    final faint = GlassPalette.inkFaintOf(brightness);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: selected
              ? scheme.primary.withOpacity(brightness == Brightness.dark ? 0.22 : 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? scheme.primary.withOpacity(0.5) : GlassPalette.hairline(brightness),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              title,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: selected ? scheme.primary : GlassPalette.inkOf(brightness),
              ),
            ),
            const SizedBox(height: 2),
            Text(subtitle, style: TextStyle(fontSize: 10, color: faint)),
          ],
        ),
      ),
    );
  }

  Widget _statusLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 11,
            letterSpacing: 0.6,
            color: accentFaintOf(context),
          ),
        ),
      );

  /// 普通模式：带字段标签的引导式人设输入
  List<Widget> _buildGuidedPersona() {
    final brightness = Theme.of(context).brightness;
    final scheme = Theme.of(context).colorScheme;

    return <Widget>[
      GlassSurface(
        radius: 20,
        blur: 14,
        alpha: brightness == Brightness.dark ? 0.55 : 0.52,
        lift: 0.7,
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _guidedRow('性别', _gGender, '女', scheme),
            _guidedRow('年龄', _gAge, '19', scheme),
            _guidedRow('性格', _gCharacter, '活泼、爱撒娇、占有欲强', scheme,
                multiline: true),
            _guidedRow('外貌', _gLooks, '身高167cm，淡粉色长发，常穿校服', scheme,
                multiline: true),
            _guidedRow('癖好', _gKinks, '喜欢被摸头发、怕痒', scheme,
                multiline: true),
            _guidedRow(
              '补充',
              _gExtra,
              '其他想补充的设定，写多少都行',
              scheme,
              minLines: 3,
              multiline: true,
            ),
          ],
        ),
      ),
    ];
  }

  Widget _guidedRow(
    String label,
    TextEditingController controller,
    String hint,
    ColorScheme scheme, {
    int minLines = 1,
    bool multiline = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            margin: const EdgeInsets.only(top: 7),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: scheme.primary.withOpacity(0.14),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: scheme.primary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              minLines: minLines,
              // 多行档随内容长高，Enter 直接换行；单行档 Enter 只会收起键盘
              maxLines: multiline ? null : 1,
              scrollPhysics:
                  multiline ? const NeverScrollableScrollPhysics() : null,
              keyboardType: multiline ? TextInputType.multiline : null,
              onChanged: (_) {
                _guidedDirty = true;
                _scheduleDraftSave();
              },
              style: const TextStyle(fontSize: 14, height: 1.5),
              decoration: InputDecoration(
                hintText: hint,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 9),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 高级模式：一个窗口写完整个角色的人设
  ///
  /// 底层仍是 description 一处字段；导入卡里的 scenario / personality
  /// 会在载入时按段落前缀并进同一个文本，保存时收敛到一处，不再分散。
  List<Widget> _buildAdvancedPersona() {
    final brightness = Theme.of(context).brightness;
    return <Widget>[
      GlassSurface(
        radius: 20,
        blur: 14,
        alpha: brightness == Brightness.dark ? 0.55 : 0.52,
        lift: 0.7,
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '角色人设',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 4),
              Text(
                '角色是谁、世界长什么样、希望怎么演，都写在这里：身份、年龄、外貌、性格、经历、'
                '说话方式、周围的人与关系、人称与格式、回复长度、禁忌。',
                style: TextStyle(
                  fontSize: 10.5,
                  height: 1.5,
                  color: accentFaintOf(context),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _description,
                // 两个都要：maxLines=null 让框随内容长高（不产生内部滚动区），
                // scrollPhysics=Never 保证 EditableText 内部的 Scrollable 永远不抢纵向拖动。
                // 只设 maxLines 时，一旦聚焦/键盘弹出使可视区变矮，内部滚动仍会接管手势，
                // 表现就是「手指落在输入框里滑不动，落在外面能滑」。
                minLines: 14,
                maxLines: null,
                scrollPhysics: const NeverScrollableScrollPhysics(),
                onChanged: (_) => _scheduleDraftSave(),
                style: const TextStyle(fontSize: 14, height: 1.6),
                decoration: const InputDecoration(
                  hintText: '在这里写下这个角色的一切……',
                ),
              ),
          ],
        ),
      ),
    ];
  }

  /// 人设文本是否「基础模式的字段装不下」。
  ///
  /// 判据：出现空行（段落分隔）、【】小节标题，或有两行以上不是 `键：值` 形式。
  /// 这类文本走基础模式保存会被压成一串单行，所以载入时直接进高级模式。
  static bool _needsAdvancedPersona(String text) {
    if (text.trim().isEmpty) return false;
    if (RegExp(r'\n[ \t]*\n').hasMatch(text)) return true;
    var stray = 0;
    for (final raw in text.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('【')) return true;
      if (!RegExp(r'^[^：:]{1,8}[：:]').hasMatch(line)) stray++;
    }
    return stray >= 2;
  }

  /// 把导入卡里分散的人设段落并进同一段文本
  static String _mergePersona(
    String description,
    String scenario,
    String personality, {
    String systemPrompt = '',
    String postHistory = '',
  }) {
    final parts = <String>[];
    if (description.trim().isNotEmpty) parts.add(description.trim());
    if (scenario.trim().isNotEmpty) parts.add('【世界观】\n${scenario.trim()}');
    if (personality.trim().isNotEmpty) {
      parts.add('【扮演与输出规则】\n${personality.trim()}');
    }
    if (systemPrompt.trim().isNotEmpty) {
      parts.add('【系统提示】\n${systemPrompt.trim()}');
    }
    if (postHistory.trim().isNotEmpty) {
      parts.add('【历史后置指令】\n${postHistory.trim()}');
    }
    return parts.join('\n\n');
  }

  String _descriptionFromGuided() {
    final pairs = <String, String>{
      '性别': _gGender.text.trim(),
      '年龄': _gAge.text.trim(),
      '性格': _gCharacter.text.trim(),
      '外貌': _gLooks.text.trim(),
      '癖好': _gKinks.text.trim(),
    };
    final buffer = StringBuffer();
    for (final e in pairs.entries) {
      if (e.value.isEmpty) continue;
      buffer.writeln('${e.key}：${e.value}');
    }
    final extra = _gExtra.text.trim();
    if (extra.isNotEmpty) {
      buffer.writeln(extra);
    }
    return buffer.toString().trim();
  }

  void _fillGuidedFromDescription(String text) {
    final known = <String, TextEditingController>{
      '性别': _gGender,
      '年龄': _gAge,
      '性格': _gCharacter,
      '外貌': _gLooks,
      '癖好': _gKinks,
      '性癖': _gKinks,
    };
    for (final c in known.values.toSet()) {
      c.clear();
    }
    _gExtra.clear();
    final extraLines = <String>[];
    for (final rawLine in text.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      final match = RegExp(r'^([^：:]{1,8})[：:]\s*(.*)$').firstMatch(line);
      final key = match?.group(1)?.trim() ?? '';
      final value = match?.group(2)?.trim() ?? '';
      final target = known[key];
      if (target != null && value.isNotEmpty) {
        target.text = value;
      } else {
        extraLines.add(line);
      }
    }
    _gExtra.text = extraLines.join('\n');
  }

  /// 基础 / 高级 写卡模式切换
  Widget _buildModeToggle() {
    final brightness = Theme.of(context).brightness;
    final scheme = Theme.of(context).colorScheme;
    final faint = GlassPalette.inkFaintOf(brightness);

    Widget pill(String label, bool active, VoidCallback onTap) {
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              color: active
                  ? scheme.primary.withOpacity(brightness == Brightness.dark ? 0.26 : 0.16)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: active ? scheme.primary : faint,
              ),
            ),
          ),
        ),
      );
    }

    return GlassSurface(
      radius: 18,
      blur: 14,
      alpha: brightness == Brightness.dark ? 0.55 : 0.52,
      lift: 0.7,
      padding: const EdgeInsets.all(6),
      child: Row(
        children: <Widget>[
          pill('基础', !_advancedMode, () {
            if (_advancedMode) {
              final losesLayout = _needsAdvancedPersona(_description.text);
              setState(() {
                _advancedMode = false;
                // 只把原文投影到引导字段，不回写 description；
                // 用户没动字段的话，保存仍然用原文，换行不会丢。
                _fillGuidedFromDescription(_description.text);
                _guidedDirty = false;
              });
              _scheduleDraftSave();
              if (losesLayout) {
                showToast(
                  context,
                  '基础模式会把段落压成「键：值」单行；想保留换行请切回高级模式',
                );
              }
            }
          }),
          pill('高级', _advancedMode, () {
            if (!_advancedMode) {
              setState(() {
                _advancedMode = true;
                // 没改过引导字段就保留原排版，不拿字段重排覆盖它
                if (_guidedDirty) _description.text = _descriptionFromGuided();
                _guidedDirty = false;
                // 高级档状态栏只走纯文本
                _statusFormat = statusFormatTemplate;
                _statusText.text = _statusTextFromEntries();
              });
              _scheduleDraftSave();
            }
          }),
        ],
      ),
    );
  }

  /// 世界书配置区（仅高级模式可见）
  Widget _buildWorldBookSection() {
    final brightness = Theme.of(context).brightness;
    final faint = GlassPalette.inkFaintOf(brightness);
    const estimator = TokenEstimator();
    final constantCount =
        _worldEntries.where((e) => e.kind == WorldEntryKind.constant).length;
    final keywordCount = _worldEntries.length - constantCount;
    final tokens = _worldEntries.fold<int>(
      0,
      (sum, e) => sum + estimator.estimate(e.contentController.text),
    );

    return _section(
      id: 'world',
      title: '世界书',
      summary: '常驻 $constantCount · 关键词 $keywordCount',
      trailing: Text(
        '≈$tokens tokens',
        style: TextStyle(fontSize: 10.5, color: faint),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: _worldEntries.length,
            onReorder: _reorderWorldEntries,
            proxyDecorator: (child, index, animation) => Material(
              color: Colors.transparent,
              child: child,
            ),
            itemBuilder: (context, i) => KeyedSubtree(
              key: ValueKey<String>(_worldEntries[i].id),
              child: _buildWorldEntryCard(i, brightness),
            ),
          ),
          Row(
            children: <Widget>[
              TextButton.icon(
                onPressed: () => _addWorldEntry(WorldEntryKind.constant),
                icon: const Icon(Icons.add_rounded, size: 17),
                label: const Text('常驻条目'),
              ),
              TextButton.icon(
                onPressed: () => _addWorldEntry(WorldEntryKind.keyword),
                icon: const Icon(Icons.add_rounded, size: 17),
                label: const Text('关键词条目'),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _importSnippets,
                icon: const Icon(Icons.star_rounded, size: 17),
                label: const Text('导入世界书'),
              ),
            ],
          ),
        ],
      ),
    );
  }
  /// 从这张角色卡里删除一个世界书条目（二次确认，保存后不可恢复）
  Future<void> _deleteWorldEntry(int index) async {
    if (index < 0 || index >= _worldEntries.length) return;
    final entry = _worldEntries[index];
    final name = entry.commentController.text.trim();
    final ok = await showConfirmDialog(
      context,
      title: '删除世界书条目',
      message: '「${name.isEmpty ? '未命名条目' : name}」会从这张角色卡里移除，'
          '保存后不可恢复。收藏里的副本不受影响。',
      confirmText: '删除',
      danger: true,
    );
    if (ok != true || !mounted) return;
    setState(() => _worldEntries.removeAt(index).dispose());
    _scheduleDraftSave();
  }

  /// 星标是一个开关，判断依据是「标题 + 内容」：
  /// * 未收藏（含改了内容的情况）→ 收藏/更新到世界书收藏
  /// * 已收藏 → 从收藏里删掉同名条目（等于导入面板里的垃圾桶）
  ///
  /// 同名但内容不同时不会新建重复条目，而是更新那一条 —— 收藏里始终一个标题一条。
  void _toggleSnippet(int index) {
    final entry = _worldEntries[index];
    final title = entry.commentController.text.trim();
    final content = entry.contentController.text;
    final dao = ref.read(worldSnippetDaoProvider);

    if (!_isCollected(title, content)) {
      if (content.trim().isEmpty) {
        showToast(context, '这个条目还没有内容，先写点东西再收藏');
        return;
      }
      final base = WorldSnippet.fromEntry(entry.toEntry());
      final sameTitle = dao
          .list()
          .where((s) => s.title.trim() == base.title.trim())
          .toList();

      if (sameTitle.isEmpty) {
        dao.save(base);
        showToast(context, '已收藏「${base.title}」到世界书收藏');
      } else {
        // 同名但内容变了：覆盖那一条，多余的重复副本一并清掉
        dao.save(
          sameTitle.first.copyWith(
            content: base.content,
            kind: base.kind,
            keywords: base.keywords,
            insertionOrder: base.insertionOrder,
            probability: base.probability,
            updatedAt: nowMs(),
          ),
        );
        for (final extra in sameTitle.skip(1)) {
          dao.delete(extra.id);
        }
        showToast(context, '已更新收藏「${base.title}」');
      }
      setState(_refreshFavoriteKeys);
      return;
    }

    // 已同步 → 取消收藏
    for (final s in dao.list().where((s) => s.title.trim() == title)) {
      dao.delete(s.id);
    }
    setState(_refreshFavoriteKeys);
    showToast(context, '已取消收藏「$title」');
  }

  /// 从世界书收藏导入条目：重名默认跳过，可勾选覆盖；可全部按常驻导入
  Future<void> _importSnippets() async {
    final selection = await showWorldSnippetPicker(context, ref);
    if (selection == null || !mounted) return;

    var added = 0;
    var replaced = 0;
    var skipped = 0;

    for (final snippet in selection.snippets) {
      final title = snippet.title.trim();
      final kind = selection.forceConstant
          ? WorldEntryKind.constant
          : snippet.kind;
      final index = _worldEntries.indexWhere(
        (e) => e.commentController.text.trim() == title,
      );
      if (index >= 0) {
        if (!selection.overwrite) {
          skipped++;
          continue;
        }
        final target = _worldEntries[index];
        target.kind = kind;
        target.keywordsController.text = snippet.keywords;
        target.orderController.text = '${snippet.insertionOrder}';
        target.probabilityController.text = '${snippet.probability}';
        target.contentController.text = snippet.content;
        replaced++;
        continue;
      }
      _worldEntries.add(
        _WorldEntryDraft(
          id: newId(),
          kind: kind,
          comment: title,
          keywords: snippet.keywords,
          insertionOrder: snippet.insertionOrder,
          probability: snippet.probability,
          content: snippet.content,
        ),
      );
      added++;
    }

    setState(() {});
    _scheduleDraftSave();
    ref
        .read(worldSnippetDaoProvider)
        .bumpUse(selection.snippets.map((e) => e.id));

    final parts = <String>[
      if (added > 0) '导入 $added 条',
      if (replaced > 0) '覆盖 $replaced 条',
      if (skipped > 0) '跳过 $skipped 条（重名）',
    ];
    if (parts.isEmpty) return;
    if (mounted) showToast(context, parts.join('，'));
  }

  Widget _buildWorldEntryCard(int index, Brightness brightness) {
    final entry = _worldEntries[index];
    final isConstant = entry.kind == WorldEntryKind.constant;
    final isDark = brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final faint = GlassPalette.inkFaintOf(brightness);

    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.fromLTRB(2, 2, 2, 6),
      decoration: BoxDecoration(
        // 暗色：不画线，靠底色分三层（页面 → 条目卡 → 内部输入框），
        // 每一层亮一档，圆角块本身就浮起来了。
        // 注意第一版只给了 0.035，几乎和背景同色，圆角矩形看起来"消失"了，
        // 所以条目卡这一层要够亮（0.075），输入框再亮一档（0.13）。
        color: isDark
            ? Colors.white.withOpacity(0.075)
            : Colors.white.withOpacity(0.55),
        borderRadius: BorderRadius.circular(14),
        border: isDark
            ? null
            : Border.all(color: GlassPalette.hairline(brightness)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            height: 36,
            child: Row(
              children: <Widget>[
                ReorderableDragStartListener(
                  index: index,
                  child: SizedBox(
                    width: 32,
                    child: Icon(
                      Icons.drag_indicator_rounded,
                      size: 17,
                      color: faint,
                    ),
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: entry.commentController,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    onChanged: (_) => _scheduleDraftSave(),
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: '条目名',
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
                Text(
                  isConstant ? '常驻' : '关键词',
                  style: TextStyle(
                    fontSize: 10,
                    color: isConstant ? scheme.secondary : scheme.primary,
                  ),
                ),
                SizedBox(
                  width: 40,
                  height: 32,
                  child: FittedBox(
                    fit: BoxFit.contain,
                    child: Switch(
                      value: entry.enabled,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      onChanged: (v) {
                        setState(() => entry.enabled = v);
                        _scheduleDraftSave();
                      },
                    ),
                  ),
                ),
                SizedBox(
                  width: 28,
                  height: 32,
                  child: AnimatedBuilder(
                    animation: Listenable.merge(<Listenable>[
                      entry.commentController,
                      entry.contentController,
                    ]),
                    builder: (context, _) {
                      final favorited = _isCollected(
                        entry.commentController.text,
                        entry.contentController.text,
                      );
                      return IconButton(
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                        splashRadius: 16,
                        tooltip: favorited ? '已收藏（点击取消收藏）' : '收藏为世界书',
                        onPressed: () => _toggleSnippet(index),
                        icon: Icon(
                          favorited
                              ? Icons.star_rounded
                              : Icons.star_border_rounded,
                          size: 18,
                          color: favorited ? scheme.primary : faint,
                        ),
                      );
                    },
                  ),
                ),
                SizedBox(
                  width: 28,
                  height: 32,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    splashRadius: 16,
                    tooltip: entry.expanded ? '收起' : '展开',
                    onPressed: () =>
                        setState(() => entry.expanded = !entry.expanded),
                    icon: Icon(
                      entry.expanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      size: 19,
                    ),
                  ),
                ),
                SizedBox(
                  width: 28,
                  height: 32,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    splashRadius: 16,
                    tooltip: '从这张卡删除',
                    onPressed: () => _deleteWorldEntry(index),
                    icon: const Icon(
                      Icons.remove_circle_outline_rounded,
                      size: 17,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (entry.expanded) ...<Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 4, 8, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (!isConstant) ...<Widget>[
                    TextField(
                      controller: entry.keywordsController,
                      style: const TextStyle(fontSize: 12.5),
                      onChanged: (_) => _scheduleDraftSave(),
                      decoration: _worldFieldDecoration(
                        brightness,
                        hint: '关键词，半角逗号分隔，如：疲劳, 伤害',
                      ),
                    ),
                    const SizedBox(height: 6),
                  ],
                  Row(
                    children: <Widget>[
                      SizedBox(
                        width: 82,
                        child: _worldNumberField(
                          brightness,
                          label: '顺序',
                          controller: entry.orderController,
                          focusNode: entry.orderFocus,
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 82,
                        child: _worldNumberField(
                          brightness,
                          label: '概率',
                          controller: entry.probabilityController,
                          focusNode: entry.probabilityFocus,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '顺序只影响注入位置，概率 100 为必触发',
                          style: TextStyle(fontSize: 9.5, color: faint),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: entry.contentController,
                    minLines: 4,
                    maxLines: null,
                    scrollPhysics: const NeverScrollableScrollPhysics(),
                    keyboardType: TextInputType.multiline,
                    style: const TextStyle(fontSize: 13, height: 1.6),
                    onChanged: (_) {
                      setState(() {});
                      _scheduleDraftSave();
                    },
                    decoration: _worldFieldDecoration(
                      brightness,
                      hint: '条目内容：命中后会注入角色设定',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }


  /// 世界书条目里的「顺序 / 概率」小输入框。
  ///
  /// 尺寸与 3123（用 labelText 的原版）严格对齐，只做平移，不缩放：
  /// * 液泡框 82×47 —— 与原来 `isDense + labelText` 的 TextField 实测同高；
  /// * 标签 12px —— 与 M3 浮动标签同字号，放在液泡内部左上角（原来浮在
  ///   描边线上，无边框时就"溢"出去了）；
  /// * 数值 12.5px —— 与原输入框同字号，挪到液泡右下（中后部）；
  /// * 输入框本身不显形：无边框、无填充、无内边距（主题默认 `filled: true`，
  ///   不显式关掉就会在液泡里多出一块小底——3124 的问题）。
  Widget _worldNumberField(
    Brightness brightness, {
    required String label,
    required TextEditingController controller,
    required FocusNode focusNode,
  }) {
    final isDark = brightness == Brightness.dark;
    return GestureDetector(
      // 整个液泡都是热区：点标签、点空白处都能进入编辑状态。
      // 视觉完全不变，只是把命中区域从「那一行小字」放大到整块。
      behavior: HitTestBehavior.opaque,
      onTap: () => focusNode.requestFocus(),
      child: Container(
        height: 47,
        padding: const EdgeInsets.fromLTRB(12, 5, 12, 7),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withOpacity(0.13)
              : Colors.white.withOpacity(0.72),
          borderRadius: BorderRadius.circular(12),
          border: isDark
              ? null
              : Border.all(color: GlassPalette.hairline(brightness)),
        ),
        child: Stack(
          children: <Widget>[
            Align(
              alignment: Alignment.topLeft,
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.2,
                  color: GlassPalette.inkSoftOf(brightness),
                ),
              ),
            ),
            Align(
              alignment: Alignment.bottomRight,
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 12.5, height: 1.2),
                onChanged: (_) => _scheduleDraftSave(),
                decoration: const InputDecoration(
                  // 与「条目名」输入框同一套写法：各状态边框全显式置空。
                  // 只写 border 不够——enabledBorder / focusedBorder 仍会从主题
                  // 继承（细边框 + 聚焦时主题色高亮），于是静止有框、点进去还亮。
                  isCollapsed: true,
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  errorBorder: InputBorder.none,
                  focusedErrorBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                  hintText: '100',
                  hintStyle: TextStyle(fontSize: 12.5, height: 1.2),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 世界书条目内部的输入框样式。
  ///
  /// 暗色下走「无边框」：不画线，只用底色把输入框从条目卡里浮出来
  /// （条目卡 white@0.075 → 输入框 white@0.13，一档色差就是液泡感）。
  ///
  /// 注意别用 `InputBorder.none`：填充区域的形状是由 border 的
  /// `getOuterPath` 决定的，`InputBorder.none` 给的是**直角矩形**，
  /// 圆角会跟着一起消失。这里用「零宽度 + 透明描边」的圆角边框：
  /// 路径仍是圆角（填充跟着圆），但一根线都不画。
  InputDecoration _worldFieldDecoration(
    Brightness brightness, {
    String? hint,
  }) {
    final base = InputDecoration(isDense: true, hintText: hint);
    if (brightness != Brightness.dark) return base;
    const shape = OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(12)),
      borderSide: BorderSide.none,
    );
    return base.copyWith(
      filled: true,
      fillColor: Colors.white.withOpacity(0.13),
      border: shape,
      enabledBorder: shape,
      focusedBorder: shape,
      disabledBorder: shape,
      errorBorder: shape,
      focusedErrorBorder: shape,
    );
  }

  /// 拖动排序：只调整编辑页的显示顺序，注入时仍按条目「顺序」字段
  void _reorderWorldEntries(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final entry = _worldEntries.removeAt(oldIndex);
      _worldEntries.insert(newIndex, entry);
    });
    _scheduleDraftSave();
  }

  void _addWorldEntry(WorldEntryKind kind) {
    setState(() {
      _worldEntries.add(
        _WorldEntryDraft(
          id: newId(),
          kind: kind,
          expanded: true,
        ),
      );
    });
    _scheduleDraftSave();
  }

  /// 带标签的多行输入框。
  ///
  /// 高度随内容增长（maxLines: null），并关掉内部滚动：
  /// 否则长文本会在框里自己滚，外层 ListView 反而滑不动这块区域。
  Widget _field(
    String label,
    TextEditingController? controller, {
    String? hint,
    int minLines = 3,
  }) {
    if (controller == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 6),
            child: Text(
              label,
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500),
            ),
          ),
          TextField(
            controller: controller,
            minLines: minLines,
            maxLines: null,
            scrollPhysics: const NeverScrollableScrollPhysics(),
            keyboardType: TextInputType.multiline,
            onChanged: (_) => _scheduleDraftSave(),
            style: const TextStyle(fontSize: 14, height: 1.5),
            decoration: InputDecoration(hintText: hint),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final file = ref.watch(avatarStorageProvider).file(_avatarPath);
    return Row(
      children: [
        GestureDetector(
          onTap: _pickAvatar,
          child: Stack(
            children: [
              if (_pendingAvatar != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.memory(
                    _pendingAvatar!,
                    width: 76,
                    height: 76,
                    fit: BoxFit.cover,
                  ),
                )
              else
                CharacterAvatar(
                  file: file,
                  name: _cardName,
                  size: 76,
                  radius: 16,
                ),
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.photo_camera_rounded,
                    size: 13,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            '点击头像可从相册选择图片。\n头像会随角色卡一起保存在本地。',
            style: TextStyle(
              fontSize: 12,
              height: 1.6,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGreetingsEditor() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < _greetings.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _greetings[i],
                    minLines: 3,
                    maxLines: null,
                    scrollPhysics: const NeverScrollableScrollPhysics(),
                    keyboardType: TextInputType.multiline,
                    onChanged: (_) => _scheduleDraftSave(),
                    style: const TextStyle(fontSize: 14, height: 1.5),
                    decoration: InputDecoration(
                      hintText: '备选开场白 ${i + 1}',
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '删除',
                  onPressed: () {
                    setState(() {
                      _greetings.removeAt(i).dispose();
                    });
                    _scheduleDraftSave();
                  },
                  icon: const Icon(Icons.remove_circle_outline_rounded, size: 20),
                ),
              ],
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () {
              setState(() => _greetings.add(TextEditingController()));
              _scheduleDraftSave();
            },
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('添加备选开场白'),
          ),
        ),
      ],
    );
  }

  Future<void> _pickAvatar() async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 88,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      setState(() => _pendingAvatar = bytes);
      _scheduleDraftSave();
    } catch (e) {
      if (mounted) showToast(context, '选择图片失败：$e');
    }
  }

  Future<void> _previewPrompt() async {
    // 打开预览对话框前释放输入焦点：编辑页的文本框常有焦点，
    // 否则对话框关闭时焦点还原会把输入法重新唤出
    parkKeyboard(context);
    final card = _buildCard();
    // 预览要等于实际请求：扫描文本同样带上状态栏的值，
    // 否则「人格 / 阶段」条目在预览里不出现，和真实发送的内容对不上。
    final statusHint =
        card.statusInitial.values.map((v) => '$v').join(' ');
    final world = const WorldBookEngine().activate(
      entries: card.worldBook,
      recentText: WorldBookEngine.scanText(
        recentLines: const <String>[],
        userInput: '（用户输入）',
        statusState: card.statusInitial,
      ),
    );
    // 预览与真实请求保持同一套拆分：人格段单独走 personaText
    final personaEntries = world.included
        .where((e) => WorldBookEngine.drivenByStatus(e, statusHint))
        .toList();
    final personaIds = personaEntries.map((e) => e.id).toSet();
    final worldText = WorldBookEngine.render(
      world.included.where((e) => !personaIds.contains(e.id)),
    );
    final personaText = WorldBookEngine.render(personaEntries);
    final preview = const PromptBuilder().buildPreview(
      card,
      worldText: worldText,
      personaText: personaText,
      // 预览也要反映设置里的全局提示词，否则看到的内容和实际请求不一致
      globalStylePrompt: ref.read(appSettingsProvider).systemPrompt,
      nsfwEnabled: ref.read(appSettingsProvider).nsfwEnabled,
      maxReplyLength: ref.read(appSettingsProvider).maxReplyLength,
      narrativeMode: ref.read(appSettingsProvider).narrativeMode,
    );
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('最终提示词预览', style: TextStyle(fontSize: 16)),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(
              preview,
              style: const TextStyle(
                // 提示词预览用等宽对齐缩进，但 monospace 没有中文字形，
                // 挂上回退链，中文才不会被系统字体接管
                fontFamily: 'monospace',
                fontFamilyFallback: kCjkFallback,
                fontSize: 12,
                height: 1.6,
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  void _resetForm() {
    for (final c in [
      _description,
      _personality,
      _scenario,
      _mesExample,
      _firstMes,
      _systemPrompt,
      _postHistory,
      _statusText,
      _gGender,
      _gAge,
      _gCharacter,
      _gLooks,
      _gKinks,
      _gExtra,
    ]) {
      c.clear();
    }
    for (final c in _greetings) {
      c.dispose();
    }
    for (final e in _statusEntries) {
      e.dispose();
    }
    for (final e in _worldEntries) {
      e.dispose();
    }
    _statusRules.clear();
    _statusTemplate.clear();
    setState(() {
      _statusEntries.clear();
      _worldEntries.clear();
      _statusEnabled = false;
      _statusFormat = statusFormatTemplate;
      _greetings.clear();
      _cardName = '';
      _cardSummary = '';
      _cardTags = const <String>[];
      _editingId = null;
      _createdAt = 0;
      _avatarPath = null;
      _pendingAvatar = null;
      _rawJson = null;
      _source = 'manual';
      _guidedDirty = false;
      _dirty = false;
      _draftRestored = false;
    });
    _clearDraft();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final repo = ref.read(characterRepositoryProvider);
      var card = _buildCard();
      if (_pendingAvatar != null) {
        final rel = await repo.saveAvatar(card.id, _pendingAvatar!);
        card = card.copyWith(avatarPath: rel);
        _avatarPath = rel;
        _pendingAvatar = null;
      }
      await repo.save(card);
      // 卡改过之后，已打开的聊天页还攥着旧卡（开场白列表是旧的），
      // 这里作废一次，下次进入重新读卡
      ref.invalidate(chatControllerProvider(card.id));
      _editingId = card.id;
      _createdAt = card.createdAt;
      _dirty = false;
      _clearDraft();
      ref.read(characterListProvider.notifier).refresh();
      if (!mounted) return;
      showToast(context, widget.embedded ? '保存成功，已加入角色卡仓库' : '保存成功');
      if (!widget.embedded) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) showToast(context, '保存失败：$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

/// 世界书条目编辑态
class _WorldEntryDraft {
  _WorldEntryDraft({
    required this.id,
    this.kind = WorldEntryKind.keyword,
    this.enabled = true,
    this.expanded = false,
    String comment = '',
    String keywords = '',
    int insertionOrder = 100,
    int probability = 100,
    String content = '',
  })  : commentController = TextEditingController(text: comment),
        keywordsController = TextEditingController(text: keywords),
        orderController = TextEditingController(text: '$insertionOrder'),
        probabilityController = TextEditingController(text: '$probability'),
        contentController = TextEditingController(text: content);

  factory _WorldEntryDraft.fromEntry(WorldEntry entry) => _WorldEntryDraft(
        id: entry.id,
        kind: entry.kind,
        enabled: entry.enabled,
        comment: entry.comment,
        keywords: entry.keywords,
        insertionOrder: entry.insertionOrder,
        probability: entry.probability,
        content: entry.content,
      );

  final String id;
  WorldEntryKind kind;
  bool enabled;
  bool expanded;

  final TextEditingController commentController;
  final TextEditingController keywordsController;
  final TextEditingController orderController;
  final TextEditingController probabilityController;
  final TextEditingController contentController;

  /// 「顺序 / 概率」小框的焦点节点：整个液泡都是热区，点哪都能进入编辑
  final FocusNode orderFocus = FocusNode();
  final FocusNode probabilityFocus = FocusNode();

  WorldEntry toEntry() => WorldEntry(
        id: id,
        enabled: enabled,
        kind: kind,
        comment: commentController.text.trim(),
        keywords: keywordsController.text.trim(),
        insertionOrder: int.tryParse(orderController.text.trim()) ?? 100,
        probability:
            (int.tryParse(probabilityController.text.trim()) ?? 100).clamp(0, 100).toInt(),
        content: contentController.text.trim(),
      );

  void dispose() {
    commentController.dispose();
    keywordsController.dispose();
    orderController.dispose();
    probabilityController.dispose();
    contentController.dispose();
    orderFocus.dispose();
    probabilityFocus.dispose();
  }
}

/// 状态栏键值行
class _StatusEntry {
  _StatusEntry({String key = '', String value = ''})
      : keyController = TextEditingController(text: key),
        valueController = TextEditingController(text: value);

  final TextEditingController keyController;
  final TextEditingController valueController;

  String get key => keyController.text.trim();
  String get rawValue => valueController.text.trim();

  /// 尽量还原成数字/布尔，便于展示成进度条
  dynamic get parsedValue {
    final raw = rawValue;
    if (raw.isEmpty) return '';
    final asInt = int.tryParse(raw);
    if (asInt != null) return asInt;
    final asDouble = double.tryParse(raw);
    if (asDouble != null) return asDouble;
    if (raw == 'true') return true;
    if (raw == 'false') return false;
    return raw;
  }

  void dispose() {
    keyController.dispose();
    valueController.dispose();
  }
}

/// 紧凑开关。
///
/// Material 的 Switch 在这样一行里视觉重量太大（52×32 加上最小触控区），
/// 换成 38×22 的小胶囊：只保留「开/关」这一个语义，不抢标题。
class _MiniSwitch extends StatelessWidget {
  const _MiniSwitch({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final accent = accentOf(context);
    final off = GlassPalette.inkFaintOf(brightness);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged(!value),
      child: SizedBox(
        width: 44,
        height: 30,
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            width: 38,
            height: 22,
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: value ? accent : off.withOpacity(0.35),
              borderRadius: BorderRadius.circular(11),
            ),
            child: AnimatedAlign(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOutCubic,
              alignment: value ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: Colors.black.withOpacity(0.12),
                      blurRadius: 3,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
