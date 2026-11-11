import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:cms_player/data/models/play_record.dart';
import 'package:cms_player/data/sync/sync_payload.dart';
import 'package:cms_player/data/sync/sync_transport.dart';
import 'package:cms_player/data/sync/webdav_transport.dart';

import 'helpers/fakes.dart';

/// WebDAV 通道：URL 拼接、鉴权、四种 HTTP 方法与错误码转中文提示。
///
/// 全部走注入的假 http.Client，不发真实请求。
void main() {
  final DateTime now = DateTime(2026, 3, 10, 12).toUtc();

  SyncPayload payload({List<PlayRecord> history = const <PlayRecord>[]}) =>
      SyncPayload(
        updatedAt: now,
        history: history,
        tombstones: <String, Map<String, int>>{
          SyncBox.favorites: <String, int>{'gone': now.millisecondsSinceEpoch},
        },
      );

  PlayRecord rec(String key) => PlayRecord(
        key: key,
        sourceId: 'src',
        sourceName: '测试站',
        vodId: key,
        vodName: '测试影片',
        positionMs: 42,
        updatedAt: now,
      );

  WebDavTransport t(
    FakeHttpClient client, {
    String baseUrl = 'https://dav.example.com/dav/',
    String remotePath = '/cmsplayer/sync.json',
    String user = '',
    String pass = '',
  }) =>
      WebDavTransport(
        baseUrl: baseUrl,
        username: user,
        password: pass,
        remotePath: remotePath,
        client: client,
      );

  group('远端地址', () {
    test('baseUrl 自带路径时，远端路径接在后面而不是顶掉', () {
      expect(
        t(FakeHttpClient(), baseUrl: 'https://dav.example.com/dav/')
            .fileUri
            .toString(),
        'https://dav.example.com/dav/cmsplayer/sync.json',
      );
      // 没写尾斜杠也要补上。
      expect(
        t(FakeHttpClient(), baseUrl: 'https://dav.example.com/dav')
            .fileUri
            .toString(),
        'https://dav.example.com/dav/cmsplayer/sync.json',
      );
    });

    test('remotePath 的开头斜杠、空串都归一到默认路径', () {
      expect(
        t(FakeHttpClient(), remotePath: 'cmsplayer/sync.json').fileUri.path,
        '/dav/cmsplayer/sync.json',
      );
      expect(
        t(FakeHttpClient(), remotePath: '///custom/data.json').fileUri.path,
        '/dav/custom/data.json',
      );
      expect(
        t(FakeHttpClient(), remotePath: '   ').fileUri.path,
        '/dav/cmsplayer/sync.json',
      );
      expect(
        t(FakeHttpClient(), remotePath: '///').fileUri.path,
        '/dav/cmsplayer/sync.json',
      );
    });

    test('空地址 / 非 http(s) 地址给出可读错误', () {
      expect(
        () => t(FakeHttpClient(), baseUrl: '').fileUri,
        throwsA(isA<SyncException>()),
      );
      expect(
        () => t(FakeHttpClient(), baseUrl: 'ftp://dav.example.com/').fileUri,
        throwsA(isA<SyncException>().having(
          (SyncException e) => e.message,
          'message',
          contains('http(s)'),
        )),
      );
    });
  });

  group('请求头', () {
    test('填了账号才发 Basic 鉴权，且 UA / Content-Type 齐全', () async {
      final FakeHttpClient client =
          FakeHttpClient((RecordedRequest r) => fakeResponse(404, ''));
      await t(client, user: 'u', pass: 'p').download();

      expect(client.last.method, 'GET');
      expect(client.last.headers['Authorization'],
          'Basic ${base64Encode(utf8.encode('u:p'))}');
      expect(client.last.headers['User-Agent'], isNotEmpty);
      expect(client.last.headers['Content-Type'], contains('application/json'));
    });

    test('没填账号时不发 Authorization', () async {
      final FakeHttpClient client =
          FakeHttpClient((RecordedRequest r) => fakeResponse(404, ''));
      await t(client).download();
      expect(client.last.headers.containsKey('Authorization'), isFalse);
    });
  });

  group('拉取', () {
    test('404 表示远端还没有文件，返回 null 而不是报错', () async {
      final FakeHttpClient client =
          FakeHttpClient((RecordedRequest r) => fakeResponse(404, ''));
      expect(await t(client).download(), isNull);
    });

    test('200 能还原条目与墓碑', () async {
      final SyncPayload p = payload(history: <PlayRecord>[rec('h1')]);
      final FakeHttpClient client =
          FakeHttpClient((RecordedRequest r) => fakeResponse(200, p.encode()));

      final SyncPayload? back = await t(client).download();

      expect(back, isNotNull);
      expect(back!.history.single.key, 'h1');
      expect(back.history.single.positionMs, 42);
      expect(back.tombstones[SyncBox.favorites]!['gone'],
          now.millisecondsSinceEpoch);
    });

    test('文件损坏时给出可读提示', () async {
      final FakeHttpClient client =
          FakeHttpClient((RecordedRequest r) => fakeResponse(200, '不是 JSON'));
      await expectLater(
        t(client).download(),
        throwsA(isA<SyncException>().having(
          (SyncException e) => e.message,
          'message',
          contains('无法解析'),
        )),
      );
    });

    test('401 / 507 / 500 分别转成中文原因（404 已在上面作为空文件处理）', () async {
      for (final MapEntry<int, String> case_ in <MapEntry<int, String>>[
        const MapEntry<int, String>(401, '账号或密码'),
        const MapEntry<int, String>(403, '账号或密码'),
        const MapEntry<int, String>(507, '空间不足'),
        const MapEntry<int, String>(500, 'HTTP 500'),
      ]) {
        final FakeHttpClient client = FakeHttpClient(
          (RecordedRequest r) => fakeResponse(case_.key, ''),
        );
        await expectLater(
          t(client).download(),
          throwsA(isA<SyncException>().having(
            (SyncException e) => e.message,
            'message',
            contains(case_.value),
          )),
          reason: 'HTTP ${case_.key}',
        );
      }
    });

    test('连接不上不外抛底层异常', () async {
      final FakeHttpClient client =
          FakeHttpClient((RecordedRequest r) => throw StateError('boom'));
      await expectLater(
        t(client).download(),
        throwsA(isA<SyncException>().having(
          (SyncException e) => e.message,
          'message',
          contains('连不上 WebDAV'),
        )),
      );
    });
  });

  group('推送', () {
    test('先逐级建目录再 PUT，内容就是数据包的编码结果', () async {
      final FakeHttpClient client = FakeHttpClient((RecordedRequest r) {
        if (r.method == 'MKCOL') return fakeResponse(405, ''); // 已存在
        return fakeResponse(201, '');
      });
      final WebDavTransport transport = t(client);
      final SyncPayload p = payload(history: <PlayRecord>[rec('h1')]);

      final SyncPayload? back = await transport.upload(p);

      expect(back, isNull, reason: 'WebDAV 不会二次合并，对方就是我发的这份');
      expect(client.requests.map((RecordedRequest r) => r.method).toList(),
          <String>['MKCOL', 'MKCOL', 'PUT']);
      expect(client.requests[0].url.toString(), 'https://dav.example.com/dav/');
      expect(client.requests[1].url.toString(),
          'https://dav.example.com/dav/cmsplayer/');
      expect(client.last.url, transport.fileUri);
      final SyncPayload? sent = SyncPayload.decode(client.last.body);
      expect(sent, isNotNull);
      expect(sent!.history.single.key, 'h1');
    });

    test('服务器不支持 MKCOL 也不阻断 PUT', () async {
      final FakeHttpClient client = FakeHttpClient((RecordedRequest r) {
        if (r.method == 'MKCOL') throw StateError('MKCOL disabled');
        return fakeResponse(200, '');
      });

      await t(client).upload(payload());

      expect(client.last.method, 'PUT');
    });

    test('PUT 失败照样抛中文错误', () async {
      final FakeHttpClient client = FakeHttpClient(
        (RecordedRequest r) => fakeResponse(507, ''),
      );
      await expectLater(
        t(client).upload(payload()),
        throwsA(isA<SyncException>().having(
          (SyncException e) => e.message,
          'message',
          contains('空间不足'),
        )),
      );
    });
  });

  group('连通性测试', () {
    test('向目录发 PROPFIND 且 Depth 为 0', () async {
      final FakeHttpClient client =
          FakeHttpClient((RecordedRequest r) => fakeResponse(207, ''));
      await t(client).test();

      expect(client.last.method, 'PROPFIND');
      expect(client.last.headers['Depth'], '0');
      expect(client.last.url.path, '/dav/cmsplayer', reason: '不带最后一段文件名');
    });

    test('401 / 404 / 500 给出针对性的排查提示', () async {
      for (final MapEntry<int, String> case_ in <MapEntry<int, String>>[
        const MapEntry<int, String>(401, '账号或密码不对'),
        const MapEntry<int, String>(403, '账号或密码不对'),
        const MapEntry<int, String>(404, '地址不存在'),
        const MapEntry<int, String>(500, '不支持 WebDAV'),
      ]) {
        final FakeHttpClient client = FakeHttpClient(
          (RecordedRequest r) => fakeResponse(case_.key, ''),
        );
        await expectLater(
          t(client).test(),
          throwsA(isA<SyncException>().having(
            (SyncException e) => e.message,
            'message',
            contains(case_.value),
          )),
          reason: 'HTTP ${case_.key}',
        );
      }
    });
  });

  test('close 会关掉注入的客户端', () {
    final FakeHttpClient client = FakeHttpClient();
    t(client).close();
    expect(client.closed, isTrue);
  });
}
