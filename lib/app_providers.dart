import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/db/app_database.dart';
import 'core/network/openai_client.dart';
import 'core/security/secure_key_store.dart';
import 'features/characters/data/avatar_storage.dart';
import 'features/characters/data/card_generation_dao.dart';
import 'features/characters/data/character_dao.dart';
import 'features/chat/data/session_tag_dao.dart';
import 'features/characters/data/world_snippet_dao.dart';
import 'features/characters/data/character_repository.dart';
import 'features/chat/data/message_dao.dart';
import 'features/chat/data/session_dao.dart';
import 'features/settings/data/settings_dao.dart';
import 'features/settings/data/settings_repository.dart';
import 'features/settings/domain/settings_models.dart';
import 'features/stats/data/usage_dao.dart';

/// 由 bootstrap 覆写
final databaseProvider = Provider<AppDatabase>(
  (ref) => throw UnimplementedError('databaseProvider 必须在 bootstrap 中覆写'),
);

final avatarStorageProvider = Provider<AvatarStorage>(
  (ref) => throw UnimplementedError('avatarStorageProvider 必须在 bootstrap 中覆写'),
);

final keyStoreProvider = Provider<SecureKeyStore>((ref) => SecureKeyStore());

final openAiClientProvider = Provider<OpenAiClient>((ref) => OpenAiClient());

// ───────────────────────────── DAO ─────────────────────────────

final characterDaoProvider =
    Provider<CharacterDao>((ref) => CharacterDao(ref.watch(databaseProvider)));

final sessionDaoProvider =
    Provider<SessionDao>((ref) => SessionDao(ref.watch(databaseProvider)));

final messageDaoProvider =
    Provider<MessageDao>((ref) => MessageDao(ref.watch(databaseProvider)));

final sessionTagDaoProvider = Provider<SessionTagDao>(
  (ref) => SessionTagDao(ref.watch(databaseProvider)),
);

final worldSnippetDaoProvider = Provider<WorldSnippetDao>(
  (ref) => WorldSnippetDao(ref.watch(databaseProvider)),
);

final cardGenerationDaoProvider = Provider<CardGenerationDao>(
  (ref) => CardGenerationDao(ref.watch(databaseProvider)),
);

final usageDaoProvider =
    Provider<UsageDao>((ref) => UsageDao(ref.watch(databaseProvider)));

final settingsDaoProvider =
    Provider<SettingsDao>((ref) => SettingsDao(ref.watch(databaseProvider)));

final apiConfigDaoProvider =
    Provider<ApiConfigDao>((ref) => ApiConfigDao(ref.watch(databaseProvider)));

final pricingDaoProvider =
    Provider<PricingDao>((ref) => PricingDao(ref.watch(databaseProvider)));

// ───────────────────────────── Repository ─────────────────────────────

final characterRepositoryProvider = Provider<CharacterRepository>(
  (ref) => CharacterRepository(
    dao: ref.watch(characterDaoProvider),
    avatars: ref.watch(avatarStorageProvider),
    generation: ref.watch(cardGenerationDaoProvider),
  ),
);

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepository(
    settingsDao: ref.watch(settingsDaoProvider),
    apiConfigDao: ref.watch(apiConfigDaoProvider),
    pricingDao: ref.watch(pricingDaoProvider),
    keyStore: ref.watch(keyStoreProvider),
  ),
);

// ───────────────────────────── 设置状态 ─────────────────────────────

class AppSettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() => ref.watch(settingsRepositoryProvider).loadSettings();

  void _persist(AppSettings next) {
    state = next;
    ref.read(settingsRepositoryProvider).saveSettings(next);
  }

  void setThemeMode(String mode) => _persist(state.copyWith(themeMode: mode));

  /// 十六进制主题色（空串 = 恢复默认淡蓝）
  void setThemeAccent(String hex) =>
      _persist(state.copyWith(themeAccent: hex.trim()));

  /// 十六进制点缀色（空串 = 恢复默认粉红）
  void setThemeSpot(String hex) =>
      _persist(state.copyWith(themeSpot: hex.trim()));

  void setNavOrder(List<String> order) {
    if (order.length != 4) return;
    _persist(state.copyWith(navOrder: order));
  }

  void setDefaultApiConfig(String? id) {
    final repo = ref.read(settingsRepositoryProvider);
    if (id == null) {
      repo.removeRaw(SettingKeys.defaultApiConfigId);
      state = state.copyWith(defaultApiConfigId: '');
      return;
    }
    repo.setRaw(SettingKeys.defaultApiConfigId, id);
    repo.setDefaultApiConfig(id);
    state = state.copyWith(defaultApiConfigId: id);
  }

  void setContextLimit(int value) =>
      _persist(state.copyWith(contextLimit: value.clamp(512, 200000)));

  void setTemperature(double value) =>
      _persist(state.copyWith(temperature: value.clamp(0, 2)));

  void setTopP(double value) => _persist(state.copyWith(topP: value.clamp(0, 1)));

  void setStreamEnabled(bool value) =>
      _persist(state.copyWith(streamEnabled: value));

  void setCharsPerToken(double value) =>
      _persist(state.copyWith(charsPerToken: value.clamp(1, 8)));

  void setLibraryViewMode(String mode) =>
      _persist(state.copyWith(libraryViewMode: mode));

  /// 第一人称系统提示词。传空串表示回到内置默认。
  void setFirstPersonPrompt(String value) =>
      _persist(state.copyWith(firstPersonPrompt: value));

  /// 第三人称系统提示词。传空串表示回到内置默认。
  void setThirdPersonPrompt(String value) =>
      _persist(state.copyWith(thirdPersonPrompt: value));

  /// 成人向提示词（破限 + 尺度合成的一份）。传空串表示回到内置默认。
  void setAdultPrompt(String value) =>
      _persist(state.copyWith(adultPrompt: value));

  /// 关于页连点软件名：第一次解锁并开启，之后每次点击都是开关切换。
  ///
  /// 不再有界面上的滑块 —— 一个开关放在设置页里，等于把「这软件支持
  /// 成人向」摆在明面上；连点是个刻意的门槛，也给误触留了缓冲。
  void toggleNsfwByTap() {
    if (!state.nsfwUnlocked) {
      _persist(state.copyWith(nsfwUnlocked: true, nsfwEnabled: true));
      return;
    }
    _persist(state.copyWith(nsfwEnabled: !state.nsfwEnabled));
  }

  /// 单次回复总字数上限（0 = 不限制）。
  void setMaxReplyLength(int value) =>
      _persist(state.copyWith(maxReplyLength: value.clamp(0, 1000)));

  /// 叙述视角：'character' 角色扮演 / 'author' 作者第三人称
  void setNarrativeMode(String mode) =>
      _persist(state.copyWith(narrativeMode: mode));

  /// API 配置增删后刷新（默认配置可能已变化）
  void reload() => state = ref.read(settingsRepositoryProvider).loadSettings();
}

final appSettingsProvider =
    NotifierProvider<AppSettingsNotifier, AppSettings>(AppSettingsNotifier.new);
