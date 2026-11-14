import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/utils/debouncer.dart';
import '../../core/utils/responsive.dart';
import '../../data/models/vod_item.dart';
import '../../data/models/vod_source.dart';
import '../../state/app_state.dart';
import '../../state/search_store.dart';
import '../../state/source_store.dart';
import '../navigation.dart';
import '../widgets/empty_state.dart';
import '../widgets/poster_skeleton.dart';
import '../widgets/vod_grid.dart';

/// 搜索页：支持单源搜索与多源并发搜索。
class SearchPage extends StatefulWidget {
  const SearchPage({super.key, this.focusNode});

  /// 由外壳传入的输入焦点。
  ///
  /// 快捷键 `Ctrl/⌘ + F` 要在页面还没挂载时就能"预埋"焦点，所以节点由
  /// shell 持有；为 null 时页面自己建一个（单独使用本页时仍然能用）。
  final FocusNode? focusNode;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage>
    with AutomaticKeepAliveClientMixin {
  final TextEditingController _controller = TextEditingController();
  late final FocusNode _focusNode = widget.focusNode ?? FocusNode();
  late final bool _ownsFocusNode = widget.focusNode == null;

  /// 联想词去抖：敲字段期间不发请求，停下 350ms 才查一次。
  final Debouncer _suggestDebouncer =
      Debouncer(const Duration(milliseconds: 350));

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    final SearchStore store = context.read<SearchStore>();
    _controller.text = store.query;
    store.loadHistory();
  }

  @override
  void dispose() {
    _suggestDebouncer.dispose();
    _controller.dispose();
    if (_ownsFocusNode) _focusNode.dispose();
    super.dispose();
  }

  /// 手动搜索：只有回车、搜索按钮、切换多源、点历史记录才会真的发请求。
  ///
  /// 打字过程不再自动搜（原先 450ms 去抖逐字触发），既省请求，也避免
  /// 快速敲字时对同一源站连打多次而触发 WAF 降级。
  Future<void> _search(String text) async {
    final String q = text.trim();
    final SearchStore store = context.read<SearchStore>();
    _suggestDebouncer.cancel();
    if (q.isEmpty) {
      store.clearResult();
      return;
    }
    await _execute(q);
  }

  void _pickHistory(String q) {
    _controller.text = q;
    _search(q);
  }

  Future<void> _execute(String q) async {
    if (!mounted) return;
    final SourceStore sourceStore = context.read<SourceStore>();
    final bool multi = context.read<AppState>().multiSourceSearch &&
        sourceStore.enabledSources.length > 1;
    await context.read<SearchStore>().search(
          keyword: q,
          active: sourceStore.active,
          all: sourceStore.enabledSources,
          multiSource: multi,
        );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final ThemeData theme = Theme.of(context);
    final SearchStore store = context.watch<SearchStore>();
    final SourceStore sourceStore = context.watch<SourceStore>();
    final bool compact = context.isCompact;

    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  // 桌面端进搜索页直接能打字；手机端不自动弹软键盘。
                  autofocus: PlatformInfo.isDesktop,
                  textInputAction: TextInputAction.search,
                  // 打字只刷新清空按钮的显隐；联想词经过去抖，不会逐字打接口。
                  onChanged: (String value) {
                    setState(() {});
                    final SearchStore store = context.read<SearchStore>();
                    final SourceStore sources = context.read<SourceStore>();
                    final List<VodSource> enabled = sources.enabledSources;
                    final VodSource? target = sources.active ??
                        (enabled.isEmpty ? null : enabled.first);
                    _suggestDebouncer.run(() {
                      if (mounted) store.suggest(value, target);
                    });
                  },
                  onSubmitted: _search,
                  decoration: InputDecoration(
                    hintText: '搜索影片、剧集…',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _controller.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: '清空',
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _controller.clear();
                              _search('');
                              setState(() {});
                            },
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (compact)
                Tooltip(
                  message: '搜索',
                  child: FilledButton.tonal(
                    // 360dp 手机上带「搜索」二字会把输入框压到不足 200dp，
                    // 只留图标，语义交给 Tooltip / 屏幕阅读器。
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(52, 52),
                      padding: EdgeInsets.zero,
                    ),
                    onPressed: () => _search(_controller.text),
                    child: const Icon(Icons.search),
                  ),
                )
              else
                FilledButton.tonalIcon(
                  // 与输入框等高，否则 40px 的按钮贴着 56px 的框会显得没对齐。
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(56, 56),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                  ),
                  onPressed: () => _search(_controller.text),
                  icon: const Icon(Icons.search),
                  label: const Text('搜索'),
                ),
            ],
          ),
        ),
        if (sourceStore.enabledSources.length > 1)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: <Widget>[
                FilterChip(
                  label: Text('搜索全部 ${sourceStore.enabledSources.length} 个源'),
                  selected: store.multiSource,
                  onSelected: (bool v) {
                    store.setMultiSource(v);
                    context.read<AppState>().setMultiSourceSearch(v);
                    if (store.query.isNotEmpty) _search(store.query);
                  },
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    store.multiSource ? '结果会合并去重' : '仅搜索当前源',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                if (store.query.isNotEmpty)
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    icon: const Icon(Icons.compare_arrows, size: 18),
                    label: const Text('全源对比'),
                    onPressed: () => AppRoutes.openCompare(
                      context,
                      title: store.query,
                    ),
                  ),
              ],
            ),
          ),
        if (store.suggestions.isNotEmpty &&
            _controller.text.trim().isNotEmpty &&
            _controller.text.trim() != store.query)
          _SuggestionStrip(words: store.suggestions, onPick: _pickHistory),
        const SizedBox(height: 4),
        Expanded(child: _buildBody(context, store, sourceStore)),
      ],
    );
  }

  Widget _buildBody(
    BuildContext context,
    SearchStore store,
    SourceStore sourceStore,
  ) {
    if (store.query.isEmpty) {
      return _HistoryPanel(store: store, onPick: _pickHistory);
    }

    if (store.loading && store.items.isEmpty) {
      return const PosterGridSkeleton();
    }

    if (store.error != null && store.items.isEmpty) {
      return ErrorState(message: store.error!);
    }

    if (store.items.isEmpty) {
      return EmptyState(
        icon: Icons.search_off,
        title: '没有找到「${store.query}」',
        subtitle: store.multiSource
            ? '换个关键词，或在上面取消「搜索全部源」只搜当前源。'
            : '换个关键词，或开启「搜索全部源」扩大范围。',
      );
    }

    return RefreshIndicator(
      onRefresh: () => store.search(
        keyword: store.query,
        active: sourceStore.active,
        all: sourceStore.enabledSources,
        multiSource: store.multiSource,
      ),
      child: VodGrid(
        items: store.items,
        canLoadMore: store.canLoadMore,
        loadingMore: store.loading,
        onLoadMore: () => store.loadMore(
          active: sourceStore.active,
          all: sourceStore.enabledSources,
        ),
        sourceLabelOf: store.multiSource
            ? (VodItem item) {
                final VodSource? s = store.sourceOf(item);
                if (s == null) return '';
                final int n = store.sourceCountOf(item);
                // 聚合之后一条结果可能来自多个源，标清楚这一条有几个源
                // 可选，用户切源时心里有数。
                return n > 1 ? '${s.name} · $n 源' : s.name;
              }
            : (VodItem item) => '',
        onTap: (VodItem item) {
          final VodSource? source = store.sourceOf(item) ?? sourceStore.active;
          if (source == null) return;
          AppRoutes.openDetail(context, item: item, source: source);
        },
      ),
    );
  }
}

/// 搜索框下方的联想词横条。点一个词等价于「填入 + 回车」。
class _SuggestionStrip extends StatelessWidget {
  const _SuggestionStrip({required this.words, required this.onPick});

  final List<String> words;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 40,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: words.length,
          separatorBuilder: (_, __) => const SizedBox(width: 6),
          itemBuilder: (BuildContext context, int index) => ActionChip(
            label: Text(words[index], overflow: TextOverflow.ellipsis),
            onPressed: () => onPick(words[index]),
          ),
        ),
      );
}

/// 空查询时展示搜索历史。
class _HistoryPanel extends StatelessWidget {
  const _HistoryPanel({required this.store, required this.onPick});

  final SearchStore store;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<String> history = store.history;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                '搜索历史',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (history.isNotEmpty)
              TextButton(
                onPressed: store.clearHistory,
                child: const Text('清空'),
              ),
          ],
        ),
        if (history.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              '输入片名后按回车或点「搜索」。多源模式下会同时查询所有已启用的资源站并合并结果。',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final String q in history)
                InputChip(
                  label: Text(q),
                  onPressed: () => onPick(q),
                  onDeleted: () => store.removeHistory(q),
                ),
            ],
          ),
      ],
    );
  }
}
