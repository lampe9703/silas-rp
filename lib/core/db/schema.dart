/// 数据库 schema 定义（v1）。
///
/// 设计要点见 DESIGN.md，此处只列不可变的结构。
/// 所有时间字段为毫秒时间戳（INTEGER），所有金额为「微单位」（INTEGER）。
library;

const int kSchemaVersion = 5;

/// v1 建表语句。按依赖顺序排列（被引用的表在前）。
const List<String> kSchemaV1 = <String>[
  // ───────────────────────────── 角色卡 ─────────────────────────────
  '''
CREATE TABLE character_cards (
  id            TEXT    PRIMARY KEY,
  name          TEXT    NOT NULL,
  description   TEXT    NOT NULL DEFAULT '',
  personality   TEXT    NOT NULL DEFAULT '',
  scenario      TEXT    NOT NULL DEFAULT '',
  first_mes     TEXT    NOT NULL DEFAULT '',
  mes_example   TEXT    NOT NULL DEFAULT '',
  system_prompt TEXT    NOT NULL DEFAULT '',
  post_history_instructions TEXT NOT NULL DEFAULT '',
  creator       TEXT    NOT NULL DEFAULT '',
  card_version  TEXT    NOT NULL DEFAULT '',
  avatar_path   TEXT,
  source        TEXT    NOT NULL DEFAULT 'manual',
  spec          TEXT    NOT NULL DEFAULT 'v2',
  raw_json      TEXT,
  is_favorite   INTEGER NOT NULL DEFAULT 0,
  created_at    INTEGER NOT NULL,
  updated_at    INTEGER NOT NULL,
  last_chat_at  INTEGER
)
''',

  // 标签多对多：WITHOUT ROWID 省掉一层 B-Tree
  '''
CREATE TABLE character_tags (
  card_id TEXT NOT NULL REFERENCES character_cards(id) ON DELETE CASCADE,
  tag     TEXT NOT NULL,
  PRIMARY KEY (card_id, tag)
) WITHOUT ROWID
''',

  // 备选开场白（first_mes 留在主表作为「主开场白」）
  '''
CREATE TABLE character_greetings (
  id      TEXT    PRIMARY KEY,
  card_id TEXT    NOT NULL REFERENCES character_cards(id) ON DELETE CASCADE,
  seq     INTEGER NOT NULL,
  content TEXT    NOT NULL
)
''',

  // ───────────────────────────── 会话 / 消息 ─────────────────────────────
  '''
CREATE TABLE chat_sessions (
  id                TEXT    PRIMARY KEY,
  card_id           TEXT    NOT NULL REFERENCES character_cards(id) ON DELETE CASCADE,
  title             TEXT    NOT NULL DEFAULT '',
  greeting_seq      INTEGER NOT NULL DEFAULT 0,
  message_count     INTEGER NOT NULL DEFAULT 0,
  preview_text      TEXT    NOT NULL DEFAULT '',
  last_message_at   INTEGER,
  last_message_role TEXT,
  is_archived       INTEGER NOT NULL DEFAULT 0,
  created_at        INTEGER NOT NULL,
  updated_at        INTEGER NOT NULL
)
''',

  '''
CREATE TABLE messages (
  id                    TEXT    PRIMARY KEY,
  session_id            TEXT    NOT NULL REFERENCES chat_sessions(id) ON DELETE CASCADE,
  seq                   INTEGER NOT NULL,
  role                  TEXT    NOT NULL CHECK (role IN ('system','user','assistant')),
  content               TEXT    NOT NULL DEFAULT '',
  status                TEXT    NOT NULL DEFAULT 'done'
                        CHECK (status IN ('pending','streaming','done','error','cancelled')),
  variant_group         TEXT,
  variant_index         INTEGER NOT NULL DEFAULT 0,
  is_active_variant     INTEGER NOT NULL DEFAULT 1,
  excluded_from_context INTEGER NOT NULL DEFAULT 0,
  token_count           INTEGER,
  model                 TEXT,
  api_config_id         TEXT,
  error_message         TEXT,
  finish_reason         TEXT,
  latency_ms            INTEGER,
  created_at            INTEGER NOT NULL,
  updated_at            INTEGER NOT NULL
)
''',

  // ───────────────────────────── API 配置 / 计价 ─────────────────────────────
  '''
CREATE TABLE api_configs (
  id                   TEXT    PRIMARY KEY,
  name                 TEXT    NOT NULL,
  base_url             TEXT    NOT NULL,
  model                TEXT    NOT NULL,
  is_openai_compatible INTEGER NOT NULL DEFAULT 1,
  key_ref              TEXT    NOT NULL,
  extra_headers        TEXT    NOT NULL DEFAULT '{}',
  max_tokens           INTEGER,
  temperature          REAL,
  top_p                REAL,
  stream               INTEGER NOT NULL DEFAULT 1,
  is_default           INTEGER NOT NULL DEFAULT 0,
  created_at           INTEGER NOT NULL,
  updated_at           INTEGER NOT NULL
)
''',

  '''
CREATE TABLE model_pricing (
  id            TEXT    PRIMARY KEY,
  model_pattern TEXT    NOT NULL UNIQUE,
  input_per_1m  INTEGER NOT NULL,
  output_per_1m INTEGER NOT NULL,
  currency      TEXT    NOT NULL DEFAULT 'USD',
  updated_at    INTEGER NOT NULL
)
''',

  // ───────────────────────────── 调用统计 ─────────────────────────────
  // card_id / session_id 为弱引用（不建外键）：删卡后历史统计必须保留
  '''
CREATE TABLE api_call_logs (
  id                TEXT    PRIMARY KEY,
  request_at        INTEGER NOT NULL,
  session_id        TEXT,
  message_id        TEXT,
  card_id           TEXT,
  card_name         TEXT    NOT NULL DEFAULT '',
  api_config_id     TEXT,
  model             TEXT    NOT NULL DEFAULT '',
  status            TEXT    NOT NULL CHECK (status IN ('success','error','cancelled')),
  http_status       INTEGER,
  prompt_tokens     INTEGER NOT NULL DEFAULT 0,
  completion_tokens INTEGER NOT NULL DEFAULT 0,
  total_tokens      INTEGER NOT NULL DEFAULT 0,
  is_estimated      INTEGER NOT NULL DEFAULT 0,
  cost_micros       INTEGER NOT NULL DEFAULT 0,
  latency_ms        INTEGER NOT NULL DEFAULT 0,
  ttft_ms           INTEGER,
  error_code        TEXT
)
''',

  // 按天预聚合：所有图表/汇总的唯一数据源
  '''
CREATE TABLE api_usage_daily (
  day               TEXT    NOT NULL,
  model             TEXT    NOT NULL,
  card_id           TEXT    NOT NULL DEFAULT '',
  card_name         TEXT    NOT NULL DEFAULT '',
  requests          INTEGER NOT NULL DEFAULT 0,
  errors            INTEGER NOT NULL DEFAULT 0,
  prompt_tokens     INTEGER NOT NULL DEFAULT 0,
  completion_tokens INTEGER NOT NULL DEFAULT 0,
  cost_micros       INTEGER NOT NULL DEFAULT 0,
  latency_sum_ms    INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (day, model, card_id)
) WITHOUT ROWID
''',

  '''
CREATE TABLE app_settings (
  key   TEXT PRIMARY KEY,
  value TEXT NOT NULL
) WITHOUT ROWID
''',

  // ───────────────────────────── 索引 ─────────────────────────────
  'CREATE INDEX idx_cards_updated ON character_cards(updated_at DESC, id DESC)',
  'CREATE INDEX idx_cards_last_chat ON character_cards(last_chat_at DESC) WHERE last_chat_at IS NOT NULL',
  'CREATE INDEX idx_tags_tag ON character_tags(tag, card_id)',
  'CREATE INDEX idx_greetings_card ON character_greetings(card_id, seq)',

  'CREATE INDEX idx_sessions_card ON chat_sessions(card_id, last_message_at DESC)',
  'CREATE INDEX idx_sessions_recent ON chat_sessions(is_archived, last_message_at DESC)',

  'CREATE INDEX idx_msg_session_seq ON messages(session_id, seq)',
  // 同一 (session, seq) 只允许一条生效变体：DB 层兜底并发/重入
  'CREATE UNIQUE INDEX uq_msg_active ON messages(session_id, seq) WHERE is_active_variant = 1',

  'CREATE INDEX idx_logs_time ON api_call_logs(request_at DESC, id DESC)',
  'CREATE INDEX idx_logs_model ON api_call_logs(model, request_at DESC, id DESC)',
  'CREATE INDEX idx_logs_card ON api_call_logs(card_id, request_at DESC, id DESC)',
  'CREATE INDEX idx_usage_day ON api_usage_daily(day)',

  // 只允许一个默认 API 配置
  'CREATE UNIQUE INDEX uq_api_default ON api_configs(is_default) WHERE is_default = 1',

  // ───────────────────────────── 触发器 ─────────────────────────────
  // 冗余计数：应用层漏更新也不会漂
  '''
CREATE TRIGGER trg_msg_insert AFTER INSERT ON messages BEGIN
  UPDATE chat_sessions
     SET message_count = message_count + 1,
         last_message_at = NEW.created_at,
         last_message_role = NEW.role,
         preview_text = CASE WHEN NEW.content <> '' THEN substr(NEW.content, 1, 80) ELSE preview_text END,
         updated_at = NEW.created_at
   WHERE id = NEW.session_id;
END
''',

  '''
CREATE TRIGGER trg_msg_delete AFTER DELETE ON messages BEGIN
  UPDATE chat_sessions SET message_count = message_count - 1 WHERE id = OLD.session_id;
END
''',
];

/// v2：角色卡状态栏 + 会话状态快照
const List<String> kSchemaV2 = <String>[
  'ALTER TABLE character_cards ADD COLUMN status_enabled INTEGER NOT NULL DEFAULT 0',
  "ALTER TABLE character_cards ADD COLUMN status_initial TEXT NOT NULL DEFAULT '{}'",
  "ALTER TABLE character_cards ADD COLUMN status_rules TEXT NOT NULL DEFAULT ''",
  "ALTER TABLE character_cards ADD COLUMN status_template TEXT NOT NULL DEFAULT ''",
  "ALTER TABLE chat_sessions ADD COLUMN status_state TEXT NOT NULL DEFAULT '{}'",
];

/// v3：状态栏输出格式 + 世界书（条目以 JSON 数组随卡片整体保存）
const List<String> kSchemaV3 = <String>[
  "ALTER TABLE character_cards ADD COLUMN status_format TEXT NOT NULL DEFAULT 'template'",
  "ALTER TABLE character_cards ADD COLUMN world_book TEXT NOT NULL DEFAULT '[]'",
];

/// v4：简介独立成列（人设正文不再兼任列表简介）
const List<String> kSchemaV4 = <String>[
  "ALTER TABLE character_cards ADD COLUMN summary TEXT NOT NULL DEFAULT ''",
];

/// v5：把模型的思考过程（reasoning_content）存下来，供「查看思考过程」使用。
///
/// 单独一列而不是塞进 content：思考绝不能回灌上下文，
/// 分列之后 `contextWindow` 天然只取 content。
const List<String> kSchemaV5 = <String>[
  "ALTER TABLE messages ADD COLUMN reasoning TEXT NOT NULL DEFAULT ''",
];

/// 全文检索相关对象单独成组：运行时探测 FTS5+trigram 是否可用，不可用则整体降级为 LIKE。
///
/// 中文关键：unicode61 对无空格中文整句只切出一个 token，必须用 trigram。
const List<String> kSchemaV1Fts = <String>[
  '''
CREATE VIRTUAL TABLE character_cards_fts USING fts5(
  name, description, tags, tokenize='trigram'
)
''',
  // FTS 同步（standalone 表，rowid 与 character_cards.rowid 对齐）
  '''
CREATE TRIGGER trg_cards_fts_ai AFTER INSERT ON character_cards BEGIN
  INSERT INTO character_cards_fts(rowid, name, description, tags)
  VALUES (NEW.rowid, NEW.name, NEW.description, '');
END
''',
  '''
CREATE TRIGGER trg_cards_fts_au AFTER UPDATE ON character_cards BEGIN
  DELETE FROM character_cards_fts WHERE rowid = OLD.rowid;
  INSERT INTO character_cards_fts(rowid, name, description, tags)
  VALUES (NEW.rowid, NEW.name, NEW.description, '');
END
''',
  '''
CREATE TRIGGER trg_cards_fts_ad AFTER DELETE ON character_cards BEGIN
  DELETE FROM character_cards_fts WHERE rowid = OLD.rowid;
END
''',
];
