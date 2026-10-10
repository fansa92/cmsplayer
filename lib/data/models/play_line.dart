import '../../core/utils/text_utils.dart';

/// 一集可播放的内容。
class PlayEpisode {
  const PlayEpisode({
    required this.name,
    required this.url,
    this.mirrors = const <String>[],
  });

  /// 集名，例如 `第01集`、`正片`、`预告`。
  final String name;

  /// 主播放地址。
  final String url;

  /// 同一集的备用地址（macCMS 允许 `名称$url1$url2`）。
  final List<String> mirrors;

  factory PlayEpisode.fromJson(Map<String, dynamic> json) {
    return PlayEpisode(
      name: strOf(json['name']),
      url: strOf(json['url']),
      mirrors: (json['mirrors'] as List?)
              ?.map((Object? e) => strOf(e))
              .where((String e) => e.isNotEmpty)
              .toList() ??
          const <String>[],
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'name': name,
        'url': url,
        'mirrors': mirrors,
      };

  @override
  String toString() => 'PlayEpisode($name)';
}

/// 一条播放线路（例如 `m3u8`、`ffm3u8`、`dbm3u8`）。
class PlayLine {
  const PlayLine({required this.name, required this.episodes});

  /// 线路名，来自 `vod_play_from`。
  final String name;
  final List<PlayEpisode> episodes;

  bool get isEmpty => episodes.isEmpty;
  int get length => episodes.length;

  factory PlayLine.fromJson(Map<String, dynamic> json) {
    return PlayLine(
      name: strOf(json['name']),
      episodes: (json['episodes'] as List?)
              ?.whereType<Map>()
              .map((Map e) => PlayEpisode.fromJson(e.cast<String, dynamic>()))
              .toList() ??
          const <PlayEpisode>[],
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'name': name,
        'episodes': episodes.map((PlayEpisode e) => e.toJson()).toList(),
      };

  @override
  String toString() => 'PlayLine($name, ${episodes.length} eps)';
}
