import '../../core/constants.dart';
import '../../core/logger.dart';
import '../../core/storage/json_store.dart';
import '../models/vod_source.dart';

/// 资源站持久化。
class SourceRepository {
  SourceRepository._();

  static Future<List<VodSource>> load() async {
    final List<Map<String, dynamic>> raw = await JsonStore.readList(K.boxSources);
    final List<VodSource> sources = <VodSource>[];
    final Set<String> seen = <String>{};
    for (final Map<String, dynamic> json in raw) {
      try {
        final VodSource source = VodSource.fromJson(json);
        if (!source.isUsable) continue;
        if (!seen.add(source.id)) continue;
        sources.add(source);
      } on Object catch (e) {
        AppLog.e('SourceRepository', 'bad source entry: $e');
      }
    }

    if (sources.isEmpty) return builtin();
    sources.sort((VodSource a, VodSource b) => a.sort.compareTo(b.sort));
    return sources;
  }

  static Future<void> save(List<VodSource> sources) async {
    await JsonStore.writeList(
      K.boxSources,
      sources.map((VodSource s) => s.toJson()).toList(),
    );
  }

  /// 首次启动的内置示例源。
  static List<VodSource> builtin() {
    final List<VodSource> list = K.builtinSources
        .asMap()
        .entries
        .map((MapEntry<int, Map<String, String>> e) =>
            VodSource.fromRaw(e.value, sort: e.key))
        .toList();
    list.sort((VodSource a, VodSource b) => a.sort.compareTo(b.sort));
    return list;
  }
}
