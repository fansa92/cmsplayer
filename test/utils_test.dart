import 'package:flutter_test/flutter_test.dart';

import 'package:cms_player/core/utils/collections.dart';
import 'package:cms_player/core/utils/debouncer.dart';
import 'package:cms_player/core/utils/formatter.dart';
import 'package:cms_player/core/utils/text_utils.dart';

/// core/utils 的边界用例。
///
/// 这些函数被列表、详情页、播放器同时调用，参数来自外部接口，
/// 空值 / 负数 / 异常格式都得有确定行为，不能把异常抛到界面上。
void main() {
  group('时长格式化', () {
    test('不足一小时用 m:ss，超过一小时补上小时', () {
      expect(formatDuration(const Duration(seconds: 65)), '1:05');
      expect(formatDuration(const Duration(seconds: 5)), '0:05');
      expect(
        formatDuration(const Duration(hours: 1, minutes: 2, seconds: 3)),
        '1:02:03',
      );
      // 拖动进度条时可能拿到负的差值，按绝对值处理。
      expect(formatDuration(const Duration(seconds: -65)), '1:05');
      expect(formatDuration(Duration.zero), '0:00');
    });

    test('紧凑格式分钟补零，小时不补零', () {
      expect(formatDurationShort(const Duration(seconds: 65)), '01:05');
      expect(formatDurationShort(const Duration(seconds: 5)), '00:05');
      expect(
        formatDurationShort(const Duration(hours: 1, minutes: 2, seconds: 3)),
        '1:02:03',
      );
    });
  });

  group('播放量 / 字节数', () {
    test('万、亿的进位与小数位', () {
      expect(formatCount(9999), '9999');
      expect(formatCount(10000), '1.0万');
      expect(formatCount(12345), '1.2万');
      expect(formatCount(99999999), '10000.0万');
      expect(formatCount(100000000), '1.0亿');
      expect(formatCount(130000000), '1.3亿');
    });

    test('字节数按 1024 进位，精度随量级收紧', () {
      expect(formatBytes(0), '0 B');
      expect(formatBytes(-1), '0 B');
      expect(formatBytes(512), '512 B');
      expect(formatBytes(1024), '1.00 KB');
      expect(formatBytes(10 * 1024), '10.0 KB');
      expect(formatBytes(100 * 1024), '100 KB');
      expect(formatBytes(1024 * 1024), '1.00 MB');
      expect(formatBytes(1024 * 1024 * 1024), '1.00 GB');
    });
  });

  group('相对时间', () {
    final DateTime now = DateTime(2026, 3, 10, 12, 0);

    test('按分钟 / 小时 / 天逐级显示', () {
      expect(
        formatRelativeTime(now.subtract(const Duration(seconds: 59)), now: now),
        '刚刚',
      );
      expect(
        formatRelativeTime(now.subtract(const Duration(seconds: 60)), now: now),
        '1分钟前',
      );
      expect(
        formatRelativeTime(now.subtract(const Duration(minutes: 59)), now: now),
        '59分钟前',
      );
      expect(
        formatRelativeTime(now.subtract(const Duration(hours: 1)), now: now),
        '1小时前',
      );
      expect(
        formatRelativeTime(now.subtract(const Duration(hours: 23)), now: now),
        '23小时前',
      );
      expect(
        formatRelativeTime(now.subtract(const Duration(hours: 24)), now: now),
        '昨天',
      );
      expect(
        formatRelativeTime(now.subtract(const Duration(days: 3)), now: now),
        '3天前',
      );
    });

    test('超过 30 天回落到绝对日期', () {
      final DateTime old = DateTime(2024, 1, 2, 8, 30);
      expect(formatRelativeTime(old, now: now), '2024-01-02');
    });

    // 时钟被用户调过、或两端设备时间不一致时会出现"未来"的时间戳，
    // 不能显示成负数分钟。
    test('未来时间不出现负数文案', () {
      expect(
        formatRelativeTime(now.add(const Duration(hours: 2)), now: now),
        '刚刚',
      );
    });
  });

  group('数值保护', () {
    test('safeRatio 防除零、防 NaN、并夹在 0..1', () {
      expect(safeRatio(50, 0), 0);
      expect(safeRatio(50, -1), 0);
      expect(safeRatio(50, 100), 0.5);
      expect(safeRatio(500, 100), 1);
      expect(safeRatio(-5, 100), 0);
      expect(safeRatio(double.nan, 100), 0);
      expect(safeRatio(50, double.nan), 0);
    });

    test('clampDouble 保持边界包含', () {
      expect(clampDouble(-1, 0, 1), 0);
      expect(clampDouble(2, 0, 1), 1);
      expect(clampDouble(0.4, 0, 1), 0.4);
    });
  });

  group('接口字段清洗', () {
    test('strOf 处理 null / 数字 / 首尾空白', () {
      expect(strOf(null), '');
      expect(strOf(null, '兜底'), '兜底');
      expect(strOf('  庆余年  '), '庆余年');
      expect(strOf(12), '12');
      expect(strOf(true), 'true');
    });

    test('intOf 兼容字符串数字与小数字符串', () {
      expect(intOf(null), 0);
      expect(intOf(null, 7), 7);
      expect(intOf(12), 12);
      expect(intOf(2.6), 3);
      expect(intOf('12'), 12);
      expect(intOf(' 12 '), 12);
      expect(intOf('12.6'), 13);
      expect(intOf(''), 0);
      expect(intOf('不是数字', 9), 9);
    });

    test('decodeEntities 处理命名实体与数字实体', () {
      expect(decodeEntities('A&amp;B&lt;C&gt;'), 'A&B<C>');
      expect(decodeEntities('&ldquo;你好&rdquo;&mdash;&nbsp;完'), '“你好”— 完');
      expect(decodeEntities('&#x4E2D;&#25991;'), '中文');
      expect(decodeEntities('&quot;x&apos;y&#039;z&quot;'), '"x\'y\'z"');
      // 没有 & 时直接返回，不做无谓替换。
      expect(decodeEntities('普通文本'), '普通文本');
    });

    test('stripHtml 换行归一并去掉多余空行', () {
      expect(stripHtml(null), '');
      expect(stripHtml(''), '');
      expect(stripHtml('<p>简介<br/>第二行</p>'), '简介\n第二行');
      expect(stripHtml('一<br>二</p >三'), '一\n二\n三');
      expect(stripHtml('一<BR />二'), '一\n二');
      expect(stripHtml('a\n\n\n\nb'), 'a\n\nb');
      expect(stripHtml('<b>粗体</b>&nbsp;收尾'), '粗体 收尾');
    });

    test('hashId 稳定、互斥，且输出与历史数据完全一致', () {
      final String a = hashId('测试站|https://a.com/api.php/provide/vod/');
      final String b = hashId('测试站|https://a.com/api.php/provide/vod/');

      expect(a, b);
      expect(a, isNot(hashId('测试站2|https://a.com/api.php/provide/vod/')));
      // 只差一个中文字符也必须不同（不能简单地按 codeUnit 截断）。
      expect(hashId('庆余年'), isNot(hashId('庆余岁')));

      // FNV-1a 在 Dart 的有符号 64 位整数上算出来的值可能是负数，
      // 于是结果是「负号 + 16 位十六进制」共 17 个字符（源码注释写的
      // 16 位并不准）。这个字符串已经作为 VodSource.id 落进用户的
      // sources.json / 收藏 / 历史，改算法会让所有旧 key 失效，
      // 所以这里把当前输出钉死，防止有人"顺手修一下注释里的长度"。
      expect(a, '-78bbd4eafaaddfcb');
      expect(hashId('庆余年'), '-a0a0de2a0c597f4');
      expect(a.length, 17);
      expect(int.tryParse(a, radix: 16), isNotNull);
    });

    test('originOf 只保留 scheme://host[:port]', () {
      expect(
        originOf('https://example.com:8080/api/x?a=1#f'),
        'https://example.com:8080',
      );
      expect(originOf('http://example.com/a/b'), 'http://example.com');
      expect(originOf('不是网址'), '');
      expect(originOf(''), '');
    });

    test('resolveUrl 不改写绝对地址，也不吞掉相对地址', () {
      expect(resolveUrl(null), isNull);
      expect(resolveUrl('   '), isNull);
      expect(resolveUrl('rtsp://a.com/live', base: 'https://x.com/'),
          'rtsp://a.com/live');
      expect(resolveUrl('file:///C:/a.mp4', base: 'https://x.com/'),
          'file:///C:/a.mp4');
      // 协议相对地址在没有 base 时默认补 https。
      expect(resolveUrl('//cdn.a.com/x.m3u8'), 'https://cdn.a.com/x.m3u8');
      // 没有 base 的相对地址原样返回，交给调用方决定。
      expect(resolveUrl('vod/1.m3u8'), 'vod/1.m3u8');
      expect(
        resolveUrl('../vod/1.m3u8', base: 'https://site.com/api/list/'),
        'https://site.com/api/vod/1.m3u8',
      );
    });

    test('isDirectPlayable 认扩展名、忽略查询串与大小写', () {
      expect(isDirectPlayable('https://a.com/x.M3U8?t=1'), isTrue);
      expect(isDirectPlayable('https://a.com/x.mp4?t=1'), isTrue);
      expect(isDirectPlayable('https://a.com/x.mpd?t=1'), isTrue);
      expect(isDirectPlayable('https://a.com/x.m3u8?t=1'), isTrue);
      expect(isDirectPlayable('rtmp://a.com/live'), isTrue);
      expect(isDirectPlayable('rtsp://a.com/live'), isTrue);
      expect(isDirectPlayable('https://a.com/player/?url=abc'), isFalse);
      expect(isDirectPlayable(''), isFalse);
    });
  });

  group('集合小工具', () {
    test('firstWhereOrNull 找不到时返回 null 而不是抛异常', () {
      expect(<int>[1, 2, 3].firstWhereOrNull((int e) => e > 2), 3);
      expect(<int>[1, 2, 3].firstWhereOrNull((int e) => e > 9), isNull);
      expect(<int>[].firstWhereOrNull((int e) => true), isNull);
    });

    test('mapIndexed 给出从 0 开始的序号', () {
      expect(
        <String>['a', 'b', 'c']
            .mapIndexed((int i, String e) => '$i:$e')
            .toList(),
        <String>['0:a', '1:b', '2:c'],
      );
      expect(<int>[].mapIndexed((int i, int e) => i).toList(), isEmpty);
    });
  });

  group('防抖与节流', () {
    test('连续触发只执行最后一次回调', () async {
      final Debouncer debouncer = Debouncer(const Duration(milliseconds: 20));
      final List<int> calls = <int>[];
      debouncer.run(() {
        calls.add(1);
      });
      debouncer.run(() {
        calls.add(2);
      });
      debouncer.run(() {
        calls.add(3);
      });

      await Future<void>.delayed(const Duration(milliseconds: 90));

      expect(calls, <int>[3]);
      debouncer.dispose();
    });

    test('cancel 之后不再触发', () async {
      final Debouncer debouncer = Debouncer(const Duration(milliseconds: 20));
      int calls = 0;
      debouncer.run(() {
        calls++;
      });
      debouncer.cancel();

      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(calls, 0);
      debouncer.dispose();
    });

    test('节流窗口内只放行一次，reset 后重新放行', () {
      final Throttler throttler = Throttler(const Duration(minutes: 1));
      expect(throttler.shouldRun, isTrue);
      expect(throttler.shouldRun, isFalse);
      expect(throttler.shouldRun, isFalse);

      throttler.reset();
      expect(throttler.shouldRun, isTrue);
    });

    test('零间隔节流等价于每次都放行', () {
      final Throttler throttler = Throttler(Duration.zero);
      expect(throttler.shouldRun, isTrue);
      expect(throttler.shouldRun, isTrue);
    });
  });

  group('影片元信息格式化', () {
    test('doubleOf 容忍单位与脏字符', () {
      expect(doubleOf(null), 0);
      expect(doubleOf(''), 0);
      expect(doubleOf('8.5分'), 8.5);
      expect(doubleOf('8.5'), 8.5);
      expect(doubleOf(7), 7);
      expect(doubleOf('abc'), 0);
    });

    test('hitsOf 支持千分位与「万」', () {
      expect(hitsOf('12,345'), 12345);
      expect(hitsOf('1.2万'), 12000);
      expect(hitsOf(88), 88);
      expect(hitsOf('—'), 0);
    });

    test('formatHits 小于一万原样，超过换算成万', () {
      expect(formatHits(0), '');
      expect(formatHits(999), '999');
      expect(formatHits(10000), '1万');
      expect(formatHits(12345), '1.2万');
      expect(formatHits(1234000), '123万');
    });
  });
}
