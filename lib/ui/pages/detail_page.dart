import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SliverConstraints;
import 'package:provider/provider.dart';

import '../../core/utils/responsive.dart';
import '../../data/models/paged_result.dart';
import '../../data/models/play_line.dart';
import '../../data/models/play_record.dart';
import '../../data/models/play_task.dart';
import '../../data/models/vod_item.dart';
import '../../data/models/vod_source.dart';
import '../../data/repository/vod_repository.dart';
import '../../state/app_state.dart';
import '../../state/favorites_store.dart';
import '../../state/history_store.dart';
import '../actions.dart';
import '../navigation.dart';
import '../widgets/cached_image.dart';
import '../widgets/vod_grid.dart';

/// 详情页：影片信息 + 多线路多选集 + 收藏 + 续播。
///
/// 主内容是 sliver 序列而不是一个大的 `SliverToBoxAdapter`：选集用
/// [SliverGrid] 懒构建，几百集的剧只建屏幕上那几十个按钮。
/// 宽屏用 [SliverCrossAxisGroup] 把「海报 + 操作」和「信息 + 选集」
/// 排成左右两栏，仍然各自是 sliver。
///
/// 有播放记录时，首次进入会把线路切到上次看的那条，并把列表滚到那一集
/// 附近。因为网格是懒构建的，"那一集"很可能还不在树里，没法用
/// `ensureVisible`，所以改成算偏移量：网格的滚动位置由
/// `SliverLayoutBuilder` 的 `precedingScrollExtent` 给出，行高和列数
/// 由网格自己的参数推出来，两者相加就是目标位置。
class DetailPage extends StatefulWidget {
  const DetailPage({super.key, required this.item, required this.source});

  final VodItem item;
  final VodSource source;

  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  /// 与选集 [SliverGrid] 的参数保持一致，滚动定位要用它们算行高和列数。
  static const double _episodeExtent = 36;
  static const double _episodeSpacing = 8;
  static const double _episodeMaxCrossExtent = 88;
  static const double _episodeRowPitch = _episodeExtent + _episodeSpacing;

  /// 目标集停在固定工具栏下方这么远，避免正好被压住。
  static const double _resumeTopGap = 72;

  late VodItem _item;
  final ScrollController _scroll = ScrollController();
  bool _loadingDetail = false;
  String? _error;
  int _lineIndex = 0;
  bool _contentExpanded = false;

  /// 续播定位只做一次：之后用户自己切线路、切集，不该被弹回去。
  bool _resumeApplied = false;

  /// 待滚动的目标（线路 + 集），首帧布局完成后消费。
  ({int line, int episode})? _pendingResume;

  /// 「相似推荐」横条的数据。拉不到就整块不显示，不必打扰用户。
  List<VodItem> _similar = <VodItem>[];
  bool _similarLoading = false;

  /// 选集网格最近一次布局的度量，供 [_scrollToPendingResume] 算偏移。
  double? _gridPreceding;
  double? _gridCrossExtent;

  @override
  void initState() {
    super.initState();
    _item = widget.item;
    if (!_item.hasPlayInfo) {
      _loadDetail();
    }
    // list 模式下多半已经带 type_id；没有的话等详情补回来再拉一次。
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeLoadSimilar());
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadDetail({bool force = false}) async {
    setState(() {
      _loadingDetail = true;
      _error = null;
    });
    try {
      final VodItem detail = await VodRepository.instance.ensureDetail(
        source: widget.source,
        item: _item,
        force: force,
      );
      if (!mounted) return;
      setState(() {
        _item = detail;
        _loadingDetail = false;
        if (!detail.hasPlayInfo) {
          _error = '该资源站没有返回播放地址';
        }
      });
      // 详情回来了才可能拿到 type_id。
      _maybeLoadSimilar();
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingDetail = false;
        _error = e.toString();
      });
    }
  }

  // ---------------------------------------------------------------- 相似推荐

  /// 拉同分类下的其它影片。
  ///
  /// 只做一次，失败就静默放弃：推荐位是锦上添花，为了让它在详情页末尾
  /// 冒出来而弹一个错误提示并不划算。
  Future<void> _maybeLoadSimilar() async {
    if (!mounted || _similarLoading || _similar.isNotEmpty) return;
    final int typeId = _item.typeId;
    if (typeId <= 0) return;

    _similarLoading = true;
    try {
      final VodPage page = await VodRepository.instance.query(
        source: widget.source,
        typeId: typeId,
        pageSize: 12,
        detail: true,
      );
      if (!mounted) return;
      setState(() {
        _similar = page.items
            .where((VodItem e) => e.id != _item.id)
            .take(10)
            .toList(growable: false);
      });
    } on Object {
      // 忽略：没有推荐位不影响正常观看。
    } finally {
      _similarLoading = false;
    }
  }

  void _play(int lineIndex, int episodeIndex) {
    final PlayTask task = PlayTask(
      source: widget.source,
      item: _item,
      lineIndex: lineIndex,
      episodeIndex: episodeIndex,
    );
    AppRoutes.openPlayer(context, task: task);
  }

  // ---------------------------------------------------------------- 续播定位

  /// 首次拿到播放地址后，把线路切到上次播放的那条，并安排滚动到那一集。
  ///
  /// 在 build 里调用（此时 [_lineIndex] 还没被这一帧消费，直接改即可），
  /// 详情是异步补的，所以每次 build 都要再试一次，直到成功一次为止。
  void _applyResumeOnce(PlayRecord? record) {
    if (_resumeApplied) return;
    final List<PlayLine> lines = _item.playLines;
    if (record == null || lines.isEmpty) return;

    _resumeApplied = true;
    final int line = _clamp(record.lineIndex, lines.length);
    final int episode =
        _clamp(record.episodeIndex, lines[line].episodes.length);
    _lineIndex = line;
    _pendingResume = (line: line, episode: episode);
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _scrollToPendingResume());
  }

  /// 首帧布局完成后把列表滚到续播的那一集。
  ///
  /// 选集网格是懒的，目标格子可能根本没建出来，所以不能 `ensureVisible`；
  /// 这里用网格的起始滚动位置 + 行号 × 行高算出目标偏移。
  void _scrollToPendingResume() {
    final ({int line, int episode})? pending = _pendingResume;
    final double? preceding = _gridPreceding;
    final double? crossExtent = _gridCrossExtent;
    _pendingResume = null;
    if (!mounted ||
        pending == null ||
        preceding == null ||
        crossExtent == null) {
      return;
    }
    final List<PlayLine> lines = _item.playLines;
    if (pending.line >= lines.length) return;
    final int count = lines[pending.line].episodes.length;
    if (count == 0) return;

    final int columns = math.max(
      1,
      (crossExtent / (_episodeMaxCrossExtent + _episodeSpacing)).ceil(),
    );
    final int visual = context.read<AppState>().episodeOrderReverse
        ? count - 1 - pending.episode
        : pending.episode;
    final int row = visual ~/ columns;

    // 第一行的集本来就贴着页头，滚过去反而会把简介顶走，不值得。
    if (row == 0) return;

    final double target = preceding + row * _episodeRowPitch - _resumeTopGap;
    if (!_scroll.hasClients) return;
    final double upper = _scroll.position.maxScrollExtent;
    if (upper <= 0) return;
    _scroll.animateTo(
      target.clamp(0.0, upper),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final FavoritesStore favorites = context.watch<FavoritesStore>();
    final HistoryStore history = context.watch<HistoryStore>();
    final bool isFavorite = favorites.contains(widget.source.id, _item.id);
    final PlayRecord? record = history.byIds(widget.source.id, _item.id);
    _applyResumeOnce(record);

    final Widget side = _buildSide(theme, isFavorite, favorites, record);
    final List<Widget> mainSlivers = <Widget>[
      SliverToBoxAdapter(child: _buildHeader(theme)),
      ..._buildEpisodeSlivers(theme, record),
      if (_similar.isNotEmpty)
        SliverToBoxAdapter(child: _buildSimilar(theme)),
      SliverToBoxAdapter(child: _buildFooter(theme)),
    ];

    return Scaffold(
      body: CustomScrollView(
        controller: _scroll,
        slivers: <Widget>[
          SliverAppBar(
            expandedHeight: 240,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  CachedImage(url: _item.pic, headers: widget.source.headers),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: <Color>[
                          Colors.black.withValues(alpha: 0.15),
                          Colors.black.withValues(alpha: 0.75),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
            sliver: context.useDetailTwoPane
                ? SliverCrossAxisGroup(
                    slivers: <Widget>[
                      // 214 = 190 的栏宽 + 24 的栏间距。
                      SliverConstrainedCrossAxis(
                        maxExtent: 214,
                        sliver: SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.only(right: 24),
                            child: side,
                          ),
                        ),
                      ),
                      SliverCrossAxisExpanded(
                        flex: 1,
                        sliver: SliverMainAxisGroup(slivers: mainSlivers),
                      ),
                    ],
                  )
                : SliverMainAxisGroup(
                    slivers: <Widget>[
                      ...mainSlivers,
                      const SliverToBoxAdapter(child: SizedBox(height: 20)),
                      SliverToBoxAdapter(child: side),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- 主内容

  Widget _buildHeader(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: Text(
                _item.name.isEmpty ? '未命名' : _item.name,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                ),
              ),
            ),
            if (_item.remarks.isNotEmpty) ...<Widget>[
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: theme.colorScheme.tertiaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _item.remarks,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onTertiaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),
        _MetaChips(
          item: _item,
          onTypeTap: _item.typeId <= 0 || _item.typeName.isEmpty
              ? null
              : () => AppRoutes.openCategory(
                    context,
                    source: widget.source,
                    typeId: _item.typeId,
                    title: _item.typeName,
                  ),
        ),
        if (_item.director.isNotEmpty || _item.actor.isNotEmpty) ...<Widget>[
          const SizedBox(height: 12),
          if (_item.director.isNotEmpty)
            _PeopleLine(
              label: '导演',
              names: _splitNames(_item.director),
              onTap: _openName,
            ),
          if (_item.actor.isNotEmpty)
            _PeopleLine(
              label: '演员',
              names: _splitNames(_item.actor),
              onTap: _openName,
            ),
        ],
        if (_item.content.isNotEmpty) ...<Widget>[
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () => setState(() => _contentExpanded = !_contentExpanded),
            child: Text(
              _item.content,
              maxLines: _contentExpanded ? null : 3,
              overflow: _contentExpanded ? null : TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.6,
              ),
            ),
          ),
          GestureDetector(
            onTap: () => setState(() => _contentExpanded = !_contentExpanded),
            child: Text(
              _contentExpanded ? '收起' : '展开全部',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
        ],
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildSimilar(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '相似推荐',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (_item.typeName.isNotEmpty)
                TextButton(
                  onPressed: _item.typeId <= 0
                      ? null
                      : () => AppRoutes.openCategory(
                            context,
                            source: widget.source,
                            typeId: _item.typeId,
                            title: _item.typeName,
                          ),
                  child: const Text('更多'),
                ),
            ],
          ),
          const SizedBox(height: 6),
          // 详情页本身已经有 16 的页边距，横条不再重复留白，只把左侧对齐。
          VodRow(
            items: _similar,
            headers: widget.source.headers,
            itemWidth: 96,
            padding: EdgeInsets.zero,
            onTap: (VodItem item) => AppRoutes.openDetail(
              context,
              item: item,
              source: widget.source,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Text(
        '内容来自「${widget.source.name}」',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- 侧栏

  Widget _buildSide(
    ThemeData theme,
    bool isFavorite,
    FavoritesStore favorites,
    PlayRecord? record,
  ) {
    final bool canResume = record != null &&
        !record.finished &&
        record.positionMs > 0 &&
        _item.hasPlayInfo;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: AspectRatio(
            aspectRatio: 2 / 3,
            child: CachedImage(
              url: _item.pic,
              headers: widget.source.headers,
              fit: BoxFit.cover,
            ),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 46),
            textStyle: theme.textTheme.titleSmall,
          ),
          icon:
              Icon(canResume ? Icons.play_arrow : Icons.movie_filter_outlined),
          label: Text(
              canResume ? '继续播放' : (_item.hasPlayInfo ? '立即播放' : '暂无可播放内容')),
          onPressed: _item.hasPlayInfo
              ? () {
                  final int li = canResume
                      ? _clamp(record.lineIndex, _item.playLines.length)
                      : (_lineIndex < _item.playLines.length ? _lineIndex : 0);
                  final int ei = canResume ? record.episodeIndex : 0;
                  _play(li, ei);
                }
              : null,
        ),
        if (canResume)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '${record.episodeLabel} · ${record.progressLabel}',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        const SizedBox(height: 10),
        Row(
          children: <Widget>[
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 42)),
                icon: Icon(
                  isFavorite ? Icons.favorite : Icons.favorite_border,
                  size: 18,
                  color: isFavorite ? theme.colorScheme.error : null,
                ),
                label: Text(isFavorite ? '已收藏' : '收藏'),
                onPressed: () async {
                  final bool added = await favorites.toggle(
                    source: widget.source,
                    item: _item,
                  );
                  if (mounted) {
                    AppActions.snack(
                      context,
                      added ? '已加入收藏' : '已取消收藏',
                    );
                  }
                },
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              tooltip: '重新加载详情',
              style: IconButton.styleFrom(minimumSize: const Size(42, 42)),
              onPressed: _loadingDetail ? null : () => _loadDetail(force: true),
              icon: _loadingDetail
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
            ),
          ],
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 42)),
          icon: const Icon(Icons.compare_arrows, size: 18),
          label: const Text('全源对比'),
          onPressed: () => AppRoutes.openCompare(
            context,
            title: _item.name,
            year: _item.year,
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------- 选集

  List<Widget> _buildEpisodeSlivers(ThemeData theme, PlayRecord? record) {
    final List<PlayLine> lines = _item.playLines;

    if (_loadingDetail && lines.isEmpty) {
      return <Widget>[
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
            ),
          ),
        ),
      ];
    }

    if (_error != null && lines.isEmpty) {
      return <Widget>[SliverToBoxAdapter(child: _buildEpisodeError(theme))];
    }

    if (lines.isEmpty) return const <Widget>[];

    final int lineIdx = _lineIndex.clamp(0, lines.length - 1);
    final PlayLine line = lines[lineIdx];
    final bool resumeOnThisLine = record != null && record.lineIndex == lineIdx;
    final bool reverse = context.watch<AppState>().episodeOrderReverse;
    final List<int> order = reverse
        ? <int>[for (int i = line.episodes.length - 1; i >= 0; i--) i]
        : <int>[for (int i = 0; i < line.episodes.length; i++) i];

    return <Widget>[
      SliverToBoxAdapter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '播放线路',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            if (lines.length > 1)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (int i = 0; i < lines.length; i++)
                    ChoiceChip(
                      label: Text(
                          '${lines[i].name} (${lines[i].episodes.length})'),
                      selected: i == lineIdx,
                      onSelected: (_) => setState(() => _lineIndex = i),
                    ),
                ],
              ),
            const SizedBox(height: 14),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    <String>[
                      line.name,
                      '共 ${line.episodes.length} 集',
                      if (_item.endLabel != null) _item.endLabel!,
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                if (line.episodes.length > 1)
                  TextButton.icon(
                    icon: const Icon(Icons.swap_vert, size: 18),
                    label: Text(reverse ? '反序' : '正序'),
                    onPressed: () => context
                        .read<AppState>()
                        .setEpisodeOrderReverse(!reverse),
                  ),
                if (line.episodes.length > 1)
                  TextButton.icon(
                    icon: const Icon(Icons.play_circle_outline, size: 18),
                    label: const Text('从头播放'),
                    onPressed: () => _play(lineIdx, 0),
                  ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
      // 用 SliverLayoutBuilder 拿网格自己的布局约束：起始滚动位置和
      // 可用宽度都是续播定位要用的量，而它们只有布局时才知道。
      SliverLayoutBuilder(
        builder: (BuildContext context, SliverConstraints constraints) {
          _gridPreceding = constraints.precedingScrollExtent;
          _gridCrossExtent = constraints.crossAxisExtent;
          return SliverGrid(
            // 懒构建：只有可见区附近的单元格会被创建。
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: _episodeMaxCrossExtent,
              mainAxisExtent: _episodeExtent,
              crossAxisSpacing: _episodeSpacing,
              mainAxisSpacing: _episodeSpacing,
            ),
            delegate: SliverChildBuilderDelegate(
              (BuildContext context, int index) {
                final int ep = order[index];
                return _EpisodeButton(
                  name: line.episodes[ep].name,
                  selected: resumeOnThisLine && record.episodeIndex == ep,
                  watched: resumeOnThisLine && ep < record.episodeIndex,
                  onPressed: () => _play(lineIdx, ep),
                );
              },
              childCount: order.length,
            ),
          );
        },
      ),
    ];
  }

  Widget _buildEpisodeError(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '无法获取播放地址',
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.onErrorContainer,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _error!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onErrorContainer,
            ),
          ),
          const SizedBox(height: 10),
          FilledButton.tonal(
            onPressed: () => _loadDetail(force: true),
            child: const Text('重试'),
          ),
        ],
      ),
    );
  }

  /// 点演员 / 导演名，看同一个源里还有哪些他/她的片子。
  void _openName(String name) {
    final String keyword = name.trim();
    if (keyword.isEmpty || keyword == '等') return;
    AppRoutes.openKeyword(context, source: widget.source, keyword: keyword);
  }

  /// 把 `"张三,李四/王五"` 拆成一个个可点的名字。
  ///
  /// 各个源的分隔符五花八门，逗号、顿号、斜杠都用过；名字太多时只留前
  /// 六个，剩下的用「等」带过，否则一行标签能把简介挤到屏幕外。
  static List<String> _splitNames(String raw) {
    final List<String> parts = raw
        .split(RegExp(r'[,，/、|]+'))
        .map((String e) => e.trim())
        .where((String e) => e.isNotEmpty && e != '未知' && e != '暂无')
        .toList(growable: false);
    if (parts.length <= 6) return parts;
    return <String>[...parts.take(6), '等'];
  }

  int _clamp(int value, int length) {
    if (length <= 0) return 0;
    return value < 0 ? 0 : (value >= length ? length - 1 : value);
  }
}

// ---------------------------------------------------------------- 子组件

class _EpisodeButton extends StatelessWidget {
  const _EpisodeButton({
    required this.name,
    required this.selected,
    required this.watched,
    required this.onPressed,
  });

  final String name;
  final bool selected;
  final bool watched;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return FilledButton(
      style: FilledButton.styleFrom(
        minimumSize: Size.zero,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        backgroundColor: selected
            ? theme.colorScheme.primary
            : theme.colorScheme.surfaceContainerHighest,
        foregroundColor: selected
            ? theme.colorScheme.onPrimary
            : (watched
                ? theme.colorScheme.onSurfaceVariant
                : theme.colorScheme.onSurface),
        textStyle: theme.textTheme.labelMedium,
        shape: const StadiumBorder(),
      ),
      onPressed: onPressed,
      child: Text(
        name,
        maxLines: 1,
        textAlign: TextAlign.center,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class _MetaChips extends StatelessWidget {
  const _MetaChips({required this.item, this.onTypeTap});

  final VodItem item;

  /// 点分类名时触发；为 null 时分类标签不可点。
  final VoidCallback? onTypeTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<String> parts = <String>[
      if (item.typeName.isNotEmpty) item.typeName,
      if (item.year.isNotEmpty) item.year,
      if (item.area.isNotEmpty) item.area,
      if (item.lang.isNotEmpty) item.lang,
      if (item.duration.isNotEmpty) item.duration,
      if (item.hitsLabel.isNotEmpty) '${item.hitsLabel}次播放',
      if (item.endLabel != null) item.endLabel!,
    ];
    if (parts.isEmpty && item.scoreLabel.isEmpty) return const SizedBox.shrink();

    // 琥珀色在深色底上要用浅一档，否则对比度不足。
    final Color scoreColor = theme.brightness == Brightness.dark
        ? Colors.amber.shade300
        : Colors.amber.shade800;

    // 分类标签可点，其余（年代 / 地区 / 片长 / 播放量）只是信息。
    Widget chip(String text, {VoidCallback? onTap}) {
      final Widget box = Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          text,
          style: theme.textTheme.labelMedium?.copyWith(
            color: onTap == null
                ? theme.colorScheme.onSurfaceVariant
                : theme.colorScheme.primary,
          ),
        ),
      );
      if (onTap == null) return box;
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: box,
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: <Widget>[
        if (item.scoreLabel.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(Icons.star_rounded, size: 14, color: scoreColor),
                const SizedBox(width: 2),
                Text(
                  item.scoreLabel,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scoreColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        for (final String p in parts)
          chip(p, onTap: p == item.typeName ? onTypeTap : null),
      ],
    );
  }
}

/// 导演 / 演员一行：每个名字都是可点的，点进去看该名字在这个源下的作品。
class _PeopleLine extends StatelessWidget {
  const _PeopleLine({
    required this.label,
    required this.names,
    required this.onTap,
  });

  final String label;
  final List<String> names;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final TextStyle? style = theme.textTheme.bodySmall?.copyWith(height: 1.5);

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 42,
            child: Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          Expanded(
            child: Wrap(
              spacing: 2,
              runSpacing: 2,
              children: <Widget>[
                for (final String name in names)
                  if (name == '等')
                    Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      child: Text(
                        name,
                        style: style?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  else
                    InkWell(
                      onTap: () => onTap(name),
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 2,
                        ),
                        child: Text(
                          name,
                          style: style?.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
