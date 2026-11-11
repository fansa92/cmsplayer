import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cms_player/data/models/play_task.dart';
import 'package:cms_player/data/models/vod_item.dart';
import 'package:cms_player/ui/player/player_chrome.dart';
import 'package:cms_player/ui/player/player_controls.dart';
import 'package:cms_player/ui/player/player_controls_binding.dart';
import 'package:cms_player/ui/player/player_window.dart';

import 'helpers/fakes.dart';

/// 控制层的交互回归：键盘映射、锁定吞键、自动隐藏、OSD、手势分发。
///
/// [PlayerControls] 只通过 [PlayerControlsBinding] 跟状态层打交道，所以这里
/// 用一个内存假体驱动，不需要 media_kit / window_manager 的原生插件。
void main() {
  const Size surface = Size(800, 600);

  late FakeBinding binding;
  int backs = 0;
  bool windowFullScreen = false;
  int setFullScreenCalls = 0;
  int toggleFullScreenCalls = 0;

  Widget host() => MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.black,
          body: PlayerControls(
            controller: binding,
            onBack: () => backs++,
          ),
        ),
      );

  void setSize(WidgetTester tester) {
    tester.view.physicalSize = surface;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(host());
    // initState 里的窗口状态查询 + 补一帧请求焦点。
    await tester.pump();
  }

  /// 主动卸载，避免自动隐藏 / OSD 的 Timer 在用例结束时还挂着。
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  setUp(() {
    binding = FakeBinding();
    backs = 0;
    windowFullScreen = false;
    setFullScreenCalls = 0;
    toggleFullScreenCalls = 0;

    PlayerWindow.isFullScreenForTest = () async => windowFullScreen;
    PlayerWindow.setFullScreenForTest = (bool v) async {
      setFullScreenCalls++;
      windowFullScreen = v;
    };
    PlayerWindow.toggleFullScreenForTest = () async {
      toggleFullScreenCalls++;
      windowFullScreen = !windowFullScreen;
      return windowFullScreen;
    };
  });

  tearDown(() {
    PlayerWindow.isFullScreenForTest = null;
    PlayerWindow.setFullScreenForTest = null;
    PlayerWindow.toggleFullScreenForTest = null;
  });

  group('键盘', () {
    testWidgets('空格 / K 切换播放，长按重复不再触发', (WidgetTester tester) async {
      setSize(tester);
      await mount(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.pump();
      expect(
          binding.calls.where((String c) => c == 'togglePlay'), hasLength(2));

      // 按住空格会产生 Repeat 事件，播放键必须吃掉但不能再切一次。
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(
          binding.calls.where((String c) => c == 'togglePlay'), hasLength(2));

      await unmount(tester);
    });

    testWidgets('J / L / 左右方向键快进快退 10 秒并弹 OSD', (WidgetTester tester) async {
      setSize(tester);
      await mount(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(binding.calls, contains('seekBy:10000'));
      expect(find.text('快进 10 秒'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
      await tester.pump();
      expect(binding.calls, contains('seekBy:-10000'));
      expect(find.text('快退 10 秒'), findsOneWidget);

      // OSD 1.4 秒后自动消失。
      await tester.pump(const Duration(milliseconds: 1500));
      expect(find.text('快退 10 秒'), findsNothing);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(
        binding.calls.where((String c) => c.startsWith('seekBy:')),
        hasLength(4),
      );

      await unmount(tester);
    });

    testWidgets('上下方向键调音量，OSD 用返回值显示百分比', (WidgetTester tester) async {
      setSize(tester);
      await mount(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(binding.calls, contains('stepVolume:5.0'));
      expect(find.text('音量 55%'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(binding.calls, contains('stepVolume:-5.0'));

      await unmount(tester);
    });

    testWidgets('拿不到音量时不弹 OSD', (WidgetTester tester) async {
      setSize(tester);
      binding.volumeResult = null;
      await mount(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(find.text('音量 55%'), findsNothing);
      expect(find.byIcon(Icons.volume_up), findsNothing);

      await unmount(tester);
    });

    testWidgets('锁定时吞掉播放类按键，F 与 Esc 仍可用', (WidgetTester tester) async {
      setSize(tester);
      binding.locked = true;
      await mount(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(binding.calls, isEmpty, reason: '锁定后按键不能穿透到底下的列表');

      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.pump();
      expect(toggleFullScreenCalls, 1);
      expect(windowFullScreen, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(backs, 0, reason: '全屏时 Esc 先退出全屏，不返回');
      expect(setFullScreenCalls, 1);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(backs, 1);

      await unmount(tester);
    });
  });

  group('自动隐藏', () {
    testWidgets('4 秒无操作收起控制栏，点画面再唤出', (WidgetTester tester) async {
      setSize(tester);
      await mount(tester);
      expect(find.byType(PlayerTopBar), findsOneWidget);

      await tester.pump(const Duration(seconds: 4));
      expect(find.byType(PlayerTopBar), findsNothing);

      // 避开顶栏、底栏、中央键和左侧锁定键。
      await tester.tapAt(const Offset(200, 150));
      // 同时注册了 onTap / onDoubleTap 时，单击要等双击判定窗口才回调。
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(PlayerTopBar), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('正在拖动进度时不自动隐藏', (WidgetTester tester) async {
      setSize(tester);
      binding.seeking = true;
      await mount(tester);

      await tester.pump(const Duration(seconds: 9));
      expect(find.byType(PlayerTopBar), findsOneWidget,
          reason: 'seeking 期间计时器要反复顺延');

      await unmount(tester);
    });
  });

  group('手势', () {
    testWidgets('双击中间切换播放，单击只切控制栏', (WidgetTester tester) async {
      setSize(tester);
      await mount(tester);

      // 800 宽，中间区是 266..533；y 取 200 避开中央播放键。
      await tester.tapAt(const Offset(400, 200));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(const Offset(400, 200));
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        binding.calls.where((String c) => c == 'togglePlay'),
        hasLength(1),
        reason: '双击只触发一次播放切换，单击被抑制',
      );
      expect(binding.calls, isNot(contains('seekBy:-10000')));

      await unmount(tester);
    });

    testWidgets('双击左侧快退、右侧快进，并弹 OSD', (WidgetTester tester) async {
      setSize(tester);
      await mount(tester);

      await tester.tapAt(const Offset(100, 300));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(const Offset(100, 300));
      await tester.pump(const Duration(milliseconds: 400));
      expect(binding.calls, contains('seekBy:-10000'));
      expect(find.text('快退 10 秒'), findsOneWidget);
      expect(binding.calls, isNot(contains('togglePlay')));

      await tester.tapAt(const Offset(700, 300));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(const Offset(700, 300));
      await tester.pump(const Duration(milliseconds: 400));
      expect(binding.calls, contains('seekBy:10000'));
      expect(find.text('快进 10 秒'), findsOneWidget);
      expect(binding.calls, isNot(contains('togglePlay')));

      await unmount(tester);
    });

    testWidgets('长按临时 2 倍速，松手恢复', (WidgetTester tester) async {
      setSize(tester);
      await mount(tester);

      // (400, 200)：中间偏上，避开中央播放键。
      final TestGesture g = await tester.startGesture(const Offset(400, 200));
      await tester.pump(const Duration(milliseconds: 800));
      expect(binding.calls, contains('startBurstRate'));
      expect(find.text('2.0x 快放中'), findsOneWidget);

      await g.up();
      await tester.pump();
      expect(binding.calls, contains('endBurstRate'));
      expect(find.text('2.0x 快放中'), findsNothing);

      await unmount(tester);
    });

    testWidgets('横向拖动走预览进度并提交', (WidgetTester tester) async {
      setSize(tester);
      await mount(tester);

      await tester.dragFrom(const Offset(200, 150), const Offset(80, 0));
      await tester.pump(const Duration(milliseconds: 400));

      expect(binding.calls, contains('startSeek'));
      expect(binding.calls.where((String c) => c.startsWith('updateSeek:')),
          isNotEmpty);
      expect(binding.calls, contains('commitSeek'));

      await unmount(tester);
    });

    testWidgets('右半屏纵滑调音量、左半屏调亮度', (WidgetTester tester) async {
      setSize(tester);
      await mount(tester);

      await tester.dragFrom(const Offset(700, 300), const Offset(0, -60));
      await tester.pump(const Duration(milliseconds: 400));
      expect(binding.calls, contains('startVerticalGesture:true'));
      expect(binding.calls, contains('endVerticalGesture'));

      await tester.dragFrom(const Offset(100, 300), const Offset(0, -60));
      await tester.pump(const Duration(milliseconds: 400));
      expect(binding.calls, contains('startVerticalGesture:false'));

      await unmount(tester);
    });

    testWidgets('锁定时纵向手势与双击都被摘掉', (WidgetTester tester) async {
      setSize(tester);
      binding.locked = true;
      await mount(tester);

      await tester.dragFrom(const Offset(700, 300), const Offset(0, -60));
      await tester.pump(const Duration(milliseconds: 400));
      expect(binding.calls, isEmpty);
      expect(find.byType(PlayerCenterButton), findsNothing);
      expect(find.byIcon(Icons.lock), findsOneWidget);

      await unmount(tester);
    });
  });

  group('音轨 / 定时 / 片头尾', () {
    testWidgets('只有一条音轨时不显示切换入口', (WidgetTester tester) async {
      setSize(tester);
      binding.audioTracks = <PlayerAudioTrack>[
        const PlayerAudioTrack(id: '1', label: '国语'),
      ];
      await mount(tester);
      expect(find.text('音轨'), findsNothing);
      await unmount(tester);
    });

    testWidgets('多条音轨时弹层列出并回传选择', (WidgetTester tester) async {
      setSize(tester);
      binding.audioTracks = <PlayerAudioTrack>[
        const PlayerAudioTrack(id: '1', label: '国语', codec: 'aac'),
        const PlayerAudioTrack(id: '2', label: '粤语', codec: 'ac-3'),
      ];
      binding.audioId = '1';
      await mount(tester);

      await tester.tap(find.text('音轨'));
      await tester.pumpAndSettle();
      expect(find.text('粤语'), findsOneWidget);
      expect(find.textContaining('AC-3'), findsOneWidget);

      await tester.tap(find.text('粤语'));
      await tester.pumpAndSettle();
      expect(binding.calls, contains('selectAudioTrack:2'));

      await unmount(tester);
    });

    testWidgets('定时弹层回传所选时长，生效后药丸显示剩余', (WidgetTester tester) async {
      setSize(tester);
      await mount(tester);

      await tester.tap(find.text('定时'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('30 分钟'));
      await tester.pumpAndSettle();
      expect(binding.calls, contains('setSleepTimer:30'));

      binding.sleepRemaining = const Duration(minutes: 29, seconds: 30);
      binding.notifyListeners();
      await tester.pump();
      expect(find.text('29:30'), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('定时弹层可以选「本集播完」', (WidgetTester tester) async {
      setSize(tester);
      await mount(tester);

      await tester.tap(find.text('定时'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('本集播完'));
      await tester.pumpAndSettle();
      expect(binding.calls, contains('setSleepAtEnd:true'));

      await unmount(tester);
    });

    testWidgets('片头尾弹层把当前进度记为标记', (WidgetTester tester) async {
      setSize(tester);
      binding.position = const Duration(seconds: 95);
      await mount(tester);

      await tester.tap(find.text('片头尾'));
      await tester.pumpAndSettle();
      expect(find.text('片头片尾'), findsOneWidget);

      await tester.tap(find.text('设为当前').first);
      await tester.pump();
      expect(binding.calls, contains('markIntroAt:95'));

      await unmount(tester);
    });

    testWidgets('片头内出现「跳过片头」，点了就跳', (WidgetTester tester) async {
      setSize(tester);
      binding.inIntro = true;
      await mount(tester);

      expect(find.text('跳过片头'), findsOneWidget);
      await tester.tap(find.text('跳过片头'));
      await tester.pump();
      expect(binding.calls, contains('skipIntro'));

      await unmount(tester);
    });
  });

  group('换源', () {
    testWidgets('只有一个资源站时不显示换源入口', (WidgetTester tester) async {
      setSize(tester);
      binding.canSwitchSource = false;
      await mount(tester);
      expect(find.text('换源'), findsNothing);
      await unmount(tester);
    });

    testWidgets('弹层列出候选，选中后回传源 id', (WidgetTester tester) async {
      setSize(tester);
      binding.canSwitchSource = true;
      binding.sourceOptions = const <PlayerSourceOption>[
        PlayerSourceOption(
          id: 's2',
          label: '备用站',
          episodeLabel: 'm3u8 · 第01集',
        ),
      ];
      await mount(tester);

      await tester.tap(find.text('换源'));
      await tester.pumpAndSettle();

      expect(binding.calls, contains('findAlternateSources'));
      expect(find.text('切换资源站'), findsOneWidget);
      expect(find.text('备用站'), findsOneWidget);
      expect(find.text('m3u8 · 第01集'), findsOneWidget);

      await tester.tap(find.text('备用站'));
      await tester.pumpAndSettle();
      expect(binding.calls, contains('switchToSource:s2'));
      expect(find.text('切换资源站'), findsNothing);

      await unmount(tester);
    });

    testWidgets('没有候选时给出说明，不显示空列表', (WidgetTester tester) async {
      setSize(tester);
      binding.canSwitchSource = true;
      await mount(tester);

      await tester.tap(find.text('换源'));
      await tester.pumpAndSettle();

      expect(find.text('其它资源站里没找到这部片子'), findsOneWidget);
      expect(find.text('重新查找'), findsOneWidget);

      await unmount(tester);
    });
  });

  group('控制栏按钮与错误态', () {
    testWidgets('倍速药丸打开弹层并把选择回传给状态层', (WidgetTester tester) async {
      setSize(tester);
      await mount(tester);

      await tester.tap(find.text('1.0x'));
      await tester.pumpAndSettle();
      expect(find.text('2.0x'), findsOneWidget);

      await tester.tap(find.text('2.0x'));
      await tester.pumpAndSettle();
      expect(binding.calls, contains('setRate:2.0'));

      await unmount(tester);
    });

    testWidgets('画幅与下一集按钮各自发对应命令', (WidgetTester tester) async {
      setSize(tester);
      await mount(tester);

      await tester.tap(find.text('适应'));
      await tester.pump();
      expect(binding.calls, contains('cycleFit'));

      await tester.tap(find.byTooltip('下一集'));
      await tester.pump();
      expect(binding.calls, contains('next'));
      expect(binding.calls, isNot(contains('previous')),
          reason: '第一集不该出现上一集按钮');

      await unmount(tester);
    });

    testWidgets('播放失败时显示原因并能重试', (WidgetTester tester) async {
      setSize(tester);
      binding.error = '连接超时';
      await mount(tester);

      expect(find.text('播放失败'), findsOneWidget);
      expect(find.text('连接超时'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, '重试'));
      await tester.pump();
      expect(binding.calls, contains('retry'));

      await unmount(tester);
    });
  });
}

/// 控制层状态假体：记录所有命令，状态可按需改写。
class FakeBinding extends ChangeNotifier implements PlayerControlsBinding {
  final List<String> calls = <String>[];

  late final PlayTask _task = PlayTask(
    source: sourceOf('测试站'),
    item: VodItem(
      id: 1,
      name: '测试片',
      playFrom: 'm3u8',
      playUrl: r'第1集$https://a.com/1.m3u8#第2集$https://a.com/2.m3u8',
    ),
    lineIndex: 0,
    episodeIndex: 0,
  );

  @override
  PlayTask get task => _task;

  @override
  Duration position = const Duration(seconds: 30);

  @override
  Duration duration = const Duration(minutes: 10);

  @override
  double positionRatio = 0.05;

  @override
  double seekRatio = 0.2;

  @override
  double rate = 1.0;

  @override
  double gestureVolume = 0.5;

  @override
  double gestureBrightness = 0.7;

  @override
  String fitLabel = '适应';

  @override
  bool playing = true;

  @override
  bool buffering = false;

  @override
  bool starting = false;

  @override
  bool locked = false;

  @override
  bool seeking = false;

  @override
  bool adjustingVolume = false;

  @override
  bool adjustingBrightness = false;

  @override
  String? error;

  @override
  String? fallbackTrying;

  @override
  String? fallbackNotice;

  @override
  String? resolutionLabel;

  @override
  String? fpsLabel;

  @override
  String? videoCodec;

  @override
  String? videoDecoder;

  @override
  String? pixelFormat;

  @override
  String? audioCodec;

  @override
  String? audioChannels;

  @override
  int? audioSampleRate;

  @override
  List<PlayerAudioTrack> audioTracks = const <PlayerAudioTrack>[];

  @override
  String? audioId;

  @override
  bool canSwitchSource = false;

  /// findAlternateSources 的返回值，用例里按需塞候选。
  List<PlayerSourceOption> sourceOptions = const <PlayerSourceOption>[];

  @override
  Duration? sleepRemaining;

  @override
  bool sleepAtEnd = false;

  @override
  int introMs = 0;

  @override
  int outroMs = 0;

  @override
  bool inIntro = false;

  @override
  bool autoSkipIntro = true;

  @override
  bool autoSkipOutro = true;

  double? volumeResult = 55.0;

  @override
  Future<void> togglePlay() async => calls.add('togglePlay');

  @override
  Future<void> seek(Duration target) async => calls.add('seek:$target');

  @override
  Future<void> seekBy(Duration delta) async =>
      calls.add('seekBy:${delta.inMilliseconds}');

  @override
  Future<void> setRate(double value) async => calls.add('setRate:$value');

  @override
  Future<double?> stepVolume(double deltaPercent) async {
    calls.add('stepVolume:$deltaPercent');
    return volumeResult;
  }

  @override
  Future<void> cycleFit() async => calls.add('cycleFit');

  @override
  void toggleLock() => calls.add('toggleLock');

  @override
  Future<void> next() async => calls.add('next');

  @override
  Future<void> previous() async => calls.add('previous');

  @override
  Future<void> selectEpisode(int lineIndex, int episodeIndex) async =>
      calls.add('selectEpisode:$lineIndex:$episodeIndex');

  @override
  Future<void> retry() async => calls.add('retry');

  @override
  Future<void> selectAudioTrack(String id) async =>
      calls.add('selectAudioTrack:$id');

  @override
  Future<List<PlayerSourceOption>> findAlternateSources() async {
    calls.add('findAlternateSources');
    return sourceOptions;
  }

  @override
  Future<void> switchToSource(String sourceId) async =>
      calls.add('switchToSource:$sourceId');

  @override
  Future<void> setSleepTimer(Duration? remaining) async =>
      calls.add('setSleepTimer:${remaining?.inMinutes}');

  @override
  Future<void> setSleepAtEnd(bool value) async =>
      calls.add('setSleepAtEnd:$value');

  @override
  Future<void> markIntroAt(Duration position) async =>
      calls.add('markIntroAt:${position.inSeconds}');

  @override
  Future<void> markOutroAt(Duration position) async =>
      calls.add('markOutroAt:${position.inSeconds}');

  @override
  Future<void> clearSkipMarks() async => calls.add('clearSkipMarks');

  @override
  Future<void> skipIntro() async => calls.add('skipIntro');

  @override
  Future<void> setAutoSkipIntro(bool value) async {
    calls.add('setAutoSkipIntro:$value');
    autoSkipIntro = value;
    notifyListeners();
  }

  @override
  Future<void> setAutoSkipOutro(bool value) async {
    calls.add('setAutoSkipOutro:$value');
    autoSkipOutro = value;
    notifyListeners();
  }

  @override
  Future<void> startBurstRate() async => calls.add('startBurstRate');

  @override
  Future<void> endBurstRate() async => calls.add('endBurstRate');

  @override
  void startSeek() => calls.add('startSeek');

  @override
  void updateSeek(Duration delta) => calls.add('updateSeek:$delta');

  @override
  void commitSeek() => calls.add('commitSeek');

  @override
  void cancelSeek() => calls.add('cancelSeek');

  @override
  Future<void> startVerticalGesture({required bool isVolume}) async =>
      calls.add('startVerticalGesture:$isVolume');

  @override
  Future<void> updateVerticalGesture(double delta) async =>
      calls.add('updateVerticalGesture:$delta');

  @override
  Future<void> endVerticalGesture() async => calls.add('endVerticalGesture');
}
