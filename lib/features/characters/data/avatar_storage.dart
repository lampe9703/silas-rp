import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 头像文件存储。
///
/// 数据库只存相对路径（`avatars/<id>.png`）：iOS 应用沙盒的绝对路径在
/// 重装/迁移后会变，存绝对路径必然失效。
class AvatarStorage {
  AvatarStorage._(this._baseDir);

  final Directory _baseDir;

  static Future<AvatarStorage> create() async {
    final base = await getApplicationSupportDirectory();
    await Directory(p.join(base.path, 'avatars')).create(recursive: true);
    return AvatarStorage._(base);
  }

  Future<String> save(String cardId, Uint8List bytes) async {
    final rel = p.join('avatars', '$cardId.png');
    final file = File(p.join(_baseDir.path, rel));
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
    return rel;
  }

  File? file(String? relativePath) {
    if (relativePath == null || relativePath.isEmpty) return null;
    final f = File(p.join(_baseDir.path, relativePath));
    return f.existsSync() ? f : null;
  }

  Future<void> remove(String? relativePath) async {
    final f = file(relativePath);
    if (f == null) return;
    try {
      await f.delete();
    } catch (_) {
      // 文件已被删除或占用时忽略
    }
  }

  /// 导出 PNG 时读取原始头像字节
  Future<Uint8List?> readBytes(String? relativePath) async {
    final f = file(relativePath);
    if (f == null) return null;
    return f.readAsBytes();
  }
}
