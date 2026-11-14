import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cms_player/data/models/play_line.dart';
import 'package:cms_player/data/models/play_task.dart';
import 'package:cms_player/data/models/vod_item.dart';
import 'package:cms_player/state/playback_bridge.dart';
import 'package:cms_player/ui/player/player_controls_binding.dart';

import 'helpers/fakes.dart';

/// 只实现桥接层用到的那几项，其余成员走 noSuchMethod。
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

void main() {
  useIsolatedStores();

  PlayTask taskWith({String name = '繁花', int episode = 0}) => PlayTask(
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
        episodeIndex: episode,
      );

  setUp(PlaybackBridge.resetForTest);
  tearDown(PlaybackBridge.resetForTest);

  test('挂上播放器后标题与状态同步', () {
    final _FakeControls controls = _FakeControls(taskWith(episode: 1));
    PlaybackBridge.attach(controls);

    expect(PlaybackBridge.hasPlayer, isTrue);
    expect(PlaybackBridge.active.value, isTrue);
    expect(PlaybackBridge.playing.value, isFalse);
    expect(PlaybackBridge.title.value, '繁花 · 第02集');

    controls.isPlaying = true;
    controls.notifyListeners();
    expect(PlaybackBridge.playing.value, isTrue);
  });

  test('桥接转发的播放控制会落到当前播放器', () async {
    final _FakeControls controls = _FakeControls(taskWith());
    PlaybackBridge.attach(controls);

    await PlaybackBridge.togglePlay();
    await PlaybackBridge.next();
    await PlaybackBridge.previous();

    expect(controls.toggles, 1);
    expect(controls.nexts, 1);
    expect(controls.prevs, 1);
    expect(PlaybackBridge.playing.value, isTrue);
  });

  test('摘掉播放器后状态归零，且不再响应旧实例', () async {
    final _FakeControls old = _FakeControls(taskWith());
    PlaybackBridge.attach(old);
    PlaybackBridge.detach(old);

    expect(PlaybackBridge.hasPlayer, isFalse);
    expect(PlaybackBridge.active.value, isFalse);
    expect(PlaybackBridge.title.value, '');

    // 旧实例再发通知不该把桥接重新点亮。
    old.notifyListeners();
    expect(PlaybackBridge.active.value, isFalse);

    // 没有播放器时控制调用是安全的空操作。
    await PlaybackBridge.togglePlay();
    expect(old.toggles, 0);
  });

  test('换成另一个播放器时只认新的那个', () async {
    final _FakeControls first = _FakeControls(taskWith(name: '第一部'));
    final _FakeControls second = _FakeControls(taskWith(name: '第二部'));
    PlaybackBridge.attach(first);
    PlaybackBridge.attach(second);

    expect(PlaybackBridge.title.value, '第二部 · 第01集');

    // 旧页面退出时会把「自己」摘掉，不能连累新页面。
    PlaybackBridge.detach(first);
    expect(PlaybackBridge.hasPlayer, isTrue);
    expect(PlaybackBridge.title.value, '第二部 · 第01集');
  });
}
