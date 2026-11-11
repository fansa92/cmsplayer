import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';

import 'package:cms_player/core/constants.dart';
import 'package:cms_player/core/storage/settings_store.dart';
import 'package:cms_player/data/models/play_line.dart';
import 'package:cms_player/data/models/play_record.dart';
import 'package:cms_player/data/models/play_task.dart';
import 'package:cms_player/data/models/vod_item.dart';
import 'package:cms_player/data/models/vod_source.dart';
import 'package:cms_player/state/app_state.dart';
import 'package:cms_player/state/history_store.dart';
import 'package:cms_player/state/source_store.dart';
import 'package:cms_player/ui/player/player_controller.dart';

import 'helpers/fake_player.dart';
import 'helpers/fakes.dart';

/// 播放状态机本体（原先零覆盖的 841 行）：地址解析、流绑定、控制命令、
/// 手势累加、播放记录节流、续播、自动下一集。
///
/// 通过 [PlayerController.environment] 注入内存版 media_kit 内核与可控时钟，
/// 不加载 libmpv、不碰任何平台通道，也不依赖 widget 树。
void main() {
  useIsolatedStores();

  late FakePlayerRig rig;
  late PlayerController controller;
  late AppState app;
  late HistoryStore history;
  late SourceStore sources;
  late PlayTask task;

  int notifications = 0;
  int historyWrites = 0;

  VodSource source({String parseApi = '', String host = 'a.com'}) =>
      VodSource.fromRaw(<String, Object>{
        'name': '测试站',
        'api': 'https://$host/api.php/provide/vod/',
        if (parseApi.isNotEmpty) 'parseApi': parseApi,
      });

  VodItem item({
    List<PlayLine>? lines,
    String name = '测试影片',
  }) =>
      VodItem(
        id: 7,
        name: name,
        pic: 'https://a.com/p.jpg',
        typeName: '电视剧',
        playLines: lines ??
            <PlayLine>[
              const PlayLine(
                name: 'm3u8',
                episodes: <PlayEpisode>[
                  PlayEpisode(
                    name: '第01集',
                    url: 'https://a.com/1.m3u8',
                    mirrors: <String>['https://a.com/1b.m3u8'],
                  ),
                  PlayEpisode(
                    name: '第02集',
                    url: 'https://a.com/2.m3u8',
                  ),
                ],
              ),
              const PlayLine(
                name: '备用线路',
                episodes: <PlayEpisode>[
                  PlayEpisode(
                    name: '第01集',
                    url: 'https://a.com/alt1.m3u8',
                  ),
                ],
              ),
            ],
      );

  PlayRecord record({
    int lineIndex = 0,
    int episodeIndex = 0,
    int positionMs = 30000,
    int durationMs = 120000,
  }) =>
      PlayRecord(
        key: task.recordKey,
        sourceId: task.source.id,
        sourceName: task.source.name,
        vodId: '${task.item.id}',
        vodName: task.item.name,
        lineIndex: lineIndex,
        episodeIndex: episodeIndex,
        lineName: 'm3u8',
        episodeName: '第01集',
        positionMs: positionMs,
        durationMs: durationMs,
        updatedAt: DateTime(2026, 1, 1),
      );

  Future<void> mount({
    VodSource? src,
    VodItem? vod,
    bool autoNext = true,
    bool resume = true,
    double defaultRate = 1.0,
    List<PlayRecord> records = const <PlayRecord>[],
    List<VodSource> extraSources = const <VodSource>[],
  }) async {
    rig = FakePlayerRig();
    PlayerController.environment = rig.environment;

    final SettingsStore settings = SettingsStore();
    await settings.init();
    await settings.setAutoNextEpisode(autoNext);
    await settings.setResumePlayback(resume);
    await settings.setDefaultRate(defaultRate);

    app = AppState(settings);
    history = HistoryStore();
    sources = SourceStore(settings);
    task = PlayTask(
      source: src ?? source(),
      item: vod ?? item(),
      lineIndex: 0,
      episodeIndex: 0,
    );
    for (final PlayRecord r in records) {
      await history.upsert(r);
    }
    for (final VodSource s in extraSources) {
      await sources.add(s);
    }
    historyWrites = 0;
    history.addListener(() => historyWrites++);

    controller = PlayerController(
      task: task,
      app: app,
      history: history,
      sources: sources,
    );
    notifications = 0;
    controller.addListener(() => notifications++);
    await rig.settle();
  }

  tearDown(() async {
    controller.dispose();
    await rig.settle();
    PlayerController.resetEnvironmentForTest();
  });

  // ------------------------------------------------------------ 地址解析

  group('播放地址解析', () {
    test('直链原样返回，不套解析接口', () async {
      await mount(src: source(parseApi: 'https://jx.com/?url='));
      expect(controller.resolveRawUrl('https://cdn.com/v.m3u8'),
          'https://cdn.com/v.m3u8');
      expect(controller.resolveRawUrl('  https://cdn.com/a.mp4?x=1  '),
          'https://cdn.com/a.mp4?x=1');
    });

    test('相对地址按接口地址补全', () async {
      await mount();
      expect(
        controller.resolveRawUrl('/play/1.m3u8'),
        'https://a.com/play/1.m3u8',
      );
      expect(
        controller.resolveRawUrl('//cdn.com/1.m3u8'),
        'https://cdn.com/1.m3u8',
      );
    });

    test('非直链走解析接口：无占位符时拼在末尾并编码', () async {
      await mount(src: source(parseApi: 'https://jx.com/play/?url='));
      expect(
        controller.resolveRawUrl('https://v.com/page?id=1&t=2'),
        'https://jx.com/play/?url=https%3A%2F%2Fv.com%2Fpage%3Fid%3D1%26t%3D2',
      );
    });

    test('解析接口里的 {url} 占位符会被替换（可出现多次）', () async {
      await mount(
        src: source(parseApi: 'https://jx.com/?u={url}&back={url}'),
      );
      expect(
        controller.resolveRawUrl('https://v.com/page'),
        'https://jx.com/?u=https%3A%2F%2Fv.com%2Fpage'
        '&back=https%3A%2F%2Fv.com%2Fpage',
      );
    });

    test('没有解析接口时返回补全后的原始地址', () async {
      await mount();
      expect(
          controller.resolveRawUrl('https://v.com/page'), 'https://v.com/page');
    });

    test('空串与纯空白返回 null', () async {
      await mount();
      expect(controller.resolveRawUrl(''), isNull);
      expect(controller.resolveRawUrl('   \n '), isNull);
    });

    test('resolvePlayUrl 委托给 resolveRawUrl，并带上 HTTP 头开播', () async {
      await mount();
      expect(controller.resolvePlayUrl(task.episode!), 'https://a.com/1.m3u8');
      expect(rig.platform.opens, <String>['https://a.com/1.m3u8']);
      expect(rig.platform.rates, <double>[1.0]);
    });
  });

  // ------------------------------------------------------------ 流绑定

  group('流绑定与状态', () {
    test('position / duration / playing / buffering 同步到 getter', () async {
      await mount();
      await rig.emitProgress(
          const Duration(seconds: 120), const Duration(seconds: 30));
      rig.platform.emitPlaying(true);
      rig.platform.emitBuffering(true);
      await rig.settle();

      expect(controller.duration, const Duration(seconds: 120));
      expect(controller.rawPosition, const Duration(seconds: 30));
      expect(controller.position, const Duration(seconds: 30));
      expect(controller.playing, isTrue);
      expect(controller.buffering, isTrue);
      expect(controller.starting, isFalse, reason: 'playing 应清掉开播转圈');
      expect(notifications, greaterThan(0));
    });

    test('拿到时长也会清掉 starting', () async {
      await mount();
      // open 本身不清 starting（要等 playing / duration 流或兜底超时）。
      expect(controller.starting, isTrue);
      rig.platform.emitDuration(const Duration(seconds: 60));
      await rig.settle();
      expect(controller.starting, isFalse);

      // 切集后重新置 true，再被新的 duration 清掉。
      // 注意底层 duration 流带 distinct，必须换一个值才会推送事件。
      await controller.selectEpisode(0, 1);
      await rig.settle();
      expect(controller.starting, isTrue);
      rig.platform.emitDuration(const Duration(seconds: 61));
      await rig.settle();
      expect(controller.starting, isFalse);
    });

    test('20 秒兜底定时器强制收起转圈', () async {
      await mount();
      // 没有任何 playing / duration 事件，模拟网络卡死。
      expect(controller.starting, isTrue);
      rig.fireTimersOf(K.startupTimeout);
      await rig.settle();
      expect(controller.starting, isFalse);
    });

    test('positionRatio / seekRatio 在时长为 0 或越界时收敛', () async {
      await mount();
      expect(controller.positionRatio, 0);
      expect(controller.seekRatio, 0);

      await rig.emitProgress(
          const Duration(seconds: 100), const Duration(seconds: 25));
      await rig.settle();
      expect(controller.positionRatio, closeTo(0.25, 0.001));

      controller.startSeek();
      controller.updateSeek(const Duration(seconds: 500));
      expect(controller.seekRatio, 1.0);
      controller.cancelSeek();
    });

    test('rate / volume 流更新，seeking 时展示的是预览进度', () async {
      await mount();
      rig.platform.emitRate(1.5);
      rig.platform.emitVolume(77);
      await rig.emitProgress(
          const Duration(seconds: 100), const Duration(seconds: 10));
      await rig.settle();

      expect(controller.rate, 1.5);
      expect(controller.volume, 77);
      controller.startSeek();
      controller.updateSeek(const Duration(seconds: 20));
      expect(controller.position, const Duration(seconds: 30));
      expect(controller.rawPosition, const Duration(seconds: 10));
      controller.cancelSeek();
    });

    test('tracks 只取真实轨，跳过 auto / no 占位', () async {
      await mount();
      rig.platform.emitTracks(Tracks(
        video: <VideoTrack>[
          VideoTrack.auto(),
          VideoTrack.no(),
          const VideoTrack('1', 'h264', null,
              codec: 'h264', decoder: 'h264', fps: 23.976),
        ],
        audio: <AudioTrack>[
          AudioTrack.auto(),
          const AudioTrack('1', 'aac', null,
              codec: 'aac', channels: 'stereo', samplerate: 48000),
        ],
      ));
      rig.platform.emitWidth(1920);
      rig.platform.emitHeight(1080);
      rig.platform.emitVideoParams(const VideoParams(pixelformat: 'yuv420p'));
      await rig.settle();

      expect(controller.videoCodec, 'h264');
      expect(controller.videoDecoder, 'h264');
      expect(controller.pixelFormat, 'yuv420p');
      expect(controller.audioCodec, 'aac');
      expect(controller.audioChannels, 'stereo');
      expect(controller.audioSampleRate, 48000);
      expect(controller.resolutionLabel, '1920x1080');
      expect(controller.fpsLabel, '23.976');
    });

    test('fpsLabel 去掉无意义小数尾，audioParams 补缺字段', () async {
      await mount();
      rig.platform.emitTracks(const Tracks(
        video: <VideoTrack>[
          VideoTrack('1', null, null, codec: 'hevc', fps: 30.000),
        ],
      ));
      rig.platform.emitAudioParams(const AudioParams(
        hrChannels: '5.1',
        sampleRate: 44100,
      ));
      await rig.settle();
      expect(controller.fpsLabel, '30');
      expect(controller.resolutionLabel, isNull);
      expect(controller.audioChannels, '5.1');
      expect(controller.audioSampleRate, 44100);
    });

    test('切集会清掉上一集遗留的流信息', () async {
      await mount();
      rig.platform.emitWidth(1280);
      rig.platform.emitHeight(720);
      rig.platform.emitVideoParams(const VideoParams(pixelformat: 'nv12'));
      await rig.settle();
      expect(controller.resolutionLabel, '1280x720');

      await controller.selectEpisode(0, 1);
      await rig.settle();
      expect(controller.resolutionLabel, isNull);
      expect(controller.videoWidth, isNull);
      expect(controller.pixelFormat, isNull);
      expect(rig.platform.opens.last, 'https://a.com/2.m3u8');
    });
  });

  // ------------------------------------------------------------ 控制命令

  group('控制命令', () {
    test('togglePlay 转发给内核', () async {
      await mount();
      await controller.togglePlay();
      expect(rig.platform.playOrPauseCalls, 1);
    });

    test('seek 夹在 [0, duration]，时长未知时不发指令', () async {
      await mount();
      await controller.seek(const Duration(seconds: 10));
      expect(rig.platform.seeks, isEmpty);

      rig.platform.emitDuration(const Duration(seconds: 100));
      await rig.settle();
      await controller.seek(const Duration(seconds: 999));
      await controller.seek(const Duration(seconds: -5));
      expect(rig.platform.seeks, <Duration>[
        const Duration(seconds: 100),
        Duration.zero,
      ]);
    });

    test('seekBy 相对当前位置偏移', () async {
      await mount();
      await rig.emitProgress(
          const Duration(seconds: 100), const Duration(seconds: 20));
      await rig.settle();
      await controller.seekBy(const Duration(seconds: 10));
      expect(rig.platform.seeks, <Duration>[const Duration(seconds: 30)]);
    });

    test('setRate 立即更新并下发内核', () async {
      await mount(defaultRate: 1.25);
      expect(controller.rate, 1.25);
      expect(rig.platform.rates, <double>[1.25]);
      await controller.setRate(2.0);
      expect(controller.rate, 2.0);
      expect(rig.platform.rates, <double>[1.25, 2.0]);
    });

    test('cycleFit 三态循环且 fitLabel 同步', () async {
      await mount();
      expect(controller.fitLabel, '适应');
      expect(controller.fit, BoxFit.contain);
      await controller.cycleFit();
      expect(controller.fitLabel, '裁剪');
      expect(controller.fit, BoxFit.cover);
      await controller.cycleFit();
      expect(controller.fitLabel, '拉伸');
      expect(controller.fit, BoxFit.fill);
      await controller.cycleFit();
      expect(controller.fitLabel, '适应');
    });

    test('toggleLock 翻转锁定', () async {
      await mount();
      expect(controller.locked, isFalse);
      controller.toggleLock();
      expect(controller.locked, isTrue);
      controller.toggleLock();
      expect(controller.locked, isFalse);
    });

    test('next / previous / selectEpisode 越界时不切换', () async {
      await mount();
      await controller.previous();
      await controller.selectEpisode(9, 0);
      await controller.selectEpisode(0, 9);
      await controller.next(); // 0 -> 1
      await controller.next(); // 1 已是最后一集
      await rig.settle();
      expect(controller.task.episodeIndex, 1);
      expect(rig.platform.opens, <String>[
        'https://a.com/1.m3u8',
        'https://a.com/2.m3u8',
      ]);
    });

    test('selectEpisode 换线路时打开对应地址', () async {
      await mount();
      await controller.selectEpisode(1, 0);
      await rig.settle();
      expect(controller.task.lineIndex, 1);
      expect(controller.task.subtitle, '备用线路 · 第01集');
      expect(rig.platform.opens.last, 'https://a.com/alt1.m3u8');
    });

    test('没有可播放地址时直接给出错误，不调用 open', () async {
      rig = FakePlayerRig();
      PlayerController.environment = rig.environment;
      final SettingsStore settings = SettingsStore();
      await settings.init();
      controller = PlayerController(
        task: PlayTask(
          source: source(),
          item: item(lines: <PlayLine>[]),
          lineIndex: 0,
          episodeIndex: 0,
        ),
        app: AppState(settings),
        history: HistoryStore(),
        sources: SourceStore(settings),
      );
      await rig.settle();
      expect(controller.error, '没有可播放的地址');
      expect(controller.starting, isFalse);
      expect(rig.platform.opens, isEmpty);
    });
  });

  // ------------------------------------------------------------ 手势

  group('手势累加', () {
    test('updateSeek 在上一帧目标上累加并夹在时长内', () async {
      await mount();
      await rig.emitProgress(
          const Duration(seconds: 100), const Duration(seconds: 10));
      await rig.settle();

      controller.startSeek();
      expect(controller.seeking, isTrue);
      controller.updateSeek(const Duration(seconds: 5));
      controller.updateSeek(const Duration(seconds: 5));
      expect(controller.position, const Duration(seconds: 20));
      controller.updateSeek(const Duration(seconds: 500));
      expect(controller.position, const Duration(seconds: 100));
      controller.updateSeek(const Duration(seconds: -500));
      expect(controller.position, Duration.zero);
      controller.cancelSeek();
      expect(controller.seeking, isFalse);
    });

    test('commitSeek 下发目标并退出 seeking，cancelSeek 不下发', () async {
      await mount();
      rig.platform.emitDuration(const Duration(seconds: 100));
      await rig.settle();

      controller.startSeek();
      controller.updateSeek(const Duration(seconds: 42));
      controller.commitSeek();
      await rig.settle();
      expect(rig.platform.seeks, <Duration>[const Duration(seconds: 42)]);
      expect(controller.seeking, isFalse);

      controller.startSeek();
      controller.updateSeek(const Duration(seconds: 10));
      controller.cancelSeek();
      expect(rig.platform.seeks, hasLength(1));
    });

    test('时长未知时 updateSeek 不动，未开始手势时忽略', () async {
      await mount();
      controller.updateSeek(const Duration(seconds: 5));
      expect(controller.seeking, isFalse);
      controller.startSeek();
      controller.updateSeek(const Duration(seconds: 5));
      expect(controller.position, Duration.zero);
      controller.cancelSeek();
    });

    test('音量手势逐帧累加增量，不是只认最后一下', () async {
      await mount();
      await controller.startVerticalGesture(isVolume: true);
      expect(controller.adjustingVolume, isTrue);
      expect(controller.gestureVolume, closeTo(0.4, 0.001));

      await controller.updateVerticalGesture(0.1);
      await controller.updateVerticalGesture(0.1);
      await controller.updateVerticalGesture(0.1);
      expect(controller.gestureVolume, closeTo(0.7, 0.001));
      expect(rig.volumeWrites, <Matcher>[
        closeTo(0.5, 0.001),
        closeTo(0.6, 0.001),
        closeTo(0.7, 0.001),
      ]);

      await controller.updateVerticalGesture(5);
      expect(controller.gestureVolume, 1.0);
      await controller.updateVerticalGesture(-5);
      expect(controller.gestureVolume, 0.0);
      await controller.endVerticalGesture();
      expect(controller.adjustingVolume, isFalse);
    });

    test('亮度手势同样逐帧累加并夹在 0..1', () async {
      await mount();
      await controller.startVerticalGesture(isVolume: false);
      expect(controller.adjustingBrightness, isTrue);
      await controller.updateVerticalGesture(0.2);
      await controller.updateVerticalGesture(0.2);
      expect(controller.gestureBrightness, closeTo(1.0, 0.001));
      expect(rig.brightnessWrites, <Matcher>[
        closeTo(0.8, 0.001),
        closeTo(1.0, 0.001),
      ]);
      await controller.endVerticalGesture();
      expect(controller.adjustingBrightness, isFalse);
    });

    test('stepVolume 与手势共用系统音量读数', () async {
      await mount();
      await controller.startVerticalGesture(isVolume: true);
      expect(controller.systemVolume, closeTo(40, 0.001));
      await controller.endVerticalGesture();

      final double? result = await controller.stepVolume(10);
      expect(result, closeTo(50, 0.001));
      expect(controller.systemVolume, closeTo(50, 0.001));
      expect(rig.systemVolume, closeTo(0.5, 0.001));
    });

    test('stepVolume 夹在 0..100', () async {
      await mount();
      expect(await controller.stepVolume(500), 100.0);
      expect(await controller.stepVolume(-500), 0.0);
    });

    test('平台读不到系统音量时 stepVolume 返回 null 而不崩', () async {
      await mount();
      rig.readVolumeThrows = true;
      // 构造后还没读过系统音量（_systemVolume == -1），命中读取分支。
      expect(controller.systemVolume, -1);
      expect(await controller.stepVolume(5), isNull);
    });

    test('平台插件抛错时竖手势安静退出', () async {
      await mount();
      rig.readBrightnessThrows = true;
      await controller.startVerticalGesture(isVolume: false);
      expect(controller.adjustingBrightness, isFalse);
      await controller.updateVerticalGesture(0.5);
      await controller.endVerticalGesture();
    });

    test('dispose 会还原亮度并释放内核', () async {
      await mount();
      controller.dispose();
      await rig.settle();
      expect(rig.platform.disposed, isTrue);
      expect(rig.resetBrightnessCalls, 1);
    });
  });

  // ------------------------------------------------------------ 历史节流

  group('播放记录节流写入', () {
    test('时长不足 20 秒不写记录', () async {
      await mount();
      await rig.emitProgress(
          const Duration(seconds: 10), const Duration(seconds: 1));
      await rig.settle();
      expect(history.records, isEmpty);
    });

    test('8 秒节流：窗口内不重复写，时钟推进后再写', () async {
      await mount();
      await rig.emitProgress(
          const Duration(seconds: 120), const Duration(seconds: 1));
      await rig.settle();
      expect(historyWrites, 1);
      expect(history.byKey(task.recordKey)!.positionMs, 1000);

      rig.platform.emitPosition(const Duration(seconds: 2));
      rig.platform.emitPosition(const Duration(seconds: 3));
      await rig.settle();
      expect(historyWrites, 1);
      expect(history.byKey(task.recordKey)!.positionMs, 1000);

      rig.clock = rig.clock.add(K.historyThrottle + const Duration(seconds: 1));
      rig.platform.emitPosition(const Duration(seconds: 30));
      await rig.settle();
      expect(historyWrites, 2);
      expect(history.byKey(task.recordKey)!.positionMs, 30000);
    });

    test('记录字段完整，接近看完自动标记 finished', () async {
      await mount();
      await rig.emitProgress(
          const Duration(seconds: 100), const Duration(seconds: 96));
      await rig.settle();

      final PlayRecord r = history.byKey(task.recordKey)!;
      expect(r.key, task.recordKey);
      expect(r.sourceId, task.source.id);
      expect(r.vodId, '7');
      expect(r.vodName, '测试影片');
      expect(r.typeName, '电视剧');
      expect(r.lineName, 'm3u8');
      expect(r.episodeName, '第01集');
      expect(r.durationMs, 100000);
      expect(r.finished, isTrue);
      expect(r.updatedAt, rig.clock);
    });

    test('播放完成按 finished 写入，位置取总时长', () async {
      await mount(autoNext: false);
      rig.platform.emitDuration(const Duration(seconds: 100));
      await rig.settle();
      rig.platform.emitCompleted(true);
      await rig.settle();

      final PlayRecord r = history.byKey(task.recordKey)!;
      expect(r.finished, isTrue);
      expect(r.positionMs, 100000);
      expect(r.durationMs, 100000);
    });

    test('dispose 强制补写一条，且只写一条', () async {
      await mount();
      await rig.emitProgress(
          const Duration(seconds: 100), const Duration(seconds: 5));
      await rig.settle();
      expect(historyWrites, 1);
      controller.dispose();
      await rig.settle();
      expect(historyWrites, 2);
      controller.dispose();
      await rig.settle();
      expect(historyWrites, 2);
    });
  });

  // ------------------------------------------------------------ 续播

  group('续播', () {
    test('记录匹配且进度合适时跳到上次位置，只跳一次', () async {
      await mount(records: <PlayRecord>[record()]);
      await rig.emitProgress(
          const Duration(seconds: 120), const Duration(seconds: 1));
      await rig.settle();
      expect(rig.platform.seeks, <Duration>[const Duration(seconds: 30)]);

      rig.platform.emitPosition(const Duration(seconds: 2));
      rig.platform.emitPosition(const Duration(seconds: 3));
      await rig.settle();
      expect(rig.platform.seeks, hasLength(1));
    });

    test('关闭续播开关时不跳转', () async {
      await mount(records: <PlayRecord>[record()], resume: false);
      await rig.emitProgress(
          const Duration(seconds: 120), const Duration(seconds: 1));
      await rig.settle();
      expect(rig.platform.seeks, isEmpty);
    });

    test('线路或集数对不上时不跳转', () async {
      await mount(records: <PlayRecord>[record(episodeIndex: 1)]);
      await rig.emitProgress(
          const Duration(seconds: 120), const Duration(seconds: 1));
      await rig.settle();
      expect(rig.platform.seeks, isEmpty);
    });

    test('进度落后不足 10 秒时不跳转', () async {
      await mount(records: <PlayRecord>[record(positionMs: 5000)]);
      await rig.emitProgress(
          const Duration(seconds: 120), const Duration(seconds: 1));
      await rig.settle();
      expect(rig.platform.seeks, isEmpty);
    });

    test('上次已接近看完时不跳转，避免把人拖回片尾', () async {
      await mount(
        records: <PlayRecord>[record(positionMs: 119000, durationMs: 120000)],
      );
      await rig.emitProgress(
          const Duration(seconds: 120), const Duration(seconds: 1));
      await rig.settle();
      expect(rig.platform.seeks, isEmpty);
    });

    test('没有时长时不急着跳，拿到时长后才生效', () async {
      await mount(records: <PlayRecord>[record()]);
      rig.platform.emitPosition(const Duration(seconds: 1));
      await rig.settle();
      expect(rig.platform.seeks, isEmpty);
      await rig.emitProgress(
          const Duration(seconds: 120), const Duration(seconds: 2));
      await rig.settle();
      expect(rig.platform.seeks, <Duration>[const Duration(seconds: 30)]);
    });

    test('切集后重新判定续播', () async {
      await mount();
      await history.upsert(record(episodeIndex: 1, positionMs: 45000));
      await controller.selectEpisode(0, 1);
      await rig.settle();
      await rig.emitProgress(
          const Duration(seconds: 120), const Duration(seconds: 1));
      await rig.settle();
      expect(rig.platform.seeks, <Duration>[const Duration(seconds: 45)]);
    });
  });

  // ------------------------------------------------------------ 自动下一集

  group('自动下一集', () {
    test('播完且开启自动下一集时切到下一集并开播', () async {
      await mount();
      rig.platform.emitDuration(const Duration(seconds: 100));
      await rig.settle();
      rig.platform.emitCompleted(true);
      await rig.settle();

      expect(controller.task.episodeIndex, 1);
      expect(rig.platform.opens.last, 'https://a.com/2.m3u8');
      // 切到下一集时 _openUrl 会把 completed 重置，但「已看完」这一条
      // 记录必须在切集之前就落盘。
      expect(controller.completed, isFalse);
      expect(history.byKey(task.recordKey)!.finished, isTrue);
    });

    test('关闭开关或已是最后一集时停在当前集', () async {
      await mount(autoNext: false);
      rig.platform.emitCompleted(true);
      await rig.settle();
      expect(controller.task.episodeIndex, 0);
      expect(rig.platform.opens, hasLength(1));

      await mount();
      await controller.selectEpisode(0, 1);
      await rig.settle();
      rig.platform.emitCompleted(true);
      await rig.settle();
      expect(controller.task.episodeIndex, 1);
      expect(rig.platform.opens, <String>[
        'https://a.com/1.m3u8',
        'https://a.com/2.m3u8',
      ]);
    });
  });
}
