import 'dart:convert';

import '../../core/logger.dart';
import '../models/favorite_item.dart';
import '../models/play_record.dart';
import '../models/vod_source.dart';

/// 同步数据包的格式版本。
///
/// 只加字段、不改已有字段的含义；读到更高的版本直接拒绝合并 ——
/// 让老客户端去猜新字段的语义，只会把数据合坏。
const int kSyncFormatVersion = 1;

/// 集合名。同时也是墓碑表的键，三处必须保持一致。
class SyncBox {
  SyncBox._();

  static const String history = 'history';
  static const String favorites = 'favorites';
  static const String sources = 'sources';
  static const List<String> all = <String>[history, favorites, sources];
}

/// 一次同步搬运的全部内容：播放记录、收藏、源列表，外加删除墓碑。
class SyncPayload {
  const SyncPayload({
    required this.updatedAt,
    this.history = const <PlayRecord>[],
    this.favorites = const <FavoriteItem>[],
    this.sources = const <VodSource>[],
    this.tombstones = const <String, Map<String, int>>{},
  });

  final DateTime updatedAt;
  final List<PlayRecord> history;
  final List<FavoriteItem> favorites;
  final List<VodSource> sources;

  /// `集合名 -> (条目 key -> 删除时刻毫秒)`。
  ///
  /// 没有它，"在手机上取消收藏" 同步一次又会被电脑上的旧条目复活，
  /// 表现为收藏永远删不掉。合并时拿删除时刻和条目自身的时刻比，新的赢。
  final Map<String, Map<String, int>> tombstones;

  int get totalItems => history.length + favorites.length + sources.length;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'v': kSyncFormatVersion,
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        SyncBox.history: history.map((PlayRecord e) => e.toJson()).toList(),
        SyncBox.favorites:
            favorites.map((FavoriteItem e) => e.toJson()).toList(),
        SyncBox.sources: sources.map((VodSource e) => e.toJson()).toList(),
        'tombstones': tombstones,
      };

  String encode() => jsonEncode(toJson());

  factory SyncPayload.fromJson(Map<String, dynamic> json) {
    final Object? version = json['v'];
    if (version is num && version > kSyncFormatVersion) {
      throw FormatException(
        '远端同步数据是版本 $version，本应用只认到 $kSyncFormatVersion',
      );
    }
    return SyncPayload(
      updatedAt: DateTime.tryParse('${json['updatedAt']}') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      history: _maps(json[SyncBox.history]).map(PlayRecord.fromJson).toList(),
      favorites:
          _maps(json[SyncBox.favorites]).map(FavoriteItem.fromJson).toList(),
      sources: _maps(json[SyncBox.sources]).map(VodSource.fromJson).toList(),
      tombstones: _tombstonesOf(json['tombstones']),
    );
  }

  /// 解析远端文本。任何异常都返回 null —— 同步失败要给出可读原因，
  /// 而不是一个从 JSON 解析器里冒出来的堆栈。
  static SyncPayload? decode(String text) {
    if (text.trim().isEmpty) return null;
    try {
      final Object? decoded = jsonDecode(text);
      if (decoded is! Map) return null;
      return SyncPayload.fromJson(decoded.cast<String, dynamic>());
    } on Object catch (e) {
      AppLog.w('Sync', 'decode payload failed: $e');
      return null;
    }
  }

  /// 空数据包，用作"远端还不存在"时的本地基线。
  static SyncPayload empty() =>
      SyncPayload(updatedAt: DateTime.fromMillisecondsSinceEpoch(0));

  static List<Map<String, dynamic>> _maps(Object? raw) => raw is List
      ? raw
          .whereType<Map>()
          .map((Map e) => e.cast<String, dynamic>())
          .toList()
      : <Map<String, dynamic>>[];

  static Map<String, Map<String, int>> _tombstonesOf(Object? raw) {
    if (raw is! Map) return <String, Map<String, int>>{};
    final Map<String, Map<String, int>> out = <String, Map<String, int>>{};
    raw.forEach((Object? k, Object? v) {
      if (k == null || v is! Map) return;
      final Map<String, int> inner = <String, int>{};
      v.forEach((Object? ik, Object? iv) {
        if (ik == null || iv is! num) return;
        inner[ik.toString()] = iv.toInt();
      });
      if (inner.isNotEmpty) out[k.toString()] = inner;
    });
    return out;
  }

  /// 墓碑清理。
  ///
  /// 墓碑只用来裁决"删除 vs 改动"谁更新，一年没再碰过的删除早就尘埃落定；
  /// 不清理的话它会跟着同步无限增长。
  static Map<String, Map<String, int>> pruneTombstones(
    Map<String, Map<String, int>> raw, {
    DateTime? now,
    Duration keepFor = const Duration(days: 365),
    int maxEntries = 4000,
  }) {
    final int cutoff = (now ?? DateTime.now()).subtract(keepFor).millisecondsSinceEpoch;
    final Map<String, Map<String, int>> out = <String, Map<String, int>>{};
    final List<MapEntry<String, MapEntry<String, int>>> flat =
        <MapEntry<String, MapEntry<String, int>>>[];

    for (final MapEntry<String, Map<String, int>> e in raw.entries) {
      final Map<String, int> inner = <String, int>{};
      for (final MapEntry<String, int> ie in e.value.entries) {
        if (ie.value < cutoff) continue;
        inner[ie.key] = ie.value;
        flat.add(MapEntry<String, MapEntry<String, int>>(e.key, ie));
      }
      if (inner.isNotEmpty) out[e.key] = inner;
    }

    if (flat.length <= maxEntries) return out;

    // 超限时按时刻升序丢最老的，保留最近的 maxEntries 条。
    flat.sort((MapEntry<String, MapEntry<String, int>> a,
            MapEntry<String, MapEntry<String, int>> b) =>
        a.value.value.compareTo(b.value.value));
    final Set<String> keep = <String>{};
    for (final MapEntry<String, MapEntry<String, int>> e
        in flat.sublist(flat.length - maxEntries)) {
      keep.add('${e.key}/${e.value.key}');
    }
    final Map<String, Map<String, int>> trimmed = <String, Map<String, int>>{};
    for (final MapEntry<String, Map<String, int>> e in out.entries) {
      final Map<String, int> inner = <String, int>{};
      for (final MapEntry<String, int> ie in e.value.entries) {
        if (keep.contains('${e.key}/${ie.key}')) inner[ie.key] = ie.value;
      }
      if (inner.isNotEmpty) trimmed[e.key] = inner;
    }
    return trimmed;
  }
}
