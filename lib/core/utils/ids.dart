import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// UUID v7：前缀为时间戳，插入时 B-Tree 局部性好，避免随机主键造成的页分裂。
String newId() => _uuid.v7();
