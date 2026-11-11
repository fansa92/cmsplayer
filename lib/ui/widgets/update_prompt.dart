import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/constants.dart';
import '../../data/api/update_checker.dart';
import '../actions.dart';

/// 发现新版本时的提示框。
///
/// 只提供「复制下载链接」：应用内直接跳浏览器需要 `url_launcher`，
/// 为了一个链接引入原生插件不划算，复制到剪贴板反而更通用
/// （手机可以粘到微信里，桌面可以粘到浏览器）。
Future<void> showUpdatePrompt(
  BuildContext context,
  UpdateInfo info, {
  String currentVersion = K.appVersion,
}) async {
  final bool? copy = await showDialog<bool>(
    context: context,
    builder: (BuildContext ctx) {
      final ThemeData theme = Theme.of(ctx);
      final String notes = _summarize(info.notes);
      return AlertDialog(
        title: Text('发现新版本 ${info.version}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '当前 $currentVersion · 最新 ${info.version}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (notes.isNotEmpty) ...<Widget>[
                const SizedBox(height: 12),
                Text(notes, style: theme.textTheme.bodySmall),
              ],
              const SizedBox(height: 12),
              SelectableText(
                info.url,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('以后再说'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(ctx).pop(true),
            icon: const Icon(Icons.copy, size: 18),
            label: const Text('复制下载链接'),
          ),
        ],
      );
    },
  );

  if (copy != true || !context.mounted) return;
  // 剪贴板在部分平台（无剪贴板服务的 Linux 会话、受限桌面环境）会直接抛错。
  // 复制失败不该变成一个没人处理的异常 —— 链接本身在弹窗里是可选中的，
  // 让用户手动复制即可。
  try {
    await Clipboard.setData(ClipboardData(text: info.url));
    if (!context.mounted) return;
    AppActions.snack(context, '下载链接已复制');
  } on Object {
    if (!context.mounted) return;
    AppActions.snack(context, '复制失败，请选中链接手动复制');
  }
}

/// 发行说明取前几行：完整的 Markdown 塞进对话框会撑成一整屏滚动。
String _summarize(String notes, {int maxLines = 8, int maxChars = 320}) {
  final List<String> lines = notes
      .split('\n')
      .map((String l) => l.trimRight())
      .where((String l) => l.trim().isNotEmpty)
      .take(maxLines)
      .toList();
  String text = lines.join('\n');
  if (text.length > maxChars) text = '${text.substring(0, maxChars)}…';
  return text;
}
