/// 各种 macCMS 接口字段的解析与清洗工具。
library;

/// 任意类型转字符串，null / 数字安全。
String strOf(Object? value, [String fallback = '']) {
  if (value == null) return fallback;
  if (value is String) return value.trim();
  if (value is num) return value.toString();
  return value.toString().trim();
}

/// 任意类型转整数，解析失败返回 [fallback]。
int intOf(Object? value, [int fallback = 0]) {
  if (value == null) return fallback;
  if (value is int) return value;
  if (value is double) return value.round();
  if (value is num) return value.toInt();
  final String text = strOf(value);
  if (text.isEmpty) return fallback;
  return int.tryParse(text) ?? double.tryParse(text)?.round() ?? fallback;
}

/// 去掉 HTML 标签并解码实体，简介 / 演员字段会带 `<p>`、`<br>`。
String stripHtml(String? input) {
  if (input == null || input.isEmpty) return '';
  String text = input.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
  text = text.replaceAll(RegExp(r'</p\s*>', caseSensitive: false), '\n');
  text = text.replaceAll(RegExp(r'<[^>]*>'), '');
  text = decodeEntities(text);
  text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  return text.trim();
}

/// 解码 HTML 实体。只处理常见集合，避免引入额外依赖。
String decodeEntities(String input) {
  if (!input.contains('&')) return input;
  return input
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#039;', "'")
      .replaceAll('&apos;', "'")
      .replaceAll('&ldquo;', '“')
      .replaceAll('&rdquo;', '”')
      .replaceAll('&mdash;', '—')
      .replaceAllMapped(
        RegExp(r'&#x([0-9a-fA-F]+);'),
        (Match m) => String.fromCharCode(
          int.parse(m.group(1)!, radix: 16),
        ),
      )
      .replaceAllMapped(
        RegExp(r'&#(\d+);'),
        (Match m) => String.fromCharCode(int.parse(m.group(1)!)),
      );
}

/// 生成稳定 ID：同名同接口的源重复导入时不会产生重复项。
String hashId(String input) {
  // FNV-1a 64bit，转 16 位十六进制。
  int hash = 0xcbf29ce484222325;
  const int prime = 0x100000001b3;
  final List<int> bytes = _utf8(input);
  for (final int b in bytes) {
    hash ^= b;
    hash = (hash * prime) & 0xFFFFFFFFFFFFFFFF;
  }
  return hash.toRadixString(16).padLeft(16, '0');
}

/// 最小 UTF-8 编码，避免为了一个 hash 再引依赖。
List<int> _utf8(String input) {
  final List<int> out = <int>[];
  for (final int rune in input.runes) {
    if (rune < 0x80) {
      out.add(rune);
    } else if (rune < 0x800) {
      out.add(0xC0 | (rune >> 6));
      out.add(0x80 | (rune & 0x3F));
    } else if (rune < 0x10000) {
      out.add(0xE0 | (rune >> 12));
      out.add(0x80 | ((rune >> 6) & 0x3F));
      out.add(0x80 | (rune & 0x3F));
    } else {
      out.add(0xF0 | (rune >> 18));
      out.add(0x80 | ((rune >> 12) & 0x3F));
      out.add(0x80 | ((rune >> 6) & 0x3F));
      out.add(0x80 | (rune & 0x3F));
    }
  }
  return out;
}

/// 从接口地址推导站点源站（scheme://host[:port]），用于 Referer。
String originOf(String api) {
  final Uri? uri = Uri.tryParse(api.trim());
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) return '';
  return uri.replace(path: '', query: null, fragment: null).toString();
}

/// 把可能缺少协议头的地址补全为绝对地址。
String? resolveUrl(String? raw, {String? base}) {
  final String text = strOf(raw);
  if (text.isEmpty) return null;
  if (text.startsWith('http://') ||
      text.startsWith('https://') ||
      text.startsWith('rtmp://') ||
      text.startsWith('rtsp://') ||
      text.startsWith('file://')) {
    return text;
  }
  if (text.startsWith('//')) {
    final Uri? baseUri = base == null ? null : Uri.tryParse(base);
    final String scheme = baseUri?.scheme.isEmpty ?? true ? 'https' : baseUri!.scheme;
    return '$scheme:$text';
  }
  if (base == null || base.isEmpty) return text;
  final Uri? baseUri = Uri.tryParse(base);
  if (baseUri == null) return text;
  try {
    return baseUri.resolve(text).toString();
  } on Object {
    return text;
  }
}

/// 判断一个播放地址能否被 libmpv 直接打开。
/// 不能直接打开的（多为站点私有播放页）需要走"解析接口"。
bool isDirectPlayable(String url) {
  final String lower = url.toLowerCase().split('?').first;
  if (lower.endsWith('.m3u8') ||
      lower.endsWith('.mp4') ||
      lower.endsWith('.mkv') ||
      lower.endsWith('.flv') ||
      lower.endsWith('.avi') ||
      lower.endsWith('.mov') ||
      lower.endsWith('.wmv') ||
      lower.endsWith('.ts') ||
      lower.endsWith('.webm') ||
      lower.endsWith('.m4v') ||
      lower.endsWith('.rmvb') ||
      lower.endsWith('.mpd')) {
    return true;
  }
  if (url.contains('.m3u8') || url.contains('.mpd')) return true;
  return url.startsWith('rtmp://') || url.startsWith('rtsp://');
}
