import '../../core/constants.dart';
import '../../core/utils/text_utils.dart';

/// 一个 VOD 资源站（macCMS 接口）。
///
/// 官方 JSON 列表只用到 `name` / `api` / `note` 三个键；
/// 这里额外支持几个可选键，用于兼容部分需要 Referer 或解析接口的站点：
/// ```json
/// {
///   "name": "示例站",
///   "api": "https://example.com/api.php/provide/vod/",
///   "note": "备注",
///   "referer": "https://example.com/",
///   "userAgent": "Mozilla/5.0 ...",
///   "parseApi": "https://jx.example.com/?url="
/// }
/// ```
class VodSource {
  const VodSource({
    required this.id,
    required this.name,
    required this.api,
    this.note = '',
    this.parseApi = '',
    this.referer = '',
    this.userAgent = '',
    this.enabled = true,
    this.sort = 0,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String api;
  final String note;

  /// 可选解析接口前缀。播放地址不是直链时使用：`parseApi + Uri.encodeComponent(url)`。
  final String parseApi;

  /// 可选自定义 Referer，留空则用接口地址的源站。
  final String referer;

  /// 可选自定义 UA。
  final String userAgent;

  final bool enabled;
  final int sort;
  final DateTime createdAt;

  factory VodSource.fromRaw(Map<String, dynamic> json, {int sort = 0}) {
    final String api = normalizeApi(strOf(json['api']));
    final String name = strOf(json['name']);
    final Object? enabledRaw = json['enabled'];
    return VodSource(
      id: hashId('$name|$api'),
      name: name.isEmpty ? hostOf(api) : name,
      api: api,
      note: strOf(json['note']),
      parseApi: strOf(json['parseApi'] ?? json['jx']),
      referer: strOf(json['referer']),
      userAgent: strOf(json['userAgent'] ?? json['ua']),
      enabled: enabledRaw == null
          ? true
          : (enabledRaw == true || enabledRaw == 1 || enabledRaw == '1'),
      sort: intOf(json['sort'], sort),
      createdAt: DateTime.tryParse(strOf(json['createdAt'])) ?? DateTime.now(),
    );
  }

  factory VodSource.fromJson(Map<String, dynamic> json) =>
      VodSource.fromRaw(json);

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'api': api,
        'note': note,
        'parseApi': parseApi,
        'referer': referer,
        'userAgent': userAgent,
        'enabled': enabled,
        'sort': sort,
        'createdAt': createdAt.toIso8601String(),
      };

  /// 接口地址的源站，例如 `https://example.com`。
  String get origin => originOf(api);

  bool get isUsable => api.isNotEmpty && id.isNotEmpty;

  /// 请求头。Referer 为空时用源站兜底，很多资源站会拒绝无 Referer 的请求。
  Map<String, String> get headers {
    final String ua = userAgent.isEmpty ? K.defaultUserAgent : userAgent;
    final String ref = referer.isNotEmpty
        ? referer
        : (origin.isEmpty ? '' : '$origin/');
    return <String, String>{
      'User-Agent': ua,
      if (ref.isNotEmpty) 'Referer': ref,
      'Accept': '*/*',
    };
  }

  VodSource copyWith({
    String? name,
    String? api,
    String? note,
    String? parseApi,
    String? referer,
    String? userAgent,
    bool? enabled,
    int? sort,
  }) =>
      VodSource(
        id: id,
        name: name ?? this.name,
        api: api ?? this.api,
        note: note ?? this.note,
        parseApi: parseApi ?? this.parseApi,
        referer: referer ?? this.referer,
        userAgent: userAgent ?? this.userAgent,
        enabled: enabled ?? this.enabled,
        sort: sort ?? this.sort,
        createdAt: createdAt,
      );

  /// 规范化接口地址：去尾部 `?`，必要时补 `/`。
  static String normalizeApi(String raw) {
    String api = raw.trim();
    if (api.isEmpty) return '';
    while (api.endsWith('?') || api.endsWith('#')) {
      api = api.substring(0, api.length - 1);
    }
    api = api.trimRight();
    if (api.isEmpty) return '';
    if (!api.contains('?') && !api.endsWith('/')) api = '$api/';
    return api;
  }

  static String hostOf(String api) {
    final Uri? uri = Uri.tryParse(api);
    if (uri == null || uri.host.isEmpty) return '未命名资源站';
    return uri.host;
  }

  @override
  bool operator ==(Object other) => other is VodSource && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'VodSource($name, $api)';
}
