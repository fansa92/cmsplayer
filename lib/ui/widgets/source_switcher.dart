import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models/vod_source.dart';
import '../../state/source_store.dart';
import '../shell/app_shell.dart';

/// 顶栏上的资源站切换器。
class SourceSwitcher extends StatelessWidget {
  const SourceSwitcher({super.key, required this.source});

  final VodSource source;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final SourceStore store = context.watch<SourceStore>();
    final List<VodSource> enabled = store.enabledSources;

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: enabled.length <= 1 ? null : () => _showSheet(context, store, enabled),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.public,
              size: 18,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width * 0.42,
              ),
              child: Text(
                source.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (enabled.length > 1) ...<Widget>[
              const SizedBox(width: 2),
              Icon(
                Icons.arrow_drop_down,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showSheet(
    BuildContext context,
    SourceStore store,
    List<VodSource> enabled,
  ) {
    final BuildContext outer = context;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext ctx) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(ctx).height * 0.7,
            ),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: 12),
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text(
                    '切换资源站',
                    style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
                for (final VodSource s in enabled)
                  ListTile(
                    dense: true,
                    leading: Icon(
                      s.id == store.activeId
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      color: s.id == store.activeId
                          ? Theme.of(ctx).colorScheme.primary
                          : null,
                    ),
                    title: Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: s.note.isEmpty
                        ? null
                        : Text(s.note, maxLines: 1, overflow: TextOverflow.ellipsis),
                    onTap: () {
                      Navigator.of(ctx).pop();
                      store.setActive(s);
                    },
                  ),
                const Divider(),
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.dns_outlined),
                  title: const Text('管理资源站…'),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (outer.mounted) {
                        AppShellActions.openSourceManager(outer);
                      }
                    });
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
