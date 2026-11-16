import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
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

  /// 支持作者的弹窗：GitHub / 爱发电 / 转发 集中在这里，不占设置页的版面。
  ///
  /// 三条并列，转发放最后 —— 对这个阶段来说它其实最有用：
  /// 一个人因此找到它，比一杯咖啡值钱。所以除了文案，还给了一个
  /// 直接调系统分享的入口（链接已经在里面，不用手动复制）。
  void _showSupportDialog(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        contentPadding: const EdgeInsets.fromLTRB(24, 22, 24, 8),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '支持作者：',
              style: TextStyle(
                fontSize: 16,
                height: 1.3,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
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
            const SizedBox(height: 6),
            Text(
              '或者在你的朋友圈子里帮我宣传一下——把它转给那个也在找手机端角色扮演客户端的人。',
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
            const SizedBox(height: 8),
            _SupportLinkRow(
              icon: Icons.ios_share_rounded,
              label: '转发给朋友',
              detail: '打开系统分享',
              trailing: Icons.ios_share_rounded,
              onTap: () {
                Navigator.of(dialogContext).pop();
                _shareApp(context);
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

  /// 系统分享：链接直接带在文本里，不用对方再问「在哪下」。
  Future<void> _shareApp(BuildContext context) async {
    try {
      await Share.share(
        '在手机上玩 AI 角色扮演的一个客户端，开源免费、装完就能用：\n'
        'https://github.com/lampe9703/silas-rp',
        subject: 'Silas RP',
      );
    } catch (_) {
      if (context.mounted) showToast(context, '分享失败，可以先复制链接');
    }
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
          _PromptSettingsCard(
            nsfwUnlocked: settings.nsfwUnlocked,
            nsfwEnabled: settings.nsfwEnabled,
          ),
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
                  'GitHub · 爱发电 · 转发给朋友',
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

/// 提示词设置。
///
/// 四份可编辑文本，共用同一套「折叠 → 编辑 → 保存 / 恢复默认」交互：
/// * 第一人称 / 第三人称各自独立 —— 人称是硬约束，写在同一段里必然互相污染；
/// * 成人向拆成「越狱协议」和「内容尺度」两段，因为注入位置不同（最前 / 风格层之后）。
///
/// 成人向的开关**不在这里**：设置页摆一个滑块，等于把这件事写在明面上，
/// 改成关于页连点软件名切换（见 AboutPage 的 _onNameTap）。
class _PromptSettingsCard extends ConsumerWidget {
  const _PromptSettingsCard({
    required this.nsfwUnlocked,
    required this.nsfwEnabled,
  });

  final bool nsfwUnlocked;
  final bool nsfwEnabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final notifier = ref.read(appSettingsProvider.notifier);

    return SectionCard(
      title: '提示词',
      subtitle: '第一人称与第三人称各自独立，用哪套由卡片的「叙述视角」决定。',
      padding: EdgeInsets.zero,
      children: <Widget>[
        _PromptBlock(
          title: '第一人称系统提示词',
          hint: '角色以「我」叙述，代替角色名作主语',
          value: settings.firstPersonPrompt,
          defaultText: PromptBuilder.defaultFirstPersonPrompt,
          onSave: notifier.setFirstPersonPrompt,
        ),
        const Divider(height: 1, indent: 16, endIndent: 16),
        _PromptBlock(
          title: '第三人称系统提示词',
          hint: '作者视角，第三人称全知，可写所有角色',
          value: settings.thirdPersonPrompt,
          defaultText: PromptBuilder.defaultThirdPersonPrompt,
          onSave: notifier.setThirdPersonPrompt,
        ),
        // 成人向整块只在「已解锁 + 已开启」时出现：关掉就什么都不显示。
        // 开关做成连点软件名，本来就是为了这个 —— 设置页不该留任何
        // 「这软件支持成人向」的痕迹，哪怕只是一行状态。
        if (nsfwUnlocked && nsfwEnabled) ...<Widget>[
          const Divider(height: 1),
          _PromptBlock(
            title: '成人向提示词',
            hint: '注入在 system 最前；连点软件名 7 次可关闭',
            value: settings.adultPrompt,
            defaultText: PromptBuilder.adultPrompt,
            onSave: notifier.setAdultPrompt,
          ),
        ],
      ],
    );
  }
}

/// 单份提示词：折叠头 + 编辑框 + 保存 / 恢复默认。
///
/// 保存时若内容与内置默认一致，写回空串 —— 数据库里只留「玩家真的改过」
/// 的那几份，以后升级默认文本也能自动生效，不会被一份旧拷贝钉住。
class _PromptBlock extends StatefulWidget {
  const _PromptBlock({
    required this.title,
    required this.hint,
    required this.value,
    required this.defaultText,
    required this.onSave,
  });

  final String title;
  final String hint;

  /// 玩家保存过的内容；空串 = 用 [defaultText]
  final String value;
  final String defaultText;
  final ValueChanged<String> onSave;

  @override
  State<_PromptBlock> createState() => _PromptBlockState();
}

class _PromptBlockState extends State<_PromptBlock> {
  late final TextEditingController _controller;
  bool _expanded = false;
  bool _dirty = false;

  String get _effective =>
      widget.value.trim().isEmpty ? widget.defaultText : widget.value;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _effective);
  }

  @override
  void didUpdateWidget(covariant _PromptBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 别的地方改了值（恢复默认）时同步过来；正在编辑就不动，免得吞掉输入
    if (!_dirty && oldWidget.value != widget.value) {
      _controller.text = _effective;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final text = _controller.text.trim();
    widget.onSave(text == widget.defaultText.trim() ? '' : text);
    setState(() => _dirty = false);
    parkKeyboard(context);
    showToast(context, '${widget.title}已保存');
  }

  void _reset() {
    _controller.text = widget.defaultText;
    widget.onSave('');
    setState(() => _dirty = false);
    showToast(context, '${widget.title}已恢复默认');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final customized = widget.value.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 10),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Text(
                            widget.title,
                            style: const TextStyle(fontSize: 14),
                          ),
                          const SizedBox(width: 6),
                          if (customized)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: scheme.primary.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '已自定义',
                                style: TextStyle(
                                  fontSize: 9.5,
                                  height: 1.4,
                                  color: scheme.primary,
                                ),
                              ),
                            ),
                          if (_dirty)
                            Padding(
                              padding: const EdgeInsets.only(left: 6),
                              child: Text(
                                '未保存',
                                style: TextStyle(
                                  fontSize: 9.5,
                                  color: scheme.error,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.hint,
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.4,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
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
        if (_expanded) ...<Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _controller,
              maxLines: null,
              minLines: 8,
              onChanged: (_) {
                if (!_dirty) setState(() => _dirty = true);
              },
              style: const TextStyle(fontSize: 12.5, height: 1.55),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: <Widget>[
                FilledButton.tonal(
                  onPressed: _dirty ? _save : null,
                  child: const Text('保存'),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: _reset,
                  child: const Text('恢复默认'),
                ),
              ],
            ),
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
    this.trailing = Icons.open_in_new_rounded,
  });

  final IconData icon;
  final String label;
  final String detail;
  final VoidCallback onTap;

  /// 行尾图标：默认是「打开新页面」，分享这类动作用自己的图标更准
  final IconData trailing;

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
              trailing,
              size: 15,
              color: scheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}
