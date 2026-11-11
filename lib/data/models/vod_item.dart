import '../../core/utils/text_utils.dart';
import 'play_line.dart';

/// 影片条目。
///
/// `list` 模式下没有播放地址，`detail` 模式才有。因此 [playLines] 可能为空，
/// 详情页在遇到空 [playLines] 时应再拉一次 `ac=detail`。
///
/// 除了播放必需的那几个字段，macCMS 还会带回一堆"展示用"的元信息
/// （评分 / 播放量 / 是否完结 / 片长……）。这些字段各个源给的完整度差别很大，
/// 所以统一按"缺省即无"处理：数字字段缺省为 0，字符串缺省为空，
/// [isEnd] 用可空布尔区分"源站说没完结"和"源站没说"。
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
    this.score = 0,
    this.hits = 0,
    this.isEnd,
    this.serial = '',
    this.totalEpisodes = 0,
    this.duration = '',
    this.pubDate = '',
    this.subName = '',
    this.letter = '',
    this.upCount = 0,
    this.downCount = 0,
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

  /// 评分，0~10；0 表示源站没给。
  final double score;

  /// 播放量；0 表示源站没给。
  final int hits;

  /// 是否完结。null 表示源站没给这个字段（既不能说完结也不能说在更新）。
  final bool? isEnd;

  /// 更新进度，如「更新至第 12 集」。
  final String serial;

  /// 总集数（源站给的值，可能与实际选集数不一致）。
  final int totalEpisodes;

  /// 片长，如「45分钟」。
  final String duration;

  /// 上映日期。
  final String pubDate;

  /// 别名。
  final String subName;

  /// 首字母，用于 A–Z 索引。
  final String letter;

  final int upCount;
  final int downCount;

  final List<PlayLine> playLines;

  /// 是否已包含可播放的线路。
  bool get hasPlayInfo => playLines.isNotEmpty;

  bool get isEmpty => id <= 0 && name.isEmpty;

  int get episodeCount =>
      playLines.fold(0, (int sum, PlayLine l) => sum + l.episodes.length);

  /// 评分文案，没有评分时为空串。
  String get scoreLabel => score > 0 ? score.toStringAsFixed(1) : '';

  /// 播放量文案，`12345` → `1.2万`。
  String get hitsLabel => formatHits(hits);

  /// 海报角标文案：备注 → 更新进度 → 完结状态，取第一个有值的。
  ///
  /// 这些字段在不同源里经常是"有备注没进度、有进度没备注"，挨个兜底比
  /// 只认 `remarks` 能多显示不少信息。
  String get badgeText {
    if (remarks.isNotEmpty) return remarks;
    if (serial.isNotEmpty) return serial;
    if (isEnd == true) return '已完结';
    return '';
  }

  /// 完结状态文案，源站没给时为 null。
  String? get endLabel {
    final bool? end = isEnd;
    if (end == null) return null;
    return end ? '已完结' : '连载中';
  }

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
      score: doubleOf(json['vod_score']),
      hits: hitsOf(json['vod_hits']),
      isEnd: _boolOrNull(json['vod_isend']),
      serial: decodeEntities(strOf(json['vod_serial'])),
      totalEpisodes: intOf(json['vod_total']),
      duration: strOf(json['vod_duration']),
      pubDate: strOf(json['vod_pubdate']),
      subName: decodeEntities(strOf(json['vod_sub'])),
      letter: strOf(json['vod_letter']).toUpperCase(),
      upCount: intOf(json['vod_up']),
      downCount: intOf(json['vod_down']),
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
        'vod_score': score,
        'vod_hits': hits,
        if (isEnd != null) 'vod_isend': isEnd! ? 1 : 0,
        'vod_serial': serial,
        'vod_total': totalEpisodes,
        'vod_duration': duration,
        'vod_pubdate': pubDate,
        'vod_sub': subName,
        'vod_letter': letter,
        'vod_up': upCount,
        'vod_down': downCount,
        'playLines': playLines.map((PlayLine e) => e.toJson()).toList(),
      };

  VodItem copyWith({
    List<PlayLine>? lines,
    String? remarks,
    double? score,
    int? hits,
    bool? isEnd,
    String? serial,
    int? totalEpisodes,
    String? duration,
    String? pubDate,
    String? subName,
    String? letter,
    int? upCount,
    int? downCount,
  }) =>
      VodItem(
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
        score: score ?? this.score,
        hits: hits ?? this.hits,
        isEnd: isEnd ?? this.isEnd,
        serial: serial ?? this.serial,
        totalEpisodes: totalEpisodes ?? this.totalEpisodes,
        duration: duration ?? this.duration,
        pubDate: pubDate ?? this.pubDate,
        subName: subName ?? this.subName,
        letter: letter ?? this.letter,
        upCount: upCount ?? this.upCount,
        downCount: downCount ?? this.downCount,
        playLines: lines ?? playLines,
      );

  /// `vod_isend` 在 macCMS 里是 `1` / `0`，也有源给 `true` / `"完结"`。
  /// 认不出来就当"源站没说"，不要猜成连载中。
  static bool? _boolOrNull(Object? value) {
    if (value == null) return null;
    if (value is bool) return value;
    final String text = strOf(value).toLowerCase();
    if (text.isEmpty) return null;
    if (text == '1' || text == 'true' || text == '已完结' || text == '完结') {
      return true;
    }
    if (text == '0' || text == 'false' || text == '连载' || text == '连载中') {
      return false;
    }
    return null;
  }

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

      final String lineName =
          (i < froms.length && froms[i].isNotEmpty) ? froms[i] : '线路${i + 1}';

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
