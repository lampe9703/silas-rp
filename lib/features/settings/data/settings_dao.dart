import '../../../core/db/app_database.dart';
import '../../../core/utils/ids.dart';
import '../../../core/utils/time_utils.dart';
import '../domain/settings_models.dart';

/// 键值设置
class SettingsDao {
  SettingsDao(this._db);

  final AppDatabase _db;

  Map<String, String> all() {
    final rows = _db.select('SELECT key, value FROM app_settings');
    return <String, String>{
      for (final r in rows) r['key'] as String: (r['value'] as String?) ?? '',
    };
  }

  String? get(String key) {
    final rows = _db.select(
      'SELECT value FROM app_settings WHERE key = ?',
      [key],
    );
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  void set(String key, String value) {
    _db.execute(
      'INSERT INTO app_settings(key, value) VALUES (?, ?) '
      'ON CONFLICT(key) DO UPDATE SET value = excluded.value',
      [key, value],
    );
  }

  void setAll(Map<String, String> values) {
    _db.transaction(() {
      values.forEach(set);
    });
  }

  void remove(String key) {
    _db.execute('DELETE FROM app_settings WHERE key = ?', [key]);
  }
}

/// API 配置。明文 Key 存安全存储，这里只存 keyRef 引用。
class ApiConfigDao {
  ApiConfigDao(this._db);

  final AppDatabase _db;

  List<ApiConfig> list() {
    final rows = _db.select(
      'SELECT * FROM api_configs ORDER BY is_default DESC, created_at ASC',
    );
    return rows.map(ApiConfig.fromRow).toList();
  }

  ApiConfig? byId(String id) {
    final rows = _db.select('SELECT * FROM api_configs WHERE id = ?', [id]);
    if (rows.isEmpty) return null;
    return ApiConfig.fromRow(rows.first);
  }

  ApiConfig? defaultConfig() {
    final rows = _db.select(
      'SELECT * FROM api_configs ORDER BY is_default DESC, created_at ASC LIMIT 1',
    );
    if (rows.isEmpty) return null;
    return ApiConfig.fromRow(rows.first);
  }

  void save(ApiConfig config) {
    _db.execute(
      '''
INSERT INTO api_configs (
  id, name, base_url, model, is_openai_compatible, key_ref, extra_headers,
  max_tokens, temperature, top_p, stream, is_default, created_at, updated_at
) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)
ON CONFLICT(id) DO UPDATE SET
  name = excluded.name,
  base_url = excluded.base_url,
  model = excluded.model,
  is_openai_compatible = excluded.is_openai_compatible,
  key_ref = excluded.key_ref,
  extra_headers = excluded.extra_headers,
  max_tokens = excluded.max_tokens,
  temperature = excluded.temperature,
  top_p = excluded.top_p,
  stream = excluded.stream,
  is_default = excluded.is_default,
  updated_at = excluded.updated_at
''',
      <Object?>[
        config.id,
        config.name,
        config.baseUrl,
        config.model,
        config.isOpenAiCompatible ? 1 : 0,
        config.keyRef,
        _encodeHeaders(config.extraHeaders),
        config.maxTokens,
        config.temperature,
        config.topP,
        config.stream ? 1 : 0,
        config.isDefault ? 1 : 0,
        config.createdAt,
        config.updatedAt,
      ],
    );
  }

  static String _encodeHeaders(Map<String, String> headers) {
    if (headers.isEmpty) return '{}';
    final entries = headers.entries
        .where((e) => e.key.trim().isNotEmpty)
        .map((e) => '"${_escape(e.key)}":"${_escape(e.value)}"')
        .join(',');
    return '{$entries}';
  }

  static String _escape(String raw) => raw
      .replaceAll(r'\', r'\\')
      .replaceAll('"', r'\"')
      .replaceAll('\n', r'\n');

  /// 设为默认：先清空其他默认值，避免部分唯一索引冲突
  void setDefault(String id) {
    _db.transaction(() {
      _db.execute('UPDATE api_configs SET is_default = 0 WHERE is_default = 1');
      _db.execute('UPDATE api_configs SET is_default = 1 WHERE id = ?', [id]);
    });
  }

  void delete(String id) {
    _db.execute('DELETE FROM api_configs WHERE id = ?', [id]);
  }

  int count() {
    final rows = _db.select('SELECT COUNT(*) AS c FROM api_configs');
    return (rows.first['c'] as int?) ?? 0;
  }
}

/// 模型单价（微单位 / 1M token）
class PricingDao {
  PricingDao(this._db);

  final AppDatabase _db;

  List<ModelPricing> list() {
    final rows = _db.select(
      'SELECT * FROM model_pricing ORDER BY model_pattern',
    );
    return rows.map(ModelPricing.fromRow).toList();
  }

  /// 解析单价：精确匹配优先，其次通配，最后取第一条通配规则
  ModelPricing? resolve(String model) {
    if (model.trim().isEmpty) return null;
    final all = list();
    for (final p in all) {
      if (!p.modelPattern.contains('*') &&
          p.modelPattern.toLowerCase() == model.toLowerCase()) {
        return p;
      }
    }
    for (final p in all) {
      if (p.matches(model)) return p;
    }
    return null;
  }

  void save({
    required String pattern,
    required int inputPer1M,
    required int outputPer1M,
    String currency = 'USD',
  }) {
    final now = nowMs();
    _db.execute(
      'INSERT INTO model_pricing(id, model_pattern, input_per_1m, output_per_1m, currency, updated_at) '
      'VALUES (?,?,?,?,?,?) '
      'ON CONFLICT(model_pattern) DO UPDATE SET '
      'input_per_1m = excluded.input_per_1m, output_per_1m = excluded.output_per_1m, '
      'currency = excluded.currency, updated_at = excluded.updated_at',
      [newId(), pattern.trim(), inputPer1M, outputPer1M, currency, now],
    );
  }

  void delete(String id) {
    _db.execute('DELETE FROM model_pricing WHERE id = ?', [id]);
  }
}
