import 'dart:convert';

import '../../../core/security/secure_key_store.dart';
import '../../../core/utils/ids.dart';
import '../../../core/utils/time_utils.dart';
import 'settings_dao.dart';
import '../domain/settings_models.dart';

class SettingsRepository {
  SettingsRepository({
    required SettingsDao settingsDao,
    required ApiConfigDao apiConfigDao,
    required PricingDao pricingDao,
    required SecureKeyStore keyStore,
  })  : _settingsDao = settingsDao,
        _apiConfigDao = apiConfigDao,
        _pricingDao = pricingDao,
        _keyStore = keyStore;

  final SettingsDao _settingsDao;
  final ApiConfigDao _apiConfigDao;
  final PricingDao _pricingDao;
  final SecureKeyStore _keyStore;

  // ───────────────────────────── 应用设置 ─────────────────────────────

  AppSettings loadSettings() {
    final raw = _settingsDao.all();
    const defaults = AppSettings();

    var navOrder = defaults.navOrder;
    final navRaw = raw[SettingKeys.navOrder];
    if (navRaw != null && navRaw.isNotEmpty) {
      try {
        final decoded = jsonDecode(navRaw);
        if (decoded is List) {
          final parsed = decoded.whereType<String>().toList();
          if (parsed.length == 4 && parsed.toSet().length == 4) {
            navOrder = parsed;
          }
        }
      } catch (_) {
        // 配置损坏时回落到默认顺序
      }
    }

    return AppSettings(
      themeMode: raw[SettingKeys.themeMode] ?? defaults.themeMode,
      themeAccent: raw[SettingKeys.themeAccent] ?? defaults.themeAccent,
      themeSpot: raw[SettingKeys.themeSpot] ?? defaults.themeSpot,
      navOrder: navOrder,
      defaultApiConfigId: raw[SettingKeys.defaultApiConfigId],
      contextLimit: int.tryParse(raw[SettingKeys.contextLimit] ?? '') ?? defaults.contextLimit,
      temperature:
          double.tryParse(raw[SettingKeys.temperature] ?? '') ?? defaults.temperature,
      topP: double.tryParse(raw[SettingKeys.topP] ?? '') ?? defaults.topP,
      streamEnabled:
          (raw[SettingKeys.streamEnabled] ?? 'true') == 'true',
      charsPerToken:
          double.tryParse(raw[SettingKeys.charsPerToken] ?? '') ?? defaults.charsPerToken,
      outputRatio:
          double.tryParse(raw[SettingKeys.outputRatio] ?? '') ?? defaults.outputRatio,
      libraryViewMode: raw[SettingKeys.libraryViewMode] ?? defaults.libraryViewMode,
      systemPrompt: raw[SettingKeys.systemPrompt] ?? defaults.systemPrompt,
      nsfwUnlocked:
          (raw[SettingKeys.nsfwUnlocked] ?? 'false') == 'true',
      nsfwEnabled: (raw[SettingKeys.nsfwEnabled] ?? 'false') == 'true',
      maxReplyLength: int.tryParse(raw[SettingKeys.maxReplyLength] ?? '') ??
          defaults.maxReplyLength,
      narrativeMode:
          raw[SettingKeys.narrativeMode] ?? defaults.narrativeMode,
    );
  }

  void saveSettings(AppSettings settings) {
    _settingsDao.setAll(<String, String>{
      SettingKeys.themeMode: settings.themeMode,
      SettingKeys.themeAccent: settings.themeAccent,
      SettingKeys.themeSpot: settings.themeSpot,
      SettingKeys.navOrder: jsonEncode(settings.navOrder),
      if (settings.defaultApiConfigId != null)
        SettingKeys.defaultApiConfigId: settings.defaultApiConfigId!,
      SettingKeys.contextLimit: '${settings.contextLimit}',
      SettingKeys.temperature: '${settings.temperature}',
      SettingKeys.topP: '${settings.topP}',
      SettingKeys.streamEnabled: '${settings.streamEnabled}',
      SettingKeys.charsPerToken: '${settings.charsPerToken}',
      SettingKeys.outputRatio: '${settings.outputRatio}',
      SettingKeys.libraryViewMode: settings.libraryViewMode,
      SettingKeys.systemPrompt: settings.systemPrompt,
      SettingKeys.nsfwUnlocked: '${settings.nsfwUnlocked}',
      SettingKeys.nsfwEnabled: '${settings.nsfwEnabled}',
      SettingKeys.maxReplyLength: '${settings.maxReplyLength}',
      SettingKeys.narrativeMode: settings.narrativeMode,
    });
  }

  String? rawSetting(String key) => _settingsDao.get(key);

  void setRaw(String key, String value) => _settingsDao.set(key, value);

  void removeRaw(String key) => _settingsDao.remove(key);

  // ───────────────────────────── API 配置 ─────────────────────────────

  List<ApiConfig> apiConfigs() => _apiConfigDao.list();

  ApiConfig? apiConfig(String id) => _apiConfigDao.byId(id);

  ApiConfig? defaultApiConfig() => _apiConfigDao.defaultConfig();

  /// 保存配置。[plainApiKey] 非空时写入安全存储，数据库只留 keyRef。
  Future<ApiConfig> saveApiConfig(ApiConfig config, {String? plainApiKey}) async {
    var keyRef = config.keyRef;
    if (keyRef.isEmpty) {
      keyRef = 'api_key_${config.id}';
    }
    if (plainApiKey != null && plainApiKey.isNotEmpty) {
      await _keyStore.write(keyRef, plainApiKey);
    }
    final now = nowMs();
    final saved = config.copyWith(keyRef: keyRef, updatedAt: now);
    _apiConfigDao.save(saved);
    if (saved.isDefault) {
      _apiConfigDao.setDefault(saved.id);
    }
    return saved;
  }

  Future<String> apiKey(ApiConfig config) async {
    if (config.keyRef.isEmpty) return '';
    final value = await _keyStore.read(config.keyRef);
    return value ?? '';
  }

  Future<void> deleteApiConfig(ApiConfig config) async {
    _apiConfigDao.delete(config.id);
    if (config.keyRef.isNotEmpty) {
      await _keyStore.delete(config.keyRef);
    }
  }

  void setDefaultApiConfig(String id) => _apiConfigDao.setDefault(id);

  ApiConfig newApiConfigTemplate() {
    final now = nowMs();
    final id = newId();
    return ApiConfig(
      id: id,
      name: '',
      baseUrl: 'https://api.openai.com/v1',
      model: 'gpt-4o-mini',
      keyRef: 'api_key_$id',
      createdAt: now,
      updatedAt: now,
    );
  }

  // ───────────────────────────── 单价 ─────────────────────────────

  List<ModelPricing> pricings() => _pricingDao.list();

  ModelPricing? resolvePricing(String model) => _pricingDao.resolve(model);

  void savePricing({
    required String pattern,
    required int inputPer1M,
    required int outputPer1M,
    String currency = 'USD',
  }) =>
      _pricingDao.save(
        pattern: pattern,
        inputPer1M: inputPer1M,
        outputPer1M: outputPer1M,
        currency: currency,
      );

  void deletePricing(String id) => _pricingDao.delete(id);

  Future<void> clearAllSecrets() => _keyStore.deleteAll();
}
