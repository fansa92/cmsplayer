import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models/vod_item.dart';
import '../../data/models/vod_source.dart';
import '../../state/app_state.dart';
import '../../state/search_store.dart';
import '../../state/source_store.dart';
import '../navigation.dart';
import '../widgets/empty_state.dart';
import '../widgets/vod_grid.dart';

/// 搜索页：支持单源搜索与多源并发搜索。
class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage>
    with AutomaticKeepAliveClientMixin {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

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
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// 手动搜索：只有回车、搜索按钮、切换多源、点历史记录才会真的发请求。
  ///
  /// 打字过程不再自动搜（原先 450ms 去抖逐字触发），既省请求，也避免
  /// 快速敲字时对同一源站连打多次而触发 WAF 降级。
  Future<void> _search(String text) async {
    final String q = text.trim();
    final SearchStore store = context.read<SearchStore>();
    if (q.isEmpty) {
      store.clearResult();
      return;
    }
    await _execute(q);
  }

  Future<void> _execute(String q) async {
    if (!mounted) return;
    final SourceStore sourceStore = context.read<SourceStore>();
    final bool multi =
        context.read<AppState>().multiSourceSearch && sourceStore.enabledSources.length > 1;
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
                  textInputAction: TextInputAction.search,
                  // 打字只刷新清空按钮的显隐，不发请求。
                  onChanged: (_) => setState(() {}),
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
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
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
    if (store.query.isEmpty) return _HistoryPanel(store: store);

    if (store.loading && store.items.isEmpty) {
      return const PageLoading(label: '正在搜索…');
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
            ? (VodItem item) => store.sourceOf(item)?.name ?? ''
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

/// 空查询时展示搜索历史。
class _HistoryPanel extends StatelessWidget {
  const _HistoryPanel({required this.store});

  final SearchStore store;

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
                  onPressed: () => _refill(context, q),
                  onDeleted: () => store.removeHistory(q),
                ),
            ],
          ),
      ],
    );
  }

  void _refill(BuildContext context, String q) {
    final _SearchPageState? state =
        context.findAncestorStateOfType<_SearchPageState>();
    state?._controller.text = q;
    state?._search(q);
  }
}
