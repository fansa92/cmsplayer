import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 应用数据目录。所有持久化都收敛到这里，方便"清除缓存"功能一键清理。
class AppDirs {
  AppDirs._();

  static late final Directory root;
  static late final Directory data;
  static late final Directory imageCache;
  static bool _ready = false;

  static bool get isReady => _ready;

  static Future<void> init() async {
    if (_ready) return;
    Directory base;
    try {
      base = await getApplicationSupportDirectory();
    } on Object {
      // 个别桌面平台在沙箱未就绪时会抛错，退化到当前工作目录。
      base = Directory.current;
    }

    root = Directory(p.join(base.path, 'cms_player'));
    data = Directory(p.join(root.path, 'data'));
    imageCache = Directory(p.join(root.path, 'cache', 'images'));

    await _ensure(root);
    await _ensure(data);
    await _ensure(imageCache);
    _ready = true;
  }

  static Future<void> _ensure(Directory dir) async {
    if (!await dir.exists()) {
      try {
        await dir.create(recursive: true);
      } on Object {
        // 忽略：只读环境下退化为内存态。
      }
    }
  }

  /// 退化路径，init 失败时仍能给出一个可用目录。
  static Directory get fallback => Directory.systemTemp;

  /// 清理图片磁盘缓存，返回释放的字节数。
  static Future<int> clearImageCache() async {
    if (!await imageCache.exists()) return 0;
    var freed = 0;
    await for (final entity in imageCache.list()) {
      if (entity is File) {
        try {
          freed += await entity.length();
          await entity.delete();
        } on Object {
          // 忽略单个文件的失败。
        }
      }
    }
    return freed;
  }

  /// 图片缓存当前占用字节数。
  static Future<int> imageCacheSize() async {
    if (!await imageCache.exists()) return 0;
    var total = 0;
    await for (final entity in imageCache.list()) {
      if (entity is File) {
        try {
          total += await entity.length();
        } on Object {
          // 忽略。
        }
      }
    }
    return total;
  }
}
