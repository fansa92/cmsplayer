import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/constants.dart';
import '../../core/errors.dart';
import '../../core/logger.dart';

/// 一个可用的发行版。
class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.tag,
    required this.url,
    this.notes = '',
    this.publishedAt,
  });

  /// 去掉前缀 `v` 与构建号的版本号，例如 `1.0.3`。
  final String version;

  /// 远端原始标签，例如 `v1.0.3`。
  final String tag;

  /// 发行版页面地址。
  final String url;

  /// 发行说明正文（Markdown 原文）。
  final String notes;

  final DateTime? publishedAt;

  /// 相对本机版本是否有更新。
  bool get isNewer => UpdateChecker.isNewer(version, K.appVersion);
}

/// 应用内更新检查。
///
/// 仓库是公开的，直接读 GitHub 的 `releases/latest`，不需要 token，也不必
/// 引入任何原生插件 —— 检出结果后把下载页地址交给用户复制即可。
///
/// 只做了「检查 + 提示」，没有做自动下载安装：换掉正在运行的可执行文件
/// 属于平台相关的活儿（Windows 上还要处理占用），为这点便利引入插件和
/// 权限不值当。
class UpdateChecker {
  UpdateChecker({http.Client? client}) : _client = client ?? _shared;

  /// 全局实例。测试里直接替换成注入了假客户端的版本。
  static UpdateChecker instance = UpdateChecker();

  static final http.Client _shared = http.Client();

  final http.Client _client;

  /// 拉取最新发行版。没有发行版（404）时返回 null。
  Future<UpdateInfo?> latest() async {
    final Uri uri = Uri.parse(K.releaseLatestApi);
    AppLog.d('Update', 'GET $uri');

    final http.Response response;
    try {
      response = await _client.get(
        uri,
        headers: const <String, String>{
          'Accept': 'application/vnd.github+json',
          'User-Agent': K.appName,
        },
      ).timeout(K.requestTimeout);
    } on Object catch (e) {
      throw VodException('检查更新失败：网络不可用', url: uri.toString(), cause: e);
    }

    // 仓库还没有任何发行版时 GitHub 给 404，这不是错误，只是「没得更新」。
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw VodException(
        '检查更新失败：服务返回 ${response.statusCode}',
        url: uri.toString(),
      );
    }

    final Object? decoded = _decode(response.bodyBytes);
    if (decoded is! Map) {
      throw const VodException('检查更新失败：返回内容无法解析');
    }
    return parseRelease(decoded.cast<String, dynamic>());
  }

  /// 解析一次 `releases/latest` 的响应体。
  ///
  /// 抽成静态方法是为了能直接喂 JSON 做单元测试，不必绕网络。
  static UpdateInfo? parseRelease(Map<String, dynamic> json) {
    final String tag = '${json['tag_name'] ?? ''}'.trim();
    if (tag.isEmpty) return null;
    // 预发布版不提示：作者自己标了「还没准备好」。
    if (json['prerelease'] == true || json['draft'] == true) return null;

    final String url = '${json['html_url'] ?? ''}'.trim();
    return UpdateInfo(
      version: normalizeVersion(tag),
      tag: tag,
      url: url.isEmpty ? K.releasesPage : url,
      notes: '${json['body'] ?? ''}'.trim(),
      publishedAt: DateTime.tryParse('${json['published_at'] ?? ''}'),
    );
  }

  /// `v1.0.2+3` → `1.0.2`。
  static String normalizeVersion(String raw) {
    String text = raw.trim();
    if (text.startsWith('v') || text.startsWith('V')) {
      text = text.substring(1);
    }
    final int cut = text.indexOf(RegExp(r'[+\-]'));
    if (cut >= 0) text = text.substring(0, cut);
    return text.trim();
  }

  /// 版本号比较。返回 >0 表示 [a] 比 [b] 新。
  ///
  /// 只比数字段：`1.0.10` 必须大于 `1.0.9`，所以不能按字符串比。段数不同
  /// 时短的补 0（`1.1` == `1.1.0`），非数字段按 0 处理，宁可判成「一样」
  /// 也不要因为一个奇怪的标签把用户引到降级下载页。
  static int compareVersions(String a, String b) {
    final List<int> left = _segments(a);
    final List<int> right = _segments(b);
    final int count = left.length > right.length ? left.length : right.length;
    for (int i = 0; i < count; i++) {
      final int x = i < left.length ? left[i] : 0;
      final int y = i < right.length ? right[i] : 0;
      if (x != y) return x > y ? 1 : -1;
    }
    return 0;
  }

  /// [remote] 是否比 [local] 新。
  static bool isNewer(String remote, String local) =>
      compareVersions(remote, local) > 0;

  static List<int> _segments(String raw) {
    final String text = normalizeVersion(raw);
    return text
        .split('.')
        .map((String part) => int.tryParse(part.replaceAll(RegExp(r'\D'), '')) ?? 0)
        .toList();
  }

  static Object? _decode(List<int> bytes) {
    try {
      return jsonDecode(utf8.decode(bytes, allowMalformed: true));
    } on Object catch (e) {
      AppLog.w('Update', 'decode failed: $e');
      return null;
    }
  }
}
