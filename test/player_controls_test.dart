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
    testWidgets('双击切换播放，单击只切控制栏', (WidgetTester tester) async {
      setSize(tester);
      await mount(tester);

      await tester.tapAt(const Offset(200, 150));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(const Offset(200, 150));
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        binding.calls.where((String c) => c == 'togglePlay'),
        hasLength(1),
        reason: '双击只触发一次播放切换，单击被抑制',
      );
      expect(binding.calls, isNot(contains('seek:')));

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
