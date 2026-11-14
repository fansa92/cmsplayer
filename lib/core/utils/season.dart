import '../../data/models/play_line.dart';

/// 一个季度 / 一季的集数分组。
class SeasonGroup {
  const SeasonGroup({
    required this.season,
    required this.label,
    required this.indices,
  });

  /// 季度序号；0 表示"没写季"的那一堆。
  final int season;

  /// 显示用的标签，例如 `第 2 季`。
  final String label;

  /// 这一季在原始集数列表里的下标，保持原顺序。
  final List<int> indices;
}

/// 从集名里抽季度序号。
///
/// 支持 `第2季 第01集`、`第二季`、`S02E01` 这几种常见写法；
/// 抽不到返回 null —— 绝大多数单季剧的集名就是「第01集」。
int? seasonOf(String name) {
  final String text = name.trim();
  if (text.isEmpty) return null;

  final RegExpMatch? cn =
      RegExp(r'第\s*([0-9一二三四五六七八九十]+)\s*季').firstMatch(text);
  if (cn != null) {
    final int? value = _numberOf(cn.group(1)!);
    if (value != null && value > 0) return value;
  }

  final RegExpMatch? en = RegExp(r'[Ss](\d{1,2})\s*[Ee]\d{1,3}').firstMatch(text);
  if (en != null) {
    final int? value = int.tryParse(en.group(1)!);
    if (value != null && value > 0) return value;
  }
  return null;
}

/// 按季分组。少于两季时返回空列表 —— 只有一个"第 1 季"的话，
/// 多出一排只有一项的筛选条只是噪音。
List<SeasonGroup> groupBySeason(List<PlayEpisode> episodes) {
  if (episodes.isEmpty) return const <SeasonGroup>[];

  final Map<int, List<int>> buckets = <int, List<int>>{};
  for (int i = 0; i < episodes.length; i++) {
    final int season = seasonOf(episodes[i].name) ?? 0;
    buckets.putIfAbsent(season, () => <int>[]).add(i);
  }

  final List<int> seasons = buckets.keys.toList()..sort();
  // 只有一季（或全是"无季"）就不分组。
  final int named = seasons.where((int s) => s > 0).length;
  if (named < 2) return const <SeasonGroup>[];

  return <SeasonGroup>[
    for (final int season in seasons)
      SeasonGroup(
        season: season,
        label: season > 0 ? '第 $season 季' : '其他',
        indices: List<int>.unmodifiable(buckets[season]!),
      ),
  ];
}

int? _numberOf(String raw) {
  final int? direct = int.tryParse(raw);
  if (direct != null) return direct;
  const String digits = '零一二三四五六七八九';
  int total = 0;
  int current = 0;
  for (final int rune in raw.runes) {
    final String ch = String.fromCharCode(rune);
    if (ch == '十') {
      total += (current == 0 ? 1 : current) * 10;
      current = 0;
      continue;
    }
    final int digit = digits.indexOf(ch);
    if (digit < 0) return null;
    current = digit;
  }
  return total + current;
}
