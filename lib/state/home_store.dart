import 'package:flutter/foundation.dart';

import '../core/logger.dart';
import '../data/api/maccms_api.dart';
import '../data/models/paged_result.dart';
import '../data/models/vod_item.dart';
import '../data/models/vod_source.dart';
import '../data/repository/vod_repository.dart';

/// 首页的一个横排板块。
@immutable
class HomeSection {
  const HomeSection({
    required this.id,
    required this.title,
    required this.items,
  });

  /// 板块标识，同时用于「和前面板块是不是同一批内容」的去重判断。
  final String id;
  final String title;
  final List<VodItem> items;
}

/// 首页的多板块推荐。
///
/// 首页主体网格（最近更新）仍归 [BrowseStore]，这里只管网格上方那几条
/// 横排：今日热播、本月热门、高分佳作。
///
/// 三个板块之间没有任何依赖，所以逐个串行拉：部分资源站（实测
/// cj.ffzyapi.com）对短时间内连发的请求会降级返回，并发三轮很容易把
/// 其中两个打成失败。串行的代价是首屏慢一两秒，换来的是板块更稳。
class HomeStore extends ChangeNotifier {
  /// 每个板块取多少条。
  static const int sectionSize = 12;

  /// 与已有板块的重合度超过这个比例就认为内容一样，不再重复展示。
  ///
  /// 站点不认 `h` / `m` 时 [MacCmsApi.hot] 会退化成「第一个分类的最新
  /// 内容」，那时两个热播板块和网格几乎是同一批片子。
  static const double _duplicateRatio = 0.8;

  VodSource? _source;
  List<HomeSection> _sections = <HomeSection>[];
  bool _loading = false;
  bool _disposed = false;

  /// 每次刷新自增，用来丢弃被后来者取代的那一轮结果。
  int _stamp = 0;

  VodSource? get source => _source;
  List<HomeSection> get sections => _sections;
  bool get loading => _loading;
  bool get isEmpty => _sections.isEmpty;

  void _emit() {
    if (_disposed) return;
    notifyListeners();
  }

  Future<void> attach(VodSource source, {bool force = false}) async {
    if (_source?.id == source.id && !force) return;
    _source = source;
    _sections = <HomeSection>[];
    _emit();
    await refresh(force: force);
  }

  Future<void> refresh({bool force = false}) async {
    final VodSource? source = _source;
    if (source == null) return;

    final int stamp = ++_stamp;
    _loading = true;
    _emit();

    final List<HomeSection> next = <HomeSection>[];
    for (final _SectionSpec spec in _specs) {
      // 被新一轮刷新（换源 / 下拉刷新）取代了，收尾交给它。
      if (stamp != _stamp) return;
      try {
        final List<VodItem> items = await spec.load(source, force);
        if (items.isEmpty) continue;
        if (_tooSimilar(items, next)) {
          AppLog.d('Home', 'section ${spec.id} duplicates a previous one');
          continue;
        }
        next.add(HomeSection(id: spec.id, title: spec.title, items: items));
      } on Object catch (e) {
        // 单个板块失败就当它不存在，不能让整页变成错误态。
        AppLog.d('Home', 'section ${spec.id} failed: $e');
      }
    }

    if (stamp != _stamp) return;
    _sections = next;
    _loading = false;
    _emit();
  }

  bool _tooSimilar(List<VodItem> candidate, List<HomeSection> existing) {
    if (existing.isEmpty) return false;
    final Set<int> ids = candidate.map((VodItem e) => e.id).toSet();
    if (ids.isEmpty) return true;
    final int threshold = (ids.length * _duplicateRatio).ceil();
    for (final HomeSection section in existing) {
      final Set<int> prev = section.items.map((VodItem e) => e.id).toSet();
      if (ids.intersection(prev).length >= threshold) return true;
    }
    return false;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class _SectionSpec {
  const _SectionSpec(this.id, this.title, this.load);

  final String id;
  final String title;
  final Future<List<VodItem>> Function(VodSource source, bool force) load;
}

final List<_SectionSpec> _specs = <_SectionSpec>[
  _SectionSpec('day', '今日热播', (VodSource source, bool force) async {
    final VodPage page = await VodRepository.instance.hot(
      source: source,
      pageSize: HomeStore.sectionSize,
      window: HotWindow.day,
      force: force,
    );
    return page.items;
  }),
  _SectionSpec('month', '本月热门', (VodSource source, bool force) async {
    final VodPage page = await VodRepository.instance.hot(
      source: source,
      pageSize: HomeStore.sectionSize,
      window: HotWindow.month,
      force: force,
    );
    return page.items;
  }),
  _SectionSpec('score', '高分佳作', (VodSource source, bool force) async {
    final VodPage page = await VodRepository.instance.query(
      source: source,
      pageSize: HomeStore.sectionSize,
      sortBy: 'score',
      detail: true,
      force: force,
    );
    return page.items;
  }),
];
