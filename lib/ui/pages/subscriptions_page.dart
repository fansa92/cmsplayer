import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/utils/formatter.dart';
import '../../data/models/subscription.dart';
import '../../state/subscription_store.dart';
import '../actions.dart';
import '../widgets/empty_state.dart';

/// 订阅管理：一个地址维护一批资源站。
class SubscriptionsPage extends StatefulWidget {
  const SubscriptionsPage({super.key});

  @override
  State<SubscriptionsPage> createState() => _SubscriptionsPageState();
}

class _SubscriptionsPageState extends State<SubscriptionsPage> {
  Future<void> _add() async {
    final _SubscriptionDraft? draft = await showDialog<_SubscriptionDraft>(
      context: context,
      builder: (BuildContext ctx) => const _AddDialog(),
    );
    if (draft == null || !mounted) return;

    final SubscriptionStore store = context.read<SubscriptionStore>();
    try {
      final Subscription sub =
          await store.add(name: draft.name, url: draft.url);
      if (!mounted) return;
      // 加完立刻拉一次：只加不拉的话列表里是一行"还没刷新过"，用户会以为没生效。
      final SubscribeResult result = await store.refresh(sub);
      if (!mounted) return;
      AppActions.snack(
        context,
        '「${result.subscription.name}」${result.total} 个源 · ${result.summary}',
      );
    } on Object catch (e) {
      if (!mounted) return;
      AppActions.snackError(context, e);
    }
  }

  Future<void> _refreshOne(Subscription sub) async {
    final SubscriptionStore store = context.read<SubscriptionStore>();
    try {
      final SubscribeResult result = await store.refresh(sub);
      if (!mounted) return;
      AppActions.snack(context, '「${sub.name}」${result.summary}');
    } on Object catch (e) {
      if (!mounted) return;
      AppActions.snackError(context, e);
    }
  }

  Future<void> _refreshAll() async {
    final SubscriptionStore store = context.read<SubscriptionStore>();
    if (store.enabledCount == 0) {
      AppActions.snack(context, '还没有可刷新的订阅');
      return;
    }
    final int ok = await store.refreshAll();
    if (!mounted) return;
    AppActions.snack(
      context,
      ok == store.enabledCount
          ? '${store.enabledCount} 条订阅已刷新'
          : '$ok/${store.enabledCount} 条订阅刷新成功，其余看列表里的红色提示',
    );
  }

  Future<void> _remove(Subscription sub) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text('删除「${sub.name}」？'),
        content: const Text('只删这条订阅，已经导入的资源站会保留。'),
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
    if (ok != true || !mounted) return;
    await context.read<SubscriptionStore>().remove(sub.id);
  }

  @override
  Widget build(BuildContext context) {
    final SubscriptionStore store = context.watch<SubscriptionStore>();
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('订阅源'),
        actions: <Widget>[
          IconButton(
            tooltip: '全部刷新',
            onPressed: store.busy ? null : _refreshAll,
            icon: store.busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add_link),
        label: const Text('添加订阅'),
      ),
      body: store.isEmpty
          ? EmptyState(
              icon: Icons.rss_feed,
              title: '还没有订阅',
              subtitle: '粘贴一个源列表地址，一次导入整批资源站；之后刷新会自动增删。',
              actionLabel: '添加订阅',
              onAction: _add,
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(0, 8, 0, 96),
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Text(
                    '共 ${store.items.length} 条订阅 · 启用 ${store.enabledCount} 条。'
                    '刷新时消失的资源站只会被停用，不会删除。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                for (final Subscription sub in store.items)
                  _SubscriptionTile(
                    sub: sub,
                    busy: store.busy,
                    onRefresh: () => _refreshOne(sub),
                    onToggle: (bool v) => store.setEnabled(sub.id, v),
                    onDelete: () => _remove(sub),
                  ),
              ],
            ),
    );
  }
}

class _SubscriptionTile extends StatelessWidget {
  const _SubscriptionTile({
    required this.sub,
    required this.busy,
    required this.onRefresh,
    required this.onToggle,
    required this.onDelete,
  });

  final Subscription sub;
  final bool busy;
  final VoidCallback onRefresh;
  final ValueChanged<bool> onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool failed = sub.lastError.isNotEmpty;
    final DateTime? at = sub.lastFetchedAt;

    final String status;
    if (failed) {
      status = '上次刷新失败：${sub.lastError}';
    } else if (at == null) {
      status = '还没刷新过';
    } else {
      status = '${formatRelativeTime(at)}更新 · ${sub.sourceCount} 个源';
    }

    return ListTile(
      leading: Icon(
        failed ? Icons.error_outline : Icons.rss_feed,
        color: failed ? theme.colorScheme.error : theme.colorScheme.primary,
      ),
      title: Row(
        children: <Widget>[
          Flexible(
            child: Text(
              sub.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (!sub.enabled)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(
                '已停用',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            sub.url,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            status,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: failed
                  ? theme.colorScheme.error
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      isThreeLine: true,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          IconButton(
            tooltip: '刷新',
            onPressed: busy ? null : onRefresh,
            icon: const Icon(Icons.refresh),
          ),
          PopupMenuButton<String>(
            tooltip: '更多',
            onSelected: (String value) {
              switch (value) {
                case 'toggle':
                  onToggle(!sub.enabled);
                  break;
                case 'delete':
                  onDelete();
                  break;
              }
            },
            itemBuilder: (BuildContext ctx) => <PopupMenuEntry<String>>[
              PopupMenuItem<String>(
                value: 'toggle',
                child: Text(sub.enabled ? '停用这条订阅' : '启用这条订阅'),
              ),
              const PopupMenuItem<String>(
                value: 'delete',
                child: Text('删除订阅'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SubscriptionDraft {
  const _SubscriptionDraft({required this.name, required this.url});

  final String name;
  final String url;
}

class _AddDialog extends StatefulWidget {
  const _AddDialog();

  @override
  State<_AddDialog> createState() => _AddDialogState();
}

class _AddDialogState extends State<_AddDialog> {
  final TextEditingController _url = TextEditingController();
  final TextEditingController _name = TextEditingController();

  @override
  void dispose() {
    _url.dispose();
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final String url = _url.text.trim();
    if (url.isEmpty) return;
    Navigator.of(context).pop(
      _SubscriptionDraft(name: _name.text.trim(), url: url),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return AlertDialog(
      title: const Text('添加订阅'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          TextField(
            controller: _url,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: '订阅地址',
              hintText: 'https://…/source.json',
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: '名称（可留空）',
              hintText: '例如「我的常用源」',
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 12),
          Text(
            '支持官方源列表那样的 JSON 数组；加完会立刻拉一次。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            K.officialSourceListMirror,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('添加')),
      ],
    );
  }
}
