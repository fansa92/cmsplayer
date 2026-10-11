import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../data/sync/lan_transport.dart';
import '../../state/sync_store.dart';

/// 数据同步设置页。
///
/// 两条通路：WebDAV（跨网络、异步）和局域网（同网段、可直连）。
/// 两者共用同一套合并规则，区别只在传输层，所以界面上的"同步"语义一致。
class SyncPage extends StatefulWidget {
  const SyncPage({super.key});

  @override
  State<SyncPage> createState() => _SyncPageState();
}

class _SyncPageState extends State<SyncPage> {
  late final TextEditingController _url;
  late final TextEditingController _user;
  late final TextEditingController _pass;
  late final TextEditingController _path;
  late final TextEditingController _host;
  late final TextEditingController _port;
  late final TextEditingController _device;

  @override
  void initState() {
    super.initState();
    // 页面打开时 app.dart 的 _bootstrap 已经调过 load()，配置是就绪的。
    final SyncStore s = context.read<SyncStore>();
    _url = TextEditingController(text: s.webdavUrl);
    _user = TextEditingController(text: s.webdavUser);
    _pass = TextEditingController(text: s.webdavPass);
    _path = TextEditingController(text: s.webdavPath);
    _host = TextEditingController(text: s.lanHost);
    _port = TextEditingController(text: '${s.lanPort}');
    _device = TextEditingController(
      text: s.deviceName.isEmpty ? s.defaultDeviceName : s.deviceName,
    );
  }

  @override
  void dispose() {
    _url.dispose();
    _user.dispose();
    _pass.dispose();
    _path.dispose();
    _host.dispose();
    _port.dispose();
    _device.dispose();
    super.dispose();
  }

  /// WebDAV 字段改动后保存。逐个字段保存而不是攒着提交：这一页没有"提交"
  /// 按钮，攒着的话用户中途退出就全丢了。
  Future<void> _saveWebDav() => context.read<SyncStore>().saveWebDav(
        url: _url.text,
        user: _user.text,
        pass: _pass.text,
        path: _path.text,
      );

  Future<void> _saveLan() => context.read<SyncStore>().saveLanTarget(
        _host.text,
        int.tryParse(_port.text.trim()) ?? 0,
      );

  @override
  Widget build(BuildContext context) {
    final SyncStore sync = context.watch<SyncStore>();
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('数据同步')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: <Widget>[
          _StatusCard(sync: sync, theme: theme),

          const _SectionLabel('WebDAV'),
          const _Hint('适合跨网络同步。坚果云、Nextcloud 等支持 WebDAV 的服务都可以。'),
          _field(
            controller: _url,
            label: '服务地址',
            hint: 'https://dav.example.com/dav',
            keyboard: TextInputType.url,
            onSubmitted: (_) => _saveWebDav(),
          ),
          _field(
            controller: _user,
            label: '用户名',
            onSubmitted: (_) => _saveWebDav(),
          ),
          _field(
            controller: _pass,
            label: '应用密码',
            obscure: true,
            onSubmitted: (_) => _saveWebDav(),
          ),
          _field(
            controller: _path,
            label: '存储路径',
            hint: K.defaultWebDavPath,
            onSubmitted: (_) => _saveWebDav(),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: FilledButton.tonal(
                    onPressed: sync.busy
                        ? null
                        : () async {
                            await _saveWebDav();
                            if (!context.mounted) return;
                            await context.read<SyncStore>().testWebDav();
                          },
                    child: const Text('测试连接'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: sync.busy || sync.webdavUrl.trim().isEmpty
                        ? null
                        : () async {
                            await _saveWebDav();
                            if (!context.mounted) return;
                            await context.read<SyncStore>().syncWebDav();
                          },
                    child: const Text('同步'),
                  ),
                ),
              ],
            ),
          ),

          const _SectionLabel('局域网'),
          const _Hint('两台设备在同一个网络下直连，不需要服务器。'),
          _field(
            controller: _device,
            label: '本设备名称',
            hint: sync.defaultDeviceName,
            onSubmitted: (String v) => context.read<SyncStore>().saveDeviceName(v),
          ),
          _field(
            controller: _host,
            label: '对方地址',
            hint: '192.168.1.8',
            keyboard: TextInputType.url,
            onSubmitted: (String v) => _saveLan(),
          ),
          _field(
            controller: _port,
            label: '端口',
            hint: '${K.defaultLanPort}',
            keyboard: TextInputType.number,
            onSubmitted: (String v) => _saveLan(),
          ),
          if (sync.peers.isNotEmpty)
            _PeerList(
              sync: sync,
              onPick: (LanPeer p) {
                sync.pickPeer(p);
                _host.text = p.ip;
                _port.text = '${p.port}';
              },
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: FilledButton.tonal(
                    onPressed:
                        sync.busy || sync.discovering ? null : () async {
                      await _saveLan();
                      if (!context.mounted) return;
                      await context.read<SyncStore>().discover();
                    },
                    child: Text(sync.discovering ? '查找中…' : '查找设备'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: sync.busy || sync.lanHost.trim().isEmpty
                        ? null
                        : () async {
                            await _saveLan();
                            if (!context.mounted) return;
                            await context.read<SyncStore>().syncLan();
                          },
                    child: const Text('同步'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          ListTile(
            leading: Icon(
              sync.hostingRunning ? Icons.stop_circle_outlined : Icons.wifi_tethering,
            ),
            title: Text(sync.hostingRunning ? '关闭局域网主机' : '开启局域网主机'),
            subtitle: Text(
              sync.hostingRunning
                  ? '其他设备可连接 ${sync.hostingAddress}'
                  : '开启后，别的设备可以主动连到本机拉取数据',
            ),
            onTap: sync.busy
                ? null
                : () => sync.hostingRunning
                    ? context.read<SyncStore>().stopHost()
                    : context.read<SyncStore>().startHost(),
          ),

          const _SectionLabel('说明'),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: Text(
              '同步的是播放记录、收藏和源列表三样，不含账号与密码。\n\n'
              '两边都有改动时按时间取新，删除会保留为"墓碑"，'
              '不会被对方的旧数据复活。\n\n'
              '本机的 WebDAV 密码以明文存在本机，请只在信任的设备上使用。',
              style: TextStyle(fontSize: 12, height: 1.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    String? hint,
    bool obscure = false,
    TextInputType? keyboard,
    required ValueChanged<String> onSubmitted,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        keyboardType: keyboard,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
        onSubmitted: (_) => onSubmitted(controller.text),
      ),
    );
  }
}

// ---------------------------------------------------------------- 子组件

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.sync, required this.theme});

  final SyncStore sync;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final String? error = sync.lastError;
    final String? message = sync.lastMessage;

    if (error == null && message == null && sync.lastSyncAt == null) {
      return const SizedBox.shrink();
    }

    final Color tint = error != null
        ? theme.colorScheme.error
        : theme.colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: tint.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: tint.withValues(alpha: 0.25)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (sync.busy)
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: tint),
                ),
              )
            else
              Icon(
                error != null ? Icons.error_outline : Icons.check_circle_outline,
                size: 18,
                color: tint,
              ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                error ?? message ?? '',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: tint,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PeerList extends StatelessWidget {
  const _PeerList({required this.sync, required this.onPick});

  final SyncStore sync;
  final ValueChanged<LanPeer> onPick;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: <Widget>[
            for (int i = 0; i < sync.peers.length; i++)
              ListTile(
                dense: true,
                leading: const Icon(Icons.lan_outlined, size: 20),
                title: Text(sync.peers[i].label),
                subtitle: Text('${sync.peers[i].ip}:${sync.peers[i].port}'),
                trailing: const Icon(Icons.chevron_right, size: 20),
                onTap: () => onPick(sync.peers[i]),
              ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.outline,
            ),
      ),
    );
  }
}
