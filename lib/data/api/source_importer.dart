import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/errors.dart';
import '../../core/logger.dart';
import '../models/vod_source.dart';

/// JSON 源列表导入工具。
///
/// 兼容 cms-player/vod-source 官方格式（`[{name, api, note}]`），
/// 也兼容单个对象、以及带 `sources` 包装的格式。
class SourceImporter {
  SourceImporter._();

  static Future<String> fetchText(String url) async {
    final Uri? uri = Uri.tryParse(url.trim());
    if (uri == null || !uri.hasScheme) {
      throw const VodException('URL 无效');
    }
    try {
      final http.Response resp =
          await http.get(uri).timeout(const Duration(seconds: 25));
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw VodException('HTTP ${resp.statusCode}', url: url);
      }
      return utf8.decode(resp.bodyBytes, allowMalformed: true);
    } on VodException {
      rethrow;
    } on Object catch (e) {
      throw VodException('下载失败：$e', url: url, cause: e);
    }
  }

  /// 解析一段 JSON 文本，返回待导入的源列表。
  static List<VodSource> parse(String text) {
    final String raw = _stripBom(text).trim();
    if (raw.isEmpty) throw const VodException('内容为空');

    Object? data;
    try {
      data = _decodeLenient(raw);
    } on Object catch (e) {
      throw VodException('不是合法的 JSON', cause: e);
    }

    final List<Map<String, dynamic>> entries = <Map<String, dynamic>>[];

    if (data is List) {
      entries.addAll(data.whereType<Map>().map((Map e) => e.cast<String, dynamic>()));
    } else if (data is Map) {
      final Map<String, dynamic> map = data.cast<String, dynamic>();
      final Object? nested = map['sources'] ?? map['list'] ?? map['data'];
      if (nested is List) {
        entries.addAll(
          nested.whereType<Map>().map((Map e) => e.cast<String, dynamic>()),
        );
      } else {
        // 单个源对象。
        entries.add(map);
      }
    } else {
      throw const VodException('JSON 顶层应为数组或对象');
    }

    final List<VodSource> result = <VodSource>[];
    final Set<String> seen = <String>{};
    int sort = 0;
    for (final Map<String, dynamic> entry in entries) {
      if (entry['api'] == null && entry['url'] == null) continue;
      if (entry['api'] == null) {
        entry['api'] = entry['url'];
      }
      try {
        final VodSource source = VodSource.fromRaw(entry, sort: sort++);
        if (!source.isUsable) continue;
        if (!seen.add(source.id)) continue;
        result.add(source);
      } on Object catch (e) {
        AppLog.d('SourceImporter', 'skip entry: $e');
      }
    }

    if (result.isEmpty) {
      throw const VodException('没有解析到任何有效资源站（检查 JSON 是否包含 name / api）');
    }
    return result;
  }

  static String _stripBom(String text) {
    if (text.isEmpty) return text;
    return text.startsWith('﻿') ? text.substring(1) : text;
  }

  /// 按标准 JSON 解析，失败时清洗一遍再试。
  ///
  /// 官方源列表 `cms-player/vod-source/source.json` 自己就带尾逗号：
  /// ```json
  /// { "name": "黑木耳", "api": "https://…/", },
  /// ```
  /// 标准 `jsonDecode` 会抛 `Illegal trailing comma`，让"从 URL 导入"必挂。
  /// 先严格试一次，能过就说明格式本来就干净；不行才清洗，
  /// 这样真正的语法错误仍然会原样暴露给用户。
  static Object? _decodeLenient(String text) {
    try {
      return jsonDecode(text);
    } on FormatException {
      return jsonDecode(_stripJsonNoise(text));
    }
  }

  /// 去掉 JSON 里的尾逗号与注释；字符串字节内的一切原样保留。
  static String _stripJsonNoise(String text) {
    final StringBuffer out = StringBuffer();
    bool inString = false;
    bool escaped = false;

    for (int i = 0; i < text.length; i++) {
      final String ch = text[i];

      if (inString) {
        out.write(ch);
        if (escaped) {
          escaped = false;
        } else if (ch == r'\') {
          escaped = true;
        } else if (ch == '"') {
          inString = false;
        }
        continue;
      }

      if (ch == '"') {
        inString = true;
        out.write(ch);
        continue;
      }

      // 块注释 /* ... */
      if (ch == '/' && i + 1 < text.length && text[i + 1] == '*') {
        final int end = text.indexOf('*/', i + 2);
        i = end < 0 ? text.length - 1 : end + 1;
        continue;
      }

      // 行注释 // ...
      if (ch == '/' && i + 1 < text.length && text[i + 1] == '/') {
        int j = i + 1;
        while (j < text.length && text[j] != '\n' && text[j] != '\r') {
          j++;
        }
        i = j;
        continue;
      }

      // 尾逗号：逗号后第一个非空白字符是 } 或 ] 时丢弃该逗号。
      if (ch == ',') {
        int j = i + 1;
        while (j < text.length && _isJsonSpace(text[j])) {
          j++;
        }
        if (j < text.length && (text[j] == '}' || text[j] == ']')) {
          continue;
        }
      }

      out.write(ch);
    }
    return out.toString();
  }

  static bool _isJsonSpace(String ch) =>
      ch == ' ' || ch == '\t' || ch == '\r' || ch == '\n';

  /// 导出为官方兼容格式。
  static String export(List<VodSource> sources) {
    final List<Map<String, Object?>> list = sources
        .map((VodSource s) => <String, Object?>{
              'name': s.name,
              'api': s.api,
              if (s.note.isNotEmpty) 'note': s.note,
              if (s.parseApi.isNotEmpty) 'parseApi': s.parseApi,
              if (s.referer.isNotEmpty) 'referer': s.referer,
              if (s.userAgent.isNotEmpty) 'userAgent': s.userAgent,
              'enabled': s.enabled,
            })
        .toList();
    return const JsonEncoder.withIndent('  ').convert(list);
  }
}
