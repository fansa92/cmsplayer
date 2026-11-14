import 'package:flutter_test/flutter_test.dart';

import 'package:cms_player/core/storage/settings_store.dart';
import 'package:cms_player/data/models/source_health.dart';
import 'package:cms_player/data/models/vod_source.dart';
import 'package:cms_player/state/source_health_store.dart';
import 'package:cms_player/state/source_store.dart';

import 'helpers/fakes.dart';

/// 源测速：并发执行、结果档位、排序、落盘。
void main() {
  useIsolatedStores();

  final VodSource fast = sourceOf('快站', host: 'fast.com');
  final VodSource normal = sourceOf('中站', host: 'mid.com');
  final VodSource slow = sourceOf('慢站', host: 'slow.com');
  final VodSource dead = sourceOf('挂站', host: 'dead.com');

  /// 按 host 返回预设延迟；host 不在表里就当失败。
  void serve(Map<String, int> table) {
    SourceHealthStore.prober = (VodSource source) async {
      final int? ms = table[Uri.parse(source.api).host];
      if (ms == null) return -1;
      // 留一点真实等待，让「并发」有机会真的重叠。
      await Future<void>.delayed(Duration(milliseconds: ms ~/ 50 + 1));
      return ms;
    };
  }

  test('并发测速并记录延迟与档位', () async {
    serve(<String, int>{
      'fast.com': 120,
      'mid.com': 500,
      'slow.com': 1200,
      'dead.com': -1,
    });

    final Map<String, SourceHealth> result = await SourceHealthStore.instance
        .probeAll(<VodSource>[fast, normal, slow, dead], concurrency: 2);

    expect(result.length, 4);
    expect(result[fast.id]!.ok, isTrue);
    expect(result[fast.id]!.latencyMs, 120);
    expect(result[fast.id]!.speed, SourceSpeed.fast);
    expect(result[normal.id]!.speed, SourceSpeed.normal);
    expect(result[slow.id]!.speed, SourceSpeed.slow);
    expect(result[dead.id]!.ok, isFalse);
    expect(result[dead.id]!.latencyLabel, '不可用');

    // ranked：可用的按延迟升序，失败的垫底。
    expect(
      SourceHealthStore.instance.ranked.map((SourceHealth h) => h.sourceId),
      <String>[fast.id, normal.id, slow.id, dead.id],
    );
  });

  test('并发数受上限约束', () async {
    int running = 0;
    int peak = 0;
    SourceHealthStore.prober = (VodSource source) async {
      running++;
      peak = peak > running ? peak : running;
      await Future<void>.delayed(const Duration(milliseconds: 12));
      running--;
      return 100;
    };

    await SourceHealthStore.instance.probeAll(
      <VodSource>[fast, normal, slow, dead],
      concurrency: 2,
    );

    expect(peak, lessThanOrEqualTo(2));
  });

  test('按速度排序：失败与未测的留在后面，保持原有相对顺序', () async {
    serve(<String, int>{'fast.com': 600, 'mid.com': 80, 'slow.com': 900});

    await SourceHealthStore.instance
        .probeAll(<VodSource>[fast, normal, slow]);

    final List<String> order = SourceHealthStore.instance.orderBySpeed(
      <VodSource>[fast, normal, slow, dead],
    );

    // mid 最快，其次 fast，再 slow；dead 没测过，排最后。
    expect(order, <String>[normal.id, fast.id, slow.id, dead.id]);
  });

  test('测速结果会落盘，重启后还能读到', () async {
    serve(<String, int>{'fast.com': 240});

    final SourceHealth health =
        await SourceHealthStore.instance.probeOne(fast);
    expect(health.latencyMs, 240);

    SourceHealthStore.instance.resetForTest();
    await SourceHealthStore.instance.ensureLoaded();

    final SourceHealth? reloaded = SourceHealthStore.instance.of(fast.id);
    expect(reloaded, isNotNull);
    expect(reloaded!.latencyMs, 240);
    expect(reloaded.ok, isTrue);
  });

  test('按测速结果重排资源站顺序', () async {
    final SettingsStore settings = SettingsStore();
    await settings.init();
    final SourceStore store = SourceStore(settings);
    await store.load();
    // 首次启动会带一个内置示例源，先清掉，只留下面三个。
    await store.removeMany(
      store.sources.map((VodSource s) => s.id).toList(growable: false),
    );
    await store.add(dead);
    await store.add(slow);
    await store.add(fast);

    SourceHealthStore.instance.seedForTest(<SourceHealth>[
      SourceHealth(
        sourceId: fast.id,
        latencyMs: 90,
        checkedAt: DateTime.now(),
      ),
      SourceHealth(
        sourceId: slow.id,
        latencyMs: 900,
        checkedAt: DateTime.now(),
      ),
    ]);

    await store.applyOrder(
      SourceHealthStore.instance.orderBySpeed(store.sources),
    );

    expect(
      store.sources.map((VodSource s) => s.name),
      <String>['快站', '慢站', '挂站'],
    );
    expect(store.sources.map((VodSource s) => s.sort), <int>[0, 1, 2]);
    store.dispose();
  });

  test('清理不存在的源', () async {
    serve(<String, int>{'fast.com': 100, 'mid.com': 100});
    await SourceHealthStore.instance.probeAll(<VodSource>[fast, normal]);

    await SourceHealthStore.instance.pruneTo(<String>[fast.id]);

    expect(SourceHealthStore.instance.of(fast.id), isNotNull);
    expect(SourceHealthStore.instance.of(normal.id), isNull);
  });
}
