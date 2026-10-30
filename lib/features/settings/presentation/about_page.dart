import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app_providers.dart';
import '../../../core/theme/glass_theme.dart';
import '../../../shared/widgets/app_widgets.dart';

class AboutPage extends ConsumerStatefulWidget {
  const AboutPage({super.key});

  static const String version = '1.0.0';

  @override
  ConsumerState<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends ConsumerState<AboutPage> {
  /// 连点软件名解锁成人向设置：需要 7 次，且相邻两次间隔不超过 1.2 秒
  static const int _unlockTaps = 7;
  static const Duration _tapWindow = Duration(milliseconds: 1200);

  int _tapCount = 0;
  DateTime? _lastTapAt;

  void _onNameTap() {
    final now = DateTime.now();
    final last = _lastTapAt;
    if (last != null && now.difference(last) > _tapWindow) {
      _tapCount = 0;
    }
    _lastTapAt = now;
    _tapCount++;

    if (_tapCount < _unlockTaps) return;
    _tapCount = 0;

    final unlocked = ref.read(appSettingsProvider).nsfwUnlocked;
    if (unlocked) {
      showToast(context, '成人向设置已解锁，可在设置页调整');
      return;
    }
    ref.read(appSettingsProvider.notifier).unlockNsfw();
    showToast(context, '已解锁成人向设置，回到设置页即可看到');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('关于')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          Center(
            child: Column(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: scheme.primary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(
                    Icons.auto_stories_rounded,
                    size: 34,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: _onNameTap,
                  behavior: HitTestBehavior.opaque,
                  child: const Text(
                    'Silas RP',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '版本 ${AboutPage.version}',
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          _block(
            context,
            '这是什么',
            '一个纯本地的 AI 角色扮演前端「壳程序」。应用本身不内置任何模型、不提供任何 API Key、'
            '也不内置角色卡——所有 AI 能力由你接入自己的 OpenAI 兼容服务，所有角色卡由你导入或编写。',
          ),
          _block(
            context,
            '数据与隐私',
            '角色卡、会话、消息、统计数据全部存储在本机 SQLite 数据库；'
            'API Key 存放在系统安全存储（iOS Keychain / Android Keystore）。'
            '应用不设后端，不上传任何数据，也不含任何统计埋点。'
            '唯一的网络请求是你主动发起的、指向你自己配置的 API 地址。',
          ),
          _block(
            context,
            '角色卡格式',
            '兼容 SillyTavern Character Card V1 / V2 / V3。'
            'PNG 角色卡从 tEXt 块（keyword 为 chara 或 ccv3）中读取 base64 JSON；'
            '也支持直接导入 JSON。导出的 PNG 会把数据写回 tEXt，可直接被 SillyTavern 读取。',
          ),
          _licenseEntry(context),
          const SizedBox(height: 8),
          Text(
            '请遵守你所使用 API 服务提供方的服务条款，以及当地关于 AI 生成内容的法律法规。',
            style: TextStyle(
              fontSize: 11,
              height: 1.6,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  /// 开源许可入口。
  ///
  /// 点开是 Flutter 自带的全量许可页：构建时 pub 会把所有依赖的 LICENSE
  /// 汇总进 NOTICES，逐条列出即满足 BSD-3-Clause / Apache-2.0 要求的
  /// 「分发时附带版权声明与许可全文」；内置字体的 OFL 由 main.dart 通过
  /// LicenseRegistry 注册后一并出现。
  Widget _licenseEntry(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final scheme = Theme.of(context).colorScheme;
    final faint = GlassPalette.inkFaintOf(brightness);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: InkWell(
        onTap: () => showLicensePage(
          context: context,
          applicationName: 'Silas RP',
          applicationVersion: 'v${AboutPage.version}',
          applicationLegalese: '本应用基于 Flutter 构建，不设后端、不收集数据。',
        ),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: brightness == Brightness.dark
                ? Colors.white.withOpacity(0.04)
                : Colors.white.withOpacity(0.55),
            border: Border.all(color: GlassPalette.hairline(brightness)),
          ),
          child: Row(
            children: <Widget>[
              Icon(Icons.article_outlined, size: 18, color: scheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text(
                      '开源许可',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Flutter、Riverpod、sqlite3、dio 等 87 个组件，'
                      '含内置字体的 OFL 许可全文',
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.5,
                        color: faint,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 18, color: faint),
            ],
          ),
        ),
      ),
    );
  }

  Widget _block(BuildContext context, String title, String body) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.75,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
