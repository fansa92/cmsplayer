import '../../core/utils/text_utils.dart';
import 'play_line.dart';

/// 影片条目。
///
/// `list` 模式下没有播放地址，`detail` 模式才有。因此 [playLines] 可能为空，
/// 详情页在遇到空 [playLines] 时应再拉一次 `ac=detail`。
class VodItem {
  VodItem({
    required this.id,
    required this.name,
    this.pic = '',
    this.typeId = 0,
    this.typeName = '',
    this.remarks = '',
    this.year = '',
    this.area = '',
    this.lang = '',
    this.actor = '',
    this.director = '',
    this.content = '',
    this.playFrom = '',
    this.playUrl = '',
    this.updateTime = '',
    List<PlayLine>? playLines,
  }) : playLines = playLines ?? parsePlayLines(playFrom, playUrl);

  final int id;
  final String name;
  final String pic;
  final int typeId;
  final String typeName;
  final String remarks;
  final String year;
  final String area;
  final String lang;
  final String actor;
  final String director;
  final String content;
  final String playFrom;
  final String playUrl;
  final String updateTime;
  final List<PlayLine> playLines;

  /// 是否已包含可播放的线路。
  bool get hasPlayInfo => playLines.isNotEmpty;

  bool get isEmpty => id <= 0 && name.isEmpty;

  int get episodeCount =>
      playLines.fold(0, (int sum, PlayLine l) => sum + l.episodes.length);

  factory VodItem.fromJson(Map<String, dynamic> json) {
    final String from = strOf(json['vod_play_from']);
    final String url = strOf(json['vod_play_url']);

    // 优先用缓存里已经解析好的线路，避免重复解析。
    List<PlayLine>? cached;
    final Object? rawLines = json['playLines'];
    if (rawLines is List) {
      cached = rawLines
          .whereType<Map>()
          .map((Map e) => PlayLine.fromJson(e.cast<String, dynamic>()))
          .toList();
    }

    return VodItem(
      id: intOf(json['vod_id']),
      name: decodeEntities(strOf(json['vod_name'])),
      pic: strOf(json['vod_pic']),
      typeId: intOf(json['type_id']),
      typeName: strOf(json['type_name']),
      remarks: decodeEntities(strOf(json['vod_remarks'])),
      year: strOf(json['vod_year']),
      area: strOf(json['vod_area']),
      lang: strOf(json['vod_lang']),
      actor: decodeEntities(strOf(json['vod_actor'])),
      director: decodeEntities(strOf(json['vod_director'])),
      content: stripHtml(strOf(json['vod_content'])),
      playFrom: from,
      playUrl: url,
      updateTime: strOf(json['vod_time']),
      playLines: cached,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'vod_id': id,
        'vod_name': name,
        'vod_pic': pic,
        'type_id': typeId,
        'type_name': typeName,
        'vod_remarks': remarks,
        'vod_year': year,
        'vod_area': area,
        'vod_lang': lang,
        'vod_actor': actor,
        'vod_director': director,
        'vod_content': content,
        'vod_play_from': playFrom,
        'vod_play_url': playUrl,
        'vod_time': updateTime,
        'playLines': playLines.map((PlayLine e) => e.toJson()).toList(),
      };

  VodItem copyWith({List<PlayLine>? lines, String? remarks}) => VodItem(
        id: id,
        name: name,
        pic: pic,
        typeId: typeId,
        typeName: typeName,
        remarks: remarks ?? this.remarks,
        year: year,
        area: area,
        lang: lang,
        actor: actor,
        director: director,
        content: content,
        playFrom: playFrom,
        playUrl: playUrl,
        updateTime: updateTime,
        playLines: lines ?? playLines,
      );

  @override
  bool operator ==(Object other) => other is VodItem && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'VodItem($id, $name, ${playLines.length} lines)';

  /// 解析 macCMS 的 `vod_play_from` / `vod_play_url`。
  ///
  /// 三级结构：
  ///  * `$$$` 分隔多条线路，`vod_play_from` 与 `vod_play_url` 按下标一一对应；
  ///  * `#` 分隔一条线路内的多集；
  ///  * `$` 分隔单集的名称与地址，地址后还能再跟 `$` 表示备用地址。
  static List<PlayLine> parsePlayLines(String? from, String? url) {
    final String rawUrl = strOf(url);
    if (rawUrl.isEmpty) return const <PlayLine>[];

    final List<String> froms =
        strOf(from).split(r'$$$').map((String e) => e.trim()).toList();
    final List<String> lines = rawUrl.split(r'$$$');

    final List<PlayLine> result = <PlayLine>[];
    for (int i = 0; i < lines.length; i++) {
      final String raw = lines[i].trim();
      if (raw.isEmpty) continue;

      final String lineName = (i < froms.length && froms[i].isNotEmpty)
          ? froms[i]
          : '线路${i + 1}';

      final List<PlayEpisode> episodes = <PlayEpisode>[];
      for (final String segment in raw.split('#')) {
        final String seg = segment.trim();
        if (seg.isEmpty) continue;

        final int sep = seg.indexOf('\$');
        // 没有 `$` 的片段无法定位地址，跳过。
        if (sep <= 0) continue;

        final String epName = seg.substring(0, sep).trim();
        final String rest = seg.substring(sep + 1).trim();
        final List<String> urls = rest
            .split('\$')
            .map((String e) => e.trim())
            .where((String e) => e.isNotEmpty)
            .toList();
        if (urls.isEmpty) continue;

        episodes.add(PlayEpisode(
          name: epName.isEmpty ? '第${episodes.length + 1}集' : epName,
          url: urls.first,
          mirrors: urls.length > 1 ? urls.sublist(1) : const <String>[],
        ));
      }

      if (episodes.isEmpty) continue;
      result.add(PlayLine(name: lineName, episodes: episodes));
    }
    return result;
  }
}
