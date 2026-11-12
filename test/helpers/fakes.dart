import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cms_player/core/storage/json_store.dart';
import 'package:cms_player/data/api/maccms_api.dart';
import 'package:cms_player/data/models/vod_source.dart';
import 'package:cms_player/data/repository/vod_repository.dart';
import 'package:cms_player/data/sync/sync_tombstones.dart';
import 'package:cms_player/state/source_store.dart';

/// 被假客户端记录下来的一次请求。
class RecordedRequest {
  const RecordedRequest(this.method, this.url, this.headers, this.body);

  final String method;
  final Uri url;
  final Map<String, String> headers;
  final String body;

  @override
  String toString() => '$method $url';
}

/// 可编排的假 HTTP 客户端。
///
/// 既能按请求内容动态生成响应，也能用 [queued] 按顺序塞固定响应
/// （例如让第一次请求失败、第二次成功，用来测回退路径）。
class FakeHttpClient extends http.BaseClient {
  FakeHttpClient([this._responder]);

  http.StreamedResponse Function(RecordedRequest request)? _responder;
  final List<RecordedRequest> requests = <RecordedRequest>[];
  final List<http.StreamedResponse> queued = <http.StreamedResponse>[];
  bool closed = false;

  /// 可选闸门：设置后每个请求都会先等它完成。
  ///
  /// 用来在测试里冻结跨源搜索，确定性地观察「正在查找其它资源站…」这类
  /// 中间状态；完成闸门后流程照常继续。
  Future<void>? gate;

  set responder(http.StreamedResponse Function(RecordedRequest request) fn) =>
      _responder = fn;

  RecordedRequest get last => requests.last;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    String body = '';
    if (request is http.Request) {
      body = utf8.decode(request.bodyBytes, allowMalformed: true);
    }
    final RecordedRequest recorded = RecordedRequest(
      request.method,
      request.url,
      Map<String, String>.of(request.headers),
      body,
    );
    requests.add(recorded);
    final Future<void>? pendingGate = gate;
    if (pendingGate != null) await pendingGate;
    if (queued.isNotEmpty) return queued.removeAt(0);
    final http.StreamedResponse Function(RecordedRequest request)? fn =
        _responder;
    if (fn != null) return fn(recorded);
    return fakeResponse(200, '{}');
  }

  @override
  void close() {
    closed = true;
  }
}

/// 构造一个流式响应（`http.Response.fromStream` 能直接消费）。
http.StreamedResponse fakeResponse(
  int status,
  String body, {
  Map<String, String>? headers,
}) =>
    http.StreamedResponse(
      Stream<List<int>>.fromIterable(<List<int>>[utf8.encode(body)]),
      status,
      headers: headers ??
          <String, String>{'content-type': 'application/json; charset=utf-8'},
    );

http.StreamedResponse fakeJson(Object? value, {int status = 200}) =>
    fakeResponse(status, jsonEncode(value));

/// macCMS 的 `list` 条目。
Map<String, Object> vodJson({
  required int id,
  required String name,
  String year = '',
  String remarks = '',
  bool? isEnd,
  String playFrom = '',
  String playUrl = '',
}) =>
    <String, Object>{
      'vod_id': id,
      'vod_name': name,
      if (year.isNotEmpty) 'vod_year': year,
      if (remarks.isNotEmpty) 'vod_remarks': remarks,
      if (isEnd != null) 'vod_isend': isEnd ? 1 : 0,
      'vod_play_from': playFrom,
      'vod_play_url': playUrl,
    };

/// macCMS 的 v10 响应。
Map<String, Object> vodPageJson({
  List<Map<String, Object>>? list,
  List<Map<String, Object>>? classes,
  int page = 1,
  int pageCount = 1,
  int total = 0,
  String limit = '20',
}) =>
    <String, Object>{
      'code': 1,
      'page': page,
      'pagecount': pageCount,
      'total': total,
      'limit': limit,
      if (classes != null) 'class': classes,
      'list': list ?? <Map<String, Object>>[],
    };

VodSource sourceOf(String name, {String host = 'a.com'}) =>
    VodSource.fromRaw(<String, Object>{
      'name': name,
      'api': 'https://$host/api.php/provide/vod/',
    });

/// 每个用例一套干净的临时目录 + 空设置 + 清空的缓存与墓碑。
///
/// 必须在 `main()` 里调用（它会注册 setUp / tearDown）。
/// 生产代码通过这些静态钩子切换数据源，默认行为不受影响。
void useIsolatedStores() {
  late Directory dir;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    dir = await Directory.systemTemp.createTemp('cms_player_test_');
    JsonStore.overrideDirectory = dir;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    VodRepository.instance.clearAll();
    MacCmsApi.resetCompatForTest();
    await SyncTombstones.instance.clearAll();
  });

  tearDown(() async {
    VodRepository.resetApiFactory();
    VodRepository.instance.clearAll();
    SourceStore.resetPinger();
    await SyncTombstones.instance.clearAll();
    JsonStore.overrideDirectory = null;
    // Windows 上刚写过的文件句柄不会立刻释放，直接递归删偶发
    // PathAccessException（errno 32）。写盘本身是 fire-and-forget 的，
    // 与其在每个用例里猜等待时长，不如在这里做几次短暂重试。
    for (int attempt = 0; attempt < 16; attempt++) {
      if (!await dir.exists()) break;
      try {
        await dir.delete(recursive: true);
        break;
      } on PathAccessException {
        if (attempt == 15) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 60));
      }
    }
  });
}

/// 把仓储层的网络请求全部接到 [client] 上。
void useFakeApi(FakeHttpClient client) {
  VodRepository.instance.clearAll();
  VodRepository.apiFactory =
      (VodSource source) => MacCmsApi(source, client: client);
}
