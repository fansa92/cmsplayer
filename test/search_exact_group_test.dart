import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cms_player/data/models/vod_item.dart';
import 'package:cms_player/data/models/vod_source.dart';
import 'package:cms_player/state/search_store.dart';
import 'package:cms_player/ui/widgets/grouped_vod_grid.dart';
import 'package:cms_player/ui/widgets/vod_card.dart';

import 'helpers/fakes.dart';

/// 搜索的精确匹配与按源分组。
void main() {
  useIsolatedStores();

  final VodSource a = sourceOf('甲站', host: 'a.com');
  final VodSource b = sourceOf('乙站', host: 'b.com');

  Map<String, Object> raw(int id, String name) => <String, Object>{
        'vod_id': id,
        'vod_name': name,
        'vod_play_from': '',
        'vod_play_url': '',
      };

  VodItem vod(int id, String name) => VodItem.fromJson(raw(id, name));

  /// 两个站给出交叉的结果：同名片两边都有，另外各有一部独有。
  void serveTwoSources() {
    useFakeApi(
      FakeHttpClient((RecordedRequest r) {
        final List<Map<String, Object>> list = r.url.host == 'a.com'
            ? <Map<String, Object>>[
                raw(1, '庆余年'),
                raw(2, '庆余年 第二季'),
                raw(3, '繁花'),
              ]
            : <Map<String, Object>>[
                raw(11, '庆余年'),
                raw(12, '庆余年之风起'),
              ];
        return fakeJson(vodPageJson(list: list, total: list.length));
      }),
    );
  }

  test('多源搜索记录逐源命中，聚合视图仍然去重', () async {
    serveTwoSources();
    final SearchStore store = SearchStore();
    await store.search(
      keyword: '庆余年',
      active: a,
      all: <VodSource>[a, b],
      multiSource: true,
    );

    // 聚合后：庆余年（两源合并）、第二季、繁花、之风起。
    expect(store.items.length, 4);
    expect(
      store.items.map((VodItem e) => e.name).toList(),
      <String>['庆余年', '庆余年 第二季', '繁花', '庆余年之风起'],
    );

    final List<SourceHit> hits = store.sourceHits;
    expect(hits.length, 2);
    expect(hits.first.source.name, '甲站');
    expect(hits.first.items.length, 3);
    expect(hits.last.items.length, 2);
  });

  test('精确模式只留片名完全一致的条目', () async {
    serveTwoSources();
    final SearchStore store = SearchStore();
    await store.search(
      keyword: '庆余年',
      active: a,
      all: <VodSource>[a, b],
      multiSource: true,
      exact: true,
    );

    expect(store.exact, isTrue);
    expect(store.items.map((VodItem e) => e.name).toList(), <String>['庆余年']);
    // 两个站都各剩一条同名结果，分组还在。
    expect(store.sourceHits.length, 2);
    expect(store.sourceHits.every((SourceHit h) => h.items.length == 1), isTrue);
  });

  test('精确模式对带括号 / 版本后缀的片名仍然算同一部', () async {
    useFakeApi(
      FakeHttpClient((RecordedRequest r) => fakeJson(vodPageJson(
            list: <Map<String, Object>>[
              raw(1, '繁花(2023)'),
              raw(2, '繁花 国语版'),
              raw(3, '繁花似锦'),
            ],
            total: 3,
          ))),
    );
    final SearchStore store = SearchStore();
    await store.search(
      keyword: '繁花',
      active: a,
      all: <VodSource>[a],
      exact: true,
    );
    // 「繁花(2023)」和「繁花 国语版」归一化后是同一部，聚合时会并成一条；
    // 真正该被排除的是「繁花似锦」。
    expect(store.items.length, 1);
    expect(store.items.single.name, anyOf('繁花(2023)', '繁花 国语版'));
    expect(
      store.items.any((VodItem e) => e.name == '繁花似锦'),
      isFalse,
    );
  });

  testWidgets('分组网格可以逐组收起与展开', (WidgetTester tester) async {
    final List<SourceHit> hits = <SourceHit>[
      SourceHit(
        source: a,
        items: <VodItem>[vod(1, '甲一'), vod(2, '甲二')],
      ),
      SourceHit(source: b, items: <VodItem>[vod(3, '乙一')]),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GroupedVodGrid(
            hits: hits,
            onTap: (SourceHit _, int __) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('甲站'), findsOneWidget);
    expect(find.text('2 部'), findsOneWidget);
    expect(find.byType(VodCard), findsNWidgets(3));

    await tester.tap(find.text('甲站'));
    await tester.pumpAndSettle();

    expect(find.text('已收起'), findsOneWidget);
    expect(find.byType(VodCard), findsNWidgets(1));

    await tester.tap(find.text('甲站'));
    await tester.pumpAndSettle();
    expect(find.byType(VodCard), findsNWidgets(3));
  });
}
