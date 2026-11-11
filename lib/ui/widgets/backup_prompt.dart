import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/utils/formatter.dart';
import '../../data/sync/backup_bundle.dart';
import '../actions.dart';

/// 备份导出完成后的结果框。
///
/// 这里只做两件事：告诉用户文件在哪、把路径放进剪贴板。不做「打开所在
/// 文件夹」——那需要平台相关的 shell 调用，收益远小于维护成本。
Future<void> showBackupResult(
  BuildContext context, {
  required File file,
  required BackupBundle bundle,
}) async {
  final int bytes = await _lengthOf(file);
  if (!context.mounted) return;

  final bool? copy = await showDialog<bool>(
    context: context,
    builder: (BuildContext ctx) {
      final ThemeData theme = Theme.of(ctx);
      return AlertDialog(
        title: const Text('备份已导出'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '共 ${bundle.totalItems} 条数据'
                '（播放记录 ${bundle.history.length}、'
                '收藏 ${bundle.favorites.length}、'
                '资源站 ${bundle.sources.length}）'
                '${bytes > 0 ? '，${formatBytes(bytes)}' : ''}',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              SelectableText(
                file.path,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '文件里不含 WebDAV 密码等凭据。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('关闭'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(ctx).pop(true),
            icon: const Icon(Icons.copy, size: 18),
            label: const Text('复制路径'),
          ),
        ],
      );
    },
  );

  if (copy != true || !context.mounted) return;
  try {
    await Clipboard.setData(ClipboardData(text: file.path));
    if (!context.mounted) return;
    AppActions.snack(context, '路径已复制');
  } on Object {
    if (!context.mounted) return;
    AppActions.snack(context, '复制失败，请选中路径手动复制');
  }
}

Future<int> _lengthOf(File file) async {
  try {
    return await file.length();
  } on Object {
    return 0;
  }
}
