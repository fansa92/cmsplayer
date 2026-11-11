import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/logger.dart';
import '../../core/storage/app_dirs.dart';
import '../models/favorite_item.dart';
import '../models/play_record.dart';
import '../models/vod_source.dart';

/// 备份包的格式版本。
///
/// 与同步包（`SyncPayload`）的版本号各管各的：同步是两台设备之间的事件流，
/// 备份是给人存档的单文件，演进节奏不一样。
const int kBackupFormatVersion = 1;

/// 一份完整备份。
///
/// 与 [SyncPayload] 的区别在于它把「本机才有的东西」也带上了：搜索历史、
/// 界面 / 播放偏好、删除墓碑。同步只搬三样数据（记录、收藏、源），
/// 因为它要频繁合并；备份是一次性的快照，越完整越好。
///
/// 不含任何凭据（WebDAV 账号密码等），见 `SettingsStore.exportSnapshot`。
class BackupBundle {
  const BackupBundle({
    required this.exportedAt,
    required this.appVersion,
    this.history = const <PlayRecord>[],
    this.favorites = const <FavoriteItem>[],
    this.sources = const <VodSource>[],
    this.searches = const <String>[],
    this.settings = const <String, Object?>{},
    this.tombstones = const <String, Map<String, int>>{},
  });

  final DateTime exportedAt;
  final String appVersion;
  final List<PlayRecord> history;
  final List<FavoriteItem> favorites;
  final List<VodSource> sources;

  /// 搜索关键词（最近在前）。
  final List<String> searches;

  /// 设置快照，键名见 `SettingsStore.exportSnapshot`。
  final Map<String, Object?> settings;

  /// `集合名 -> (条目 key -> 删除时刻毫秒)`，与同步包同构。
  final Map<String, Map<String, int>> tombstones;

  int get totalItems => history.length + favorites.length + sources.length;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'v': kBackupFormatVersion,
        'kind': 'cms_player_backup',
        'exportedAt': exportedAt.toUtc().toIso8601String(),
        'appVersion': appVersion,
        'history': history.map((PlayRecord e) => e.toJson()).toList(),
        'favorites': favorites.map((FavoriteItem e) => e.toJson()).toList(),
        'sources': sources.map((VodSource e) => e.toJson()).toList(),
        'searches': searches,
        'settings': settings,
        'tombstones': tombstones,
      };

  /// 缩进输出。备份是给人留着的东西，出问题时能直接打开看比省几十 KB 值。
  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());

  factory BackupBundle.fromJson(Map<String, dynamic> json) {
    final Object? version = json['v'];
    if (version is num && version > kBackupFormatVersion) {
      throw FormatException(
        '备份文件是版本 $version，本应用只认到 $kBackupFormatVersion',
      );
    }
    final Object? searches = json['searches'];
    final Object? settings = json['settings'];
    return BackupBundle(
      exportedAt: DateTime.tryParse('${json['exportedAt']}') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      appVersion: '${json['appVersion'] ?? ''}',
      history: _maps(json['history']).map(PlayRecord.fromJson).toList(),
      favorites: _maps(json['favorites']).map(FavoriteItem.fromJson).toList(),
      sources: _maps(json['sources']).map(VodSource.fromJson).toList(),
      searches: searches is List
          ? searches.map((Object? e) => '${e ?? ''}'.trim()).where((String e) => e.isNotEmpty).toList()
          : const <String>[],
      settings: settings is Map
          ? settings.map((Object? k, Object? v) => MapEntry<String, Object?>('$k', v))
          : const <String, Object?>{},
      tombstones: _tombstonesOf(json['tombstones']),
    );
  }

  /// 解析备份文本。无法解析时返回 null —— 调用方要的是「这个文件能不能用」，
  /// 不是 JSON 解析器抛出来的堆栈。
  static BackupBundle? decode(String text) {
    if (text.trim().isEmpty) return null;
    try {
      final Object? decoded = jsonDecode(text);
      if (decoded is! Map) return null;
      return BackupBundle.fromJson(decoded.cast<String, dynamic>());
    } on Object catch (e) {
      AppLog.w('Backup', 'decode failed: $e');
      return null;
    }
  }

  static List<Map<String, dynamic>> _maps(Object? raw) => raw is List
      ? raw.whereType<Map>().map((Map e) => e.cast<String, dynamic>()).toList()
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
}

/// 把备份写成单个文件。
///
/// 目录优先级：下载目录 → 应用数据目录 → 临时目录。桌面端落在「下载」里
/// 用户能直接找到；移动端拿不到下载目录，只能退回应用私有目录，这一点
/// 在界面上如实告知（路径会显示出来）。
class BackupExporter {
  BackupExporter._();

  /// 测试注入点：换目录就不必碰 path_provider 的平台通道。
  static Directory Function()? directoryOverride;

  static const String filePrefix = 'cmsplayer-backup';

  /// 写盘并返回落地的文件。
  static Future<File> write(BackupBundle bundle) async {
    final Directory dir = await resolveDirectory();
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final File file = await _uniqueFile(dir, bundle.exportedAt);
    await file.writeAsString(bundle.encode(), flush: true);
    return file;
  }

  static Future<Directory> resolveDirectory() async {
    final Directory Function()? override = directoryOverride;
    if (override != null) return override();
    try {
      final Directory? downloads = await getDownloadsDirectory();
      if (downloads != null) return downloads;
    } on Object catch (e) {
      AppLog.d('Backup', 'downloads dir unavailable: $e');
    }
    if (AppDirs.isReady) return AppDirs.data;
    return Directory.systemTemp;
  }

  /// `cmsplayer-backup-20261111-223700.json`。
  static String fileNameAt(DateTime at) {
    String two(int v) => v.toString().padLeft(2, '0');
    final String stamp = '${at.year}${two(at.month)}${two(at.day)}'
        '-${two(at.hour)}${two(at.minute)}${two(at.second)}';
    return '$filePrefix-$stamp.json';
  }

  /// 同一秒里连点两次导出时不能互相覆盖。
  static Future<File> _uniqueFile(Directory dir, DateTime at) async {
    final String base = p.join(dir.path, fileNameAt(at));
    File file = File(base);
    int index = 1;
    while (await file.exists()) {
      file = File(p.join(dir.path, '${p.basenameWithoutExtension(base)}'
          '-$index.json'));
      index++;
    }
    return file;
  }
}
