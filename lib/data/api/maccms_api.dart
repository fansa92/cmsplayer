import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/errors.dart';
import '../../core/logger.dart';
import '../models/paged_result.dart';
import '../models/vod_category.dart';
import '../models/vod_item.dart';
import '../models/vod_source.dart';

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
/// | `yy` / `area` / `lang` | 年代 / 地区 / 语言 |
/// | `by` | 排序：`time` / `hits` / `score` / `input` |
/// | `h` / `m` | 24 小时 / 本月热播 |
class MacCmsApi {
  MacCmsApi(this.source, {http.Client? client})
      : _client = client ?? _shared;

  static final http.Client _shared = http.Client();

  final VodSource source;
  final http.Client _client;

  // ---------------------------------------------------------------- 基础

  Uri _uri(Map<String, String> params) {
    final String api = VodSource.normalizeApi(source.api);
    final Uri? base = Uri.tryParse(api);
    if (base == null || !base.hasScheme || base.host.isEmpty) {
      throw VodException('资源站接口地址无效', url: source.api);
    }
    final Map<String, String> merged = <String, String>{
      ...base.queryParameters,
      ...params,
    };
    return base.replace(queryParameters: merged);
  }

  Future<VodPage> _fetch(Map<String, String> params) async {
    final String pageSize =
        params['pagesize'] ?? params['limit'] ?? '20';
    final Map<String, String> finalParams = <String, String>{
      ...params,
      'pagesize': pageSize,
      'limit': pageSize,
    };

    final Uri uri = _uri(finalParams);
    AppLog.d('MacCms', 'GET $uri');

    try {
      final http.Request request = http.Request('GET', uri);
      request.headers.addAll(source.headers);
      final http.StreamedResponse streamed = await _client
          .send(request)
          .timeout(const Duration(seconds: 20));
      final http.Response response =
          await http.Response.fromStream(streamed).timeout(
        const Duration(seconds: 30),
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw VodException('HTTP ${response.statusCode}', url: uri.toString());
      }

      return parseVodPage(response.body, requestUrl: uri.toString());
    } on VodException {
      rethrow;
    } on TimeoutException {
      throw VodException('请求超时', url: uri.toString());
    } on Object catch (e) {
      throw VodException('请求失败：$e', url: uri.toString(), cause: e);
    }
  }

  // ---------------------------------------------------------------- 查询

  /// 列表或分类页。`detail: true` 时返回的条目才带播放地址。
  Future<VodPage> query({
    int page = 1,
    int pageSize = 20,
    int typeId = 0,
    String? keyword,
    String? year,
    String? area,
    String? lang,
    String? sortBy,
    bool detail = false,
  }) {
    final Map<String, String> params = <String, String>{
      'ac': detail ? 'detail' : 'list',
      'pg': '$page',
      'pagesize': '$pageSize',
    };
    if (typeId > 0) params['t'] = '$typeId';
    final String? kw = keyword?.trim();
    if (kw != null && kw.isNotEmpty) params['wd'] = kw;
    final String? yy = year?.trim();
    if (yy != null && yy.isNotEmpty) params['yy'] = yy;
    final String? ar = area?.trim();
    if (ar != null && ar.isNotEmpty) params['area'] = ar;
    final String? lg = lang?.trim();
    if (lg != null && lg.isNotEmpty) params['lang'] = lg;
    final String? by = sortBy?.trim();
    if (by != null && by.isNotEmpty) params['by'] = by;
    return _fetch(params);
  }

  /// 拉取该站点的分类表（`class` 字段随任意一次响应返回）。
  Future<List<VodCategory>> categories() async {
    final VodPage page = await query(pageSize: 1, detail: false);
    return page.categories;
  }

  /// 按 ID 拉取详情（含播放地址）。
  Future<VodItem?> detail(int id) async {
    final VodPage page = await _fetch(<String, String>{
      'ac': 'detail',
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
    final VodPage page = await _fetch(<String, String>{
      'ac': 'detail',
      'ids': ids.join(','),
      'pagesize': '${ids.length}',
      'limit': '${ids.length}',
    });
    return page.items;
  }

  /// 热播。部分站点不支持 `h` / `m` 参数，会回退到第一个分类。
  Future<VodPage> hot({int page = 1, int pageSize = 20, int hours = 24}) async {
    try {
      final VodPage result = await _fetch(<String, String>{
        'ac': 'detail',
        'h': '$hours',
        'pg': '$page',
        'pagesize': '$pageSize',
      });
      if (result.items.isNotEmpty) return result;
    } on VodException catch (e) {
      AppLog.d('MacCms', 'hot(h=$hours) unsupported, fallback: $e');
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
    final String raw = body.trim();
    if (raw.isEmpty) throw const VodException('资源站返回了空响应');

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
            '响应不是合法 JSON（可能是接口已失效或需要代理）',
            url: requestUrl,
            cause: e,
          );
        }
      } else {
        throw VodException(
          '响应不是合法 JSON（可能是接口已失效或需要代理）',
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

    final List<VodItem> items = _asMapList(map['list'])
        .map(VodItem.fromJson)
        .toList();

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
