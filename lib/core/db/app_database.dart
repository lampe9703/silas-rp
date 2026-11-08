import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:sqlite3_flutter_libs/sqlite3_flutter_libs.dart';

import 'schema.dart';

/// SQLite 连接封装。
///
/// 为什么不用 ORM 代码生成：本项目所有关键查询（统计聚合、键集分页、FTS）
/// 都必须写成显式 SQL 才能控制执行计划，手写 SQL + 轻量类型映射反而更透明，
/// 且免去 build_runner 这一步，`flutter run` 即可跑。
class AppDatabase {
  AppDatabase._(this._db, this.path, this.ftsAvailable);

  final Database _db;
  final String path;

  /// FTS5 + trigram 是否可用（不可用时搜索自动降级为 LIKE）
  final bool ftsAvailable;

  /// 当前事务深度（重入保护）。
  ///
  /// 历史缺陷：`CharacterDao.importAll` 在事务里循环调 `save`，而 `save`
  /// 自己又开事务 → `cannot start a transaction within a transaction`，
  /// 任何 JSON 导入必崩。现在 transaction 支持重入：嵌套调用直接并入
  /// 外层事务（同生共死），既保住原子性又不再报错。
  int _txnDepth = 0;

  static Future<AppDatabase> open({String? overridePath}) async {
    if (Platform.isAndroid) {
      // 老版本 Android 系统自带的 libsqlite 太旧，需从 APK 内解包使用
      await applyWorkaroundToOpenSqlite3OnOldAndroidVersions();
    }

    final String dbPath;
    if (overridePath != null) {
      dbPath = overridePath;
    } else {
      final dir = await getApplicationSupportDirectory();
      await Directory(dir.path).create(recursive: true);
      dbPath = p.join(dir.path, 'ai_roleplay.sqlite');
    }

    final raw = sqlite3.open(dbPath);
    _applyPragmas(raw);
    final fts = _probeFts(raw);
    _migrate(raw, fts);
    return AppDatabase._(raw, dbPath, fts);
  }

  /// 全局 PRAGMA。顺序有讲究：auto_vacuum 必须在建表前设置才生效。
  static void _applyPragmas(Database db) {
    db.execute('PRAGMA auto_vacuum = INCREMENTAL');
    db.execute('PRAGMA journal_mode = WAL');
    db.execute('PRAGMA synchronous = NORMAL');
    db.execute('PRAGMA foreign_keys = ON');
    db.execute('PRAGMA temp_store = MEMORY');
    db.execute('PRAGMA cache_size = -8000');
    db.execute('PRAGMA mmap_size = 268435456');
  }

  static bool _probeFts(Database db) {
    try {
      db.execute(
        "CREATE VIRTUAL TABLE temp.__fts_probe USING fts5(x, tokenize='trigram')",
      );
      db.execute('DROP TABLE temp.__fts_probe');
      return true;
    } catch (_) {
      return false;
    }
  }

  static void _migrate(Database db, bool fts) {
    final current =
        (db.select('PRAGMA user_version').first.values.first as int?) ?? 0;
    if (current >= kSchemaVersion) {
      if (fts) _ensureFtsObjects(db);
      return;
    }

    db.execute('BEGIN');
    try {
      if (current < 1) {
        for (final stmt in kSchemaV1) {
          db.execute(stmt);
        }
        if (fts) {
          for (final stmt in kSchemaV1Fts) {
            db.execute(stmt);
          }
        }
      }
      if (current < 2) {
        for (final stmt in kSchemaV2) {
          db.execute(stmt);
        }
      }
      if (current < 3) {
        for (final stmt in kSchemaV3) {
          db.execute(stmt);
        }
      }
      if (current < 4) {
        for (final stmt in kSchemaV4) {
          db.execute(stmt);
        }
      }
      if (current < 5) {
        for (final stmt in kSchemaV5) {
          db.execute(stmt);
        }
      }
      if (current < 6) {
        for (final stmt in kSchemaV6) {
          db.execute(stmt);
        }
      }
      if (current < 7) {
        for (final stmt in kSchemaV7) {
          db.execute(stmt);
        }
      }
      if (current < 8) {
        for (final stmt in kSchemaV8) {
          db.execute(stmt);
        }
      }
      if (current < 9) {
        // 收藏功能下线。DROP COLUMN 需要 SQLite 3.35+，
        // 老版本删不掉就留着当废弃列，不能让整次迁移失败。
        for (final stmt in kSchemaV9) {
          try {
            db.execute(stmt);
          } catch (_) {
            // 忽略：列留着不影响读写
          }
        }
      }
      db.execute('PRAGMA user_version = $kSchemaVersion');
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  /// 已是最新版本但 FTS 对象缺失（例如从降级版本恢复）时补齐
  static void _ensureFtsObjects(Database db) {
    final exists = db.select(
      "SELECT 1 FROM sqlite_master WHERE type='table' AND name='character_cards_fts'",
    );
    if (exists.isNotEmpty) return;
    for (final stmt in kSchemaV1Fts) {
      db.execute(stmt);
    }
    // 重建索引内容
    db.execute(
      "INSERT INTO character_cards_fts(rowid, name, description, tags) "
      "SELECT rowid, name, description, '' FROM character_cards",
    );
  }

  // ───────────────────────────── 基础操作 ─────────────────────────────

  ResultSet select(String sql, [List<Object?> params = const []]) =>
      _db.select(sql, params);

  void execute(String sql, [List<Object?> params = const []]) =>
      _db.execute(sql, params);

  int get lastInsertRowId => _db.lastInsertRowId;

  /// 显式事务。批量导入 / 记账必须走这里，保证原子性。
  ///
  /// 可重入：已在事务内时嵌套调用直接执行并入外层事务，
  /// 不再发出第二条 BEGIN（SQLite 不支持事务嵌套）。
  T transaction<T>(T Function() action) {
    if (_txnDepth > 0) {
      _txnDepth++;
      try {
        return action();
      } finally {
        _txnDepth--;
      }
    }
    _db.execute('BEGIN IMMEDIATE');
    _txnDepth = 1;
    try {
      final result = action();
      _db.execute('COMMIT');
      return result;
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    } finally {
      _txnDepth = 0;
    }
  }

  /// 清空全部业务数据（保留 schema）
  void wipeAll() {
    transaction(() {
      _db.execute('DELETE FROM api_call_logs');
      _db.execute('DELETE FROM api_usage_daily');
      _db.execute('DELETE FROM messages');
      _db.execute('DELETE FROM chat_sessions');
      _db.execute('DELETE FROM character_greetings');
      _db.execute('DELETE FROM character_tags');
      _db.execute('DELETE FROM character_cards');
      _db.execute('DELETE FROM api_configs');
      _db.execute('DELETE FROM model_pricing');
      _db.execute('DELETE FROM app_settings');
    });
    _db.execute('PRAGMA incremental_vacuum');
  }

  /// 启动空闲时调用，让 SQLite 更新查询计划统计
  void optimize() {
    try {
      _db.execute('PRAGMA optimize');
    } catch (_) {
      // 忽略：优化失败不影响功能
    }
  }

  void close() => _db.dispose();
}

