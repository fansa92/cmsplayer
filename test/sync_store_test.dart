import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cms_player/core/constants.dart';
import 'package:cms_player/core/storage/settings_store.dart';
import 'package:cms_player/data/models/play_record.dart';
import 'package:cms_player/data/sync/lan_transport.dart';
import 'package:cms_player/data/sync/sync_payload.dart';
import 'package:cms_player/data/sync/sync_service.dart';
import 'package:cms_player/data/sync/sync_transport.dart';
import 'package:cms_player/state/favorites_store.dart';
import 'package:cms_player/state/history_store.dart';
import 'package:cms_player/state/source_store.dart';
import 'package:cms_player/state/sync_store.dart';

import 'helpers/fakes.dart';

/// 同步配置与执行状态：设置往返、成功 / 失败状态流转、同步后重载 UI 数据。
void main() {
  useIsolatedStores();

  Future<Fixture> fixture() async {
    final Fixture f = Fixture();
    f.settings = SettingsStore();
    await f.settings.init();
    f.history = HistoryStore();
    f.favorites = FavoritesStore();
    f.sources = SourceStore(f.settings);
    await f.sources.load();
    f.sync = SyncStore(f.settings, f.history, f.favorites, f.sources);
    return f;
  }

  group('配置读写', () {
    test('load 从设置里还原全部字段与上次同步时刻', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        K.prefWebDavUrl: 'https://dav.example.com/dav/',
        K.prefWebDavUser: 'u',
        K.prefWebDavPass: 'p',
        K.prefWebDavPath: '/custom/sync.json',
        K.prefLanHost: '10.0.0.9',
        K.prefLanPort: 9999,
        K.prefDeviceName: '书房',
        K.prefLastSyncAt: 1700000000000,
      });
      final Fixture f = await fixture();

      f.sync.load();

      expect(f.sync.webdavUrl, 'https://dav.example.com/dav/');
      expect(f.sync.webdavUser, 'u');
      expect(f.sync.webdavPass, 'p');
      expect(f.sync.webdavPath, '/custom/sync.json');
      expect(f.sync.lanHost, '10.0.0.9');
      expect(f.sync.lanPort, 9999);
      expect(f.sync.deviceName, '书房');
      expect(f.sync.lastSyncAt,
          DateTime.fromMillisecondsSinceEpoch(1700000000000));
    });

    test('没同步过时 lastSyncAt 为 null，默认值可用', () async {
      final Fixture f = await fixture();
      f.sync.load();

      expect(f.sync.lastSyncAt, isNull);
      expect(f.sync.webdavPath, K.defaultWebDavPath);
      expect(f.sync.lanPort, K.defaultLanPort);
      expect(f.sync.defaultDeviceName, isNotEmpty);
      expect(f.sync.hostingRunning, isFalse);
      expect(f.sync.hostingAddress, '');
    });

    test('saveWebDav 会 trim，空路径回落到默认值，并写进设置', () async {
      final Fixture f = await fixture();
      await f.sync.saveWebDav(
        url: '  https://dav.example.com/dav/  ',
        user: '  alice  ',
        pass: ' secret ',
        path: '   ',
      );

      expect(f.sync.webdavUrl, 'https://dav.example.com/dav/');
      expect(f.sync.webdavUser, 'alice');
      expect(f.sync.webdavPass, ' secret ', reason: '密码不能 trim，空格可能就是密码的一部分');
      expect(f.sync.webdavPath, K.defaultWebDavPath);
      expect(f.settings.syncWebDavUrl, 'https://dav.example.com/dav/');
      expect(f.settings.syncWebDavUser, 'alice');
    });

    test('saveLanTarget 的非正端口回落到默认端口', () async {
      final Fixture f = await fixture();
      await f.sync.saveLanTarget('  10.0.0.3  ', 0);
      expect(f.sync.lanHost, '10.0.0.3');
      expect(f.sync.lanPort, K.defaultLanPort);
      expect(f.settings.syncLanHost, '10.0.0.3');

      await f.sync.saveLanTarget('10.0.0.4', 9001);
      expect(f.sync.lanPort, 9001);
    });

    test('saveDeviceName 与 pickPeer 更新可连接目标', () async {
      final Fixture f = await fixture();
      await f.sync.saveDeviceName('  客厅  ');
      expect(f.sync.deviceName, '客厅');
      expect(f.settings.syncDeviceName, '客厅');

      const LanPeer peer = LanPeer(ip: '10.0.0.8', port: 7777, name: '卧室');
      f.sync.pickPeer(peer);
      expect(f.sync.lanHost, '10.0.0.8');
      expect(f.sync.lanPort, 7777);
    });

    test('webDavTransport 用当前配置拼出远端地址', () async {
      final Fixture f = await fixture();
      await f.sync.saveWebDav(
        url: 'https://dav.example.com/dav/',
        user: 'u',
        pass: 'p',
        path: '/x/sync.json',
      );
      expect(
        f.sync.webDavTransport().fileUri.toString(),
        'https://dav.example.com/dav/x/sync.json',
      );
    });
  });

  group('执行同步', () {
    test('成功后写好提示与同步时刻，关掉通道并重载三个 Store', () async {
      final Fixture f = await fixture();
      // 先往磁盘塞一条历史，runWith 的 _reload 应该把它读进内存。
      await f.history.upsert(PlayRecord(
        key: 'src|1',
        sourceId: 'src',
        sourceName: '测试站',
        vodId: '1',
        vodName: '测试影片',
        updatedAt: DateTime(2026, 3, 10),
      ));
      final HistoryStore freshHistory = HistoryStore();
      f.sync = SyncStore(f.settings, freshHistory, f.favorites, f.sources);

      final StubTransport transport = StubTransport();
      await f.sync.runWith(transport);

      expect(f.sync.busy, isFalse);
      expect(f.sync.lastError, isNull);
      expect(f.sync.lastMessage, contains('已是最新'));
      expect(f.sync.lastSyncAt, isNotNull);
      expect(f.settings.syncLastAt, greaterThan(0));
      expect(transport.calls, 1);
      expect(transport.closed, isTrue);
      expect(freshHistory.records.single.key, 'src|1',
          reason: '同步完必须重载历史，界面才会跟着变');
    });

    test('远端带来新条目时提示里带新增数量', () async {
      final Fixture f = await fixture();
      final StubTransport transport = StubTransport(
        remote: SyncPayload(
          updatedAt: DateTime(2026, 3, 10),
          history: <PlayRecord>[
            PlayRecord(
              key: 'remote|1',
              sourceId: 'remote',
              sourceName: '远端',
              vodId: '1',
              vodName: '远端影片',
              updatedAt: DateTime(2026, 3, 10),
            ),
          ],
        ),
      );

      await f.sync.runWith(transport);

      expect(f.sync.lastMessage, contains('新增'));
      expect(
          (await SyncService.readLocal())
              .history
              .any((PlayRecord e) => e.key == 'remote|1'),
          isTrue);
    });

    test('失败时留住中文原因、复位 busy，且不写同步时刻', () async {
      final Fixture f = await fixture();
      final StubTransport transport = StubTransport(
        error: const SyncException('远端连不上，请检查地址'),
      );

      await f.sync.runWith(transport);

      expect(f.sync.busy, isFalse);
      expect(f.sync.lastError, '远端连不上，请检查地址');
      expect(f.sync.lastMessage, isNull);
      expect(f.sync.lastSyncAt, isNull);
      expect(f.settings.syncLastAt, 0);
      expect(transport.closed, isTrue);
    });

    test('非 SyncException 的长错误会被截断成一行', () async {
      final Fixture f = await fixture();
      await f.sync.runWith(
        StubTransport(error: StateError('x' * 300)),
      );

      expect(f.sync.lastError, isNotNull);
      expect(f.sync.lastError!.length, lessThanOrEqualTo(121));
      expect(f.sync.lastError, endsWith('…'));
    });

    test('没填对方地址时 syncLan 直接给提示，不发请求', () async {
      final Fixture f = await fixture();
      await f.sync.syncLan();
      expect(f.sync.lastError, '还没填写对方的地址');
      expect(f.sync.busy, isFalse);
    });
  });
}

class Fixture {
  late final SettingsStore settings;
  late final HistoryStore history;
  late final FavoritesStore favorites;
  late final SourceStore sources;
  late SyncStore sync;
}

/// 只记录调用、不发请求的同步通道。
class StubTransport implements SyncTransport {
  StubTransport({this.remote, this.error});

  final SyncPayload? remote;
  final Object? error;

  int calls = 0;
  bool closed = false;
  SyncPayload? uploaded;

  @override
  String get label => '测试通道';

  @override
  Future<SyncPayload?> download() async {
    calls++;
    if (error != null) throw error!;
    return remote;
  }

  @override
  Future<SyncPayload?> upload(SyncPayload payload) async {
    uploaded = payload;
    return null;
  }

  @override
  void close() {
    closed = true;
  }
}
