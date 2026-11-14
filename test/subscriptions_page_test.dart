import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:cms_player/core/storage/settings_store.dart';
import 'package:cms_player/state/source_store.dart';
import 'package:cms_player/state/subscription_store.dart';
import 'package:cms_player/ui/pages/subscriptions_page.dart';

import 'helpers/fakes.dart';

/// 订阅页：空态、添加入口、列表里的状态文案。
void main() {
  useIsolatedStores();

  late SourceStore sources;
  late SubscriptionStore subs;

  Future<void> mount(WidgetTester tester) async {
    final SettingsStore settings = SettingsStore();
    await tester.runAsync(settings.init);
    sources = SourceStore(settings);
    await tester.runAsync(sources.load);
    subs = SubscriptionStore(sources);
    await tester.runAsync(subs.load);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SourceStore>.value(value: sources),
          ChangeNotifierProvider<SubscriptionStore>.value(value: subs),
        ],
        child: const MaterialApp(home: SubscriptionsPage()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('没有订阅时给出引导，并能打开添加弹窗', (WidgetTester tester) async {
    await mount(tester);

    expect(find.text('还没有订阅'), findsOneWidget);
    expect(find.textContaining('粘贴一个源列表地址'), findsOneWidget);

    await tester.tap(find.widgetWithText(FloatingActionButton, '添加订阅'));
    await tester.pumpAndSettle();

    expect(find.text('订阅地址'), findsOneWidget);
    expect(find.text('名称（可留空）'), findsOneWidget);
  });

  testWidgets('列表显示源数量与更新时间', (WidgetTester tester) async {
    await mount(tester);

    await tester.runAsync(() async {
      final sub = await subs.add(
        name: '常用源',
        url: 'https://example.com/list.json',
      );
      // 直接构造一次"已刷新"的状态，避开真实网络。
      SubscriptionStore.fetcher = (String url) async =>
          '[{"name":"A站","api":"https://a.com/api.php/provide/vod/"}]';
      await subs.refresh(sub);
    });
    await tester.pumpAndSettle();

    expect(find.text('常用源'), findsOneWidget);
    expect(find.textContaining('1 个源'), findsOneWidget);
    expect(find.text('https://example.com/list.json'), findsOneWidget);
  });
}
