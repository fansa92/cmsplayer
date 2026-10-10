import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../logger.dart';
import 'app_dirs.dart';

/// 基于单个 JSON 文件的极简列表存储。
///
/// 之所以不用 Hive / Isar / sqflite：
///  * 零代码生成，`flutter create .` 之后即可直接构建；
///  * 数据量很小（源、收藏、历史各几百条），整文件读写完全够用；
///  * 五端行为完全一致，不依赖任何平台通道。
class JsonStore {
  JsonStore._();

  static Future<File> _file(String name) async {
    final dir = AppDirs.isReady ? AppDirs.data : AppDirs.fallback;
    return File(p.join(dir.path, name));
  }

  static Future<List<Map<String, dynamic>>> readList(String name) async {
    try {
      final File file = await _file(name);
      if (!await file.exists()) return <Map<String, dynamic>>[];
      final String text = await file.readAsString();
      if (text.trim().isEmpty) return <Map<String, dynamic>>[];
      final Object? decoded = jsonDecode(text);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((Map e) => e.cast<String, dynamic>())
            .toList();
      }
      return <Map<String, dynamic>>[];
    } on Object catch (e, s) {
      AppLog.e('JsonStore', 'read $name failed: $e', s);
      return <Map<String, dynamic>>[];
    }
  }

  static Future<void> writeList(
    String name,
    List<Map<String, dynamic>> items,
  ) async {
    try {
      final File file = await _file(name);
      final String text =
          const JsonEncoder.withIndent('  ').convert(items);
      await file.writeAsString(text, flush: true);
    } on Object catch (e, s) {
      AppLog.e('JsonStore', 'write $name failed: $e', s);
    }
  }

  static Future<void> deleteFile(String name) async {
    try {
      final File file = await _file(name);
      if (await file.exists()) await file.delete();
    } on Object catch (e) {
      AppLog.e('JsonStore', 'delete $name failed: $e');
    }
  }
}
