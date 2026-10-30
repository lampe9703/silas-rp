import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// API Key 安全存储。
///
/// 约束：
/// - 明文 Key 只存在 Keychain / Android Keystore，绝不落 SQLite；
/// - 不打印、不写日志；
/// - 导出备份时不包含任何 Key。
class SecureKeyStore {
  SecureKeyStore([FlutterSecureStorage? storage])
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock_this_device,
              ),
            );

  final FlutterSecureStorage _storage;

  Future<void> write(String keyRef, String value) =>
      _storage.write(key: keyRef, value: value);

  Future<String?> read(String keyRef) => _storage.read(key: keyRef);

  Future<void> delete(String keyRef) => _storage.delete(key: keyRef);

  /// 用于「清空全部数据」
  Future<void> deleteAll() => _storage.deleteAll();
}
