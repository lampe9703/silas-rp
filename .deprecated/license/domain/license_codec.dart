import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'license_secret.dart';

/// 激活码校验结果
class LicenseVerification {
  const LicenseVerification.valid(this.id) : error = null;

  const LicenseVerification.invalid(this.error) : id = null;

  /// 校验通过时返回的订单 ID（激活码前 8 位）
  final String? id;

  /// 校验失败的原因，直接可以展示给用户
  final String? error;

  bool get isValid => id != null;
}

/// 离线激活码的生成与校验。
///
/// 码形如 `SRP-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX`，去掉前缀和连字符后共 24 位：
/// * 前 8 位：随机订单 ID（40 bit），用来区分不同订单、方便客服核对；
/// * 后 16 位：`HMAC-SHA256(密钥, "v1|<ID>")` 截断到 80 bit。
///
/// 字符集用 Crockford Base32（剔除 I / L / O / U），避免和 1 / 0 混淆，
/// 校验时还会把 I、L 当 1、O 当 0，容错手输错误。
class LicenseCodec {
  static const String prefix = 'SRP';

  static const int _idLength = 8;
  static const int _macLength = 16;

  /// 有效字符数（不含前缀与连字符）
  static const int bodyLength = _idLength + _macLength;

  static const String _alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

  /// 规范化用户输入：转大写、去掉一切非字母数字、去前缀、修正易混字符
  static String normalize(String raw) {
    var s = raw.toUpperCase().replaceAll(RegExp(r'[^0-9A-Z]'), '');
    if (s.startsWith(prefix)) s = s.substring(prefix.length);
    return s.replaceAll('I', '1').replaceAll('L', '1').replaceAll('O', '0');
  }

  /// 展示用：每 4 位插一个连字符，带前缀
  static String format(String body) {
    final groups = <String>[];
    for (var i = 0; i < body.length; i += 4) {
      groups.add(body.substring(i, i + 4 > body.length ? body.length : i + 4));
    }
    return '$prefix-${groups.join('-')}';
  }

  /// 由订单 ID 推导出校验段
  static String macFor(String id) {
    final digest =
        Hmac(sha256, licenseSecret()).convert(utf8.encode('v1|$id')).bytes;
    return _encode(Uint8List.fromList(digest.sublist(0, 10)));
  }

  /// 生成一个随机订单 ID（8 位 Crockford Base32，40 bit）
  static String randomId() {
    final rnd = Random.secure();
    final bytes = Uint8List.fromList(
      List<int>.generate(5, (_) => rnd.nextInt(256)),
    );
    return _encode(bytes);
  }

  /// 由订单 ID 拼出完整激活码
  static String build(String id) => format('$id${macFor(id)}');

  /// 校验用户输入的激活码
  static LicenseVerification verify(String raw) {
    final body = normalize(raw);
    if (body.isEmpty) {
      return const LicenseVerification.invalid('请输入激活码');
    }
    if (body.length != bodyLength) {
      return LicenseVerification.invalid(
        '激活码应为 ${bodyLength + 6} 位（不含连字符 ${bodyLength} 位），'
        '当前 ${body.length} 位，请检查是否漏字符',
      );
    }
    for (var i = 0; i < body.length; i++) {
      if (!_alphabet.contains(body[i])) {
        return const LicenseVerification.invalid('激活码包含无效字符');
      }
    }
    final id = body.substring(0, _idLength);
    final mac = body.substring(_idLength);
    if (!_constantTimeEquals(mac, macFor(id))) {
      return const LicenseVerification.invalid('激活码无效，请核对后重试');
    }
    return LicenseVerification.valid(id);
  }

  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }

  /// 定长 Base32 编码：5 字节 → 8 位，10 字节 → 16 位
  static String _encode(Uint8List bytes) {
    final out = StringBuffer();
    var buffer = 0;
    var bits = 0;
    for (final b in bytes) {
      buffer = (buffer << 8) | b;
      bits += 8;
      while (bits >= 5) {
        bits -= 5;
        out.write(_alphabet[(buffer >> bits) & 31]);
      }
    }
    if (bits > 0) {
      out.write(_alphabet[(buffer << (5 - bits)) & 31]);
    }
    return out.toString();
  }
}
