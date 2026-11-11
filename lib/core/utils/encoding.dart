import 'dart:convert';

import 'package:charset/charset.dart';

/// 接口响应的字符编码解码。
///
/// `http` 包只认 `dart:convert` 里的编码（UTF-8 / Latin-1 / ASCII）。
/// 老资源站返回 GBK / GB2312 时，`response.body` 会在解码阶段直接抛
/// `FormatException`，最终表现为「接口加载失败」，而内容其实完全正常。
///
/// 这里改成自己按字节解码，并按下面的优先级挑编码：
///
///  1. 源里显式配置的字符集（`VodSource.charset`）—— 用户最清楚自己的站；
///  2. 响应头 `Content-Type` 里声明的 charset —— 服务端自己说的最可信；
///  3. 严格 UTF-8 —— 绝大多数站点是这个，能过就是它，不做猜测；
///  4. GBK / GB2312 兜底 —— 老站基本都在这个范围里。
///
/// 第 3 步用「严格」模式（非法字节直接抛异常）而不是事后检查替换字符：
/// GBK 的中文序列几乎不可能恰好是合法 UTF-8，而 UTF-8 序列被 GBK 解出来
/// 往往也不报错，只是变成乱码 —— 严格模式能把这两者区分开。
class ResponseDecoder {
  ResponseDecoder._();

  /// 可选字符集列表，供源编辑页展示。
  ///
  /// 只列实际支持的几个，不做完整列表 —— 用户不需要知道自己能填
  /// 「euc-jp」这种对 macCMS 站点没意义的值。
  static const List<String> supportedCharsets = <String>[
    'utf-8',
    'gbk',
    'gb2312',
    'big5',
  ];

  /// 从 `Content-Type` 里抠出 charset。
  ///
  /// 形如 `application/json; charset=GBK`，也兼容 `charset="utf-8"`。
  static String? charsetOf(String? contentType) {
    if (contentType == null) return null;
    final RegExpMatch? match = RegExp(
      r'charset\s*=\s*"?\s*([A-Za-z0-9_\-]+)',
      caseSensitive: false,
    ).firstMatch(contentType);
    return match?.group(1);
  }

  /// 解码接口响应。
  ///
  /// [preferredCharset] 是源里配置的字符集，[contentType] 是响应头原值。
  /// 两者都为空时按 UTF-8 → GBK 的顺序探测。
  static String decode(
    List<int> bytes, {
    String? preferredCharset,
    String? contentType,
  }) {
    if (bytes.isEmpty) return '';

    // 1) 源里显式配置的字符集优先。
    final String? explicit = normalizeCharset(preferredCharset);
    if (explicit != null) {
      final String? decoded = _decodeWith(bytes, explicit);
      if (decoded != null) return decoded;
    }

    // 2) 响应头声明的字符集。
    final String? fromHeader = normalizeCharset(charsetOf(contentType));
    if (fromHeader != null && fromHeader != explicit) {
      final String? decoded = _decodeWith(bytes, fromHeader);
      if (decoded != null) return decoded;
    }

    // 3) 严格 UTF-8：合法就直接用。
    try {
      return utf8.decode(bytes);
    } on FormatException {
      // 不是合法 UTF-8，继续往下兜底。
    }

    // 4) GBK / GB2312 兜底。
    final String? gbk = _decodeWith(bytes, 'gbk');
    if (gbk != null) return gbk;

    // 5) 兜底的兜底：允许坏字节，至少把能读的部分读出来，
    ///    总比直接抛异常让整个源不可用强。
    return utf8.decode(bytes, allowMalformed: true);
  }

  /// 把用户填的 / 服务端声明的字符集名归一成 `charset` 包认识的名字。
  ///
  /// 返回 null 表示"没填或认不出来"。
  static String? normalizeCharset(String? raw) {
    if (raw == null) return null;
    final String name = raw.trim().toLowerCase();
    if (name.isEmpty) return null;
    switch (name) {
      case 'utf8':
      case 'utf-8':
        return 'utf-8';
      case 'gb2312':
      case 'gb_2312':
      case 'gb-2312':
      case 'gbk':
        return 'gbk';
      case 'gb18030':
        return 'gb18030';
      case 'big5':
      case 'big-5':
        return 'big5';
      default:
        return null;
    }
  }

  /// 用指定字符集解码，失败返回 null。
  static String? _decodeWith(List<int> bytes, String charset) {
    try {
      if (charset == 'utf-8') return utf8.decode(bytes);
      final Encoding? encoding = Charset.getByName(charset);
      if (encoding == null) return null;
      return encoding.decode(bytes);
    } on Object {
      return null;
    }
  }
}
