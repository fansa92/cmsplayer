/// 展示层格式化工具。
library;

import 'dart:math' as math;

/// 时长格式化：`h:mm:ss` 或 `m:ss`。
String formatDuration(Duration d) {
  final int total = d.inSeconds.abs();
  final int h = total ~/ 3600;
  final int m = (total % 3600) ~/ 60;
  final int s = total % 60;
  final String mm = m.toString().padLeft(2, '0');
  final String ss = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:$mm:$ss' : '$m:$ss';
}

/// 拖动预览用的紧凑格式。
String formatDurationShort(Duration d) {
  final int total = d.inSeconds.abs();
  final int h = total ~/ 3600;
  final int m = (total % 3600) ~/ 60;
  final int s = total % 60;
  return h > 0
      ? '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}'
      : '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}

/// 播放量：`1.2万` / `1.3亿`。
String formatCount(num value) {
  if (value >= 100000000) {
    return '${(value / 100000000).toStringAsFixed(1)}亿';
  }
  if (value >= 10000) {
    return '${(value / 10000).toStringAsFixed(1)}万';
  }
  return value.toString();
}

/// 字节数：`12.3 MB`。
String formatBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  const List<String> units = <String>['B', 'KB', 'MB', 'GB', 'TB'];
  double size = bytes.toDouble();
  int i = 0;
  while (size >= 1024 && i < units.length - 1) {
    size /= 1024;
    i++;
  }
  return '${size.toStringAsFixed(size >= 100 ? 0 : size >= 10 ? 1 : 2)} ${units[i]}';
}

/// 相对时间：`刚刚` / `3分钟前` / `昨天` / `2024-01-02`。
String formatRelativeTime(DateTime time, {DateTime? now}) {
  final DateTime n = now ?? DateTime.now();
  final Duration diff = n.difference(time);
  if (diff.inSeconds < 60) return '刚刚';
  if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
  if (diff.inHours < 24) return '${diff.inHours}小时前';
  if (diff.inDays == 1) return '昨天';
  if (diff.inDays < 30) return '${diff.inDays}天前';
  return '${time.year}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')}';
}

/// 进度百分比，避免除零。
double safeRatio(double value, double max) {
  if (max <= 0 || value.isNaN || max.isNaN) return 0;
  return (value / max).clamp(0.0, 1.0);
}

/// 数值夹取。
double clampDouble(double v, double min, double max) => math.max(min, math.min(max, v));
