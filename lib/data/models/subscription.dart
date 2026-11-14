import '../../core/utils/text_utils.dart';

/// 一条订阅：一个地址，拉回一批资源站。
///
/// 借鉴 XPTV 的订阅玩法，但比它多记一份"上次拉到了哪些源"：
/// 刷新时订阅里消失的源只做**停用**，不删除 —— 用户可能正靠那个站看剧，
/// 而订阅地址往往由别人维护，说没就没。
class Subscription {
  const Subscription({
    required this.id,
    required this.name,
    required this.url,
    this.enabled = true,
    this.lastFetchedAt,
    this.sourceCount = 0,
    this.sourceIds = const <String>[],
    this.lastError = '',
  });

  final String id;
  final String name;
  final String url;
  final bool enabled;

  /// 上次成功拉取的时间；null 表示还没拉过。
  final DateTime? lastFetchedAt;

  /// 上次拉到的源数量。
  final int sourceCount;

  /// 上次拉到的源 ID，用来判断"这次少了的"是哪些。
  final List<String> sourceIds;

  /// 上次失败的原因，成功后清空。
  final String lastError;

  factory Subscription.create({required String name, required String url}) {
    final String trimmed = url.trim();
    return Subscription(
      id: hashId(trimmed),
      name: name.trim().isEmpty ? _fallbackName(trimmed) : name.trim(),
      url: trimmed,
    );
  }

  factory Subscription.fromJson(Map<String, dynamic> json) {
    final String url = strOf(json['url']);
    final List<String> ids = <String>[];
    final Object? rawIds = json['sourceIds'];
    if (rawIds is List) {
      for (final Object? e in rawIds) {
        final String id = strOf(e);
        if (id.isNotEmpty) ids.add(id);
      }
    }
    return Subscription(
      id: strOf(json['id']).isEmpty ? hashId(url) : strOf(json['id']),
      name: strOf(json['name']).isEmpty ? _fallbackName(url) : strOf(json['name']),
      url: url,
      enabled: json['enabled'] != false,
      lastFetchedAt: DateTime.tryParse(strOf(json['lastFetchedAt'])),
      sourceCount: intOf(json['sourceCount']),
      sourceIds: ids,
      lastError: strOf(json['lastError']),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'url': url,
        'enabled': enabled,
        'lastFetchedAt': lastFetchedAt?.toIso8601String(),
        'sourceCount': sourceCount,
        'sourceIds': sourceIds,
        'lastError': lastError,
      };

  bool get isUsable {
    final Uri? uri = Uri.tryParse(url);
    return uri != null && uri.hasScheme && uri.host.isNotEmpty;
  }

  /// 距离上次成功拉取多久；从没拉过返回 null。
  Duration? ageFrom(DateTime now) {
    final DateTime? at = lastFetchedAt;
    if (at == null) return null;
    return now.difference(at);
  }

  Subscription copyWith({
    String? name,
    String? url,
    bool? enabled,
    DateTime? lastFetchedAt,
    int? sourceCount,
    List<String>? sourceIds,
    String? lastError,
  }) =>
      Subscription(
        id: id,
        name: name ?? this.name,
        url: url ?? this.url,
        enabled: enabled ?? this.enabled,
        lastFetchedAt: lastFetchedAt ?? this.lastFetchedAt,
        sourceCount: sourceCount ?? this.sourceCount,
        sourceIds: sourceIds ?? this.sourceIds,
        lastError: lastError ?? this.lastError,
      );

  /// 没填名字时拿地址最后一段当名字，总比一串 URL 好认。
  static String _fallbackName(String url) {
    final Uri? uri = Uri.tryParse(url);
    if (uri == null) return '未命名订阅';
    final String host = uri.host;
    if (host.isEmpty) return '未命名订阅';
    final List<String> parts =
        uri.pathSegments.where((String s) => s.isNotEmpty).toList();
    if (parts.isEmpty) return host;
    return '${parts.last} · $host';
  }
}

/// 一次刷新订阅的结果。
class SubscribeResult {
  const SubscribeResult({
    required this.subscription,
    required this.added,
    required this.updated,
    required this.offline,
  });

  final Subscription subscription;

  /// 新增的源数量。
  final int added;

  /// 已存在、本次被更新的源数量。
  final int updated;

  /// 订阅里已经消失、被停用的源数量。
  final int offline;

  int get total => subscription.sourceCount;

  String get summary {
    final List<String> parts = <String>[
      if (added > 0) '新增 $added',
      if (updated > 0) '更新 $updated',
      if (offline > 0) '下线 $offline',
      if (added == 0 && updated == 0 && offline == 0) '没有变化',
    ];
    return parts.join(' · ');
  }
}
