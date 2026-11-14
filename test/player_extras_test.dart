import 'dart:convert';

import 'package:charset/charset.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';

import 'package:cms_player/core/storage/settings_store.dart';
import 'package:cms_player/core/storage/show_marks_store.dart';
import 'package:cms_player/data/models/play_line.dart';
import 'package:cms_player/data/models/play_task.dart';
import 'package:cms_player/data/models/vod_item.dart';
import 'package:cms_player/state/app_state.dart';
import 'package:cms_player/state/history_store.dart';
import 'package:cms_player/state/source_store.dart';
import 'package:cms_player/ui/player/player_controller.dart';
import 'package:cms_player/ui/player/player_window.dart';

import 'helpers/fake_player.dart';
import 'helpers/fakes.dart';

/// 第一梯队新增能力：按片名记片头片尾、外挂字幕、迷你悬浮窗。
void main() {
  useIsolatedStores();

  late FakePlayerRig rig;
  late PlayerController controller;

  VodItem item({String name = '测试影片'}) => VodItem(
        id: 7,
        name: name,
        playLines: <PlayLine>[
          const PlayLine(
            name: 'm3u8',
            episodes: <PlayEpisode>[
              PlayEpisode(name: '第01集', url: 'https://a.com/1.m3u8'),
              PlayEpisode(name: '第02集', url: 'https://a.com/2.m3u8'),
            ],
          ),
        ],
      );

  Future<PlayerController> mount({
    String name = '测试影片',
    String host = 'a.com',
    bool rememberMarks = true,
  }) async {
    rig = FakePlayerRig();
    PlayerController.environment = rig.environment;

    final SettingsStore settings = SettingsStore();
    await settings.init();
    await settings.setRememberSkipMarks(rememberMarks);

    final AppState app = AppState(settings);
    final HistoryStore history = HistoryStore();
    await history.load();
    final SourceStore sources = SourceStore(settings);
    final PlayTask task = PlayTask(
      source: sourceOf('测试站', host: host),
      item: item(name: name),
      lineIndex: 0,
      episodeIndex: 0,
    );
    controller = PlayerController(
      task: task,
      app: app,
      history: history,
      sources: sources,
    );
    addTearDown(() async {
      controller.dispose();
      // dispose 里的播放记录是 fire-and-forget 写盘，等它落完再让外层删临时目录，
      // 否则 Windows 上偶发「目录不是空的」。
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    await rig.settle();
    return controller;
  }

  group('片名级片头片尾', () {
    test('片名归一化忽略大小写、空格与括号内容', () {
      expect(ShowMarksStore.keyOf(' 庆余年（2019） '), '庆余年');
      expect(ShowMarksStore.keyOf('The Boys'), 'theboys');
      expect(ShowMarksStore.keyOf('庆余年 第二季'), '庆余年第二季');
    });

    test('保存时合并字段，两个都为 0 时删除条目', () async {
      await ShowMarksStore.instance.save('庆余年（2019）', introMs: 90000);
      expect(ShowMarksStore.instance.find('庆余年')?.introMs, 90000);

      await ShowMarksStore.instance.save('庆余年', outroMs: 2400000);
      final ShowSkipMarks? merged = ShowMarksStore.instance.find('庆余年');
      expect(merged?.introMs, 90000, reason: '没传的字段应当保留');
      expect(merged?.outroMs, 2400000);

      await ShowMarksStore.instance.clear('庆余年');
      expect(ShowMarksStore.instance.find('庆余年'), isNull);
    });

    test('重新加载后标记仍在（换进程也认）', () async {
      await ShowMarksStore.instance.save('The Boys', introMs: 60000);
      ShowMarksStore.instance.resetForTest();
      await ShowMarksStore.instance.ensureLoaded();

      expect(ShowMarksStore.instance.find('the boys')?.introMs, 60000);
    });

    test('同片换源也能读到标记', () async {
      ShowMarksStore.instance.seedForTest(
        '测试影片',
        introMs: 90000,
        outroMs: 2400000,
      );
      final PlayerController c = await mount(host: 'other.com');

      expect(c.introMs, 90000);
      expect(c.outroMs, 2400000);
    });

    test('标记片头会写进片名存储，清除时一并删掉', () async {
      final PlayerController c = await mount();

      await c.markIntroAt(const Duration(seconds: 75));
      await rig.settle();
      expect(ShowMarksStore.instance.find('测试影片')?.introMs, 75000);

      await c.clearSkipMarks();
      await rig.settle();
      expect(ShowMarksStore.instance.find('测试影片'), isNull);
    });

    test('关掉「按片名记住」后不再写片名存储', () async {
      final PlayerController c = await mount(rememberMarks: false);

      await c.markIntroAt(const Duration(seconds: 75));
      await rig.settle();

      expect(ShowMarksStore.instance.find('测试影片'), isNull);
      // 播放记录里仍然有，功能本身不该被一起砍掉。
      expect(c.introMs, 75000);
    });
  });

  group('外挂字幕', () {
    test('内嵌轨剔除 auto / no，并按标题命名', () async {
      await mount();
      rig.platform.emitTracks(const Tracks(
        subtitle: <SubtitleTrack>[
          SubtitleTrack('auto', null, null),
          SubtitleTrack('no', null, null),
          SubtitleTrack('1', '简体中文', 'chi'),
        ],
      ));
      await rig.settle();

      expect(controller.subtitleTracks, hasLength(1));
      expect(controller.subtitleTracks.single.label, '简体中文');
      expect(controller.subtitleId, 'no');
    });

    test('切换内嵌轨与关闭', () async {
      await mount();
      rig.platform.emitTracks(const Tracks(
        subtitle: <SubtitleTrack>[
          SubtitleTrack('auto', null, null),
          SubtitleTrack('no', null, null),
          SubtitleTrack('3', 'English', 'eng'),
        ],
      ));
      await rig.settle();

      await controller.selectSubtitleTrack('sub:3');
      expect(controller.subtitleId, 'sub:3');
      expect(controller.subtitleActive, isTrue);
      expect(rig.platform.subtitleTracks.last.id, '3');

      await controller.selectSubtitleTrack('no');
      expect(controller.subtitleId, 'no');
      expect(rig.platform.subtitleTracks.last.id, 'no');
    });

    test('从链接加载外挂字幕，切集后自动重新挂上', () async {
      final PlayerController c = await mount();
      rig.fetchSubtitleBytes = (Uri uri) async => utf8.encode(
            '1\n00:00:01,000 --> 00:00:02,000\n你好\n',
          );

      final bool ok = await c.loadSubtitleUrl('https://a.com/sub.srt');
      expect(ok, isTrue);
      expect(c.subtitleId, 'ext');
      expect(c.subtitleTracks.single.external, isTrue);
      expect(c.subtitleTracks.single.label, 'sub.srt');
      expect(rig.platform.subtitleTracks.last.data, isTrue);

      await c.next();
      await rig.settle();

      // open 之后应当再挂一次外挂轨。
      expect(
        rig.platform.subtitleTracks.where((SubtitleTrack t) => t.data).length,
        2,
      );
    });

    test('GBK 编码的 SRT 也能解码', () async {
      final PlayerController c = await mount();
      final Encoding gbk = Charset.getByName('gbk')!;
      rig.readSubtitleFile = (String path) async => gbk.encode(
            '1\n00:00:01,000 --> 00:00:02,000\n中文字幕\n',
          );

      final bool ok = await c.loadSubtitlePath(r'D:\字幕\第一集.srt');
      expect(ok, isTrue);
      expect(c.subtitleTracks.single.label, '第一集.srt');
    });

    test('不是字幕文本时拒收并给出提示', () async {
      final PlayerController c = await mount();
      rig.fetchSubtitleBytes = (Uri uri) async => utf8.encode('hello world');

      final bool ok = await c.loadSubtitleUrl('https://a.com/x.txt');
      expect(ok, isFalse);
      expect(c.subtitleId, 'no');
      expect(c.fallbackNotice, contains('不是可识别的字幕'));
    });

    test('链接缺协议时直接拒绝，不发请求', () async {
      final PlayerController c = await mount();
      final bool ok = await c.loadSubtitleUrl('sub.srt');
      expect(ok, isFalse);
      expect(c.fallbackNotice, contains('链接不完整'));
    });
  });

  group('迷你窗', () {
    test('toggleMini 切换状态并回调平台层', () async {
      PlayerWindow.resetForTest();
      final List<bool> calls = <bool>[];
      PlayerWindow.setMiniForTest = (bool v) async => calls.add(v);

      expect(await PlayerWindow.toggleMini(), isTrue);
      expect(PlayerWindow.miniActive, isTrue);
      expect(await PlayerWindow.toggleMini(), isFalse);
      expect(PlayerWindow.miniActive, isFalse);
      expect(calls, <bool>[true, false]);

      PlayerWindow.resetForTest();
    });
  });
}
