import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:cms_player/core/storage/settings_store.dart';
import 'package:cms_player/data/models/subscription.dart';
import 'package:cms_player/data/models/vod_source.dart';
import 'package:cms_player/state/source_store.dart';
import 'package:cms_player/state/subscription_store.dart';

import 'helpers/fakes.dart';

/// 订阅：整包导入、增量更新、下线源只停用、过期自动刷新。
void main() {
  useIsolatedStores();

  String sourceList(List<Map<String, String>> items) => jsonEncode(items);

  Map<String, String> entry(String name, String host) => <String, String>{
        'name': name,
        'api': 'https://$host/api.php/provide/vod/',
      };

  Future<(SourceStore, SubscriptionStore)> mount() async {
    final SettingsStore settings = SettingsStore();
    await settings.init();
    final SourceStore sources = SourceStore(settings);
    await sources.load();
    // 首次启动会塞一个内置示例源，先清掉，断言才数得准。
    await sources.removeMany(
      sources.sources.map((VodSource s) => s.id).toList(growable: false),
    );
    final SubscriptionStore subs = SubscriptionStore(sources);
    await subs.load();
    return (sources, subs);
  }

  test('首次刷新把整包源导入，并记下来源清单', () async {
    final (SourceStore sources, SubscriptionStore subs) = await mount();
    SubscriptionStore.fetcher = (String url) async => sourceList(<Map<String, String>>[
          entry('A站', 'a.com'),
          entry('B站', 'b.com'),
          entry('C站', 'c.com'),
        ]);

    final Subscription sub = await subs.add(
      name: '常用',
      url: 'https://example.com/list.json',
    );
    final SubscribeResult result = await subs.refresh(sub);

    expect(result.added, 3);
    expect(result.updated, 0);
    expect(result.offline, 0);
    expect(result.total, 3);
    expect(sources.sources.length, 3);
    expect(
      sources.sources.map((VodSource s) => s.name),
      <String>['A站', 'B站', 'C站'],
    );

    final Subscription saved = subs.items.single;
    expect(saved.lastFetchedAt, isNotNull);
    expect(saved.sourceCount, 3);
    expect(saved.sourceIds.length, 3);
    expect(saved.lastError, isEmpty);
  });

  test('再次刷新：新增的加入、消失的只停用不删除', () async {
    final (SourceStore sources, SubscriptionStore subs) = await mount();
    SubscriptionStore.fetcher =
        (String url) async => sourceList(<Map<String, String>>[
              entry('A站', 'a.com'),
              entry('B站', 'b.com'),
            ]);

    final Subscription sub =
        await subs.add(name: '常用', url: 'https://example.com/list.json');
    await subs.refresh(sub);

    // 第二次：B 从订阅里消失，换成 D。
    SubscriptionStore.fetcher =
        (String url) async => sourceList(<Map<String, String>>[
              entry('A站', 'a.com'),
              entry('D站', 'd.com'),
            ]);
    final SubscribeResult second = await subs.refresh(subs.items.single);

    expect(second.added, 1);
    expect(second.updated, 1);
    expect(second.offline, 1);
    expect(second.total, 2);

    // B 还在列表里，只是被停用；D 是新来的。
    expect(
      sources.sources.map((VodSource s) => s.name),
      containsAll(<String>['A站', 'B站', 'D站']),
    );
    final VodSource b =
        sources.sources.firstWhere((VodSource s) => s.name == 'B站');
    expect(b.enabled, isFalse);
    expect(sources.enabledSources.length, 2);
  });

  test('同一地址重复添加只有一条', () async {
    final (SourceStore _, SubscriptionStore subs) = await mount();
    await subs.add(name: 'A', url: 'https://example.com/list.json');
    await subs.add(name: 'B', url: 'https://example.com/list.json');
    expect(subs.items.length, 1);
    // 后加的名字覆盖前面的，但不会多出一条。
    expect(subs.items.single.name, 'B');
  });

  test('只刷新过期的订阅', () async {
    final (SourceStore _, SubscriptionStore subs) = await mount();
    DateTime now = DateTime(2026, 11, 14, 10);
    SubscriptionStore.clock = () => now;

    int calls = 0;
    SubscriptionStore.fetcher = (String url) async {
      calls++;
      return sourceList(<Map<String, String>>[entry('A站', 'a.com')]);
    };

    final Subscription sub =
        await subs.add(name: '常用', url: 'https://example.com/list.json');
    await subs.refresh(sub);
    expect(calls, 1);

    // 刚拉过：不算过期。
    expect(await subs.refreshStale(), 0);
    expect(calls, 1);

    // 过了 13 小时（阈值 12 小时）：补一轮。
    now = now.add(const Duration(hours: 13));
    expect(await subs.refreshStale(), 1);
    expect(calls, 2);
  });

  test('失败只写在那一条上，不影响其它订阅', () async {
    final (SourceStore _, SubscriptionStore subs) = await mount();
    SubscriptionStore.fetcher = (String url) async {
      if (url.contains('bad')) throw Exception('HTTP 500');
      return sourceList(<Map<String, String>>[entry('A站', 'a.com')]);
    };

    final Subscription bad =
        await subs.add(name: '坏源', url: 'https://bad.com/list.json');
    await subs.add(name: '好源', url: 'https://good.com/list.json');

    await expectLater(subs.refresh(bad), throwsA(isA<Exception>()));
    final Subscription failedFirst = subs.items.firstWhere(
      (Subscription s) => s.id == bad.id,
    );
    expect(failedFirst.lastError, contains('500'));

    final int ok = await subs.refreshAll();
    expect(ok, 1);
    final Subscription failedAgain = subs.items.firstWhere(
      (Subscription s) => s.id == bad.id,
    );
    expect(failedAgain.lastError, contains('500'));
    final Subscription good =
        subs.items.firstWhere((Subscription s) => s.id != bad.id);
    expect(good.lastError, isEmpty);
    expect(good.sourceCount, 1);
  });

  test('停用的订阅不参与自动刷新', () async {
    final (SourceStore _, SubscriptionStore subs) = await mount();
    int calls = 0;
    SubscriptionStore.fetcher = (String url) async {
      calls++;
      return sourceList(<Map<String, String>>[entry('A站', 'a.com')]);
    };

    final Subscription sub =
        await subs.add(name: '常用', url: 'https://example.com/list.json');
    await subs.setEnabled(sub.id, false);

    expect(await subs.refreshStale(), 0);
    expect(await subs.refreshAll(), 0);
    expect(calls, 0);
  });
}
