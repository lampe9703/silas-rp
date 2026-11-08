import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app_providers.dart';
import '../../../core/prompt/prompt_builder.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/glass_theme.dart';
import '../../../shared/glass_route.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../domain/settings_models.dart';
import 'api_config_edit_page.dart';
import 'about_page.dart';
import 'data_manage_page.dart';
import 'nav_order_page.dart';
import 'pricing_page.dart';

/// API 配置列表（增删改后 invalidate 即可刷新）
final apiConfigsProvider = Provider<List<ApiConfig>>(
  (ref) => ref.watch(settingsRepositoryProvider).apiConfigs(),
);

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  /// 跳转子页前先释放输入焦点（外观栏的十六进制输入框可能持有焦点，
  /// 否则子页返回时焦点还原会唤出输入法）
  static const String _githubUrl = 'https://github.com/lampe9703';
  static const String _afdianUrl = 'https://afdian.com/a/lampe9703';

  /// 用系统浏览器打开外链。失败时明确提示，避免「点了没反应」。
  Future<void> _openLink(BuildContext context, String url) async {
    try {
      final ok = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!ok && context.mounted) showToast(context, '打不开链接：$url');
    } catch (_) {
      if (context.mounted) showToast(context, '打不开链接：$url');
    }
  }

  /// 支持作者的弹窗：GitHub 与爱发电集中在这里，不占设置页的版面。
  void _showSupportDialog(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        // 不再放标题：弹窗顶部直接是「: )」符号，省掉一行大字更轻
        contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // 符号表情：比正文大一档，但收在标题与链接行之间，不抢版面。
            Text(
              ': )',
              style: TextStyle(
                fontSize: 30,
                height: 1.0,
                letterSpacing: 1.5,
                fontWeight: FontWeight.w500,
                color: scheme.primary,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '如果这一个软件，在无聊的夜晚中给你带来了一点点慰藉',
              style: TextStyle(
                fontSize: 13,
                height: 1.7,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '愿意的话，可以在爱发电请我喝杯咖啡，或者在 GitHub 上点一颗 star。',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.7,
                color: scheme.onSurfaceVariant.withOpacity(0.8),
              ),
            ),
            const SizedBox(height: 16),
            _SupportLinkRow(
              icon: Icons.code_rounded,
              label: 'GitHub',
              detail: 'github.com/lampe9703',
              onTap: () {
                Navigator.of(dialogContext).pop();
                _openLink(context, _githubUrl);
              },
            ),
            const SizedBox(height: 8),
            _SupportLinkRow(
              icon: Icons.local_cafe_outlined,
              label: '爱发电',
              detail: 'afdian.com/a/lampe9703',
              onTap: () {
                Navigator.of(dialogContext).pop();
                _openLink(context, _afdianUrl);
              },
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  void _pushPage(BuildContext context, Widget page) {
    parkKeyboard(context);
    Navigator.of(context).push(glassPageRoute<void>(page));
  }
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final configs = ref.watch(apiConfigsProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 150),
        children: [
          SectionCard(
            title: 'API 配置',
            subtitle: 'Key 保存在系统安全存储中，不会明文写入数据库',
            padding: EdgeInsets.zero,
            children: [
              if (configs.isEmpty)
                const ListTile(
                  title: Text('还没有 API 配置', style: TextStyle(fontSize: 13.5)),
                  subtitle: Text(
                    '添加后即可开始对话',
                    style: TextStyle(fontSize: 11.5),
                  ),
                ),
              for (final config in configs)
                ListTile(
                  leading: Icon(
                    config.isDefault
                        ? Icons.check_circle_rounded
                        : Icons.circle_outlined,
                    color: config.isDefault ? scheme.primary : scheme.outline,
                    size: 20,
                  ),
                  title: Text(
                    config.name.isEmpty ? config.model : config.name,
                    style: const TextStyle(fontSize: 14),
                  ),
                  subtitle: Text(
                    '${config.model} · ${config.baseUrl}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11.5),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded, size: 18),
                  onTap: () => _pushPage(context, ApiConfigEditPage(configId: config.id)),
                ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.add_rounded, size: 20),
                title: const Text('添加 API 配置', style: TextStyle(fontSize: 14)),
                onTap: () => _pushPage(context, const ApiConfigEditPage()),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _PromptSettingsCard(nsfwUnlocked: settings.nsfwUnlocked),
          const SizedBox(height: 18),
          const SizedBox(height: 18),
          SectionCard(
            title: '计费',
            padding: EdgeInsets.zero,
            children: [
              ListTile(
                leading: const Icon(Icons.payments_outlined, size: 20),
                title: const Text('模型单价', style: TextStyle(fontSize: 14)),
                subtitle: const Text(
                  '用于估算费用，支持通配符匹配',
                  style: TextStyle(fontSize: 11.5),
                ),
                trailing: const Icon(Icons.chevron_right_rounded, size: 18),
                onTap: () => _pushPage(context, const PricingPage()),
              ),
            ],
          ),
          const SizedBox(height: 18),
          SectionCard(
            title: '外观',
            subtitle: '主题色与点缀色用十六进制填写，留空恢复默认淡蓝 / 粉红',
            padding: EdgeInsets.zero,
            children: [
              RadioListTile<String>(
                dense: true,
                title: const Text('跟随系统', style: TextStyle(fontSize: 14)),
                value: 'system',
                groupValue: settings.themeMode,
                onChanged: (v) =>
                    ref.read(appSettingsProvider.notifier).setThemeMode(v!),
              ),
              RadioListTile<String>(
                dense: true,
                title: const Text('亮色', style: TextStyle(fontSize: 14)),
                value: 'light',
                groupValue: settings.themeMode,
                onChanged: (v) =>
                    ref.read(appSettingsProvider.notifier).setThemeMode(v!),
              ),
              RadioListTile<String>(
                dense: true,
                title: const Text('暗色', style: TextStyle(fontSize: 14)),
                value: 'dark',
                groupValue: settings.themeMode,
                onChanged: (v) =>
                    ref.read(appSettingsProvider.notifier).setThemeMode(v!),
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              _ColorField(
                title: '主题色',
                hint: '#7FBEE8',
                fallback: const Color(0xFF7FBEE8),
                value: settings.themeAccent,
                onChanged: (v) =>
                    ref.read(appSettingsProvider.notifier).setThemeAccent(v),
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              _ColorField(
                title: '点缀色',
                hint: '#E879A9',
                fallback: const Color(0xFFE879A9),
                value: settings.themeSpot,
                onChanged: (v) =>
                    ref.read(appSettingsProvider.notifier).setThemeSpot(v),
              ),
            ],
          ),
          const SizedBox(height: 18),
          SectionCard(
            title: '导航栏',
            padding: EdgeInsets.zero,
            children: [
              ListTile(
                leading: const Icon(Icons.swap_vert_rounded, size: 20),
                title: const Text('调整 Tab 顺序', style: TextStyle(fontSize: 14)),
                subtitle: const Text(
                  '拖拽调整底部导航的排列',
                  style: TextStyle(fontSize: 11.5),
                ),
                trailing: const Icon(Icons.chevron_right_rounded, size: 18),
                onTap: () => _pushPage(context, const NavOrderPage()),
              ),
            ],
          ),
          const SizedBox(height: 18),
          SectionCard(
            title: '数据',
            padding: EdgeInsets.zero,
            children: [
              ListTile(
                leading: const Icon(Icons.folder_open_rounded, size: 20),
                title: const Text('数据管理', style: TextStyle(fontSize: 14)),
                subtitle: const Text(
                  '导出/导入角色卡、清空数据',
                  style: TextStyle(fontSize: 11.5),
                ),
                trailing: const Icon(Icons.chevron_right_rounded, size: 18),
                onTap: () => _pushPage(context, const DataManagePage()),
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              ListTile(
                leading: const Icon(Icons.info_outline_rounded, size: 20),
                title: const Text('关于', style: TextStyle(fontSize: 14)),
                trailing: const Icon(Icons.chevron_right_rounded, size: 18),
                onTap: () => _pushPage(context, const AboutPage()),
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              ListTile(
                leading: const Icon(Icons.favorite_outline_rounded, size: 20),
                title: const Text('支持作者', style: TextStyle(fontSize: 14)),
                subtitle: const Text(
                  'GitHub · 爱发电',
                  style: TextStyle(fontSize: 11.5),
                ),
                trailing: const Icon(Icons.chevron_right_rounded, size: 18),
                onTap: () => _showSupportDialog(context),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Center(
            child: Text(
              '全部数据仅保存在本机，不会上传任何服务器',
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

/// 提示词设置：系统提示词（SFW）+ 成人向开关（NSFW）合在一张卡里。
///
/// 两者本质都是「往请求里注入提示词」，拆成两张卡会让设置页显得零碎。
/// 系统提示词区可点击展开，默认收起。
class _PromptSettingsCard extends ConsumerStatefulWidget {
  const _PromptSettingsCard({required this.nsfwUnlocked});

  /// 是否已通过关于页解锁（决定成人向开关是否出现）
  final bool nsfwUnlocked;

  @override
  ConsumerState<_PromptSettingsCard> createState() =>
      _PromptSettingsCardState();
}

class _PromptSettingsCardState extends ConsumerState<_PromptSettingsCard> {
  late final TextEditingController _controller;

  /// 系统提示词编辑区默认收起：整段提示词很长，展开会占满一屏，
  /// 设置页首屏留给更常用的项。点标题栏展开。
  bool _expanded = false;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    final saved = ref.read(appSettingsProvider).systemPrompt;
    _controller = TextEditingController(
      text: saved.trim().isEmpty ? PromptBuilder.defaultStylePrompt : saved,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final nsfwEnabled = ref.watch(appSettingsProvider).nsfwEnabled;

    return SectionCard(
      title: '提示词',
      subtitle: '所有角色卡共用的回复风格。卡片自己写了提示词时，以卡片为准。',
      children: [
        // 折叠头：点击展开/收起系统提示词编辑区
        // 用 GestureDetector 而非 InkWell：这里没有 Material 祖先，
        // InkWell 的水波纹和 onTap 都可能不响应。
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
            child: Row(
              children: <Widget>[
                const Text('系统提示词', style: TextStyle(fontSize: 14)),
                const SizedBox(width: 8),
                if (!_expanded)
                  Text(
                    _dirty ? '有未保存修改' : '已收起',
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                const Spacer(),
                AnimatedRotation(
                  turns: _expanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  child: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 20,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_expanded) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              controller: _controller,
              maxLines: null,
              minLines: 8,
              onChanged: (_) => setState(() => _dirty = true),
              style: const TextStyle(fontSize: 13, height: 1.55),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Row(
              children: <Widget>[
                FilledButton.tonal(
                  onPressed: _dirty
                      ? () {
                          ref
                              .read(appSettingsProvider.notifier)
                              .setSystemPrompt(_controller.text);
                          setState(() => _dirty = false);
                          parkKeyboard(context);
                          showToast(context, '系统提示词已保存');
                        }
                      : null,
                  child: const Text('保存'),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _controller.text = PromptBuilder.defaultStylePrompt;
                      _dirty = true;
                    });
                  },
                  child: const Text('恢复默认'),
                ),
              ],
            ),
          ),
        ],
        if (widget.nsfwUnlocked) ...[
          const Divider(height: 1, indent: 16, endIndent: 16),
          SwitchListTile(
            title: const Text('允许成人向描写', style: TextStyle(fontSize: 14)),
            subtitle: const Text(
              '追加露骨描写要求：器官直呼其名、性场景写完整、'
              '允许脏话与 BDSM。所有角色均视为成年人。'
              '关闭后本项隐藏，需重新到「关于」页连点软件名解锁。',
              style: TextStyle(fontSize: 11.5),
            ),
            value: nsfwEnabled,
            onChanged: (v) {
              final notifier = ref.read(appSettingsProvider.notifier);
              if (v) {
                notifier.unlockNsfw();
              } else {
                notifier.disableNsfw();
              }
            },
          ),
        ],
      ],
    );
  }
}

class _ColorField extends StatefulWidget {
  const _ColorField({
    required this.title,
    required this.hint,
    required this.fallback,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String hint;
  final Color fallback;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  State<_ColorField> createState() => _ColorFieldState();
}

class _ColorFieldState extends State<_ColorField> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.value);

  static final RegExp _hexPattern =
      RegExp(r'^#?([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$');

  @override
  void didUpdateWidget(_ColorField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 外部值变化（例如恢复默认）时同步输入框
    if (oldWidget.value != widget.value &&
        _controller.text != widget.value) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    // 离开页面时自动提交：焦点在输入框内直接切走（返回/切 Tab）也不丢内容。
    // dispose 里 widget 回调仍可安全使用（只是不能 setState）。
    _submit(_controller.text);
    _controller.dispose();
    super.dispose();
  }

  void _submit(String raw) {
    final text = raw.trim();
    // 空串 = 恢复默认；否则必须是合法十六进制才生效
    if (text.isEmpty || _hexPattern.hasMatch(text)) {
      widget.onChanged(text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = AppTheme.parseHexColor(_controller.text) ?? widget.fallback;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          // 色块预览：当前生效色（自定义或默认）
          Container(
            width: 34,
            height: 26,
            decoration: BoxDecoration(
              color: preview,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: GlassPalette.hairline(Theme.of(context).brightness),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(widget.title, style: const TextStyle(fontSize: 14)),
          const Spacer(),
          SizedBox(
            width: 128,
            child: TextField(
              controller: _controller,
              // 字体与占位提示完全一致：显式声明同一套 style（含字重），
              // 不靠继承链——部分设备 IME/字体回退会让输入文本渲染偏粗。
              autocorrect: false,
              enableSuggestions: false,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w400,
              ),
              inputFormatters: [
                LengthLimitingTextInputFormatter(7),
                FilteringTextInputFormatter.allow(RegExp(r'[0-9a-fA-F#]')),
              ],
              textInputAction: TextInputAction.done,
              onSubmitted: _submit,
              // 键盘下沉后点击页面任何位置 = 提交保存 + 收起键盘（消光标）；
              // 再点本输入框可重新唤起键盘继续输入
              onTapOutside: (_) {
                _submit(_controller.text);
                FocusManager.instance.primaryFocus?.unfocus();
              },
              onChanged: (_) => setState(() {}), // 实时刷新色块预览
              decoration: InputDecoration(
                hintText: widget.hint,
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                suffixIcon: _controller.text.isEmpty
                    ? null
                    : GestureDetector(
                        onTap: () {
                          _controller.clear();
                          _submit('');
                        },
                        child: const Icon(Icons.close_rounded, size: 15),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 弹窗里的单个链接行
class _SupportLinkRow extends StatelessWidget {
  const _SupportLinkRow({
    required this.icon,
    required this.label,
    required this.detail,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: scheme.primary.withOpacity(0.06),
          border: Border.all(color: scheme.outlineVariant.withOpacity(0.5)),
        ),
        child: Row(
          children: <Widget>[
            Icon(icon, size: 18, color: scheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    detail,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.open_in_new_rounded,
              size: 15,
              color: scheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}
