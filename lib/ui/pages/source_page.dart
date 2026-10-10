import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../data/models/vod_source.dart';
import '../../state/source_store.dart';
import '../actions.dart';
import '../widgets/empty_state.dart';

/// 资源站管理页。
class SourcePage extends StatefulWidget {
  const SourcePage({super.key, this.asHome = false});

  /// 为 true 时作为首页出现（一个源都没有），此时没有返回按钮。
  final bool asHome;

  @override
  State<SourcePage> createState() => _SourcePageState();
}

class _SourcePageState extends State<SourcePage> {
  final Map<String, bool> _testResults = <String, bool>{};

  @override
  Widget build(BuildContext context) {
    final SourceStore store = context.watch<SourceStore>();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.asHome ? '先添加一个资源站' : '资源站管理'),
        actions: <Widget>[
          IconButton(
            tooltip: '从 URL 导入',
            icon: const Icon(Icons.link),
            onPressed: () => _importFromUrl(context),
          ),
          IconButton(
            tooltip: '粘贴 JSON 导入',
            icon: const Icon(Icons.paste),
            onPressed: () => _importFromText(context),
          ),
          PopupMenuButton<String>(
            tooltip: '更多',
            onSelected: (String v) => _onMenu(context, v, store),
            itemBuilder: (BuildContext ctx) => const <PopupMenuEntry<String>>[
              PopupMenuItem<String>(value: 'test_all', child: Text('测试全部连通性')),
              PopupMenuItem<String>(value: 'export', child: Text('导出为 JSON')),
              PopupMenuItem<String>(value: 'builtin', child: Text('恢复内置示例源')),
              PopupMenuItem<String>(value: 'clear', child: Text('清空所有源')),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: store.loading
          ? const PageLoading()
          : store.sources.isEmpty
              ? const EmptyState(
                  icon: Icons.dns_outlined,
                  title: '还没有资源站',
                  subtitle:
                      '本应用本身不提供任何影片，只负责对接 macCMS（苹果CMS）资源站接口。'
                      '可以导入官方源列表，或手动填写接口地址。',
                )
              : _buildList(store),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editSource(context, null),
        icon: const Icon(Icons.add),
        label: const Text('添加资源站'),
      ),
    );
  }

  Widget _buildList(SourceStore store) {
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: Row(
            children: <Widget>[
              Text(
                '共 ${store.sources.length} 个源 · 启用 ${store.enabledSources.length} 个',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const Spacer(),
              if (store.busy)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
        ),
        Expanded(
          child: ReorderableListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
            buildDefaultDragHandles: false,
            itemCount: store.sources.length,
            onReorderItem: (int oldIndex, int newIndex) =>
                store.move(oldIndex, newIndex),
            itemBuilder: (BuildContext context, int index) {
              final VodSource source = store.sources[index];
              return _SourceTile(
                key: ValueKey<String>(source.id),
                index: index,
                source: source,
                isActive: source.id == store.activeId,
                isTesting: store.testingId == source.id,
                testResult: _testResults[source.id],
                onToggle: () => store.toggleEnabled(source.id),
                onSelect: () => store.setActive(source),
                onEdit: () => _editSource(context, source),
                onDelete: () => _confirmDelete(context, store, source),
                onTest: () => _testOne(context, store, source),
              );
            },
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------- 操作

  Future<void> _testOne(
    BuildContext context,
    SourceStore store,
    VodSource source,
  ) async {
    final bool ok = await store.test(source);
    if (!mounted) return;
    setState(() => _testResults[source.id] = ok);
    if (context.mounted) {
      AppActions.snack(context, ok ? '「${source.name}」连接正常' : '「${source.name}」无法连接');
    }
  }

  Future<void> _onMenu(
    BuildContext context,
    String action,
    SourceStore store,
  ) async {
    switch (action) {
      case 'test_all':
        final Route<void> loading =
            AppActions.showBlockingLoading(context, message: '正在并发测试所有源…');
        final Set<String> ok = await store.testMany(store.enabledSources);
        if (!mounted) return;
        if (!context.mounted) return;
        AppActions.dismissRoute(context, loading);
        setState(() {
          _testResults
            ..clear()
            ..addEntries(store.sources.map(
              (VodSource s) => MapEntry<String, bool>(s.id, ok.contains(s.id)),
            ));
        });
        AppActions.snack(context, '通过 ${ok.length}/${store.enabledSources.length} 个源');
        break;
      case 'export':
        await _export(context, store);
        break;
      case 'builtin':
        await store.resetToBuiltin();
        if (context.mounted) AppActions.snack(context, '已恢复内置示例源');
        break;
      case 'clear':
        final bool? ok = await showDialog<bool>(
          context: context,
          builder: (BuildContext ctx) => AlertDialog(
            title: const Text('清空所有资源站？'),
            content: const Text('收藏与观看记录会保留，但所有源都会被删除。'),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('清空'),
              ),
            ],
          ),
        );
        if (ok == true) {
          await store.clearAll();
          if (context.mounted) AppActions.snack(context, '已清空所有源');
        }
        break;
    }
  }

  Future<void> _export(BuildContext context, SourceStore store) async {
    final String json = store.exportJson();
    await showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('导出资源站'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(
              json,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('关闭'),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.copy, size: 18),
            label: const Text('复制'),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: json));
              if (ctx.mounted) AppActions.snack(ctx, '已复制到剪贴板');
            },
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    SourceStore store,
    VodSource source,
  ) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text('删除「${source.name}」？'),
        content: const Text('该资源站的收藏与观看记录会一并保留，可随时重新导入。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await store.remove(source.id);
  }

  // ---------------------------------------------------------------- 导入

  Future<void> _importFromUrl(BuildContext context) async {
    final TextEditingController controller = TextEditingController(
      text: K.officialSourceListUrl,
    );
    final String? url = await showDialog<String>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('从 URL 导入'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            TextField(
              controller: controller,
              maxLines: 2,
              decoration: const InputDecoration(hintText: 'https://…/source.json'),
            ),
            const SizedBox(height: 12),
            Text(
              '官方源列表：\n${K.officialSourceListUrl}\n\n国内打不开时改用镜像：\n${K.officialSourceListMirror}',
              style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                    fontSize: 11,
                  ),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('导入'),
          ),
        ],
      ),
    );
    if (url == null || url.isEmpty || !context.mounted) return;
    await _doImport(context, () => context.read<SourceStore>().importFromUrl(url));
  }

  Future<void> _importFromText(BuildContext context) async {
    final TextEditingController controller = TextEditingController();
    final String? text = await showDialog<String>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('粘贴 JSON 导入'),
        content: SizedBox(
          width: double.maxFinite,
          child: TextField(
            controller: controller,
            maxLines: 10,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            decoration: const InputDecoration(
              hintText: '[{"name":"示例站","api":"https://example.com/api.php/provide/vod/"}]',
            ),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          TextButton.icon(
            icon: const Icon(Icons.content_paste, size: 18),
            label: const Text('从剪贴板粘贴'),
            onPressed: () async {
              final ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
              if (data?.text != null) controller.text = data!.text!;
            },
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('导入'),
          ),
        ],
      ),
    );
    if (text == null || text.trim().isEmpty || !context.mounted) return;
    await _doImport(context, () => context.read<SourceStore>().importFromText(text));
  }

  Future<void> _doImport(
    BuildContext context,
    Future<int> Function() run,
  ) async {
    final Route<void> loading =
        AppActions.showBlockingLoading(context, message: '正在导入…');
    try {
      final int added = await run();
      if (!mounted) return;
      if (!context.mounted) return;
      AppActions.dismissRoute(context, loading);
      AppActions.snack(context, added > 0 ? '成功导入 $added 个资源站' : '没有新增资源站（可能都已存在）');
    } on Object catch (e) {
      if (!mounted) return;
      if (!context.mounted) return;
      AppActions.dismissRoute(context, loading);
      AppActions.snackError(context, e);
    }
  }

  Future<void> _editSource(BuildContext context, VodSource? existing) async {
    final VodSource? result = await showDialog<VodSource>(
      context: context,
      builder: (_) => _SourceEditDialog(existing: existing),
    );
    if (result == null || !context.mounted) return;
    final SourceStore store = context.read<SourceStore>();
    if (existing == null) {
      await store.add(result);
    } else {
      await store.update(result);
    }
    if (context.mounted) AppActions.snack(context, '已保存');
  }
}

// ---------------------------------------------------------------- 磁贴

class _SourceTile extends StatelessWidget {
  const _SourceTile({
    super.key,
    required this.index,
    required this.source,
    required this.isActive,
    required this.isTesting,
    required this.testResult,
    required this.onToggle,
    required this.onSelect,
    required this.onEdit,
    required this.onDelete,
    required this.onTest,
  });

  final int index;
  final VodSource source;
  final bool isActive;
  final bool isTesting;
  final bool? testResult;
  final VoidCallback onToggle;
  final VoidCallback onSelect;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onTest;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color statusColor = testResult == null
        ? theme.colorScheme.outline
        : (testResult! ? Colors.greenAccent : Colors.redAccent);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onSelect,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 8, 8),
            child: Row(
              children: <Widget>[
                ReorderableDragStartListener(
                  index: index,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(Icons.drag_indicator, size: 20),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          if (isActive)
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: Icon(Icons.check_circle,
                                  size: 16, color: theme.colorScheme.primary),
                            ),
                          Expanded(
                            child: Text(
                              source.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        source.api,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 11,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (source.note.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 2),
                        Text(
                          source.note,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 11,
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ],
                      const SizedBox(height: 4),
                      Row(
                        children: <Widget>[
                          _StatusDot(
                            color: statusColor,
                            label: isTesting
                                ? '测试中…'
                                : (testResult == null
                                    ? '未测试'
                                    : (testResult! ? '连接正常' : '无法连接')),
                          ),
                          const SizedBox(width: 10),
                          ActionChip(
                            visualDensity: VisualDensity.compact,
                            label: const Text('测试'),
                            onPressed: isTesting ? null : onTest,
                          ),
                          if (!source.enabled)
                            Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: Text(
                                '已停用',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontSize: 11,
                                  color: theme.colorScheme.error,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: source.enabled,
                  onChanged: (_) => onToggle(),
                ),
                PopupMenuButton<String>(
                  tooltip: '操作',
                  padding: EdgeInsets.zero,
                  onSelected: (String v) {
                    switch (v) {
                      case 'edit':
                        onEdit();
                        break;
                      case 'test':
                        onTest();
                        break;
                      case 'delete':
                        onDelete();
                        break;
                    }
                  },
                  itemBuilder: (BuildContext ctx) => const <PopupMenuEntry<String>>[
                    PopupMenuItem<String>(value: 'edit', child: Text('编辑')),
                    PopupMenuItem<String>(value: 'test', child: Text('测试连通性')),
                    PopupMenuItem<String>(value: 'delete', child: Text('删除')),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 11),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- 编辑对话框

class _SourceEditDialog extends StatefulWidget {
  const _SourceEditDialog({this.existing});

  final VodSource? existing;

  @override
  State<_SourceEditDialog> createState() => _SourceEditDialogState();
}

class _SourceEditDialogState extends State<_SourceEditDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.existing?.name ?? '',
  );
  late final TextEditingController _api = TextEditingController(
    text: widget.existing?.api ?? '',
  );
  late final TextEditingController _note = TextEditingController(
    text: widget.existing?.note ?? '',
  );
  late final TextEditingController _parse = TextEditingController(
    text: widget.existing?.parseApi ?? '',
  );
  late final TextEditingController _referer = TextEditingController(
    text: widget.existing?.referer ?? '',
  );
  late final TextEditingController _ua = TextEditingController(
    text: widget.existing?.userAgent ?? '',
  );

  bool _advanced = false;

  @override
  void dispose() {
    _name.dispose();
    _api.dispose();
    _note.dispose();
    _parse.dispose();
    _referer.dispose();
    _ua.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? '添加资源站' : '编辑资源站'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextField(
                controller: _name,
                decoration: const InputDecoration(
                  labelText: '名称',
                  hintText: '例如：某某资源站',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _api,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: '接口地址',
                  hintText: 'https://example.com/api.php/provide/vod/',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _note,
                maxLines: 2,
                decoration: const InputDecoration(labelText: '备注（可选）'),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  icon: Icon(
                    _advanced ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                  ),
                  label: Text(_advanced ? '收起高级选项' : '高级选项（解析接口 / Referer / UA）'),
                  onPressed: () => setState(() => _advanced = !_advanced),
                ),
              ),
              if (_advanced) ...<Widget>[
                const SizedBox(height: 8),
                TextField(
                  controller: _parse,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: '解析接口（可选）',
                    hintText: 'https://jx.example.com/?url=',
                    helperText: '播放地址不是直链时，会用它拼接后再交给播放器。',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _referer,
                  decoration: const InputDecoration(
                    labelText: 'Referer（可选）',
                    helperText: '留空则使用接口地址的源站。',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _ua,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'User-Agent（可选）'),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('保存'),
        ),
      ],
    );
  }

  void _submit() {
    final String api = VodSource.normalizeApi(_api.text);
    if (api.isEmpty) {
      AppActions.snack(context, '请填写接口地址');
      return;
    }
    final String name = _name.text.trim().isEmpty
        ? VodSource.hostOf(api)
        : _name.text.trim();

    if (widget.existing == null) {
      Navigator.of(context).pop(VodSource.fromRaw(<String, Object>{
        'name': name,
        'api': api,
        'note': _note.text.trim(),
        'parseApi': _parse.text.trim(),
        'referer': _referer.text.trim(),
        'userAgent': _ua.text.trim(),
      }));
      return;
    }

    Navigator.of(context).pop(
      widget.existing!.copyWith(
        name: name,
        api: api,
        note: _note.text.trim(),
        parseApi: _parse.text.trim(),
        referer: _referer.text.trim(),
        userAgent: _ua.text.trim(),
      ),
    );
  }
}
