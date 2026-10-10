import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../data/models/vod_category.dart';
import '../../data/models/vod_item.dart';
import '../../data/models/vod_source.dart';
import '../../state/browse_store.dart';
import '../../state/history_store.dart';
import '../widgets/empty_state.dart';
import '../widgets/option_picker.dart';
import '../widgets/vod_grid.dart';
import '../navigation.dart';

/// 分类页：分类导航 + 年代/地区/排序筛选 + 分页网格。
class CategoryPage extends StatelessWidget {
  const CategoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final BrowseStore browse = context.watch<BrowseStore>();
    final VodSource? source = browse.source;
    final HistoryStore history = context.watch<HistoryStore>();

    if (source == null) return const PageLoading();

    final Map<String, String> headers = source.headers;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (browse.selectableCategories.isNotEmpty) _CategoryBar(browse: browse),
        _FilterBar(browse: browse),
        Expanded(child: _buildBody(context, browse, source, headers, history)),
      ],
    );
  }

  Widget _buildBody(
    BuildContext context,
    BrowseStore browse,
    VodSource source,
    Map<String, String> headers,
    HistoryStore history,
  ) {
    if (browse.loading && browse.items.isEmpty) return const PageLoading();

    if (browse.error != null && browse.items.isEmpty) {
      return ErrorState(
        message: browse.error!,
        onRetry: () => browse.refresh(force: true),
      );
    }

    if (browse.items.isEmpty) {
      return EmptyState(
        icon: Icons.search_off,
        title: '这个筛选条件下没有内容',
        subtitle: '换个分类，或清除筛选条件再试试。',
        actionLabel: browse.hasFilter ? '清除筛选' : null,
        onAction: browse.hasFilter ? browse.clearFilter : null,
      );
    }

    return RefreshIndicator(
      onRefresh: () => browse.refresh(force: true),
      child: VodGrid(
        items: browse.items,
        headers: headers,
        canLoadMore: browse.canLoadMore,
        loadingMore: browse.loadingMore,
        onLoadMore: browse.loadMore,
        progressOf: (VodItem item) =>
            history.byIds(source.id, item.id)?.progress ?? 0,
        onTap: (VodItem item) =>
            AppRoutes.openDetail(context, item: item, source: source),
      ),
    );
  }
}

class _CategoryBar extends StatelessWidget {
  const _CategoryBar({required this.browse});

  final BrowseStore browse;

  @override
  Widget build(BuildContext context) {
    final List<VodCategory> categories = browse.selectableCategories;
    return SizedBox(
      height: 46,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: const Text('全部'),
              selected: browse.typeId == 0,
              onSelected: (_) => browse.selectCategory(0),
            ),
          ),
          for (final VodCategory c in categories)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(c.name),
                selected: browse.typeId == c.id,
                onSelected: (_) => browse.selectCategory(c.id),
              ),
            ),
        ],
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.browse});

  final BrowseStore browse;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: <Widget>[
          _FilterButton(
            label: browse.year.isEmpty ? '年代' : browse.year,
            active: browse.year.isNotEmpty,
            onTap: () => _pick(
              context,
              title: '按年代筛选',
              options: K.yearOptions,
              selected: browse.year,
              apply: (String v) => browse.applyFilter(year: v),
            ),
          ),
          const SizedBox(width: 8),
          _FilterButton(
            label: browse.area.isEmpty ? '地区' : browse.area,
            active: browse.area.isNotEmpty,
            onTap: () => _pick(
              context,
              title: '按地区筛选',
              options: K.areaOptions,
              selected: browse.area,
              apply: (String v) => browse.applyFilter(area: v),
            ),
          ),
          const SizedBox(width: 8),
          _FilterButton(
            label: browse.sortBy.isEmpty
                ? '排序'
                : (K.sortOptions[browse.sortBy] ?? browse.sortBy),
            active: browse.sortBy.isNotEmpty,
            onTap: () => _pick(
              context,
              title: '排序方式',
              options: K.sortOptions.values.toList(),
              selected: K.sortOptions[browse.sortBy],
              apply: (String v) {
                final String? key = K.sortOptions.entries
                    .where((MapEntry<String, String> e) => e.value == v)
                    .map((MapEntry<String, String> e) => e.key)
                    .firstOrNull;
                browse.applyFilter(sortBy: key ?? '');
              },
            ),
          ),
          const SizedBox(width: 4),
          if (browse.hasFilter)
            IconButton(
              tooltip: '清除筛选',
              visualDensity: VisualDensity.compact,
              onPressed: browse.clearFilter,
              icon: const Icon(Icons.filter_alt_off_outlined, size: 20),
            ),
          const Spacer(),
          if (browse.total > 0)
            Text(
              '共 ${browse.total} 部 · ${browse.pageNo}/${browse.pageCount} 页',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _pick(
    BuildContext context, {
    required String title,
    required List<String> options,
    required String? selected,
    required void Function(String) apply,
  }) async {
    final String? result = await showOptionPicker(
      context,
      title: title,
      options: options,
      selected: selected,
    );
    if (result == null) return;
    apply(result);
  }
}

class _FilterButton extends StatelessWidget {
  const _FilterButton({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: active
                    ? theme.colorScheme.onPrimaryContainer
                    : theme.colorScheme.onSurfaceVariant,
                fontWeight: active ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.keyboard_arrow_down,
              size: 16,
              color: active
                  ? theme.colorScheme.onPrimaryContainer
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final Iterator<T> it = iterator;
    return it.moveNext() ? it.current : null;
  }
}
