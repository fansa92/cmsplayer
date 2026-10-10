import 'package:flutter/material.dart';

import '../../data/models/vod_item.dart';
import 'cached_image.dart';

/// 海报卡片。
class VodCard extends StatelessWidget {
  const VodCard({
    super.key,
    required this.item,
    required this.onTap,
    this.headers = const <String, String>{},
    this.progress = 0,
    this.sourceLabel,
  });

  final VodItem item;
  final VoidCallback onTap;
  final Map<String, String> headers;

  /// 0~1 的续播进度，大于 0 时在海报底部画进度条。
  final double progress;

  /// 多源搜索时展示来源站点名。
  final String? sourceLabel;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String? badge =
        item.remarks.isEmpty ? null : _trimBadge(item.remarks);
    final double ratio = progress.clamp(0.0, 1.0);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                CachedImage(
                  url: item.pic,
                  headers: headers,
                  borderRadius: BorderRadius.circular(10),
                ),
                if (badge != null)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        badge,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 10,
                          height: 1.3,
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                if (ratio > 0)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        bottom: Radius.circular(10),
                      ),
                      child: LinearProgressIndicator(
                        value: ratio,
                        minHeight: 3,
                        backgroundColor: Colors.black45,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            item.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
          if (sourceLabel != null || item.typeName.isNotEmpty)
            Text(
              sourceLabel ?? item.typeName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 11,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }

  /// 徽标文本太长会盖住海报，做一次截断。
  static String _trimBadge(String raw) {
    final String text = raw.replaceAll('\n', ' ').trim();
    return text.length > 8 ? '${text.substring(0, 8)}…' : text;
  }
}

/// 历史记录卡片：额外显示"看到第几集"。
class HistoryCard extends StatelessWidget {
  const HistoryCard({
    super.key,
    required this.pic,
    required this.title,
    required this.subtitle,
    required this.progressLabel,
    required this.progress,
    required this.onTap,
    this.headers = const <String, String>{},
  });

  final String pic;
  final String title;
  final String subtitle;
  final String progressLabel;
  final double progress;
  final VoidCallback onTap;
  final Map<String, String> headers;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                CachedImage(
                  url: pic,
                  headers: headers,
                  borderRadius: BorderRadius.circular(10),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(10),
                    ),
                    child: LinearProgressIndicator(
                      value: progress.clamp(0.0, 1.0),
                      minHeight: 3,
                      backgroundColor: Colors.black45,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
                Positioned(
                  left: 6,
                  bottom: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      progressLabel,
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 11,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// 把年份 / 地区 / 类型拼成一行元信息。
String describeMeta(VodItem item) {
  final List<String> parts = <String>[
    if (item.year.isNotEmpty) item.year,
    if (item.area.isNotEmpty) item.area,
    if (item.typeName.isNotEmpty) item.typeName,
  ];
  return parts.join(' · ');
}
