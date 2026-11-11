import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:cms_player/core/constants.dart';
import 'package:cms_player/core/storage/settings_store.dart';
import 'package:cms_player/data/models/play_line.dart';
import 'package:cms_player/data/models/play_task.dart';
import 'package:cms_player/data/models/vod_item.dart';
import 'package:cms_player/data/models/vod_source.dart';
import 'package:cms_player/state/app_state.dart';
import 'package:cms_player/state/history_store.dart';
import 'package:cms_player/state/source_store.dart';
import 'package:cms_player/ui/player/player_controller.dart';
import 'package:cms_player/ui/player/player_controls_binding.dart';

import 'helpers/fake_player.dart';
import 'helpers/fakes.dart';

/// 播放失败后的降级状态机：同源备用地址 → 其它线路 → 跨源同名影片 →
/// 最终错误面板，以及「正在尝试」提示、notice 定时消失、并发保护与重试。
void main() {
  useIsolatedStores();

  late FakePlayerRig rig;
  late PlayerController controller;
  late SourceStore sources;
  late PlayTask task;

  VodSource mainSource() => VodSource.fromRaw(<String, Object>{
        'name': '主站',
        'api': 'https://a.com/api.php/provide/vod/',
      });

  /// 默认两条线路：主线路第 1 集带一个备用地址，备用线路有同名集。
  /// 于是同源降级链恰好是 [备用地址, 备用线路]。
  VodItem item({
    bool withMirrors = true,
    bool withSecondLine = true,
    String firstUrl = 'https://a.com/1.m3u8',
  }) =>
      VodItem(
        id: 7,
        name: '测试影片',
        playLines: <PlayLine>[
          PlayLine(
            name: 'm3u8',
            episodes: <PlayEpisode>[
              PlayEpisode(
                name: '第01集',
                url: firstUrl,
                mirrors: withMirrors
                    ? <String>['https://a.com/1b.m3u8']
                    : const <String>[],
              ),
              const PlayEpisode(name: '第02集', url: 'https://a.com/2.m3u8'),
            ],
          ),
          if (withSecondLine)
            const PlayLine(
              name: '备用线路',
              episodes: <PlayEpisode>[
                PlayEpisode(name: '第01集', url: 'https://a.com/alt1.m3u8'),
              ],
            ),
        ],
      );

  Future<void> mount({
    VodItem? vod,
    List<VodSource> extraSources = const <VodSource>[],
  }) async {
    rig = FakePlayerRig();
    PlayerController.environment = rig.environment;

    final SettingsStore settings = SettingsStore();
    await settings.init();
    sources = SourceStore(settings);
    task = PlayTask(
      source: mainSource(),
      item: vod ?? item(),
      lineIndex: 0,
      episodeIndex: 0,
    );
    for (final VodSource s in extraSources) {
      await sources.add(s);
    }

    controller = PlayerController(
      task: task,
      app: AppState(settings),
      history: HistoryStore(),
      sources: sources,
    );
    await rig.settle();
  }

  /// 跨源搜索的假响应：按被查询的站点返回同名、同集的可播放条目，
  /// 地址也用该站域名，便于从 opens 里分辨到底切到了哪个源。
  FakeHttpClient crossClient({String name = '测试影片'}) =>
      FakeHttpClient((RecordedRequest r) => fakeJson(vodPageJson(
            list: <Map<String, Object>>[
              vodJson(
                id: 9,
                name: name,
                playFrom: 'm3u8',
                playUrl: '第01集\$https://${r.url.host}/1.m3u8',
              ),
            ],
            classes: <Map<String, Object>>[
              <String, Object>{'type_id': 1, 'type_name': '电视剧'},
            ],
          )));

  /// 推一条播放错误并等降级流程落地。
  Future<void> fail([String message = '播不动']) async {
    rig.platform.emitError(message);
    await rig.settle(16);
  }

  tearDown(() async {
    controller.dispose();
    await rig.settle();
    PlayerController.resetEnvironmentForTest();
  });

  group('同源降级链', () {
    test('按「备用地址 → 其它线路同名集」顺序尝试', () async {
      await mount();
      expect(rig.platform.opens, <String>['https://a.com/1.m3u8']);

      await fail();
      expect(rig.platform.opens, <String>[
        'https://a.com/1.m3u8',
        'https://a.com/1b.m3u8',
      ]);
      expect(controller.error, isNull);
      expect(controller.fallbackTrying, isNull);

      await fail();
      expect(rig.platform.opens, <String>[
        'https://a.com/1.m3u8',
        'https://a.com/1b.m3u8',
        'https://a.com/alt1.m3u8',
      ]);
      expect(controller.error, isNull);
    });

    test('链耗尽且没有其它资源站时亮出错误面板', () async {
      await mount();
      await fail();
      await fail();
      await fail('主线路彻底挂了');

      expect(controller.error, '主线路彻底挂了');
      expect(controller.fallbackTrying, isNull);
      expect(controller.starting, isFalse);
    });

    test('空错误消息用 「播放失败」兜底', () async {
      await mount(vod: item(withMirrors: false, withSecondLine: false));
      await fail('');
      expect(controller.error, '播放失败');
    });

    test('打开地址本身抛异常时继续走下一个候选', () async {
      await mount();
      // 下一次 open（retry 触发的第 2 次）故意失败。
      rig.platform.openFailureAt = 2;
      await controller.retry();
      await rig.settle(16);

      expect(rig.platform.opens.length, greaterThanOrEqualTo(3));
      expect(rig.platform.opens, contains('https://a.com/1b.m3u8'));
      expect(controller.error, isNull);
    });

    test('降级候选地址无法解析时跳过，继续下一个', () async {
      await mount(
        vod: VodItem(
          id: 7,
          name: '测试影片',
          playLines: <PlayLine>[
            const PlayLine(
              name: 'm3u8',
              episodes: <PlayEpisode>[
                PlayEpisode(name: '第01集', url: 'https://a.com/1.m3u8'),
                PlayEpisode(name: '第02集', url: 'https://a.com/2.m3u8'),
              ],
            ),
            const PlayLine(
              name: '空线路',
              episodes: <PlayEpisode>[
                PlayEpisode(
                  name: '第01集',
                  url: '   ',
                  mirrors: <String>['https://a.com/ok.m3u8'],
                ),
              ],
            ),
          ],
        ),
      );
      await fail();

      // sameSource 会给「空线路」的主地址（空白）和它的备用地址各一项；
      // 空白项解析失败后会继续推进到备用地址。
      expect(controller.error, isNull);
      expect(rig.platform.opens, contains('https://a.com/ok.m3u8'));
    });

    test('降级成功只发出「已切换到」提示，不显示错误', () async {
      await mount();
      await fail();
      expect(controller.fallbackNotice, isNull, reason: '同源换地址不弹「已切换」横幅');
      expect(controller.error, isNull);
    });
  });

  group('跨源降级', () {
    test('同源链耗尽后切到其它资源站，任务与提示同步更新', () async {
      final FakeHttpClient client = crossClient();
      useFakeApi(client);
      await mount(
        extraSources: <VodSource>[sourceOf('备用站', host: 'b.com')],
      );

      await fail(); // 备用地址
      await fail(); // 备用线路
      await fail(); // 跨源

      expect(client.requests, isNotEmpty);
      expect(controller.task.source.name, '备用站');
      expect(controller.task.item.name, '测试影片');
      expect(controller.fallbackNotice, '已切换到「备用站」');
      expect(controller.error, isNull);
      expect(rig.platform.opens.last, 'https://b.com/1.m3u8');
    });

    test('「正在查找其它资源站…」在搜索期间可见', () async {
      final Completer<void> gate = Completer<void>();
      final FakeHttpClient client = crossClient();
      client.gate = gate.future;
      useFakeApi(client);
      await mount(
        vod: item(withMirrors: false, withSecondLine: false),
        extraSources: <VodSource>[sourceOf('备用站', host: 'b.com')],
      );

      rig.platform.emitError('挂了');
      await rig.settle(4);
      expect(controller.fallbackTrying, '正在查找其它资源站…');

      gate.complete();
      await rig.settle(24);
      expect(controller.fallbackTrying, isNull);
      expect(controller.task.source.name, '备用站');
    });

    test('降级流程进行中再来一条错误不会重复推进（_recovering）', () async {
      final Completer<void> gate = Completer<void>();
      final FakeHttpClient client = crossClient();
      client.gate = gate.future;
      useFakeApi(client);
      await mount(
        vod: item(withMirrors: false, withSecondLine: false),
        extraSources: <VodSource>[sourceOf('备用站', host: 'b.com')],
      );

      rig.platform.emitError('第一次');
      await rig.settle(4);
      rig.platform.emitError('第二次');
      await rig.settle(2);
      gate.complete();
      await rig.settle(24);

      // 第二条错误应被 _recovering 挡掉：只切一次源、只开一次新地址。
      expect(
        rig.platform.opens
            .where((String u) => u == 'https://b.com/1.m3u8')
            .length,
        1,
      );
      expect(controller.error, isNull);
    });

    test('降级提示 4 秒后自动消失', () async {
      useFakeApi(crossClient());
      await mount(
        extraSources: <VodSource>[sourceOf('备用站', host: 'b.com')],
      );
      await fail();
      await fail();
      await fail();
      expect(controller.fallbackNotice, isNotNull);

      rig.fireTimersOf(K.fallbackNoticeDuration);
      await rig.settle();
      expect(controller.fallbackNotice, isNull);
    });

    test('跨源最多切换 2 次，之后把错误交给用户', () async {
      useFakeApi(crossClient());
      await mount(
        vod: item(withMirrors: false, withSecondLine: false),
        extraSources: <VodSource>[
          sourceOf('备用站1', host: 'b.com'),
          sourceOf('备用站2', host: 'c.com'),
          sourceOf('备用站3', host: 'd.com'),
        ],
      );

      // 没有同源候选，每条错误直接触发一次跨源。
      for (int i = 0; i < 8; i++) {
        await fail('还是挂了');
      }

      // 最多切 2 次：opens 里除主站外只应出现两个不同域名。
      final Set<String> hosts =
          rig.platform.opens.map((String u) => Uri.parse(u).host).toSet();
      expect(hosts, <String>{'a.com', 'b.com', 'c.com'});
      expect(controller.error, isNotNull, reason: '次数上限耗尽后必须停止重试并报错');
    });

    test('找不到同名影片时不切源，最终显示错误', () async {
      useFakeApi(crossClient(name: '完全不同的另一部片'));
      await mount(
        extraSources: <VodSource>[sourceOf('备用站', host: 'b.com')],
      );

      await fail();
      await fail();
      await fail('全部失败');

      expect(controller.task.source.name, '主站');
      expect(controller.error, '全部失败');
      expect(controller.fallbackNotice, isNull);
    });
  });

  group('重试', () {
    test('retry 清空提示与错误，按当前任务重新打开', () async {
      useFakeApi(crossClient());
      await mount(
        extraSources: <VodSource>[sourceOf('备用站', host: 'b.com')],
      );
      await fail();
      await fail();
      await fail();
      expect(controller.task.source.name, '备用站');
      final int opensBefore = rig.platform.opens.length;

      await controller.retry();
      await rig.settle(16);
      expect(controller.fallbackNotice, isNull);
      expect(controller.fallbackTrying, isNull);
      expect(controller.error, isNull);
      expect(rig.platform.opens.length, opensBefore + 1);
      // 跨源切换后任务已指向备用站，重试是重开当前片子，不是回到最初的主站。
      expect(rig.platform.opens.last, 'https://b.com/1.m3u8');
    });

    test('retry 后跨源次数归零，还能再切到另一个源', () async {
      useFakeApi(crossClient());
      await mount(
        extraSources: <VodSource>[
          sourceOf('备用站1', host: 'b.com'),
          sourceOf('备用站2', host: 'c.com'),
        ],
      );
      await fail();
      await fail();
      await fail();
      expect(controller.task.source.name, '备用站1');

      await controller.retry();
      await rig.settle(16);
      // 计数若不归零，这里就会卡在「已切过 1 次」而直接报错。
      await fail();
      expect(controller.task.source.name, '备用站2');
      expect(rig.platform.opens.last, 'https://c.com/1.m3u8');
    });
  });

  group('手动换源', () {
    test('只有一个启用的源时没有换源入口，也不发请求', () async {
      final FakeHttpClient client = crossClient();
      useFakeApi(client);
      await mount();

      expect(controller.canSwitchSource, isFalse);
      expect(await controller.findAlternateSources(), isEmpty);
      expect(client.requests, isEmpty);
    });

    test('查找其它源时按「片名 + 同集」给出候选', () async {
      final FakeHttpClient client = crossClient();
      useFakeApi(client);
      await mount(
        extraSources: <VodSource>[sourceOf('备用站', host: 'b.com')],
      );

      expect(controller.canSwitchSource, isTrue);
      final List<PlayerSourceOption> options =
          await controller.findAlternateSources();

      expect(options, hasLength(1));
      expect(options.single.id, isNotEmpty);
      expect(options.single.label, '备用站');
      expect(options.single.episodeLabel, 'm3u8 · 第01集');
      expect(client.last.url.host, 'b.com');
    });

    test('切过去后任务与播放地址都换成新源', () async {
      useFakeApi(crossClient());
      await mount(
        extraSources: <VodSource>[sourceOf('备用站', host: 'b.com')],
      );
      final List<PlayerSourceOption> options =
          await controller.findAlternateSources();

      await controller.switchToSource(options.single.id);
      await rig.settle(16);

      expect(controller.task.source.name, '备用站');
      expect(rig.platform.opens.last, 'https://b.com/1.m3u8');
      expect(controller.error, isNull);
      expect(controller.fallbackNotice, contains('备用站'));
    });

    test('未知的源 id 直接忽略，不打断当前播放', () async {
      useFakeApi(crossClient());
      await mount(
        extraSources: <VodSource>[sourceOf('备用站', host: 'b.com')],
      );
      final int before = rig.platform.opens.length;

      await controller.switchToSource('不存在的源');
      await rig.settle(16);

      expect(rig.platform.opens, hasLength(before));
      expect(controller.task.source.name, '主站');
    });

    test('手动换源不计入自动降级的次数上限', () async {
      useFakeApi(crossClient());
      await mount(
        extraSources: <VodSource>[
          sourceOf('备用站1', host: 'b.com'),
          sourceOf('备用站2', host: 'c.com'),
        ],
      );

      // 先用自动降级把次数用满（上限 2 次，这里只走 1 次）。
      await fail();
      await fail();
      await fail();
      expect(controller.task.source.name, '备用站1');

      // 手动再换一次：不重置的话下面的自动降级会立刻拒绝。
      final List<PlayerSourceOption> options =
          await controller.findAlternateSources();
      expect(options, isNotEmpty);
      await controller.switchToSource(options.first.id);
      await rig.settle(16);

      expect(controller.task.source.name, '备用站2');
      expect(rig.platform.opens.last, 'https://c.com/1.m3u8');
      expect(controller.error, isNull);
    });
  });
}
