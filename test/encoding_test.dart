import 'dart:convert';

import 'package:charset/charset.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cms_player/core/utils/encoding.dart';

void main() {
  group('ResponseDecoder.charsetOf', () {
    test('从 Content-Type 里抠出 charset', () {
      expect(
        ResponseDecoder.charsetOf('application/json; charset=GBK'),
        'GBK',
      );
      expect(
        ResponseDecoder.charsetOf('text/html;charset="utf-8"'),
        'utf-8',
      );
      expect(ResponseDecoder.charsetOf('application/json'), isNull);
      expect(ResponseDecoder.charsetOf(null), isNull);
    });
  });

  group('ResponseDecoder.normalizeCharset', () {
    test('把常见别名归一', () {
      expect(ResponseDecoder.normalizeCharset('GB2312'), 'gbk');
      expect(ResponseDecoder.normalizeCharset('gb_2312'), 'gbk');
      expect(ResponseDecoder.normalizeCharset('utf8'), 'utf-8');
      expect(ResponseDecoder.normalizeCharset('  '), isNull);
      expect(ResponseDecoder.normalizeCharset(null), isNull);
      // 认不出来的名字返回 null，而不是原样透传。
      expect(ResponseDecoder.normalizeCharset('euc-jp'), isNull);
    });
  });

  group('ResponseDecoder.decode', () {
    test('UTF-8 响应原样解码', () {
      final String raw = '{"name":"庆余年"}';
      final List<int> bytes = utf8.encode(raw);
      expect(
        ResponseDecoder.decode(bytes, contentType: 'application/json'),
        raw,
      );
    });

    test('GBK 响应能正确解出中文', () {
      final String raw = '{"name":"庆余年第二季"}';
      final List<int> bytes = gbk.encode(raw);

      // 严格 UTF-8 解不开这段字节：说明确实需要 GBK 兜底。
      expect(() => utf8.decode(bytes), throwsFormatException);

      expect(
        ResponseDecoder.decode(bytes, contentType: 'application/json'),
        raw,
      );
    });

    test('源里显式配置的字符集优先于响应头', () {
      final String raw = '{"name":"庆余年"}';
      final List<int> bytes = gbk.encode(raw);

      // 响应头说 utf-8（服务端自己标错了），但源里显式配了 gbk —— 听源的。
      expect(
        ResponseDecoder.decode(
          bytes,
          preferredCharset: 'gbk',
          contentType: 'application/json; charset=utf-8',
        ),
        raw,
      );
    });

    test('响应头声明的 charset 生效', () {
      final String raw = '{"name":"庆余年"}';
      final List<int> bytes = gbk.encode(raw);

      expect(
        ResponseDecoder.decode(
          bytes,
          contentType: 'application/json; charset=GB2312',
        ),
        raw,
      );
    });

    test('坏字节不会让整个响应报废', () {
      // 合法 UTF-8 后面接一段非法字节。
      final List<int> bytes = <int>[
        ...utf8.encode('{"a":"'),
        0xC3, 0x28, // 非法 UTF-8 序列
        ...utf8.encode('"}'),
      ];
      final String decoded = ResponseDecoder.decode(bytes);
      expect(decoded.contains('{"a":"'), isTrue);
      expect(decoded.contains('"}'), isTrue);
    });

    test('空响应返回空串', () {
      expect(ResponseDecoder.decode(const <int>[]), '');
    });
  });
}
