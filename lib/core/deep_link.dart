import 'package:flutter/foundation.dart';

/// 外部唤起解析。
///
/// 支持三种写法，目的是让"分享一个源列表"这件事只需要一条链接：
///  * `cmsplayer://import?url=https://…/source.json`（协议唤起）
///  * `--import=https://…/source.json`（命令行 / 快捷方式参数）
///  * 直接甩一个 `.json` 地址（拖到图标上、脚本调用）
///
/// 应用本身不注册协议：那需要写注册表 / Info.plist，属于安装包的事。
/// 这里只负责"启动参数里带了导入请求时把它认出来"，注册好协议之后自然生效。
class DeepLink {
  DeepLink._();

  /// 待处理的导入地址。
  ///
  /// 启动时 [handleArgs] 把它填上；外壳挂载后消费并清空 —— 这样解析与
  /// 界面生命周期解耦，主线程不必等 Navigator 就绪。
  static final ValueNotifier<String?> pendingImport =
      ValueNotifier<String?>(null);

  static const String scheme = 'cmsplayer';

  /// 从启动参数里找出要导入的源列表地址；没有就返回 null。
  static String? parseImportUrl(List<String> args) {
    for (final String raw in args) {
      final String arg = raw.trim();
      if (arg.isEmpty) continue;

      if (arg.startsWith('--import=')) {
        final String url = arg.substring('--import='.length).trim();
        if (url.isNotEmpty) return url;
        continue;
      }

      final Uri? uri = Uri.tryParse(arg);
      if (uri == null) continue;
      final String protocol = uri.scheme.toLowerCase();

      if (protocol == scheme && uri.host == 'import') {
        final String url = (uri.queryParameters['url'] ?? '').trim();
        if (url.isNotEmpty) return url;
        continue;
      }

      // 直接给源列表地址：只认 .json，避免把任意命令参数当成源。
      if ((protocol == 'http' || protocol == 'https') &&
          uri.path.toLowerCase().endsWith('.json')) {
        return arg;
      }
    }
    return null;
  }

  /// 处理启动参数。main 里调用，解析结果留给外壳消费。
  static void handleArgs(List<String> args) {
    final String? url = parseImportUrl(args);
    if (url != null) pendingImport.value = url;
  }

  @visibleForTesting
  static void resetForTest() {
    pendingImport.value = null;
  }
}
