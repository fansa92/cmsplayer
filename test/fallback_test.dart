import 'package:flutter_test/flutter_test.dart';

import 'package:cms_player/data/models/play_task.dart';
import 'package:cms_player/data/models/vod_item.dart';
import 'package:cms_player/data/models/vod_source.dart';
import 'package:cms_player/data/repository/fallback_repository.dart';

void main() {
  group('降级候选（同源）', () {
    test('当前集的备用地址排在最前', () {
      final PlayTask task = _task(
        lines: <List<String>>[
          <String>[r'第01集$https://a.com/1.m3u8$https://b.com/1.m3u8'],
        ],
      );

      final List<UrlFallback> fallbacks = FallbackResolver.sameSource(task);

      expect(fallbacks.length, 1);
      expect(fallbacks.first.url, 'https://b.com/1.m3u8');
      expect(fallbacks.first.label, '备用地址');
    });

    test('单线路且无备用地址时没有降级候选', () {
      final PlayTask task = _task(
        lines: <List<String>>[
          <String>[r'第01集$https://a.com/1.m3u8'],
        ],
      );
      expect(FallbackResolver.sameSource(task), isEmpty);
    });

    test('同源其它线路里按集名找到同一集', () {
      final PlayTask task = _task(
        lines: <List<String>>[
          <String>[r'第01集$https://a.com/1.m3u8'],
          <String>[r'第01集$https://c.com/1.m3u8'],
        ],
      );

      final List<UrlFallback> fallbacks = FallbackResolver.sameSource(task);

      expect(fallbacks.length, 1);
      expect(fallbacks.first.url, 'https://c.com/1.m3u8');
      expect(fallbacks.first.label, contains('线路'));
    });

    test('集名对不上时不会按下标乱配', () {
      // 线路二的第一集叫「特别篇」，和当前集的「第01集」不是同一集。
      // 按下标对齐会把特别篇当成第 01 集播出去 —— 必须宁可不给候选。
      final PlayTask task = _task(
        lines: <List<String>>[
          <String>[r'第01集$https://a.com/1.m3u8'],
          <String>[r'特别篇$https://c.com/special.m3u8'],
        ],
      );

      expect(FallbackResolver.sameSource(task), isEmpty);
    });

    test('编号相同但集名格式不同也算同一集', () {
      final PlayTask task = _task(
        lines: <List<String>>[
          <String>[r'第01集$https://a.com/1.m3u8'],
          <String>[r'01$https://c.com/1.m3u8'],
        ],
      );

      final List<UrlFallback> fallbacks = FallbackResolver.sameSource(task);

      expect(fallbacks.length, 1);
      expect(fallbacks.first.url, 'https://c.com/1.m3u8');
    });

    test('其它线路的备用地址也会被收进候选', () {
      final PlayTask task = _task(
        lines: <List<String>>[
          <String>[r'第01集$https://a.com/1.m3u8'],
          <String>[r'第01集$https://c.com/1.m3u8$https://d.com/1.m3u8'],
        ],
      );

      final List<UrlFallback> fallbacks = FallbackResolver.sameSource(task);

      expect(fallbacks.length, 2);
      expect(fallbacks[0].url, 'https://c.com/1.m3u8');
      expect(fallbacks[1].url, 'https://d.com/1.m3u8');
    });

    test('当前线路本身不会被当成候选', () {
      final PlayTask task = _task(
        lines: <List<String>>[
          <String>[r'第01集$https://a.com/1.m3u8'],
          <String>[r'第02集$https://c.com/2.m3u8'],
        ],
        lineIndex: 1,
        episodeIndex: 0,
      );

      final List<UrlFallback> fallbacks = FallbackResolver.sameSource(task);

      // 线路一里没有「第02集」，所以没有候选；线路二自己被排除在外。
      expect(fallbacks, isEmpty);
    });

    test('越界的线路 / 集下标返回空，不抛异常', () {
      final List<List<String>> lines = <List<String>>[
        <String>[r'第01集$https://a.com/1.m3u8'],
      ];
      expect(
        FallbackResolver.sameSource(_task(lines: lines, lineIndex: 9)),
        isEmpty,
      );
      expect(
        FallbackResolver.sameSource(_task(lines: lines, episodeIndex: 9)),
        isEmpty,
      );
      expect(
        FallbackResolver.sameSource(_task(lines: lines, lineIndex: -1)),
        isEmpty,
      );
    });

    test('备用地址里的空白项被跳过，留下的地址不带首尾空格', () {
      final PlayTask task = _task(
        lines: <List<String>>[
          <String>[r'第01集$https://a.com/1.m3u8$   $  https://b.com/1.m3u8  '],
        ],
      );

      final List<UrlFallback> fallbacks = FallbackResolver.sameSource(task);

      expect(fallbacks.map((UrlFallback e) => e.url).toList(),
          <String>['https://b.com/1.m3u8']);
      expect(fallbacks.single.label, '备用地址');
    });

    test('顺序固定：本集备用地址 → 其它线路主地址 → 其它线路备用地址', () {
      final PlayTask task = _task(
        lines: <List<String>>[
          <String>[r'第01集$https://a.com/1.m3u8$https://a.com/bak.m3u8'],
          <String>[r'第01集$https://c.com/1.m3u8'],
          <String>[r'第01集$https://d.com/1.m3u8$https://e.com/1.m3u8'],
        ],
      );

      final List<UrlFallback> fallbacks = FallbackResolver.sameSource(task);

      expect(fallbacks.map((UrlFallback e) => e.url).toList(), <String>[
        'https://a.com/bak.m3u8',
        'https://c.com/1.m3u8',
        'https://d.com/1.m3u8',
        'https://e.com/1.m3u8',
      ]);
      expect(fallbacks[1].label, '线路「线路2」');
      expect(fallbacks[3].label, contains('备用地址'));
    });

    test('「第 1 话」与「第01集」按编号算同一集', () {
      final PlayTask task = _task(
        lines: <List<String>>[
          <String>[r'第 1 话$https://a.com/1.m3u8'],
          <String>[r'第01集$https://c.com/1.m3u8'],
        ],
      );

      final List<UrlFallback> fallbacks = FallbackResolver.sameSource(task);

      expect(fallbacks.single.url, 'https://c.com/1.m3u8');
    });

    test('集名里没有编号又对不上时不给候选', () {
      final PlayTask task = _task(
        lines: <List<String>>[
          <String>[r'正片$https://a.com/1.m3u8'],
          <String>[r'花絮$https://c.com/extra.m3u8'],
        ],
      );

      expect(FallbackResolver.sameSource(task), isEmpty);
    });
  });
}

/// 造一个带多线路的播放任务。
PlayTask _task({
  required List<List<String>> lines,
  int lineIndex = 0,
  int episodeIndex = 0,
}) {
  final String from = List<String>.generate(
    lines.length,
    (int i) => '线路${i + 1}',
  ).join(r'$$$');
  final String url =
      lines.map((List<String> line) => line.join('#')).join(r'$$$');

  return PlayTask(
    source: VodSource.fromRaw(<String, Object>{
      'name': '测试站',
      'api': 'https://a.com/api.php/provide/vod/',
    }),
    item: VodItem(id: 1, name: '测试影片', playFrom: from, playUrl: url),
    lineIndex: lineIndex,
    episodeIndex: episodeIndex,
  );
}
