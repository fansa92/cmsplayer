import '../../core/errors.dart';
import '../../core/utils/text_utils.dart';
import '../models/paged_result.dart';
import '../models/vod_category.dart';
import '../models/vod_item.dart';

/// 老版 macCMS 采集接口的 XML 响应解析。
///
/// v8 / 早期 v10 的 `/api.php/provide/vod/?ac=videolist` 默认输出 RSS 风格
/// 的 XML，字段名和现在的 `vod_*` 完全是两套：
///
/// ```xml
/// <rss version="5.0">
///   <list page="1" pagecount="23" pagesize="20" recordcount="449">
///     <video>
///       <id>493</id><tid>9</tid><name><![CDATA[流浪地球]]></name>
///       <type>恐怖片</type><pic>...</pic><year>2012</year>
///       <dl><dd from="qvod"><![CDATA[第1集$qvod://...#第2集$...]]></dd></dl>
///       <des><![CDATA[<p>简介</p>]]></des>
///     </video>
///   </list>
///   <class><ty id="1">电影</ty><ty id="5">动作片</ty></class>
/// </rss>
/// ```
///
/// 这里不引第三方 XML 包：结构固定、层级很浅，用正则按标签取值即可，
/// 还能顺手把 CDATA 和 `<des>` 里的 HTML 都归一成 `VodItem` 认识的字段，
/// 后续解码实体、拆播放地址全部复用 [VodItem.fromJson] 的既有逻辑。
class XmlVodParser {
  XmlVodParser._();

  /// 是不是一份 XML 响应（而不是 HTML 错误页）。
  static bool looksLikeXml(String body) {
    final String head = body.trimLeft().toLowerCase();
    return head.startsWith('<?xml') ||
        head.startsWith('<rss') ||
        head.startsWith('<list') ||
        head.startsWith('<video');
  }

  static VodPage parse(String body, {String? requestUrl}) {
    final String raw = body.replaceAll('\uFEFF', '').trim();
    if (!looksLikeXml(raw)) {
      throw VodException(
        '响应不是合法 JSON 或 macCMS XML（可能是接口已失效或需要代理）',
        url: requestUrl,
      );
    }

    final RegExpMatch? listTag =
        RegExp(r'<list\b([^>]*)>', caseSensitive: false).firstMatch(raw);
    final String listAttrs = listTag?.group(1) ?? '';

    final List<VodItem> items = <VodItem>[];
    for (final RegExpMatch m in RegExp(
      r'<video\b[^>]*>([\s\S]*?)</video>',
      caseSensitive: false,
    ).allMatches(raw)) {
      final VodItem item = _video(m.group(1) ?? '');
      if (!item.isEmpty) items.add(item);
    }

    // 有些站把一条片子写成 <item> 而不是 <video>。
    if (items.isEmpty) {
      for (final RegExpMatch m in RegExp(
        r'<item\b[^>]*>([\s\S]*?)</item>',
        caseSensitive: false,
      ).allMatches(raw)) {
        final VodItem item = _video(m.group(1) ?? '');
        if (!item.isEmpty) items.add(item);
      }
    }

    final List<VodCategory> categories = _classes(raw);
    final int page = _intAttr(listAttrs, 'page', 1);
    int pageCount = _intAttr(listAttrs, 'pagecount', 0);
    final int total = _intAttr(listAttrs, 'recordcount', items.length);
    if (pageCount <= 0) {
      final int size = _intAttr(listAttrs, 'pagesize', 0);
      pageCount = size <= 0 ? 1 : (total / size).ceil();
      if (pageCount < page) pageCount = page;
    }

    return VodPage(
      items: items,
      page: page,
      pageCount: pageCount < 1 ? 1 : pageCount,
      total: total,
      categories: categories,
    );
  }

  static VodItem _video(String block) {
    final List<String> froms = <String>[];
    final List<String> urls = <String>[];
    // <dl> 里每个 <dd> 是一条线路：from 属性是线路名，正文是集数串。
    for (final RegExpMatch m in RegExp(
      r'<dd\b([^>]*)>([\s\S]*?)</dd>',
      caseSensitive: false,
    ).allMatches(block)) {
      final String content = _text(m.group(2) ?? '');
      if (content.isEmpty) continue;
      froms.add(_attr(m.group(1) ?? '', 'from'));
      urls.add(content);
    }

    return VodItem.fromJson(<String, dynamic>{
      'vod_id': intOf(_tag(block, 'id')),
      'vod_name': _tag(block, 'name'),
      'vod_pic': _tag(block, 'pic'),
      'type_id': intOf(_tag(block, 'tid')),
      'type_name': _tag(block, 'type'),
      'vod_remarks': _tag(block, 'note'),
      'vod_year': _tag(block, 'year'),
      'vod_area': _tag(block, 'area'),
      'vod_lang': _tag(block, 'lang'),
      'vod_actor': _tag(block, 'actor'),
      'vod_director': _tag(block, 'director'),
      // <des> 常夹 HTML；<dl> 的播放地址不能走去标签，所以单独处理。
      'vod_content': stripHtml(_tag(block, 'des')),
      'vod_time': _tag(block, 'last'),
      'vod_isend': _tag(block, 'state'),
      'vod_play_from': froms.join(r'$$$'),
      'vod_play_url': urls.join(r'$$$'),
    });
  }

  static List<VodCategory> _classes(String raw) {
    final RegExpMatch? classBlock = RegExp(
      r'<class\b[^>]*>([\s\S]*?)</class>',
      caseSensitive: false,
    ).firstMatch(raw);
    if (classBlock == null) return const <VodCategory>[];

    final List<VodCategory> result = <VodCategory>[];
    for (final RegExpMatch m in RegExp(
      r'<ty\b([^>]*)>([\s\S]*?)</ty>',
      caseSensitive: false,
    ).allMatches(classBlock.group(1) ?? '')) {
      final int id = intOf(_attr(m.group(1) ?? '', 'id'));
      final String name = decodeEntities(_text(m.group(2) ?? '')).trim();
      if (id > 0 && name.isNotEmpty) {
        result.add(VodCategory(id: id, name: name));
      }
    }
    return result;
  }

  /// 取标签正文，剥掉 CDATA 包裹与常见实体。
  static String _tag(String block, String name) {
    final RegExpMatch? match = RegExp(
      '<$name\\b[^>]*>([\\s\\S]*?)</$name>',
      caseSensitive: false,
    ).firstMatch(block);
    if (match == null) return '';
    return _text(match.group(1) ?? '');
  }

  static String _text(String raw) => decodeEntities(
        raw
            .replaceAll('<![CDATA[', '')
            .replaceAll(']]>', '')
            .replaceAll(RegExp(r'<!--[\s\S]*?-->'), '')
            .trim(),
      );

  static String _attr(String attrs, String name) {
    final RegExpMatch? match = RegExp(
      '$name\\s*=\\s*["\']([^"\']*)["\']',
      caseSensitive: false,
    ).firstMatch(attrs);
    return match?.group(1)?.trim() ?? '';
  }

  static int _intAttr(String attrs, String name, int fallback) =>
      int.tryParse(_attr(attrs, name)) ?? fallback;
}
