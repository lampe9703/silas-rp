import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class PngChunk {
  PngChunk(this.type, this.data);
  final String type;
  final Uint8List data;
}

/// PNG 编解码：只做「读文本块」与「插入文本块」两件事。
///
/// SillyTavern 角色卡就是把 JSON base64 后塞进 tEXt 块（keyword = chara / ccv3）。
class PngCodec {
  static const List<int> _signature = <int>[137, 80, 78, 71, 13, 10, 26, 10];

  static bool isPng(Uint8List bytes) {
    if (bytes.length < 8) return false;
    for (var i = 0; i < 8; i++) {
      if (bytes[i] != _signature[i]) return false;
    }
    return true;
  }

  static List<PngChunk> readChunks(Uint8List bytes) {
    if (!isPng(bytes)) return const <PngChunk>[];
    final data = ByteData.sublistView(bytes);
    final chunks = <PngChunk>[];
    var offset = 8;
    while (offset + 8 <= bytes.length) {
      final length = data.getUint32(offset);
      final type = String.fromCharCodes(bytes.sublist(offset + 4, offset + 8));
      final dataStart = offset + 8;
      final dataEnd = dataStart + length;
      if (dataEnd + 4 > bytes.length) break;
      chunks.add(PngChunk(type, bytes.sublist(dataStart, dataEnd)));
      offset = dataEnd + 4;
      if (type == 'IEND') break;
    }
    return chunks;
  }

  /// 读取所有文本块，返回 keyword → text
  static Map<String, String> readTextChunks(Uint8List bytes) {
    final result = <String, String>{};
    for (final chunk in readChunks(bytes)) {
      try {
        switch (chunk.type) {
          case 'tEXt':
            final split = chunk.data.indexOf(0);
            if (split <= 0) break;
            final keyword = latin1.decode(chunk.data.sublist(0, split));
            final text = latin1.decode(chunk.data.sublist(split + 1));
            result[keyword] = text;
            break;
          case 'zTXt':
            final split = chunk.data.indexOf(0);
            if (split <= 0 || split + 2 > chunk.data.length) break;
            final keyword = latin1.decode(chunk.data.sublist(0, split));
            final compressed = chunk.data.sublist(split + 2);
            final raw = ZLibDecoder().convert(compressed);
            result[keyword] = utf8.decode(raw, allowMalformed: true);
            break;
          case 'iTXt':
            final parsed = _readInternationalText(chunk.data);
            if (parsed != null) result[parsed.$1] = parsed.$2;
            break;
        }
      } catch (_) {
        // 单个块损坏不影响其他块
      }
    }
    return result;
  }

  static (String, String)? _readInternationalText(Uint8List data) {
    final keywordEnd = data.indexOf(0);
    if (keywordEnd <= 0) return null;
    final keyword = latin1.decode(data.sublist(0, keywordEnd));
    if (keywordEnd + 3 > data.length) return null;
    final compressionFlag = data[keywordEnd + 1];
    var cursor = keywordEnd + 3;
    final languageEnd = data.indexOf(0, cursor);
    if (languageEnd < 0) return null;
    cursor = languageEnd + 1;
    final translatedEnd = data.indexOf(0, cursor);
    if (translatedEnd < 0) return null;
    cursor = translatedEnd + 1;
    final textBytes = data.sublist(cursor);
    if (compressionFlag == 1) {
      final raw = ZLibDecoder().convert(textBytes);
      return (keyword, utf8.decode(raw, allowMalformed: true));
    }
    return (keyword, utf8.decode(textBytes, allowMalformed: true));
  }

  /// 在 IEND 之前插入一个文本块，返回新的 PNG 字节。
  ///
  /// tEXt 按规范只允许 Latin-1：能编成 Latin-1 就用 tEXt（SillyTavern 默认读取），
  /// 否则降级为 UTF-8 的 iTXt，避免中文直接抛异常。
  ///
  /// [replaceKeywords] 里的旧文本块会被**先剔除**再写入。
  /// 这一步是必须的：头像图片往往就是从别的角色卡 PNG 里扒出来的，
  /// 里面本来就带着一份旧的 chara/ccv3 数据。读取方（SillyTavern 等）取的是
  /// **第一个**命中的块，只追加不剔除的话，导出的永远是导入时那份原始卡。
  static Uint8List embedText(
    Uint8List png,
    String keyword,
    String text, {
    Set<String>? replaceKeywords,
  }) {
    final payload = _textChunkData(keyword, text);
    final drop = <String>{
      for (final k in (replaceKeywords ?? <String>{keyword})) k.toLowerCase(),
    };
    final chunks = readChunks(png);
    final out = BytesBuilder(copy: false)..add(_signature);
    var inserted = false;

    for (final chunk in chunks) {
      if (drop.isNotEmpty &&
          _isTextChunk(chunk.type) &&
          drop.contains((_keywordOf(chunk) ?? '').toLowerCase())) {
        continue;
      }
      if (chunk.type == 'IEND' && !inserted) {
        out.add(_buildChunk(payload.$1, payload.$2));
        inserted = true;
      }
      out.add(_buildChunk(chunk.type, chunk.data));
    }
    if (!inserted) {
      out.add(_buildChunk(payload.$1, payload.$2));
    }
    return out.toBytes();
  }

  static bool _isTextChunk(String type) =>
      type == 'tEXt' || type == 'zTXt' || type == 'iTXt';

  /// 取文本块的 keyword（NUL 之前那段，按 Latin-1 解）
  static String? _keywordOf(PngChunk chunk) {
    if (!_isTextChunk(chunk.type)) return null;
    final split = chunk.data.indexOf(0);
    if (split <= 0) return null;
    return latin1.decode(chunk.data.sublist(0, split));
  }

  /// 返回 (块类型, 块数据)
  static (String, Uint8List) _textChunkData(String keyword, String text) {
    try {
      return (
        'tEXt',
        Uint8List.fromList(<int>[
          ...latin1.encode(keyword),
          0,
          ...latin1.encode(text),
        ]),
      );
    } on ArgumentError {
      // 含非 Latin-1 字符（如中文）→ iTXt：keyword\0 flag(0) method(0) lang\0 translated\0 text(utf8)
      return (
        'iTXt',
        Uint8List.fromList(<int>[
          ...latin1.encode(keyword),
          0,
          0,
          0,
          0,
          0,
          ...utf8.encode(text),
        ]),
      );
    }
  }

  static Uint8List _buildChunk(String type, Uint8List data) {
    final typeBytes = ascii.encode(type);
    final crcInput = Uint8List.fromList(<int>[...typeBytes, ...data]);
    final crc = Crc32.compute(crcInput);
    final header = ByteData(4)..setUint32(0, data.length);
    final footer = ByteData(4)..setUint32(0, crc);
    return Uint8List.fromList(<int>[
      ...header.buffer.asUint8List(),
      ...typeBytes,
      ...data,
      ...footer.buffer.asUint8List(),
    ]);
  }
}

class Crc32 {
  static final List<int> _table = _buildTable();

  static List<int> _buildTable() {
    final table = List<int>.filled(256, 0);
    for (var n = 0; n < 256; n++) {
      var c = n;
      for (var k = 0; k < 8; k++) {
        c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
      }
      table[n] = c;
    }
    return table;
  }

  static int compute(Uint8List data) {
    var crc = 0xFFFFFFFF;
    for (final byte in data) {
      crc = _table[(crc ^ byte) & 0xFF] ^ (crc >> 8);
    }
    return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
  }
}
