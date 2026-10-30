import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app_providers.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../../characters/presentation/controllers/character_list_controller.dart';
import '../domain/license_codec.dart';
import '../domain/license_policy.dart';

/// 高级版激活页：显示当前版本状态、输入激活码、解除本机激活。
class PremiumPage extends ConsumerStatefulWidget {
  const PremiumPage({super.key});

  @override
  ConsumerState<PremiumPage> createState() => _PremiumPageState();
}

class _PremiumPageState extends ConsumerState<PremiumPage> {
  final TextEditingController _controller = TextEditingController();
  String? _error;
  bool _justActivated = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _activate() {
    final result = LicenseCodec.verify(_controller.text);
    if (!result.isValid) {
      setState(() {
        _error = result.error;
        _justActivated = false;
      });
      return;
    }
    // 只存规范化后的 24 位本体，展示时再套格式
    final body = LicenseCodec.normalize(_controller.text);
    ref.read(appSettingsProvider.notifier).setLicenseCode(body);
    setState(() {
      _error = null;
      _justActivated = true;
      _controller.clear();
    });
    parkKeyboard(context);
    showToast(context, '激活成功，已解锁高级版');
  }

  Future<void> _deactivate() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('解除本机激活？'),
        content: const Text(
          '解除后回到免费版：角色卡超过 2 张时不能再新增，已有卡片不会被删除。\n'
          '激活码仍然有效，重新输入即可再次激活。',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('解除'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    ref.read(appSettingsProvider.notifier).setLicenseCode('');
    setState(() => _justActivated = false);
    showToast(context, '已恢复免费版');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final premium = ref.watch(isPremiumProvider);
    final used = ref.watch(cardCountProvider);
    final code = ref.watch(appSettingsProvider).licenseCode;
    final orderId = premium ? LicenseCodec.normalize(code).substring(0, 8) : '';

    return Scaffold(
      appBar: AppBar(title: const Text('高级版')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        children: <Widget>[
          SectionCard(
            title: '当前版本',
            children: <Widget>[
              ListTile(
                leading: Icon(
                  premium
                      ? Icons.workspace_premium_rounded
                      : Icons.lock_outline_rounded,
                  color: premium ? scheme.secondary : scheme.onSurfaceVariant,
                ),
                title: Text(
                  premium ? '高级版' : '免费版',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  premium
                      ? '角色卡不限张数 · 订单号 $orderId'
                      : '最多 ${LicensePolicy.freeCardLimit} 张角色卡 · 已用 $used 张',
                  style: const TextStyle(fontSize: 12, height: 1.5),
                ),
              ),
              if (premium)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: _deactivate,
                      child: const Text('解除本机激活'),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 18),
          if (!premium)
            SectionCard(
              title: '输入激活码',
              subtitle: '购买后拿到的激活码，形如 SRP-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX',
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
                  child: TextField(
                    controller: _controller,
                    autocorrect: false,
                    enableSuggestions: false,
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.allow(
                        RegExp(r'[0-9a-zA-Z\- ]'),
                      ),
                    ],
                    style: const TextStyle(
                      fontSize: 14,
                      letterSpacing: 1.2,
                      fontFamily: 'monospace',
                    ),
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      isDense: true,
                      hintText: 'SRP-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX',
                      hintStyle: const TextStyle(
                        fontSize: 12,
                        letterSpacing: 0.6,
                      ),
                      errorText: _error,
                      errorMaxLines: 3,
                    ),
                    onSubmitted: (_) => _activate(),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                  child: Row(
                    children: <Widget>[
                      FilledButton(
                        onPressed: _activate,
                        child: const Text('激活'),
                      ),
                      const SizedBox(width: 10),
                      TextButton.icon(
                        onPressed: () async {
                          final data =
                              await Clipboard.getData(Clipboard.kTextPlain);
                          final text = data?.text;
                          if (text == null || text.trim().isEmpty) return;
                          _controller.text = text.trim();
                          setState(() => _error = null);
                        },
                        icon: const Icon(Icons.content_paste_rounded, size: 16),
                        label: const Text('粘贴'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          if (_justActivated && premium)
            Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Row(
                children: <Widget>[
                  Icon(Icons.check_circle_rounded,
                      size: 18, color: scheme.secondary),
                  const SizedBox(width: 8),
                  Text(
                    '已激活，角色卡数量不再受限',
                    style: TextStyle(fontSize: 13, color: scheme.secondary),
                  ),
                ],
              ),
            ),
          _faq(context),
        ],
      ),
    );
  }

  Widget _faq(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const lines = <String>[
      '· 免费版可以无限次对话、切换角色，只限制「角色卡仓库」最多保存 2 张卡。',
      '· 删掉一张卡就能再存一张，不需要购买。',
      '· 激活码保存在本机，不上传、不联网校验；换手机需要重新输入（同一个码可以重复激活）。',
      '· 如果激活失败，请核对是否漏字符：连字符可以省略，大小写不敏感。',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          '说明',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        for (final line in lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              line,
              style: TextStyle(
                fontSize: 12,
                height: 1.65,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}
