import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cms_player/core/constants.dart';
import 'package:cms_player/data/models/play_line.dart';
import 'package:cms_player/ui/player/player_sheets.dart';

/// 播放器三个弹层 + codec 翻译表。弹层用的是普通 showModalBottomSheet，
/// widget 测试里能完整走一遍打开 → 选项 → 回调 → 关闭。
void main() {
  Widget host(Future<void> Function(BuildContext context) open) {
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (BuildContext context) => Center(
            child: ElevatedButton(
              onPressed: () => open(context),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> openSheet(
    WidgetTester tester,
    Future<void> Function(BuildContext context) fn,
  ) async {
    await tester.pumpWidget(host(fn));
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
  }

  List<PlayLine> lines() => <PlayLine>[
        PlayLine(
          name: 'm3u8',
          episodes: List<PlayEpisode>.generate(
            3,
            (int i) =>
                PlayEpisode(name: '第${i + 1}集', url: 'https://a/$i.m3u8'),
          ),
        ),
        const PlayLine(
          name: '备用',
          episodes: <PlayEpisode>[
            PlayEpisode(name: '正片', url: 'https://b/1.m3u8'),
          ],
        ),
      ];

  group('describeCodec', () {
    test('短名 / FourCC / 音频都能翻成人话', () {
      expect(describeCodec('h264'), 'H.264 / AVC（h264）');
      expect(describeCodec('avc1'), 'H.264 / AVC（avc1）');
      expect(describeCodec('hvc1'), 'H.265 / HEVC（hvc1）');
      expect(describeCodec('av01'), 'AV1（av01）');
      expect(describeCodec('vp09'), 'VP9（vp09）');
      expect(describeCodec('mp4a'), 'AAC（mp4a）');
      expect(describeCodec('pcm_s24le'), 'PCM (24-bit)（pcm_s24le）');
      expect(describeCodec('xvid'), 'MPEG-4 (Xvid)（xvid）');
    });

    test('大小写与空格归一化，但回显原始字符串', () {
      expect(describeCodec('  H264 '), 'H.264 / AVC（  H264 ）');
      expect(describeCodec('heaac'), 'HE-AAC（heaac）');
    });

    test('认不出就原样显示，空值与纯空白不显示', () {
      expect(describeCodec('some_future_codec'), 'some_future_codec');
      expect(describeCodec('HE-AAC'), 'HE-AAC', reason: '表里是 heaac，连字符写法不认');
      expect(describeCodec(''), '');
      expect(describeCodec(null), '');
      expect(describeCodec('   '), '');
    });
  });

  group('倍速弹层', () {
    testWidgets('列出全部档位、当前档打勾、选择后回调', (WidgetTester tester) async {
      final List<double> picked = <double>[];
      await openSheet(
        tester,
        (BuildContext context) => showRateSheet(
          context,
          current: 1.0,
          onPick: (double rate) async => picked.add(rate),
        ),
      );

      for (final double rate in K.playRates) {
        expect(find.text('${rate}x'), findsOneWidget);
      }
      // 当前档是 check，其它档都是 speed 图标。
      expect(find.byIcon(Icons.check), findsOneWidget);
      expect(find.byIcon(Icons.speed), findsNWidgets(K.playRates.length - 1));

      await tester.tap(find.text('1.5x'));
      await tester.pumpAndSettle();
      expect(picked, <double>[1.5]);
      expect(find.text('打开'), findsOneWidget, reason: '弹层已关闭');
    });

    testWidgets('点遮罩关闭时不触发回调', (WidgetTester tester) async {
      final List<double> picked = <double>[];
      await openSheet(
        tester,
        (BuildContext context) => showRateSheet(
          context,
          current: 2.0,
          onPick: (double rate) async => picked.add(rate),
        ),
      );

      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(picked, isEmpty);
    });
  });

  group('选集弹层', () {
    testWidgets('当前集带播放箭头，点集回调并关闭', (WidgetTester tester) async {
      final List<String> picked = <String>[];
      await openSheet(
        tester,
        (BuildContext context) => showEpisodeSheet(
          context,
          title: '庆余年',
          lines: lines(),
          lineIndex: 0,
          episodeIndex: 1,
          onPick: (int li, int ei) => picked.add('$li:$ei'),
        ),
      );

      expect(find.text('庆余年'), findsOneWidget);
      expect(find.text('第1集'), findsOneWidget);
      expect(find.text('正片'), findsNothing, reason: '只列当前线路的集');
      // 只有一个 ActionChip 带 avatar（当前播放的那一集）。
      final Finder chips = find.byType(ActionChip);
      expect(chips, findsNWidgets(3));
      final int withAvatar = tester.widgetList(chips).where((Widget w) {
        return (w as ActionChip).avatar != null;
      }).length;
      expect(withAvatar, 1);

      await tester.tap(find.text('第3集'));
      await tester.pumpAndSettle();
      expect(picked, <String>['0:2']);
    });

    testWidgets('切线路后列表跟着换，回调带新线路下标', (WidgetTester tester) async {
      final List<String> picked = <String>[];
      await openSheet(
        tester,
        (BuildContext context) => showEpisodeSheet(
          context,
          title: '庆余年',
          lines: lines(),
          lineIndex: 0,
          episodeIndex: 0,
          onPick: (int li, int ei) => picked.add('$li:$ei'),
        ),
      );

      await tester.tap(find.widgetWithText(ChoiceChip, '备用 (1)'));
      await tester.pumpAndSettle();
      expect(find.text('正片'), findsOneWidget);
      expect(find.text('第1集'), findsNothing);

      await tester.tap(find.text('正片'));
      await tester.pumpAndSettle();
      expect(picked, <String>['1:0']);
    });

    testWidgets('越界线路下标会被夹到最后一条', (WidgetTester tester) async {
      await openSheet(
        tester,
        (BuildContext context) => showEpisodeSheet(
          context,
          title: '庆余年',
          lines: lines(),
          lineIndex: 99,
          episodeIndex: 99,
          onPick: (_, __) {},
        ),
      );
      expect(find.byType(ChoiceChip), findsNWidgets(2));
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '备用 (1)'))
            .selected,
        isTrue,
      );
      expect(find.byType(ActionChip), findsOneWidget);
    });

    testWidgets('没有线路时直接返回，不弹层', (WidgetTester tester) async {
      await tester.pumpWidget(host((BuildContext context) => showEpisodeSheet(
            context,
            title: '空',
            lines: const <PlayLine>[],
            lineIndex: 0,
            episodeIndex: 0,
            onPick: (_, __) {},
          )));
      await tester.tap(find.text('打开'));
      await tester.pump();
      expect(find.byType(BottomSheet), findsNothing);
    });
  });

  group('视频信息弹层', () {
    testWidgets('全空时给一句说明而不是一堆「未知」', (WidgetTester tester) async {
      await openSheet(
        tester,
        (BuildContext context) => showInfoSheet(
          context,
          resolution: null,
          fps: null,
          videoCodec: null,
          videoDecoder: null,
          pixelFormat: null,
          audioCodec: null,
          audioChannels: null,
          audioSampleRate: null,
        ),
      );
      expect(find.text('视频信息'), findsOneWidget);
      expect(find.text('暂无可用的流信息'), findsOneWidget);
      expect(find.text('分辨率'), findsNothing);
    });

    testWidgets('字段格式化与 codec 翻译', (WidgetTester tester) async {
      await openSheet(
        tester,
        (BuildContext context) => showInfoSheet(
          context,
          resolution: '1920x1080',
          fps: '23.976',
          videoCodec: 'h264',
          videoDecoder: 'd3d11va',
          pixelFormat: 'yuv420p',
          audioCodec: 'aac',
          audioChannels: 'stereo',
          audioSampleRate: 48000,
        ),
      );

      for (final String label in <String>[
        '分辨率',
        '帧率',
        '视频编码',
        '解码器',
        '像素格式',
        '音频编码',
        '声道',
        '采样率',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.text('23.976 fps'), findsOneWidget);
      expect(find.text('48.0 kHz'), findsOneWidget);
      expect(find.text('H.264 / AVC（h264）'), findsOneWidget);
      expect(find.text('AAC（aac）'), findsOneWidget);
    });

    testWidgets('只给部分字段时其它行不出现', (WidgetTester tester) async {
      await openSheet(
        tester,
        (BuildContext context) => showInfoSheet(
          context,
          resolution: '720x480',
          fps: null,
          videoCodec: null,
          videoDecoder: null,
          pixelFormat: null,
          audioCodec: null,
          audioChannels: null,
          audioSampleRate: null,
        ),
      );
      expect(find.text('分辨率'), findsOneWidget);
      expect(find.text('帧率'), findsNothing);
      expect(find.text('采样率'), findsNothing);
      expect(find.text('暂无可用的流信息'), findsNothing);
    });
  });
}
