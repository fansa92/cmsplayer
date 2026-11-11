import '../../core/logger.dart';
import '../models/paged_result.dart';
import '../models/play_line.dart';
import '../models/play_task.dart';
import '../models/vod_item.dart';
import '../models/vod_source.dart';
import 'vod_repository.dart';

/// 播放失败后的降级目标。
///
/// 每种目标都带一个**原始地址**（还要过一遍「解析接口」拼接才能给 libmpv），
/// 外加一句人类可读的说明，用来在界面上告诉用户「正在尝试什么」。
sealed class FallbackTarget {
  const FallbackTarget(this.url, this.label);

  /// 原始播放地址。
  final String url;

  /// 界面提示文案。
  final String label;
}

/// 换地址：同一集的备用地址，或同源其它线路里的同一集。
class UrlFallback extends FallbackTarget {
  const UrlFallback(super.url, super.label);
}

/// 换源：另一个资源站里的同名影片。
class SourceFallback extends FallbackTarget {
  const SourceFallback(
    super.url,
    super.label, {
    required this.source,
    required this.item,
    required this.lineIndex,
    required this.episodeIndex,
  });

  final VodSource source;
  final VodItem item;
  final int lineIndex;
  final int episodeIndex;
}

/// 播放失败时的降级策略。
///
/// 降级链分两级：
///
///  1. **同源**：当前集的备用地址（macCMS 的 `名称$主地址$备用地址`），
///     再是同源其它线路里同一集的地址；
///  2. **跨源**：到别的资源站里找同名影片的同一集。
///
/// macCMS 的备用地址本来就是为「主地址挂了」准备的，之前解析出来了却
/// 从没用过 —— 这一层等于白捡的成功率。
class FallbackResolver {
  FallbackResolver._();

  /// 跨源降级时最多搜索几个源。
  ///
  /// 搜得越多越容易找到，但也越慢；一个失效的源就能吃掉 20 秒超时，
  /// 所以这里卡住上限。
  static const int _maxSearchSources = 5;

  /// 跨源降级最多返回几个候选。
  static const int _maxResults = 2;

  /// 同源降级候选。
  ///
  /// 顺序：
  ///  1. 当前集的备用地址；
  ///  2. 同源其它线路里**同一集**的地址（主地址 + 它的备用地址）。
  ///
  /// 第 2 步按集名对齐而不是按下标 —— 不同线路的集数经常对不上
  /// （一条 30 集、另一条 24 集，或者夹着特别篇），按下标会播错内容。
  static List<UrlFallback> sameSource(PlayTask task) {
    final List<UrlFallback> result = <UrlFallback>[];
    final PlayEpisode? current = task.episode;
    if (current == null) return result;

    // 1) 当前集的备用地址。
    for (final String raw in current.mirrors) {
      final String url = raw.trim();
      if (url.isEmpty) continue;
      result.add(UrlFallback(url, '备用地址'));
    }

    // 2) 其它线路里的同一集。
    final String episodeName = current.name.trim();
    for (int i = 0; i < task.lines.length; i++) {
      if (i == task.lineIndex) continue;
      final PlayLine line = task.lines[i];
      final int index = _matchEpisode(line, episodeName);
      if (index < 0) continue;
      final PlayEpisode episode = line.episodes[index];
      result.add(UrlFallback(episode.url, '线路「${line.name}」'));
      for (final String raw in episode.mirrors) {
        final String url = raw.trim();
        if (url.isEmpty) continue;
        result.add(UrlFallback(url, '线路「${line.name}」的备用地址'));
      }
    }
    return result;
  }

  /// 在其它资源站里找同名影片的同一集。
  ///
  /// macCMS 没有「按片名跨站取同一部片子」的原子接口，只能逐站搜索后
  /// 按片名匹配。匹配条件刻意收得比较紧（片名、年代、还要有同名集），
  /// 宁可漏掉一次跨源切换，也不要把用户带到另一部片子上。
  static Future<List<SourceFallback>> crossSource(
    PlayTask task,
    List<VodSource> sources,
  ) async {
    final String title = task.item.name.trim();
    if (title.isEmpty || sources.isEmpty) {
      return const <SourceFallback>[];
    }

    final List<VodSource> targets = sources.take(_maxSearchSources).toList();
    final List<VodPage> pages = await Future.wait(
      targets.map((VodSource s) async {
        try {
          return await VodRepository.instance.query(
            source: s,
            keyword: title,
            detail: true,
            pageSize: 10,
            force: true,
          );
        } on Object catch (e) {
          AppLog.d('Fallback', 'search ${s.name} failed: $e');
          return VodPage.empty();
        }
      }),
    );

    final List<SourceFallback> result = <SourceFallback>[];
    for (int i = 0; i < pages.length; i++) {
      for (final VodItem item in pages[i].items) {
        if (!_sameTitle(item.name, title)) continue;
        // 年代对不上基本可以断定是另一部片子（同名翻拍很少见）。
        final String fromYear = task.item.year.trim();
        final String toYear = item.year.trim();
        if (fromYear.isNotEmpty && toYear.isNotEmpty && fromYear != toYear) {
          continue;
        }

        final VodItem detail;
        try {
          detail = await VodRepository.instance.ensureDetail(
            source: targets[i],
            item: item,
          );
        } on Object catch (e) {
          AppLog.d('Fallback', 'ensureDetail ${targets[i].name} failed: $e');
          continue;
        }
        if (!detail.hasPlayInfo) continue;

        final _EpisodeMatch? match = _matchInItem(detail, task);
        if (match == null) continue;

        result.add(
          SourceFallback(
            detail.playLines[match.lineIndex].episodes[match.episodeIndex].url,
            targets[i].name,
            source: targets[i],
            item: detail,
            lineIndex: match.lineIndex,
            episodeIndex: match.episodeIndex,
          ),
        );
        if (result.length >= _maxResults) return result;
      }
    }
    return result;
  }

  /// 在条目里找到与当前集对应的线路与集。
  static _EpisodeMatch? _matchInItem(VodItem detail, PlayTask task) {
    final String name = task.episode?.name.trim() ?? '';
    if (name.isEmpty) return null;
    for (int i = 0; i < detail.playLines.length; i++) {
      final int index = _matchEpisode(detail.playLines[i], name);
      if (index >= 0) return _EpisodeMatch(i, index);
    }
    return null;
  }

  /// 在一条线路里找到与 [name] 对应的集。
  ///
  /// 先精确匹配集名，再按「第 N 集」的编号匹配；都对不上就返回 -1。
  /// 宁可少一个候选，也不要播错集。
  static int _matchEpisode(PlayLine line, String name) {
    if (name.isEmpty) return -1;
    for (int i = 0; i < line.episodes.length; i++) {
      if (line.episodes[i].name.trim() == name) return i;
    }
    final int? number = _episodeNumber(name);
    if (number != null) {
      for (int i = 0; i < line.episodes.length; i++) {
        if (_episodeNumber(line.episodes[i].name) == number) return i;
      }
    }
    return -1;
  }

  /// 从集名里提取序号：`第01集` / `01` / `第 1 话` 都能取出 1。
  static int? _episodeNumber(String name) {
    final RegExpMatch? match = RegExp(r'(\d+)').firstMatch(name);
    if (match == null) return null;
    return int.tryParse(match.group(1)!);
  }

  /// 两个片名是否算同一部片子。
  ///
  /// 归一化（去空白、去「高清」「国语」这类后缀）后相等，
  /// 或者一方是另一方的前缀且只多出少量修饰字，就算同一部。
  static bool _sameTitle(String a, String b) {
    final String x = _normalizeTitle(a);
    final String y = _normalizeTitle(b);
    if (x.isEmpty || y.isEmpty) return false;
    if (x == y) return true;
    if (x.startsWith(y) && x.length - y.length <= 4) return true;
    if (y.startsWith(x) && y.length - x.length <= 4) return true;
    return false;
  }

  /// 去掉片名里的空白与常见修饰后缀，便于跨站比对。
  static String _normalizeTitle(String raw) {
    String text = raw.trim().replaceAll(RegExp(r'\s+'), '');
    for (final String suffix in const <String>[
      '国语',
      '粤语',
      '台配',
      '高清',
      'HD',
      'hd',
      '完整版',
      '未删减',
      '在线观看',
      '免费观看',
    ]) {
      if (text.endsWith(suffix) && text.length > suffix.length) {
        text = text.substring(0, text.length - suffix.length);
      }
    }
    return text;
  }
}

/// 线路与集的定位结果。
class _EpisodeMatch {
  const _EpisodeMatch(this.lineIndex, this.episodeIndex);

  final int lineIndex;
  final int episodeIndex;
}
