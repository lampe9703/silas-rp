import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app_providers.dart';
import '../../../core/network/api_exception.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../data/settings_repository.dart';
import '../domain/settings_models.dart';
import 'model_picker_sheet.dart';
import 'settings_page.dart';

class ApiConfigEditPage extends ConsumerStatefulWidget {
  const ApiConfigEditPage({super.key, this.configId});

  final String? configId;

  @override
  ConsumerState<ApiConfigEditPage> createState() => _ApiConfigEditPageState();
}

class _ApiConfigEditPageState extends ConsumerState<ApiConfigEditPage> {
  final _name = TextEditingController();
  final _baseUrl = TextEditingController();
  final _model = TextEditingController();
  final _apiKey = TextEditingController();
  final _maxTokens = TextEditingController();

  ApiConfig? _existing;
  bool _isDefault = false;
  bool _stream = true;
  bool _obscure = true;
  bool _saving = false;
  bool _fetchingModels = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _name.dispose();
    _baseUrl.dispose();
    _model.dispose();
    _apiKey.dispose();
    _maxTokens.dispose();
    super.dispose();
  }

  void _load() {
    final repo = ref.read(settingsRepositoryProvider);
    if (widget.configId != null) {
      final config = repo.apiConfig(widget.configId!);
      if (config != null) {
        _existing = config;
        _name.text = config.name;
        _baseUrl.text = config.baseUrl;
        _model.text = config.model;
        _maxTokens.text = config.maxTokens?.toString() ?? '';
        _isDefault = config.isDefault;
        _stream = config.stream;
        setState(() {});
        return;
      }
    }
    final template = repo.newApiConfigTemplate();
    _existing = template;
    // 新建时不预填 URL / 模型名：由用户自己填或从模型列表里选
    setState(() {});
  }

  SettingsRepository get _repo => ref.read(settingsRepositoryProvider);

  ApiConfig _buildConfig() {
    final base = _existing!;
    return base.copyWith(
      name: _name.text.trim(),
      baseUrl: _baseUrl.text.trim(),
      model: _model.text.trim(),
      maxTokens: int.tryParse(_maxTokens.text.trim()),
      isDefault: _isDefault,
      stream: _stream,
    );
  }

  /// 填好 URL（和 Key）后拉一次模型列表，从里面选，避免手打模型名出错
  Future<void> _fetchModels() async {
    if (_baseUrl.text.trim().isEmpty) {
      showToast(context, '请先填写 Base URL');
      return;
    }
    setState(() => _fetchingModels = true);
    try {
      var key = _apiKey.text.trim();
      if (key.isEmpty && _existing != null) {
        key = await _repo.apiKey(_existing!);
      }
      final models = await ref
          .read(openAiClientProvider)
          .fetchModels(_buildConfig(), key);
      if (!mounted) return;
      if (models.isEmpty) {
        showToast(context, '接口没有返回模型列表');
        return;
      }
      final picked = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => ModelPickerSheet(models: models),
      );
      if (picked != null && mounted) {
        setState(() => _model.text = picked);
      }
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.userMessage);
    } catch (e) {
      if (mounted) showToast(context, '获取模型列表失败：$e');
    } finally {
      if (mounted) setState(() => _fetchingModels = false);
    }
  }

  Future<void> _save() async {    if (_baseUrl.text.trim().isEmpty) {
      showToast(context, '请填写 Base URL');
      return;
    }
    if (_model.text.trim().isEmpty) {
      showToast(context, '请填写模型名');
      return;
    }
    setState(() => _saving = true);
    try {
      final config = _buildConfig();
      final key = _apiKey.text.trim();
      final saved = await _repo.saveApiConfig(
        config,
        plainApiKey: key.isEmpty ? null : key,
      );
      if (_isDefault) {
        ref.read(appSettingsProvider.notifier).setDefaultApiConfig(saved.id);
      }
      ref.invalidate(apiConfigsProvider);
      if (!mounted) return;
      showToast(context, '已保存');
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) showToast(context, _friendlySaveError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// 把底层数据库异常翻译成用户能看懂的话（不再把 SQL 原文甩给用户）
  String _friendlySaveError(Object error) {
    final text = error.toString();
    if (text.contains('UNIQUE constraint failed: api_configs.is_default')) {
      return '同一时间只能有一个默认配置：请先取消原来那项的默认，'
          '或这次不勾选「设为默认配置」再保存。';
    }
    if (text.contains('UNIQUE constraint failed')) {
      return '和已有记录冲突了，请检查名称后重试。';
    }
    return '保存失败，请稍后重试。';
  }

  Future<void> _delete() async {
    final config = _existing;
    if (config == null || widget.configId == null) return;
    final ok = await showConfirmDialog(
      context,
      title: '删除 API 配置',
      message: '「${config.name.isEmpty ? config.model : config.name}」及其保存的 Key 都会被删除。',
      confirmText: '删除',
      danger: true,
    );
    if (!ok) return;
    await _repo.deleteApiConfig(config);
    ref.invalidate(apiConfigsProvider);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isNew = widget.configId == null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isNew ? '添加 API 配置' : '编辑 API 配置'),
        actions: [
          if (!isNew)
            IconButton(
              tooltip: '删除',
              onPressed: _delete,
              icon: Icon(Icons.delete_outline_rounded, color: scheme.error),
            ),
          TextButton(
            onPressed: _saving ? null : _save,
            child: const Text('保存'),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _label('名称'),
          TextField(
            controller: _name,
            decoration: const InputDecoration(hintText: '便于识别的名字，如「主力 GPT」'),
          ),
          const SizedBox(height: 14),
          _label('Base URL'),
          TextField(
            controller: _baseUrl,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              hintText: 'https://api.openai.com/v1',
            ),
          ),
          const SizedBox(height: 14),
          _label('模型名'),
          TextField(
            controller: _model,
            decoration: const InputDecoration(hintText: 'gpt-4o-mini'),
          ),
          const SizedBox(height: 14),
          _label('API Key'),
          TextField(
            controller: _apiKey,
            obscureText: _obscure,
            enableSuggestions: false,
            autocorrect: false,
            decoration: InputDecoration(
              hintText: isNew
                  ? 'sk-...（本地服务可不填）'
                  : '留空表示不修改已保存的 Key',
              suffixIcon: IconButton(
                icon: Icon(
                  _obscure
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 18,
                ),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 2),
            child: Text(
              'Key 保存在系统 Keychain / Keystore，不写入数据库，也不会出现在日志里。',
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _fetchingModels ? null : _fetchModels,
            icon: _fetchingModels
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.playlist_add_check_rounded, size: 18),
            label: Text(_fetchingModels ? '获取中…' : '测试并获取模型列表'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(46),
            ),
          ),
          const SizedBox(height: 14),
          _label('最大回复 tokens（可选）'),
          TextField(
            controller: _maxTokens,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(hintText: '留空由服务端决定'),
          ),
          const SizedBox(height: 8),
          // 流式输出开关已下线：请求一律走流式（见 ChatController._generateReply），
          // 这个开关从来没有被消费，留着只会误导。字段本身保留，保存时原样带回。
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('设为默认配置', style: TextStyle(fontSize: 14)),
            subtitle: const Text(
              '新对话默认使用该配置',
              style: TextStyle(fontSize: 11.5),
            ),
            value: _isDefault,
            onChanged: (v) => setState(() => _isDefault = v),
          ),
        ],
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(left: 2, bottom: 6),
        child: Text(
          text,
          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500),
        ),
      );
}
