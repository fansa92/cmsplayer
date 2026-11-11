import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:cms_player/data/models/play_record.dart';
import 'package:cms_player/data/sync/lan_transport.dart';
import 'package:cms_player/data/sync/sync_merge.dart';
import 'package:cms_player/data/sync/sync_payload.dart';
import 'package:cms_player/data/sync/sync_transport.dart';

import 'helpers/fakes.dart';

/// 局域网通道：客户端的拉 / 推、主机端的 HTTP 协议、以及发现报文的解析结构。
void main() {
  final DateTime now = DateTime(2026, 3, 10, 12).toUtc();

  PlayRecord rec(String key, {int positionMs = 0}) => PlayRecord(
        key: key,
        sourceId: 'src',
        sourceName: '测试站',
        vodId: key,
        vodName: '测试影片',
        positionMs: positionMs,
        updatedAt: now,
      );

  SyncPayload payload({List<PlayRecord> history = const <PlayRecord>[]}) =>
      SyncPayload(updatedAt: now, history: history);

  LanClient make(FakeHttpClient c, {String host = '192.168.1.2'}) =>
      LanClient(host: host, port: 8765, client: c);

  group('LanPeer', () {
    test('label 有设备名就带上，否则只显示地址', () {
      expect(const LanPeer(ip: '10.0.0.2', port: 9000).label, '10.0.0.2:9000');
      expect(
        const LanPeer(ip: '10.0.0.2', port: 9000, name: '书房电脑').label,
        '书房电脑（10.0.0.2:9000）',
      );
    });

    test('相等性只看 ip + port，设备名改名不算新设备', () {
      const LanPeer a = LanPeer(ip: '10.0.0.2', port: 9000, name: 'A');
      const LanPeer b = LanPeer(ip: '10.0.0.2', port: 9000, name: 'B');
      const LanPeer c = LanPeer(ip: '10.0.0.2', port: 9001, name: 'A');

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
      expect(<LanPeer>{a, b}, hasLength(1));
    });
  });

  group('LanClient 拉取', () {
    test('label 带对方地址，GET 打到 /sync 并带 UA', () async {
      final FakeHttpClient c =
          FakeHttpClient((RecordedRequest r) => fakeResponse(404, ''));
      final LanClient client = make(c);

      expect(client.label, '局域网 192.168.1.2');
      await client.download();

      expect(c.last.method, 'GET');
      expect(c.last.url.toString(), 'http://192.168.1.2:8765/sync');
      expect(c.last.headers['User-Agent'], isNotEmpty);
    });

    test('200 解析数据包，404 表示对端还没有数据', () async {
      final FakeHttpClient ok = FakeHttpClient(
        (RecordedRequest r) => fakeResponse(
          200,
          payload(history: <PlayRecord>[rec('h1', positionMs: 88)]).encode(),
        ),
      );
      final SyncPayload? back = await make(ok).download();
      expect(back!.history.single.key, 'h1');
      expect(back.history.single.positionMs, 88);

      final FakeHttpClient missing =
          FakeHttpClient((RecordedRequest r) => fakeResponse(404, ''));
      expect(await make(missing).download(), isNull);
    });

    test('非 200 与坏 JSON 分别给可读原因', () async {
      final FakeHttpClient badStatus =
          FakeHttpClient((RecordedRequest r) => fakeResponse(500, ''));
      await expectLater(
        make(badStatus).download(),
        throwsA(isA<SyncException>().having(
          (SyncException e) => e.message,
          'message',
          contains('HTTP 500'),
        )),
      );

      final FakeHttpClient badBody =
          FakeHttpClient((RecordedRequest r) => fakeResponse(200, '乱码'));
      await expectLater(
        make(badBody).download(),
        throwsA(isA<SyncException>().having(
          (SyncException e) => e.message,
          'message',
          contains('无法解析'),
        )),
      );
    });

    test('连不上对方时包成 SyncException', () async {
      final FakeHttpClient c =
          FakeHttpClient((RecordedRequest r) => throw StateError('refused'));
      await expectLater(
        make(c).download(),
        throwsA(isA<SyncException>().having(
          (SyncException e) => e.message,
          'message',
          contains('连不上对方'),
        )),
      );
    });
  });

  group('LanClient 推送', () {
    test('POST 请求带 JSON 头，正文是数据包，返回值是对端合并结果', () async {
      final SyncPayload merged =
          payload(history: <PlayRecord>[rec('h1'), rec('h2')]);
      final FakeHttpClient c = FakeHttpClient(
        (RecordedRequest r) => fakeResponse(200, merged.encode()),
      );
      final SyncPayload sent = payload(history: <PlayRecord>[rec('h1')]);

      final SyncPayload? back = await make(c).upload(sent);

      expect(c.last.method, 'POST');
      expect(c.last.url.toString(), 'http://192.168.1.2:8765/sync');
      expect(c.last.headers['Content-Type'], contains('application/json'));
      expect(SyncPayload.decode(c.last.body)!.history.single.key, 'h1');
      expect(back, isNotNull);
      expect(back!.history.map((PlayRecord e) => e.key).toList(),
          <String>['h1', 'h2']);
    });

    test('对端返回非 200 / 连不上时报错', () async {
      final FakeHttpClient bad =
          FakeHttpClient((RecordedRequest r) => fakeResponse(500, ''));
      await expectLater(
        make(bad).upload(payload()),
        throwsA(isA<SyncException>().having(
          (SyncException e) => e.message,
          'message',
          contains('HTTP 500'),
        )),
      );

      final FakeHttpClient offline =
          FakeHttpClient((RecordedRequest r) => throw StateError('refused'));
      await expectLater(
        make(offline).upload(payload()),
        throwsA(isA<SyncException>().having(
          (SyncException e) => e.message,
          'message',
          contains('连不上对方'),
        )),
      );
    });

    test('close 关掉注入的客户端', () {
      final FakeHttpClient c = FakeHttpClient();
      make(c).close();
      expect(c.closed, isTrue);
    });
  });

  group('LanHost 端到端', () {
    test('GET / POST / 非法正文 / 未知路径都按协议响应', () async {
      final SyncPayload onHost =
          payload(history: <PlayRecord>[rec('host-only')]);
      SyncPayload? received;

      final LanHost host = LanHost(
        provider: () async => onHost,
        applier: (SyncPayload incoming) async {
          received = incoming;
          return SyncMerger.merge(onHost, incoming);
        },
        port: 0, // 让系统分配端口，避免和别的用例抢 8765
        deviceName: '测试主机',
        enableDiscovery: false,
      );
      addTearDown(host.stop);
      await host.start();

      expect(host.running, isTrue);
      expect(host.boundPort, greaterThan(0));
      expect(host.address, endsWith(':${host.boundPort}'));

      final http.Client client = http.Client();
      addTearDown(client.close);
      final Uri base = Uri.parse('http://127.0.0.1:${host.boundPort}');

      // 浏览器打开根路径能看到可读提示。
      final http.Response root = await client.get(base.replace(path: '/'));
      expect(root.statusCode, 200);
      expect(root.body, contains('CMSPlayer 同步服务'));

      final http.Response got = await client.get(base.replace(path: '/sync'));
      expect(got.statusCode, 200);
      expect(SyncPayload.decode(got.body)!.history.single.key, 'host-only');

      final SyncPayload incoming =
          payload(history: <PlayRecord>[rec('from-client')]);
      final http.Response posted = await client.post(
        base.replace(path: '/sync'),
        body: incoming.encode(),
      );
      expect(posted.statusCode, 200);
      expect(received, isNotNull);
      expect(received!.history.single.key, 'from-client');
      // 回包是主机合并后的结果，两边条目都在。
      expect(
        SyncPayload.decode(posted.body)!
            .history
            .map((PlayRecord e) => e.key)
            .toSet(),
        <String>{'host-only', 'from-client'},
      );

      final http.Response broken = await client.post(
        base.replace(path: '/sync'),
        body: '这不是 JSON',
      );
      expect(broken.statusCode, 400);

      expect(
        (await client.get(base.replace(path: '/nope'))).statusCode,
        404,
      );

      await host.stop();
      expect(host.running, isFalse);
    });
  });
}
