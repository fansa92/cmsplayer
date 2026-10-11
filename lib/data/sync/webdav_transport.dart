import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/constants.dart';
import '../../core/logger.dart';
import 'sync_payload.dart';
import 'sync_transport.dart';

/// WebDAV 同步通道。
///
/// 只用到四个方法：`PROPFIND` 测连通、`MKCOL` 建目录、`GET` 拉、`PUT` 推。
/// 全部走现有的 `http` 包，不引入任何新依赖。
class WebDavTransport implements SyncTransport {
  WebDavTransport({
    required this.baseUrl,
    this.username = '',
    this.password = '',
    String remotePath = K.defaultWebDavPath,
    http.Client? client,
  })  : remotePath = remotePath.trim().isEmpty
            ? K.defaultWebDavPath
            : remotePath.trim(),
        _client = client ?? http.Client();

  final String baseUrl;
  final String username;
  final String password;
  final String remotePath;
  final http.Client _client;

  @override
  String get label => 'WebDAV';

  /// 远端文件地址。
  ///
  /// baseUrl 可能自己就带一段路径（`https://dav.example.com/dav/`），
  /// 这种情况下远端路径要接在后面，而不是把人家的路径顶掉。
  Uri get fileUri {
    final String base = baseUrl.trim();
    if (base.isEmpty) throw const SyncException('还没填写 WebDAV 地址');
    final Uri baseUri = Uri.tryParse(base.endsWith('/') ? base : '$base/')
        ?? (throw SyncException('WebDAV 地址不是合法 URL：$base'));
    if (!baseUri.isScheme('http') && !baseUri.isScheme('https')) {
      throw SyncException('WebDAV 地址必须是 http(s)：$base');
    }
    // 去掉开头的斜杠，让它以「相对」身份接到 baseUrl 之后。
    String rel = remotePath.replaceFirst(RegExp(r'^/+'), '');
    if (rel.isEmpty) rel = K.defaultWebDavPath.replaceFirst(RegExp(r'^/+'), '');
    return baseUri.resolveUri(Uri(path: rel));
  }

  /// 请求头。
  Map<String, String> get _headers => <String, String>{
        'User-Agent': K.defaultUserAgent,
        'Content-Type': 'application/json; charset=utf-8',
        if (username.isNotEmpty)
          'Authorization':
              'Basic ${base64Encode(utf8.encode('$username:$password'))}',
      };

  // ---------------------------------------------------------------- 传输

  @override
  Future<SyncPayload?> download() async {
    final http.Response r = await _send('GET', fileUri);
    if (r.statusCode == 404) return null;
    _ensureOk(r);
    final String text = utf8.decode(r.bodyBytes, allowMalformed: true);
    final SyncPayload? payload = SyncPayload.decode(text);
    if (payload == null) {
      throw const SyncException('远端同步文件无法解析，可能已损坏');
    }
    return payload;
  }

  @override
  Future<SyncPayload?> upload(SyncPayload payload) async {
    await _ensureDirs();
    final http.Response r =
        await _send('PUT', fileUri, body: payload.encode());
    _ensureOk(r);
    return null;
  }

  /// 连通性测试。成功时无返回值，失败抛 [SyncException]。
  Future<void> test() async {
    final Uri dir = fileUri.replace(
      pathSegments:
          fileUri.pathSegments.where((String s) => s.isNotEmpty).toList()
            ..removeLast(),
    );
    final http.Response r = await _send('PROPFIND', dir, depth: '0');
    if (r.statusCode == 401 || r.statusCode == 403) {
      throw const SyncException('账号或密码不对（HTTP 401）');
    }
    if (r.statusCode == 404) {
      throw const SyncException('地址不存在（HTTP 404），请检查路径');
    }
    if (r.statusCode >= 200 && r.statusCode < 300) return;
    throw SyncException(
      '服务器返回 HTTP ${r.statusCode}，它可能不支持 WebDAV',
    );
  }

  @override
  void close() => _client.close();

  // ---------------------------------------------------------------- 内部

  /// 逐级建目录。已存在时多数服务器回 405，属正常情况。
  Future<void> _ensureDirs() async {
    final List<String> segs =
        fileUri.pathSegments.where((String s) => s.isNotEmpty).toList();
    if (segs.length <= 1) return;
    segs.removeLast(); // 最后一段是文件名

    String prefix = '${fileUri.scheme}://${fileUri.authority}';
    for (final String s in segs) {
      prefix = '$prefix/${Uri.encodeComponent(s)}';
      try {
        final http.Response r =
            await _send('MKCOL', Uri.parse('$prefix/'), throwOnHttpError: false);
        // 201 = 刚建好，405 = 早就存在，301/401 交给后续请求去报错。
        if (r.statusCode == 201 || r.statusCode == 405) continue;
        AppLog.w('WebDav', 'MKCOL $prefix -> ${r.statusCode}');
      } on Object catch (e) {
        // 建目录失败不一定是致命的：有些服务器不允许 MKCOL，
        // 但 PUT 时会自动创建。真正失败会在 PUT 那一步暴露出来。
        AppLog.w('WebDav', 'MKCOL $prefix failed: $e');
      }
    }
  }

  Future<http.Response> _send(
    String method,
    Uri uri, {
    String? body,
    String? depth,
    bool throwOnHttpError = true,
  }) async {
    final http.Request request = http.Request(method, uri);
    request.headers.addAll(_headers);
    if (depth != null) request.headers['Depth'] = depth;
    if (body != null) request.bodyBytes = utf8.encode(body);

    final http.StreamedResponse streamed;
    try {
      streamed = await _client
          .send(request)
          .timeout(K.syncTimeout);
    } on Object catch (e) {
      throw SyncException('连不上 WebDAV：$e', cause: e);
    }
    final http.Response response =
        await http.Response.fromStream(streamed).timeout(K.syncTimeout);
    if (throwOnHttpError) _ensureOk(response);
    return response;
  }

  void _ensureOk(http.Response r) {
    if (r.statusCode >= 200 && r.statusCode < 300) return;
    if (r.statusCode == 401 || r.statusCode == 403) {
      throw const SyncException('WebDAV 账号或密码不对（HTTP 401）');
    }
    if (r.statusCode == 404) {
      throw const SyncException('WebDAV 路径不存在（HTTP 404）');
    }
    if (r.statusCode == 507) {
      throw const SyncException('网盘空间不足（HTTP 507）');
    }
    throw SyncException('WebDAV 返回 HTTP ${r.statusCode}');
  }
}
