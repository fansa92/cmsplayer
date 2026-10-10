import 'package:flutter/foundation.dart';

import '../data/models/play_record.dart';
import '../data/repository/record_repository.dart';

/// 播放历史 / 续播进度状态。
class HistoryStore extends ChangeNotifier {
  List<PlayRecord> _records = <PlayRecord>[];
  bool _loading = true;
  bool _disposed = false;

  List<PlayRecord> get records => _records;
  bool get loading => _loading;
  bool get isEmpty => _records.isEmpty;

  void _emit() {
    if (_disposed) return;
    notifyListeners();
  }

  Future<void> load() async {
    _loading = true;
    _emit();
    try {
      _records = await RecordRepository.loadHistory();
    } finally {
      _loading = false;
      _emit();
    }
  }

  PlayRecord? byKey(String key) {
    for (final PlayRecord r in _records) {
      if (r.key == key) return r;
    }
    return null;
  }

  PlayRecord? byIds(String sourceId, int vodId) => byKey('$sourceId|$vodId');

  List<PlayRecord> forSource(String sourceId) =>
      _records.where((PlayRecord r) => r.sourceId == sourceId).toList();

  List<PlayRecord> recent({int limit = 20}) =>
      _records.take(limit).toList();

  /// 覆盖式写入。调用方负责节流，避免播放中高频落盘。
  Future<void> upsert(PlayRecord record) async {
    final int index = _records.indexWhere((PlayRecord e) => e.key == record.key);
    if (index >= 0) {
      _records[index] = record;
    } else {
      _records.insert(0, record);
    }
    _records.sort((PlayRecord a, PlayRecord b) => b.updatedAt.compareTo(a.updatedAt));
    await _save();
    _emit();
  }

  Future<void> remove(String key) async {
    final int index = _records.indexWhere((PlayRecord e) => e.key == key);
    if (index < 0) return;
    _records.removeAt(index);
    await _save();
    _emit();
  }

  Future<void> removeMany(List<String> keys) async {
    final Set<String> set = keys.toSet();
    _records.removeWhere((PlayRecord e) => set.contains(e.key));
    await _save();
    _emit();
  }

  Future<void> clear() async {
    _records = <PlayRecord>[];
    await _save();
    _emit();
  }

  Future<void> _save() => RecordRepository.saveHistory(_records);

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
