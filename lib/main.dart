import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'app_providers.dart';
import 'core/db/app_database.dart';
import 'features/characters/data/avatar_storage.dart';

/// 注册随包分发的字体许可。
///
/// Flutter 的 `showLicensePage` 只会自动汇总 pub 依赖的 LICENSE，
/// 打包进 assets 的第三方字体不在其中，必须手动登记，
/// 否则 OFL 要求的「分发时附带版权声明与许可全文」就没被履行。
void _registerBundledFontLicense() {
  LicenseRegistry.addLicense(() async* {
    final text =
        await rootBundle.loadString('assets/licenses/OFL-NotoSansSC.txt');
    yield LicenseEntryWithLineBreaks(
      const <String>['NotoSansSC-Regular.ttf（内置简体中文字形）'],
      text,
    );
  });
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _registerBundledFontLicense();

  try {
    final database = await AppDatabase.open();
    final avatars = await AvatarStorage.create();
    // 空闲时让 SQLite 更新查询计划统计
    database.optimize();

    runApp(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          avatarStorageProvider.overrideWithValue(avatars),
        ],
        child: const AiRoleplayApp(),
      ),
    );
  } catch (error) {
    runApp(_StartupFailureApp(message: '$error'));
  }
}

/// 启动失败（数据库损坏、存储不可写等）时给一个明确提示，而不是白屏
class _StartupFailureApp extends StatelessWidget {
  const _StartupFailureApp({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6C5CE7)),
      ),
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline_rounded, size: 44),
                const SizedBox(height: 16),
                const Text(
                  '应用初始化失败',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12.5, height: 1.6),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
