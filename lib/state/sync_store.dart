import 'package:flutter/foundation.dart';

import '../../core/constants.dart';
import '../../core/logger.dart';
import '../../core/storage/settings_store.dart';
import '../../core/utils/responsive.dart';
import '../../data/sync/lan_transport.dart';
import '../../data/sync/sync_merge.dart';
import '../../data/sync/sync_payload.dart';
import '../../data/sync/sync_service.dart';
import '../../data/sync/sync_transport.dart';
import '../../data/sync/webdav_transport.dart';
import 'favorites_store.dart';
import 'history_store.dart';
import 'source_store.dart';

/// 同步配置与执行状态。
///
/// 这一层只负责"读写配置 + 调 [SyncService] + 通知 UI"，
/// 合并规则全在 [SyncMerger] 里，两边共用同一套逻辑。
class SyncStore extends ChangeNotifier {
  SyncStore(
    this._settings,
    this._history,
    this._favorites,
    this._sources,
  );

  final SettingsStore _settings;
  final HistoryStore _history;
  final FavoritesStore _favorites;
  final SourceStore _sources;

  String webdavUrl = '';
  String webdavUser = '';
  String webdavPass = '';
  String webdavPath = K.defaultWebDavPath;
  String lanHost = '';
  int lanPort = K.defaultLanPort;
  String deviceName = '';
  DateTime? lastSyncAt;

  bool busy = false;
  bool hosting = false;
  bool discovering = false;
  String? lastError;
  String? lastMessage;

  List<LanPeer> peers = const <LanPeer>[];

  LanHost? _host;
  bool _disposed = false;

  /// 本机是否已开启局域网主机模式。
  bool get hostingRunning => _host?.running ?? false;

  String get hostingAddress => _host?.address ?? '';

  void _emit() {
    if (_disposed) return;
    notifyListeners();
  }

  // ---------------------------------------------------------------- 配置

  void load() {
    webdavUrl = _settings.syncWebDavUrl;
    webdavUser = _settings.syncWebDavUser;
    webdavPass = _settings.syncWebDavPass;
    webdavPath = _settings.syncWebDavPath;
    lanHost = _settings.syncLanHost;
    lanPort = _settings.syncLanPort;
    deviceName = _settings.syncDeviceName;
    final int at = _settings.syncLastAt;
    lastSyncAt = at > 0 ? DateTime.fromMillisecondsSinceEpoch(at) : null;
    _emit();
  }

  /// 首次使用时给一个能认出来的名字，免得两台设备都叫 "CMSPlayer"。
  String get defaultDeviceName {
    final String suffix = PlatformInfo.isAndroid
        ? '安卓设备'
        : PlatformInfo.isIOS
            ? 'iOS 设备'
            : PlatformInfo.isWindows
                ? 'Windows'
                : PlatformInfo.isMacOS
                    ? 'Mac'
                    : PlatformInfo.isLinux
                        ? 'Linux'
                        : '设备';
    return '我的$suffix';
  }

  Future<void> saveWebDav({
    required String url,
    required String user,
    required String pass,
    required String path,
  }) async {
    webdavUrl = url.trim();
    webdavUser = user.trim();
    webdavPass = pass;
    webdavPath = path.trim().isEmpty ? K.defaultWebDavPath : path.trim();
    await _settings.setSyncWebDavUrl(webdavUrl);
    await _settings.setSyncWebDavUser(webdavUser);
    await _settings.setSyncWebDavPass(webdavPass);
    await _settings.setSyncWebDavPath(webdavPath);
    _emit();
  }

  Future<void> saveLanTarget(String host, int port) async {
    lanHost = host.trim();
    lanPort = port > 0 ? port : K.defaultLanPort;
    await _settings.setSyncLanHost(lanHost);
    await _settings.setSyncLanPort(lanPort);
    _emit();
  }

  Future<void> saveDeviceName(String name) async {
    deviceName = name.trim();
    await _settings.setSyncDeviceName(deviceName);
    // 主机正在跑时同步改掉，别的设备马上就能在发现列表里看到新名字。
    _host?.deviceName = deviceName;
    _emit();
  }

  // ---------------------------------------------------------------- 执行

  WebDavTransport webDavTransport() => WebDavTransport(
        baseUrl: webdavUrl,
        username: webdavUser,
        password: webdavPass,
        remotePath: webdavPath,
      );

  Future<void> testWebDav() async {
    final WebDavTransport t = webDavTransport();
    try {
      busy = true;
      lastError = null;
      _emit();
      await t.test();
      lastMessage = '连接成功，可以同步';
    } on Object catch (e) {
      lastError = _reason(e);
    } finally {
      t.close();
      busy = false;
      _emit();
    }
  }

  Future<void> syncWebDav() async {
    final WebDavTransport t = webDavTransport();
    await _run(t);
  }

  Future<void> syncLan() async {
    if (lanHost.trim().isEmpty) {
      lastError = '还没填写对方的地址';
      _emit();
      return;
    }
    final LanClient client = LanClient(host: lanHost.trim(), port: lanPort);
    await _run(client);
  }

  Future<void> _run(SyncTransport transport) async {
    busy = true;
    lastError = null;
    lastMessage = null;
    _emit();
    try {
      final SyncOutcome outcome = await SyncService.run(transport);
      await _reload();
      final int at = DateTime.now().millisecondsSinceEpoch;
      lastSyncAt = DateTime.fromMillisecondsSinceEpoch(at);
      await _settings.setSyncLastAt(at);
      final String counts =
          '记录 ${outcome.diff.history} · 收藏 ${outcome.diff.favorites} · '
          '源 ${outcome.diff.sources}';
      lastMessage = outcome.diff.isEmpty
          ? '已是最新（$counts）'
          : '${outcome.diff.summary}（$counts）';
    } on Object catch (e) {
      lastError = _reason(e);
    } finally {
      transport.close();
      busy = false;
      _emit();
    }
  }

  /// 同步完成后让三个 Store 重新读盘，界面才会跟着变。
  Future<void> _reload() async {
    await _history.load();
    await _favorites.load();
    await _sources.load();
  }

  // ---------------------------------------------------------------- 局域网主机

  Future<void> startHost() async {
    if (hosting) return;
    final LanHost host = LanHost(
      provider: SyncService.readLocal,
      applier: _applyRemote,
      port: lanPort,
      deviceName: deviceName.isEmpty ? defaultDeviceName : deviceName,
    );
    try {
      busy = true;
      lastError = null;
      _emit();
      await host.start();
      _host = host;
      hosting = true;
      lastMessage = '已开启，其他设备连接 ${host.address}';
    } on Object catch (e) {
      lastError = _reason(e);
      await host.stop();
    } finally {
      busy = false;
      _emit();
    }
  }

  Future<void> stopHost() async {
    final LanHost? host = _host;
    _host = null;
    hosting = false;
    await host?.stop();
    _emit();
  }

  /// 处理对端推来的数据包：合进本地、落盘、刷新界面，然后把合并结果回传。
  Future<SyncPayload> _applyRemote(SyncPayload incoming) async {
    final SyncPayload local = await SyncService.readLocal();
    final SyncPayload merged = SyncMerger.merge(local, incoming);
    await SyncService.writeLocal(merged);
    await _reload();
    _emit();
    return merged;
  }

  Future<void> discover() async {
    if (discovering) return;
    discovering = true;
    lastError = null;
    _emit();
    try {
      peers = await LanClient.discover();
      if (peers.isEmpty) {
        lastMessage = '没找到主机。请确认两台设备在同一网络，'
            '且对方已在设置里开启「局域网主机」。';
      }
    } on Object catch (e) {
      lastError = _reason(e);
    } finally {
      discovering = false;
      _emit();
    }
  }

  void pickPeer(LanPeer peer) {
    lanHost = peer.ip;
    lanPort = peer.port;
    _emit();
  }

  // ---------------------------------------------------------------- 其他

  /// 同步失败的原因。[SyncException] 自带中文说明，
  /// 其余异常截断成一行，别把堆栈甩到界面上。
  static String _reason(Object e) {
    if (e is SyncException) return e.message;
    final String text = e.toString();
    return text.length > 120 ? '${text.substring(0, 120)}…' : text;
  }

  /// 写操作出错时记录日志，便于事后从日志里翻。
  void logError(String where, Object e) =>
      AppLog.e('SyncStore', '$where failed: $e');

  @override
  void dispose() {
    _disposed = true;
    _host?.stop();
    super.dispose();
  }
}
