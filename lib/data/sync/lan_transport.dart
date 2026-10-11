import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../core/constants.dart';
import '../../core/logger.dart';
import 'sync_payload.dart';
import 'sync_transport.dart';

/// 局域网发现协议的魔数。带上版本号，将来改了报文格式也不会和旧版互相误认。
const String _kMagic = 'CMSPLAYER_SYNC_V1';

/// 发现应答格式：`魔数|IP|端口|设备名`。
class LanPeer {
  const LanPeer({
    required this.ip,
    required this.port,
    this.name = '',
  });

  final String ip;
  final int port;
  final String name;

  String get label => name.isEmpty ? '$ip:$port' : '$name（$ip:$port）';

  @override
  bool operator ==(Object other) =>
      other is LanPeer && other.ip == ip && other.port == port;

  @override
  int get hashCode => Object.hash(ip, port);
}

/// 取本机的局域网 IPv4。
///
/// 多网卡时取第一个非回环地址，通常就是 Wi-Fi / 有线网卡。
/// 拿不到就退回 127.0.0.1，界面里用户仍可手动填写。
Future<String> localLanAddress() async {
  try {
    final List<NetworkInterface> interfaces = await NetworkInterface.list(
      includeLoopback: false,
      includeLinkLocal: false,
      type: InternetAddressType.IPv4,
    );
    for (final NetworkInterface i in interfaces) {
      for (final InternetAddress a in i.addresses) {
        if (!a.isLoopback) return a.address;
      }
    }
  } on Object catch (e) {
    AppLog.w('Lan', 'list interfaces failed: $e');
  }
  return '127.0.0.1';
}

/// 局域网同步的**主机端**：本机起一个 HTTP 服务，别的设备来拉 / 来推。
///
/// 主机不做任何决策，拉取和合并都交给 [SyncService]，
/// 因此主机和客户端的合并规则完全一致。
class LanHost {
  LanHost({
    required this.provider,
    required this.applier,
    this.port = K.defaultLanPort,
    this.deviceName = '',
  });

  /// 取当前本地数据包，用于客户端的 `GET /sync`。
  final Future<SyncPayload> Function() provider;

  /// 把收到的数据包合进本地，返回合并结果，用于 `POST /sync`。
  final Future<SyncPayload> Function(SyncPayload incoming) applier;

  final int port;

  /// 设备名，仅用于局域网发现时给对端一个可读的名字，可随时改。
  String deviceName;

  HttpServer? _server;
  RawDatagramSocket? _discovery;
  StreamSubscription<RawSocketEvent>? _discoverySub;
  String _ip = '';

  bool get running => _server != null;

  /// 本机地址，形如 `192.168.1.5:8765`，显示给用户去别的设备上填。
  String get address => '$_ip:$port';

  Future<void> start() async {
    if (_server != null) return;
    _ip = await localLanAddress();

    final HttpServer server =
        await HttpServer.bind(InternetAddress.anyIPv4, port);
    _server = server;
    server.listen(
      (HttpRequest req) => _handle(req),
      onError: (Object e) => AppLog.e('Lan', 'server error: $e'),
      cancelOnError: false,
    );

    // 发现服务尽力而为：某些平台 / 网络会拒绝绑定广播端口，
    // 那就让用户手动填 IP，不影响同步本身。
    await _startDiscovery();
  }

  Future<void> _startDiscovery() async {
    try {
      final RawDatagramSocket sock = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        K.lanDiscoveryPort,
        reuseAddress: true,
      );
      sock.broadcastEnabled = true;
      _discovery = sock;
      _discoverySub = sock.listen((RawSocketEvent event) {
        if (event != RawSocketEvent.read) return;
        final Datagram? d = sock.receive();
        if (d == null) return;
        final String text = utf8.decode(d.data, allowMalformed: true).trim();
        if (text != _kMagic) return;
        final String reply = '$_kMagic|$_ip|$port|$deviceName';
        try {
          sock.send(utf8.encode(reply), d.address, d.port);
        } on Object catch (e) {
          AppLog.w('Lan', 'discovery reply failed: $e');
        }
      });
    } on Object catch (e) {
      AppLog.w('Lan', 'discovery disabled: $e');
    }
  }

  Future<void> _handle(HttpRequest req) async {
    try {
      if (req.method == 'GET' && req.uri.path == '/') {
        // 浏览器里打开能直接看到这行字，方便确认地址和端口填对了没有。
        req.response.headers.contentType = ContentType.text;
        req.response.write('CMSPlayer 同步服务\n本机地址：$address\n');
      } else if (req.method == 'GET' && req.uri.path == '/sync') {
        final SyncPayload payload = await provider();
        req.response.headers.contentType = ContentType.json;
        req.response.write(payload.encode());
      } else if (req.method == 'POST' && req.uri.path == '/sync') {
        final String body = await utf8.decoder.bind(req).join();
        final SyncPayload? incoming = SyncPayload.decode(body);
        if (incoming == null) {
          req.response.statusCode = HttpStatus.badRequest;
          req.response.write('无法解析同步数据');
        } else {
          final SyncPayload merged = await applier(incoming);
          req.response.headers.contentType = ContentType.json;
          req.response.write(merged.encode());
        }
      } else {
        req.response.statusCode = HttpStatus.notFound;
      }
    } on Object catch (e, s) {
      AppLog.e('Lan', 'handle ${req.method} ${req.uri.path} failed: $e', s);
      req.response.statusCode = HttpStatus.internalServerError;
      req.response.write('$e');
    } finally {
      await req.response.close();
    }
  }

  Future<void> stop() async {
    await _discoverySub?.cancel();
    _discoverySub = null;
    _discovery?.close();
    _discovery = null;
    final HttpServer? server = _server;
    _server = null;
    if (server != null) await server.close(force: true);
  }
}

/// 局域网同步的**客户端**：向主机拉取、推送。
class LanClient implements SyncTransport {
  LanClient({
    required this.host,
    this.port = K.defaultLanPort,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String host;
  final int port;
  final http.Client _client;

  @override
  String get label => '局域网 $host';

  Uri get _uri => Uri.parse('http://$host:$port/sync');

  @override
  Future<SyncPayload?> download() async {
    final http.Response r = await _get();
    if (r.statusCode == 404) return null;
    if (r.statusCode != 200) {
      throw SyncException('对端返回 HTTP ${r.statusCode}');
    }
    final SyncPayload? payload = SyncPayload.decode(r.body);
    if (payload == null) throw const SyncException('对端返回的数据无法解析');
    return payload;
  }

  @override
  Future<SyncPayload?> upload(SyncPayload payload) async {
    final http.Response r;
    try {
      r = await _client
          .post(
            _uri,
            headers: <String, String>{
              'Content-Type': 'application/json; charset=utf-8',
              'User-Agent': K.defaultUserAgent,
            },
            body: payload.encode(),
          )
          .timeout(K.syncTimeout);
    } on Object catch (e) {
      throw SyncException('连不上对方：$e', cause: e);
    }
    if (r.statusCode != 200) {
      throw SyncException('对端返回 HTTP ${r.statusCode}');
    }
    // 主机会把合并后的结果回传，我们再合一次才拿得到对方在我拉取之后的改动。
    return SyncPayload.decode(r.body);
  }

  Future<http.Response> _get() async {
    try {
      return await _client.get(_uri, headers: <String, String>{
        'User-Agent': K.defaultUserAgent,
      }).timeout(K.syncTimeout);
    } on Object catch (e) {
      throw SyncException('连不上对方：$e', cause: e);
    }
  }

  @override
  void close() => _client.close();

  /// 在局域网内广播寻找主机，返回找到的对端列表。
  ///
  /// 这是一次性的尽力探测：超时就返回已找到的那些，不抛异常 ——
  /// 找不到主机是完全正常的使用场景（手机热点下就没有），
  /// 拿错误去吓唬用户没有意义。
  static Future<List<LanPeer>> discover({
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final List<LanPeer> found = <LanPeer>[];
    RawDatagramSocket? sock;
    StreamSubscription<RawSocketEvent>? sub;
    try {
      sock = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0,
          reuseAddress: true);
      sock.broadcastEnabled = true;
      sub = sock.listen((RawSocketEvent event) {
        if (event != RawSocketEvent.read) return;
        final Datagram? d = sock?.receive();
        if (d == null) return;
        final List<String> parts =
            utf8.decode(d.data, allowMalformed: true).trim().split('|');
        if (parts.length < 3 || parts[0] != _kMagic) return;
        final LanPeer peer = LanPeer(
          ip: parts[1],
          port: int.tryParse(parts[2]) ?? K.defaultLanPort,
          name: parts.length > 3 ? parts[3] : '',
        );
        if (!found.contains(peer)) {
          found.add(peer);
          AppLog.d('Lan', 'found peer ${peer.label}');
        }
      });

      sock.send(
        utf8.encode(_kMagic),
        InternetAddress('255.255.255.255'),
        K.lanDiscoveryPort,
      );
      await Future<void>.delayed(timeout);
    } on Object catch (e) {
      AppLog.w('Lan', 'discover failed: $e');
    } finally {
      await sub?.cancel();
      sock?.close();
    }
    return found;
  }
}
