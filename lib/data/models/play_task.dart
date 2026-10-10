import 'play_line.dart';
import 'vod_item.dart';
import 'vod_source.dart';

/// 交给播放页的完整上下文。
class PlayTask {
  const PlayTask({
    required this.source,
    required this.item,
    required this.lineIndex,
    required this.episodeIndex,
  });

  final VodSource source;
  final VodItem item;
  final int lineIndex;
  final int episodeIndex;

  List<PlayLine> get lines => item.playLines;

  PlayLine? get line {
    if (lineIndex < 0 || lineIndex >= lines.length) return null;
    return lines[lineIndex];
  }

  PlayEpisode? get episode {
    final PlayLine? l = line;
    if (l == null) return null;
    if (episodeIndex < 0 || episodeIndex >= l.episodes.length) return null;
    return l.episodes[episodeIndex];
  }

  bool get isValid => line != null && episode != null;

  String get recordKey => '${source.id}|${item.id}';

  String get title => item.name;

  String get subtitle {
    final PlayLine? l = line;
    final PlayEpisode? e = episode;
    if (l == null || e == null) return '';
    return '${l.name} · ${e.name}';
  }

  bool get hasNext => episodeIndex >= 0 && episodeIndex < (line?.episodes.length ?? 0) - 1;
  bool get hasPrev => episodeIndex > 0;

  PlayTask copyWith({int? lineIndex, int? episodeIndex}) => PlayTask(
        source: source,
        item: item,
        lineIndex: lineIndex ?? this.lineIndex,
        episodeIndex: episodeIndex ?? this.episodeIndex,
      );

  @override
  String toString() => 'PlayTask(${item.name} [$lineIndex/$episodeIndex])';
}
