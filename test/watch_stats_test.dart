import 'package:flutter_test/flutter_test.dart';

import 'package:cms_player/state/watch_stats_store.dart';

import 'helpers/fakes.dart';

/// 观看时长统计的聚合逻辑：按天 / 按片 / 按来源、连续天数、裁剪、落盘。
void main() {
  useIsolatedStores();

  final DateTime now = DateTime.now();
  final DateTime today = DateTime(now.year, now.month, now.day);
  final DateTime yesterday = today.subtract(const Duration(days: 1));
  final DateTime twoDaysAgo = today.subtract(const Duration(days: 2));

  final WatchStatsStore store = WatchStatsStore.instance;

  Future<void> seed() async {
    // 今天看《庆余年》45 分钟（跨两个源），昨天 30 分钟，前天 10 分钟。
    await store.add(
      title: '庆余年',
      sourceId: 'a',
      sourceName: 'A 站',
      watched: const Duration(minutes: 30),
      at: today.add(const Duration(hours: 9)),
    );
    await store.add(
      title: '庆余年',
      sourceId: 'b',
      sourceName: 'B 站',
      watched: const Duration(minutes: 15),
      at: today.add(const Duration(hours: 10)),
    );
    await store.add(
      title: '庆余年',
      sourceId: 'a',
      sourceName: 'A 站',
      watched: const Duration(minutes: 30),
      at: yesterday.add(const Duration(hours: 20)),
    );
    await store.add(
      title: '繁花',
      sourceId: 'a',
      sourceName: 'A 站',
      watched: const Duration(minutes: 10),
      at: twoDaysAgo.add(const Duration(hours: 21)),
    );
  }

  test('按天汇总与本周总时长', () async {
    await seed();

    expect(store.secondsOn(today), 45 * 60);
    expect(store.secondsOn(yesterday), 30 * 60);
    expect(store.secondsOn(twoDaysAgo), 10 * 60);
    expect(store.totalSeconds, 85 * 60);
    expect(store.weekSeconds(), 85 * 60);
    // 今天 / 昨天 / 前天都有记录。
    expect(store.streakDays(), 3);

    final List<DayUsage> days = store.recentDays(7);
    expect(days.length, 7);
    expect(days.last.seconds, 45 * 60);
    expect(days[days.length - 2].seconds, 30 * 60);
  });

  test('同名跨源合并，片单按时长排序', () async {
    await seed();

    final List<TitleUsage> tops = store.topTitles(limit: 5);
    expect(tops.length, 2);
    expect(tops.first.title, '庆余年');
    expect(tops.first.seconds, 75 * 60);
    expect(tops[1].title, '繁花');

    // 跨源合并后「看过的片」是 2 部，而不是 3 条记录。
    expect(store.titleCount, 2);
    expect(store.activeDays, 3);
  });

  test('按来源汇总', () async {
    await seed();

    final List<SourceUsage> sources = store.bySource();
    expect(sources.length, 2);
    expect(sources.first.sourceId, 'a');
    expect(sources.first.seconds, 70 * 60);
    expect(sources[1].sourceId, 'b');
    expect(sources[1].seconds, 15 * 60);
  });

  test('连续天数：中间断一天就从断点归零', () async {
    await store.add(
      title: '庆余年',
      sourceId: 'a',
      sourceName: 'A 站',
      watched: const Duration(minutes: 10),
      at: today.add(const Duration(hours: 9)),
    );
    // 昨天没看，前天看了。
    await store.add(
      title: '庆余年',
      sourceId: 'a',
      sourceName: 'A 站',
      watched: const Duration(minutes: 10),
      at: twoDaysAgo.add(const Duration(hours: 21)),
    );

    expect(store.streakDays(), 1);
  });

  test('今天还没看时，连续天数从昨天往前数', () async {
    await store.add(
      title: '庆余年',
      sourceId: 'a',
      sourceName: 'A 站',
      watched: const Duration(minutes: 20),
      at: yesterday.add(const Duration(hours: 21)),
    );
    await store.add(
      title: '庆余年',
      sourceId: 'a',
      sourceName: 'A 站',
      watched: const Duration(minutes: 20),
      at: twoDaysAgo.add(const Duration(hours: 21)),
    );

    expect(store.secondsOn(today), 0);
    expect(store.streakDays(), 2);
  });

  test('超过保留期的数据会被裁掉', () async {
    await store.add(
      title: '老片',
      sourceId: 'a',
      sourceName: 'A 站',
      watched: const Duration(minutes: 30),
      at: today.subtract(const Duration(days: 200)),
    );

    expect(store.totalSeconds, 0);
  });

  test('落盘后重新加载，数字不变', () async {
    await seed();
    await store.flush();

    store.resetForTest();
    await store.ensureLoaded();

    expect(store.totalSeconds, 85 * 60);
    expect(store.topTitles(limit: 1).first.title, '庆余年');
  });
}
