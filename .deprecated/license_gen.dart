import 'dart:io';

import 'package:ai_roleplay/features/license/domain/license_codec.dart';

/// 激活码生成工具（只在你自己的电脑上跑，不要打包进 App）。
///
/// 用法（在 ai_roleplay 目录下执行）：
///   dart run tool/license_gen.dart 10              # 生成 10 个，带说明
///   dart run tool/license_gen.dart 10 --plain      # 只输出码，一行一个
///   dart run tool/license_gen.dart 10 --csv        # 输出 订单号,激活码
///   dart run tool/license_gen.dart --check SRP-…   # 校验一个码
///
/// 发货建议：
///   1. `dart run tool/license_gen.dart 20 --csv > codes.csv`
///   2. 表格里补上「买家 / 日期 / 金额」，卖一个划一个
///   3. 买家在 App「设置 → 高级版 → 输入激活码」里粘贴
///
/// 注意：生成逻辑依赖 lib/features/license/domain/license_secret.dart 里的密钥，
/// 密钥同时也在 App 里，所以**这个仓库不要公开**，否则别人能自己造码。
void main(List<String> args) {
  final flags = args.where((a) => a.startsWith('-')).toSet();
  final rest = args.where((a) => !a.startsWith('-')).toList();

  if (flags.contains('--help') || flags.contains('-h')) {
    _usage();
    return;
  }

  if (flags.contains('--check')) {
    final code = rest.join(' ');
    final result = LicenseCodec.verify(code);
    if (result.isValid) {
      stdout.writeln('有效 · 订单号 ${result.id}');
      stdout.writeln(
        '规范化：${LicenseCodec.format(LicenseCodec.normalize(code))}',
      );
    } else {
      stdout.writeln('无效：${result.error}');
      exitCode = 1;
    }
    return;
  }

  final count = rest.isEmpty ? 1 : (int.tryParse(rest.first) ?? 1);
  if (count <= 0 || count > 500) {
    stderr.writeln('数量需在 1 ~ 500 之间');
    exitCode = 2;
    return;
  }

  final ids = <String>[];
  final seen = <String>{};
  for (var i = 0; i < count; i++) {
    String id;
    do {
      id = LicenseCodec.randomId();
    } while (!seen.add(id));
    ids.add(id);
  }

  if (flags.contains('--csv')) {
    stdout.writeln('order_id,code');
    for (final id in ids) {
      stdout.writeln('$id,${LicenseCodec.build(id)}');
    }
    return;
  }

  if (flags.contains('--plain')) {
    for (final id in ids) {
      stdout.writeln(LicenseCodec.build(id));
    }
    return;
  }

  stdout.writeln('生成 $count 个激活码：');
  stdout.writeln('');
  for (var i = 0; i < ids.length; i++) {
    stdout.writeln(
      '${(i + 1).toString().padLeft(3)}  ${LicenseCodec.build(ids[i])}',
    );
  }
  stdout.writeln('');
  stdout.writeln('提示：码不区分大小写、连字符可省略；同一个码可在多台设备上重复激活。');
}

void _usage() {
  stdout.writeln('''
激活码工具

  dart run tool/license_gen.dart [数量]            生成（默认 1 个）
  dart run tool/license_gen.dart [数量] --plain    只输出码，一行一个
  dart run tool/license_gen.dart [数量] --csv      输出 order_id,code
  dart run tool/license_gen.dart --check <激活码>   校验

示例
  dart run tool/license_gen.dart 20 --csv > codes.csv
  dart run tool/license_gen.dart --check "SRP-72PN-P8D1-3GS4-F2ZJ-XSRR-NBR6"
''');
}
