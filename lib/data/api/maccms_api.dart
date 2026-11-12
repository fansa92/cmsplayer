import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/errors.dart';
import '../../core/logger.dart';
import '../../core/utils/encoding.dart';
import '../../core/utils/text_utils.dart';
import '../models/paged_result.dart';
import '../models/vod_category.dart';
import '../models/vod_item.dart';
import '../models/vod_source.dart';
import 'xml_vod_parser.dart';

/// 热播榜单的时间窗。
enum HotWindow {
  /// 最近 24 小时（macCMS 的 `h` 参数）。
  day,

  /// 最近一个月（macCMS 的 `m` 参数）。
  month,
}

/// macCMS（苹果CMS）VOD 接口客户端。
///
/// 支持的查询参数与官方 v10 保持一致：
///
/// | 参数 | 含义 |
/// |------|------|
/// | `ac` | `list` 简要列表 / `detail` 详细数据（含播放地址） |
/// | `t`  | 分类 ID |
/// | `pg` | 页码，从 1 开始 |
/// | `pagesize` / `limit` | 每页条数 |
/// | `wd` | 关键词搜索 |
/// | `ids` | 按 ID 查询，逗号分隔 |
/// | `year` / `area` / `lang` | 年代 / 地区 / 语言 |
/// | `by` / `order` | 排序字段 / 排序方向（`asc` / `desc`） |
/// | `letter` | 片名首字母，A–Z |
/// | `h` / `m` | 24 小时 / 本月热播 |
/// | `at` | 输出格式，默认 `json`；老站返回 XML 时另走 [XmlVodParser] |
///
/// `ac` 的第三个取值 `videolist` 是老采集接口的全字段模式，按 ID 取详情
/// 失败或没带播放地址时会自动重试，详见 [_fetchDetailByIds]。
class MacCmsApi {
  MacCmsApi(this.source, {http.Client? client}) : _client = client ?? _shared;

  static final http.Client _shared = http.Client();

  final VodSource source;
  final http.Client _client;

  // ------------------------------------------------------------ 兼容性记忆

  /// 每个源记住「哪种 ac 真的能拿到播放地址」，默认 `detail`。
  static final Map<String, String> _detailAction = <String, String>{};

  /// 两种动作都拿不到播放地址的源，不再每次详情都白试一遍。
  static final Set<String> _detailFallbackTried = <String>{};

  /// REST 联想词接口不可用的源，后续直接走 Provide 兜底。
  static final Set<String> _restSuggestUnsupported = <String>{};

  /// 测试收尾时清掉会话级记忆，避免用例之间互相影响。
  static void resetCompatForTest() {
    _detailAction.clear();
    _detailFallbackTried.clear();
    _restSuggestUnsupported.clear();
  }

  // ---------------------------------------------------------------- 基础

  Uri _uri(Map<String, String> params) {
    final String api = VodSource.normalizeApi(source.api);
    final Uri? base = Uri.tryParse(api);
    if (base == null || !base.hasScheme || base.host.isEmpty) {
      throw VodException('资源站接口地址无效', url: source.api);
    }
    // http 包只认 http/https；放行 cms:// 之类会抛 Unsupported scheme，
    // 到 UI 上就成了一个没有上下文的加载失败。
    if (base.scheme != 'http' && base.scheme != 'https') {
      throw VodException(
        '资源站协议不支持（${base.scheme}://），仅支持 http / https 接口',
        url: source.api,
      );
    }
    final Map<String, String> merged = <String, String>{
      ...base.queryParameters,
      ...params,
    };
    return base.replace(queryParameters: merged);
  }

  /// 发一次 GET，按字节解码后返回文本。错误统一包成 [VodException]。
  Future<String> _get(Uri uri) async {
    AppLog.d('MacCms', 'GET $uri');
    try {
      final http.Request request = http.Request('GET', uri);
      request.headers.addAll(source.headers);
      final http.StreamedResponse streamed =
          await _client.send(request).timeout(const Duration(seconds: 20));
      final http.Response response =
          await http.Response.fromStream(streamed).timeout(
        const Duration(seconds: 30),
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw VodException('HTTP ${response.statusCode}', url: uri.toString());
      }

      // 不用 response.body：它只按 UTF-8 / Latin-1 解码，遇到 GBK 老站
      // 会直接抛 FormatException。改成自己按字节解码，编码优先级见
      // [ResponseDecoder]。
      return ResponseDecoder.decode(
        response.bodyBytes,
        preferredCharset: source.charset,
        contentType: response.headers['content-type'],
      );
    } on VodException {
      rethrow;
    } on TimeoutException {
      throw VodException('请求超时', url: uri.toString());
    } on Object catch (e) {
      throw VodException('请求失败：$e', url: uri.toString(), cause: e);
    }
  }

  Future<VodPage> _fetch(Map<String, String> params) async {
    final String pageSize = params['pagesize'] ?? params['limit'] ?? '20';
    final Map<String, String> finalParams = <String, String>{
      ...params,
      'pagesize': pageSize,
      'limit': pageSize,
      // 老站默认吐 XML；显式要 JSON 能省掉一次解析分支，不认 at 的站忽略即可。
      'at': params['at'] ?? 'json',
    };
    final Uri uri = _uri(finalParams);
    final String body = await _get(uri);
    return parseVodPage(body, requestUrl: uri.toString());
  }

  /// 按 ID 取详情时的 `detail` → `videolist` 自动降级。
  ///
  /// 老采集接口只认 `ac=videolist`，`ac=detail` 会退化成精简列表：HTTP 200、
  /// 条目也在，就是没有 `vod_play_url`。所以除了请求抛错，**拿到条目却没有
  /// 播放地址**也要重试一次。列表查询不走这里 —— 列表本来就不需要播放地址，
  /// 否则每次翻页都会白打一次请求。
  Future<VodPage> _fetchDetailByIds(Map<String, String> params) async {
    final String primary = _detailAction[source.id] ?? 'detail';
    final String alternate = primary == 'detail' ? 'videolist' : 'detail';

    VodPage? firstPage;
    VodException? firstError;
    try {
      firstPage = await _fetch(<String, String>{...params, 'ac': primary});
    } on VodException catch (e) {
      firstError = e;
    }

    bool playable(VodPage? page) =>
        page != null && page.items.any((VodItem e) => e.hasPlayInfo);

    final bool needFallback = firstPage == null ||
        (firstPage.items.isNotEmpty && !playable(firstPage));
    if (!needFallback || _detailFallbackTried.contains(source.id)) {
      if (firstPage == null) throw firstError!;
      return firstPage;
    }

    try {
      final VodPage alt =
          await _fetch(<String, String>{...params, 'ac': alternate});
      if (playable(alt) && !playable(firstPage)) {
        _detailAction[source.id] = alternate;
        _detailFallbackTried.remove(source.id);
        return alt;
      }
      _detailFallbackTried.add(source.id);
      return firstPage ?? alt;
    } on VodException {
      _detailFallbackTried.add(source.id);
      if (firstPage == null) throw firstError!;
      return firstPage;
    }
  }

  // ---------------------------------------------------------------- 查询

  /// 列表或分类页。`detail: true` 时返回的条目才带播放地址。
  ///
  /// [typeIds] 非空时优先于 [typeId]：macCMS 的 `t` 支持逗号分隔的多个
  /// 分类 id（如 `t=6,7`），用来做分类多选。
  Future<VodPage> query({
    int page = 1,
    int pageSize = 20,
    int typeId = 0,
    List<int> typeIds = const <int>[],
    String? keyword,
    String? year,
    String? area,
    String? lang,
    String? sortBy,
    String? order,
    String? letter,
    bool? isEnd,
    bool detail = false,
  }) {
    final Map<String, String> params = <String, String>{
      'ac': detail ? 'detail' : 'list',
      'pg': '$page',
      'pagesize': '$pageSize',
    };
    final List<int> ids = typeIds.where((int e) => e > 0).toList();
    if (ids.isNotEmpty) {
      params['t'] = ids.join(',');
    } else if (typeId > 0) {
      params['t'] = '$typeId';
    }
    // `isend` 不是 macCMS v10 `provide/vod` 的标准参数，认它的站点会把
    // 结果过滤掉，不认的站点直接忽略。所以调用方拿到响应后还要本地再筛
    // 一遍，不能只靠服务端。
    if (isEnd != null) params['isend'] = isEnd ? '1' : '0';
    final String? kw = keyword?.trim();
    if (kw != null && kw.isNotEmpty) params['wd'] = kw;
    // 注意：macCMS 的年份参数是 `year`，不是 `yy`。
    // 实测 cj.ffzyapi.com：`year=2024` total 98497→10963 且返回项全部为 2024；
    // `yy=2024` 与不带参数的结果 total 和 id 序列完全一致，即被彻底忽略。
    final String? yy = year?.trim();
    if (yy != null && yy.isNotEmpty) params['year'] = yy;
    final String? ar = area?.trim();
    if (ar != null && ar.isNotEmpty) params['area'] = ar;
    final String? lg = lang?.trim();
    if (lg != null && lg.isNotEmpty) params['lang'] = lg;
    final String? by = sortBy?.trim();
    if (by != null && by.isNotEmpty) params['by'] = by;
    // `order` / `letter` 都属于站点可选实现（typefilter），认不认都得在
    // 调用方本地再兜一层，不能只指望服务端。
    final String? od = order?.trim().toLowerCase();
    if (od != null && (od == 'asc' || od == 'desc')) params['order'] = od;
    final String? lt = letter?.trim().toUpperCase();
    if (lt != null && RegExp(r'^[A-Z]$').hasMatch(lt)) {
      params['letter'] = lt;
    }
    return _fetch(params);
  }

  /// 拉取该站点的分类表（`class` 字段随任意一次响应返回）。
  Future<List<VodCategory>> categories() async {
    final VodPage page = await query(pageSize: 1, detail: false);
    return page.categories;
  }

  /// 按 ID 拉取详情（含播放地址）。
  Future<VodItem?> detail(int id) async {
    final VodPage page = await _fetchDetailByIds(<String, String>{
      'ids': '$id',
      'pagesize': '1',
      'limit': '1',
    });
    if (page.items.isEmpty) return null;
    return page.items.first;
  }

  /// 按 ID 批量拉取详情。
  Future<List<VodItem>> detailsByIds(List<int> ids) async {
    if (ids.isEmpty) return const <VodItem>[];
    final VodPage page = await _fetchDetailByIds(<String, String>{
      'ids': ids.join(','),
      'pagesize': '${ids.length}',
      'limit': '${ids.length}',
    });
    return page.items;
  }

  /// 热播。部分站点不支持 `h` / `m` 参数，会回退到第一个分类。
  ///
  /// [window] 决定用哪个时间窗：`h=24` 是最近 24 小时，`m=30` 是最近
  /// 一个月。两个参数都是 macCMS 的约定，实测多数站点至少认其中一个。
  Future<VodPage> hot({
    int page = 1,
    int pageSize = 20,
    HotWindow window = HotWindow.day,
  }) async {
    final bool month = window == HotWindow.month;
    try {
      final VodPage result = await _fetch(<String, String>{
        'ac': 'detail',
        if (month) 'm': '30' else 'h': '24',
        'pg': '$page',
        'pagesize': '$pageSize',
      });
      if (result.items.isNotEmpty) return result;
    } on VodException catch (e) {
      AppLog.d('MacCms', 'hot($window) unsupported, fallback: $e');
    }
    return _fallbackList(page: page, pageSize: pageSize);
  }

  /// 退化方案：直接取第一个分类的最新内容。
  Future<VodPage> _fallbackList({int page = 1, int pageSize = 20}) async {
    try {
      return await query(page: page, pageSize: pageSize, detail: true);
    } on VodException {
      return query(page: page, pageSize: pageSize, detail: false);
    }
  }

  // ---------------------------------------------------------------- 联想词

  /// 搜索联想词。
  ///
  /// macCMS 有两套联想接口（`/api.php/vod/suggest` 与老模板用的
  /// `/index.php/ajax/suggest`），不同版本返回的字段还不一样；都不认的站点
  /// 就退回所有 macCMS 都支持的 `ac=list&wd=` 拿前几部片名当建议。
  /// 任何一步失败都静默降级，绝不因为「联想不出来」而打断搜索。
  Future<List<String>> suggest(String keyword, {int limit = 10}) async {
    final String q = keyword.trim();
    if (q.isEmpty) return const <String>[];

    if (!_restSuggestUnsupported.contains(source.id)) {
      for (final Uri uri in _suggestEndpoints(q, limit)) {
        final List<String> words = await _trySuggestRest(uri, q, limit);
        if (words.isNotEmpty) return words;
      }
      // 两个 REST 端点都没给出东西，这个会话里不再逐个试，直接走兜底。
      _restSuggestUnsupported.add(source.id);
    }

    try {
      final VodPage page =
          await query(pageSize: limit, keyword: q, detail: false);
      return _uniqueNames(page.items.map((VodItem e) => e.name), q, limit);
    } on VodException catch (e) {
      AppLog.d('MacCms', 'suggest fallback failed: $e');
      return const <String>[];
    }
  }

  Future<List<String>> _trySuggestRest(
    Uri uri,
    String q,
    int limit,
  ) async {
    try {
      return parseSuggest(await _get(uri), exclude: q, limit: limit);
    } on Object catch (e) {
      AppLog.d('MacCms', 'suggest REST unavailable: $e');
      return const <String>[];
    }
  }

  /// 从 Provide 接口地址推导两个 REST 联想端点，保留 URL 里自带的 token。
  List<Uri> _suggestEndpoints(String q, int limit) {
    final Uri base = Uri.parse(VodSource.normalizeApi(source.api));
    final String path = base.path.replaceAll(RegExp(r'/+$'), '');
    final int at = path.indexOf('/provide/');
    // `/api.php/provide/vod/` → `/api.php`；没有 provide 段就退回站点根。
    final String apiPhp = at >= 0 ? path.substring(0, at) : '/api.php';
    final String indexPhp =
        apiPhp.replaceFirst(RegExp(r'api\.php$'), 'index.php');

    Uri build(String p, Map<String, String> query) => base.replace(
          path: p,
          queryParameters: <String, String>{...base.queryParameters, ...query},
        );

    return <Uri>[
      build('$apiPhp/vod/suggest', <String, String>{
        'wd': q,
        'limit': '$limit',
      }),
      build('$indexPhp/ajax/suggest', <String, String>{
        'mid': '1',
        'wd': q,
        'limit': '$limit',
        'timestamp': '${DateTime.now().millisecondsSinceEpoch}',
      }),
    ];
  }

  /// 解析联想响应：顶层数组或 `{info|list|data|...}` 都吃，数组元素可以是
  /// 字符串，也可以是带 `name` / `vod_name` / `word` 的对象。
  static List<String> parseSuggest(
    String body, {
    String exclude = '',
    int limit = 10,
  }) {
    Object? data;
    try {
      data = jsonDecode(body.replaceAll('\uFEFF', '').trim());
    } on Object {
      return const <String>[];
    }

    List<Object?> candidates = const <Object?>[];
    if (data is List) {
      candidates = List<Object?>.from(data);
    } else if (data is Map) {
      for (final String key in <String>[
        'info',
        'list',
        'data',
        'suggest',
        'result',
      ]) {
        final Object? value = data[key];
        if (value is List) {
          candidates = List<Object?>.from(value);
          break;
        }
        // 有些版本把词表塞在 info.list / data.list 里。
        if (value is Map && value['list'] is List) {
          candidates = List<Object?>.from(value['list'] as List);
          break;
        }
      }
    }
    return _uniqueNames(candidates.map(_suggestWord), exclude, limit);
  }

  static String _suggestWord(Object? entry) {
    if (entry is String) return entry;
    if (entry is Map) {
      for (final String key in <String>[
        'name',
        'vod_name',
        'word',
        'keyword',
        'title',
      ]) {
        final String value = strOf(entry[key]);
        if (value.isNotEmpty) return value;
      }
    }
    return '';
  }

  static List<String> _uniqueNames(
    Iterable<String> raw,
    String exclude,
    int limit,
  ) {
    final Set<String> seen = <String>{exclude.trim().toLowerCase()};
    final List<String> result = <String>[];
    for (final String value in raw) {
      final String word = decodeEntities(stripHtml(value)).trim();
      if (word.isEmpty) continue;
      if (!seen.add(word.toLowerCase())) continue;
      result.add(word);
      if (result.length >= limit) break;
    }
    return result;
  }

  /// 连通性测试：能否取回一个 JSON 结构。
  Future<bool> ping() async {
    try {
      final VodPage page = await query(pageSize: 1, detail: false);
      return page.categories.isNotEmpty || page.total > 0;
    } on Object catch (e) {
      AppLog.d('MacCms', 'ping ${source.name} failed: $e');
      return false;
    }
  }

  // ---------------------------------------------------------------- 解析

  /// 解析 macCMS 响应。
  ///
  /// 兼容两种顶层结构：
  ///  * v10 的字典 `{"code":1,"list":[...],"class":[...]}`；
  ///  * 更老版本直接返回数组 `[{...},{...}]`。
  static VodPage parseVodPage(String body, {String? requestUrl}) {
    final String raw = body.replaceAll('\uFEFF', '').trim();
    if (raw.isEmpty) throw const VodException('资源站返回了空响应');

    // 老采集接口输出 XML，字段和 vod_* 完全是两套。
    if (XmlVodParser.looksLikeXml(raw)) {
      return XmlVodParser.parse(raw, requestUrl: requestUrl);
    }

    Object? data;
    try {
      data = jsonDecode(raw);
    } on Object {
      // 有些站点会在 JSON 前后夹 HTML 注释或 BOM，尝试截取主体再试一次。
      final int start = raw.indexOf(RegExp(r'[\[{]'));
      final int end = raw.lastIndexOf(RegExp(r'[\]}]'));
      if (start >= 0 && end > start) {
        try {
          data = jsonDecode(raw.substring(start, end + 1));
        } on Object catch (e) {
          throw VodException(
            '响应不是合法 JSON 或 macCMS XML（可能是接口已失效或需要代理）',
            url: requestUrl,
            cause: e,
          );
        }
      } else {
        throw VodException(
          '响应不是合法 JSON 或 macCMS XML（可能是接口已失效或需要代理）',
          url: requestUrl,
        );
      }
    }

    // 老版本：直接是数组。
    if (data is List) {
      final List<VodItem> items = data
          .whereType<Map>()
          .map((Map e) => VodItem.fromJson(e.cast<String, dynamic>()))
          .toList();
      return VodPage(
        items: items,
        page: 1,
        pageCount: 1,
        total: items.length,
      );
    }

    if (data is! Map) {
      throw const VodException('响应格式无法识别');
    }

    final Map<String, dynamic> map = data.cast<String, dynamic>();

    final List<VodItem> items =
        _asMapList(map['list']).map(VodItem.fromJson).toList();

    // 顶层 code/msg 是源站的错误通道。以前完全忽略，`{"code":0,"msg":"接口已关闭"}`
    // 会被当成空列表，界面只说「没有内容」，用户根本不知道源站出错了。
    // 只在没有数据时才抛：少数站点用 code:0 表示「无结果」但仍带正常 list，
    // 那种情况照常展示，不要误伤。
    final Object? code = map['code'];
    final int? codeNum = code == null ? null : int.tryParse('$code');
    if (codeNum != null && codeNum <= 0 && items.isEmpty) {
      final String reason = strOf(map['msg'] ?? map['message'] ?? map['error']);
      throw VodException(
        reason.isEmpty ? '资源站返回错误（code=$code）' : reason,
        url: requestUrl,
      );
    }

    final List<VodCategory> categories = _asMapList(map['class'])
        .map(VodCategory.fromJson)
        .where((VodCategory c) => c.id > 0 && c.name.isNotEmpty)
        .toList();

    final int page = _positive(map['page'], 1);
    final int total = _positive(map['total'], items.length);
    int pageCount = _positive(map['pagecount'], 0);

    if (pageCount <= 0) {
      final int limit = _positive(map['limit'] ?? map['pagesize'], 0);
      pageCount = limit <= 0 ? 1 : (total / limit).ceil();
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

  static List<Map<String, dynamic>> _asMapList(Object? value) {
    if (value is! List) return const <Map<String, dynamic>>[];
    return value
        .whereType<Map>()
        .map((Map e) => e.cast<String, dynamic>())
        .toList();
  }

  static int _positive(Object? value, int fallback) {
    final int v = int.tryParse('$value') ?? 0;
    return v > 0 ? v : fallback;
  }

  void dispose() {
    // 共享的 [_shared] 不在这里关闭，仅关闭外部注入的实例。
    if (!identical(_client, _shared)) _client.close();
  }
}
