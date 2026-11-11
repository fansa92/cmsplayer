import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:cms_player/core/theme/app_theme.dart';
import 'package:cms_player/data/models/vod_category.dart';
import 'package:cms_player/data/models/vod_item.dart';
import 'package:cms_player/data/models/vod_source.dart';
import 'package:cms_player/state/browse_store.dart';
import 'package:cms_player/state/history_store.dart';
import 'package:cms_player/ui/pages/category_page.dart';
import 'package:cms_player/ui/shell/lazy_indexed_stack.dart';
import 'package:cms_player/ui/widgets/cached_image.dart';
import 'package:cms_player/ui/widgets/poster_skeleton.dart';
import 'package:cms_player/ui/widgets/vod_card.dart';
import 'package:cms_player/ui/widgets/vod_grid.dart';

import 'helpers/fakes.dart';

void main() {
  group('页签懒挂载', () {
    testWidgets('冷启动只创建当前页，切过去的页才第一次创建', (WidgetTester tester) async {
      final List<int> built = <int>[];
      Widget host(int index) => MaterialApp(
            home: LazyIndexedStack(
              index: index,
              itemCount: 5,
              builder: (int i) {
                built.add(i);
                return Text('页面$i');
              },
            ),
          );

      await tester.pumpWidget(host(0));
      expect(built.toSet(), <int>{0}, reason: '首屏不应该创建另外 4 个页面');
      expect(built.contains(1), isFalse);
      expect(built.contains(2), isFalse);

      await tester.pumpWidget(host(2));
      expect(built.contains(2), isTrue);
      expect(built.contains(1), isFalse, reason: '没访问过的页仍然不该被创建');
      expect(built.contains(3), isFalse);

      // 回到首页，已经访问过的搜索页继续保活，不会再被卸载。
      await tester.pumpWidget(host(0));
      expect(find.text('页面2', skipOffstage: false), findsOneWidget);
      expect(built.contains(4), isFalse);
    });
  });

  group('海报骨架屏', () {
    testWidgets('静态模式能按断点铺开且带语义标签', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PosterGridSkeleton(animate: false, itemCount: 8),
          ),
        ),
      );

      expect(find.bySemanticsLabel('正在加载内容'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('动画模式也能正常构建（不依赖 pumpAndSettle）', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: PosterGridSkeleton(itemCount: 2)),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
      // 显式卸载，确保 repeat 的 AnimationController 在测试收尾前被 dispose。
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('海报卡片语义', () {
    testWidgets('片名、角标、来源合并成一条可读标签', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 120,
              height: 240,
              child: VodCard(
                item: VodItem(
                  id: 1,
                  name: '庆余年',
                  remarks: '更新至第10集',
                  typeName: '电视剧',
                ),
                sourceLabel: '测试站',
                onTap: () {},
              ),
            ),
          ),
        ),
      );

      expect(
        find.bySemanticsLabel('庆余年，更新至第10集，测试站'),
        findsOneWidget,
      );
      expect(find.byTooltip('庆余年'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('无限滚动', () {
    testWidgets('请求还在飞时重复触发不会重复加载一页', (WidgetTester tester) async {
      final Completer<void> gate = Completer<void>();
      int calls = 0;
      Future<void> load() async {
        calls++;
        await gate.future;
      }

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 400,
              child: VodGrid(
                items: <VodItem>[
                  VodItem(id: 1, name: '片一'),
                  VodItem(id: 2, name: '片二'),
                ],
                canLoadMore: true,
                onLoadMore: load,
                onTap: (_) {},
              ),
            ),
          ),
        ),
      );

      final Finder more = find.byTooltip('加载更多');
      expect(more, findsOneWidget);
      await tester.tap(more);
      await tester.pump();
      await tester.tap(more);
      await tester.pump();
      expect(calls, 1);

      gate.complete();
      await tester.pump();
    });
  });

  group('图片内存缓存', () {
    setUp(CachedImage.clearMemoryCache);
    tearDown(CachedImage.clearMemoryCache);

    test('超过 48MB 后按字节淘汰，而不是按条目数', () {
      final Uint8List oneMb = Uint8List(1024 * 1024);
      for (int i = 0; i < 60; i++) {
        CachedImage.putMemoryCache('u$i', oneMb);
      }
      expect(CachedImage.memoryBytes, lessThanOrEqualTo(48 * 1024 * 1024));
      expect(CachedImage.memoryBytes, greaterThan(0));
    });

    test('重新写入会把条目移到 LRU 末尾，不被优先淘汰', () {
      final Uint8List oneMb = Uint8List(1024 * 1024);
      for (int i = 0; i < 48; i++) {
        CachedImage.putMemoryCache('u$i', oneMb);
      }
      CachedImage.putMemoryCache('u0', oneMb);
      CachedImage.putMemoryCache('new', oneMb);

      expect(CachedImage.hasMemoryCache('u0'), isTrue);
      expect(CachedImage.hasMemoryCache('u1'), isFalse);
      expect(CachedImage.hasMemoryCache('new'), isTrue);
    });

    test('清空后字节计数归零', () {
      CachedImage.putMemoryCache('x', Uint8List(1024));
      expect(CachedImage.memoryBytes, 1024);
      CachedImage.clearMemoryCache();
      expect(CachedImage.memoryBytes, 0);
    });
  });

  group('主题补全', () {
    test('明暗主题都带齐桌面交互需要的字段', () {
      for (final ThemeData theme in <ThemeData>[
        AppTheme.light(),
        AppTheme.dark(),
      ]) {
        expect(theme.scrollbarTheme.thickness, isNotNull);
        expect(theme.tooltipTheme.decoration, isNotNull);
        expect(theme.bottomSheetTheme.shape, isNotNull);
        expect(theme.textSelectionTheme.cursorColor, isNotNull);
        expect(theme.filledButtonTheme.style?.shape, isNotNull);
        expect(theme.visualDensity, isNotNull);
      }
    });
  });

  group('窄屏布局', () {
    testWidgets('分类筛选栏在 360 / 800 两种宽度都不溢出', (WidgetTester tester) async {
      for (final Size size in <Size>[
        const Size(360, 640),
        const Size(800, 600),
      ]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<BrowseStore>.value(
                value: _FakeBrowse(),
              ),
              ChangeNotifierProvider<HistoryStore>.value(
                value: HistoryStore(),
              ),
            ],
            child: const MaterialApp(
              home: Scaffold(body: CategoryPage()),
            ),
          ),
        );
        await tester.pump();

        expect(find.text('2024'), findsOneWidget);
        expect(find.text('清除筛选'), findsOneWidget);
        expect(tester.takeException(), isNull,
            reason: '${size.width}dp 下不应有 RenderFlex overflow');
      }
    });
  });
}

/// 只覆盖筛选栏会读到的字段，让页面停在空态（不含动画、不发网络请求），
/// 同时把 year / area / sortBy / total 全部顶到最宽，用来复现溢出。
class _FakeBrowse extends BrowseStore {
  @override
  VodSource? get source => sourceOf('测试站');

  @override
  bool get loading => false;

  @override
  List<VodItem> get items => const <VodItem>[];

  @override
  String? get error => null;

  @override
  List<VodCategory> get selectableCategories => const <VodCategory>[];

  @override
  int get typeId => 0;

  @override
  String get year => '2024';

  @override
  String get area => '美国';

  @override
  String get sortBy => 'hits';

  @override
  bool get hasFilter => true;

  @override
  int get total => 12345;

  @override
  int get pageNo => 1;

  @override
  int get pageCount => 99;
}
