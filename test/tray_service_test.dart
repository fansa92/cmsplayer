import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cms_player/data/models/play_line.dart';
import 'package:cms_player/data/models/play_task.dart';
import 'package:cms_player/data/models/vod_item.dart';
import 'package:cms_player/state/playback_bridge.dart';
import 'package:cms_player/ui/player/player_controls_binding.dart';
import 'package:cms_player/ui/shell/tray_service.dart';

import 'helpers/fakes.dart';

class _FakeControls extends ChangeNotifier implements PlayerControlsBinding {
  _FakeControls(this.task);

  @override
  final PlayTask task;

  bool isPlaying = false;
  int toggles = 0;
  int nexts = 0;
  int prevs = 0;

  @override
  bool get playing => isPlaying;

  @override
  Future<void> togglePlay() async {
    toggles++;
    isPlaying = !isPlaying;
    notifyListeners();
  }

  @override
  Future<void> next() async => nexts++;

  @override
  Future<void> previous() async => prevs++;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 内存里的托盘后端：只记录调用，方便断言。
class _FakeTrayAdapter implements TrayAdapter {
  bool installed = false;
  bool disposed = false;
  String icon = '';
  String toolTip = '';
  List<TrayEntry> menu = const <TrayEntry>[];
  ValueChanged<String>? onMenu;
  VoidCallback? onLeftClick;
  VoidCallback? onRightClick;
  int menuUpdates = 0;
  int toolTipUpdates = 0;

  @override
  Future<void> install({
    required String iconPath,
    required bool template,
    required String toolTip,
    required List<TrayEntry> menu,
    required ValueChanged<String> onMenu,
    required VoidCallback onLeftClick,
    required VoidCallback onRightClick,
  }) async {
    installed = true;
    icon = iconPath;
    this.toolTip = toolTip;
    this.menu = menu;
    this.onMenu = onMenu;
    this.onLeftClick = onLeftClick;
    this.onRightClick = onRightClick;
  }

  @override
  Future<void> updateMenu(List<TrayEntry> menu) async {
    menuUpdates++;
    this.menu = menu;
  }

  @override
  Future<void> updateToolTip(String text) async {
    toolTipUpdates++;
    toolTip = text;
  }

  @override
  Future<void> dispose() async => disposed = true;

  TrayEntry entry(String key) => menu.firstWhere((TrayEntry e) => e.key == key);
}

void main() {
  useIsolatedStores();

  late _FakeTrayAdapter adapter;
  int shows = 0;
  int quits = 0;

  PlayTask taskWith({String name = '繁花'}) => PlayTask(
        source: sourceOf('测试站'),
        item: VodItem(
          id: 1,
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
        ),
        lineIndex: 0,
        episodeIndex: 0,
      );

  Future<void> startTray() async {
    await TrayService.instance.start(
      onShow: () async => shows++,
      onQuit: () async => quits++,
    );
  }

  /// 菜单回调往往走 unawaited，让出一次事件循环再看结果。
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  setUp(() async {
    PlaybackBridge.resetForTest();
    await TrayService.resetForTest();
    adapter = _FakeTrayAdapter();
    TrayService.adapterFactory = () => adapter;
    shows = 0;
    quits = 0;
  });

  tearDown(() async {
    PlaybackBridge.resetForTest();
    await TrayService.resetForTest();
  });

  test('挂载后菜单固定五项，没有播放器时播放相关项全置灰', () async {
    await startTray();

    expect(TrayService.instance.ready, isTrue);
    expect(adapter.installed, isTrue);
    expect(adapter.icon, TrayService.iconAsset);
    expect(
      adapter.menu.where((TrayEntry e) => !e.isSeparator).map((TrayEntry e) => e.label),
      <String>['显示主窗口', '播放', '上一集', '下一集', '退出'],
    );
    expect(adapter.entry('toggle').enabled, isFalse);
    expect(adapter.entry('prev').enabled, isFalse);
    expect(adapter.entry('next').enabled, isFalse);
  });

  test('播放中菜单变成「暂停」，并带上片名提示', () async {
    await startTray();
    final _FakeControls controls = _FakeControls(taskWith());
    PlaybackBridge.attach(controls);

    expect(adapter.entry('toggle').label, '播放');
    expect(adapter.entry('toggle').enabled, isTrue);
    expect(adapter.toolTip, 'CMSPlayer · 繁花 · 第01集');

    controls.isPlaying = true;
    controls.notifyListeners();
    await settle();

    expect(adapter.entry('toggle').label, '暂停');
    expect(adapter.menuUpdates, greaterThan(0));
  });

  test('点「播放 / 上一集 / 下一集」会落到播放器上', () async {
    await startTray();
    final _FakeControls controls = _FakeControls(taskWith());
    PlaybackBridge.attach(controls);

    adapter.onMenu!('toggle');
    await settle();
    adapter.onMenu!('next');
    await settle();
    adapter.onMenu!('prev');
    await settle();

    expect(controls.toggles, 1);
    expect(controls.nexts, 1);
    expect(controls.prevs, 1);
    // 播起来之后菜单文字变成「暂停」；再点一次回到「播放」。
    expect(adapter.entry('toggle').label, '暂停');
    adapter.onMenu!('toggle');
    await settle();
    expect(adapter.entry('toggle').label, '播放');
    expect(controls.toggles, 2);
  });

  test('「显示主窗口」与「退出」交给外壳处理', () async {
    await startTray();

    adapter.onMenu!('show');
    await settle();
    expect(shows, 1);

    adapter.onMenu!('quit');
    await settle();
    expect(quits, 1);
    // 退出前先把图标拆掉，不留一个点不动的小图标。
    expect(adapter.disposed, isTrue);
    expect(TrayService.instance.ready, isFalse);
  });

  test('托盘不可用时 ready 为 false，外壳会退回直接退出', () async {
    TrayService.adapterFactory = () => _ThrowingTrayAdapter();
    await startTray();
    expect(TrayService.instance.ready, isFalse);
  });
}

class _ThrowingTrayAdapter implements TrayAdapter {
  @override
  Future<void> install({
    required String iconPath,
    required bool template,
    required String toolTip,
    required List<TrayEntry> menu,
    required ValueChanged<String> onMenu,
    required VoidCallback onLeftClick,
    required VoidCallback onRightClick,
  }) async {
    throw StateError('no appindicator');
  }

  @override
  Future<void> dispose() async {}

  @override
  Future<void> updateMenu(List<TrayEntry> menu) async {}

  @override
  Future<void> updateToolTip(String text) async {}
}
