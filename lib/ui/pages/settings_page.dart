import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/errors.dart';
import '../../core/storage/app_dirs.dart';
import '../../core/utils/formatter.dart';
import '../../core/utils/responsive.dart';
import '../../data/api/update_checker.dart';
import '../../data/models/favorite_item.dart';
import '../../data/models/play_record.dart';
import '../../data/models/vod_source.dart';
import '../../data/repository/record_repository.dart';
import '../../data/sync/backup_bundle.dart';
import '../../data/sync/sync_tombstones.dart';
import '../../state/app_state.dart';
import '../../state/favorites_store.dart';
import '../../state/history_store.dart';
import '../../state/source_store.dart';
import '../../state/sync_store.dart';
import '../actions.dart';
import '../navigation.dart';
import '../shell/tray_service.dart';
import '../widgets/backup_prompt.dart';
import '../widgets/hint_paragraph.dart';
import '../widgets/update_prompt.dart';
import 'sync_page.dart';

/// 设置页。
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  int? _cacheBytes;

  /// 检查更新中（按钮换成转圈，避免连点打出一串请求）。
  bool _checkingUpdate = false;

  /// 上次检查的结果，找到更新时挂在副标题上，没找到就什么都不显示。
  UpdateInfo? _latest;

  /// 正在导出备份。
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _refreshCacheSize();
  }

  Future<void> _refreshCacheSize() async {
    final int size = await AppDirs.imageCacheSize();
    if (mounted) setState(() => _cacheBytes = size);
  }

  /// 导出完整备份。
  ///
  /// 数据直接取内存里的 store，不再读一遍磁盘：这几个 store 在启动时已经
  /// 加载完毕，用户看到的就是它们的内容，备份理应和界面上一致。
  Future<void> _exportBackup() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      // 先把内存里的数据取下来（同步读），再做两次异步读取：
      // 中间隔着 await，之后就不该再碰 context 了。
      final List<PlayRecord> history = context.read<HistoryStore>().records;
      final List<FavoriteItem> favorites =
          context.read<FavoritesStore>().items;
      final List<VodSource> sources = context.read<SourceStore>().sources;
      final Map<String, Object?> settings =
          context.read<AppState>().settings.exportSnapshot();
      final List<String> searches =
          await RecordRepository.loadSearchKeywords();
      final Map<String, Map<String, int>> tombstones =
          await SyncTombstones.instance.load();

      final BackupBundle bundle = BackupBundle(
        exportedAt: DateTime.now(),
        appVersion: K.appVersion,
        history: history,
        favorites: favorites,
        sources: sources,
        searches: searches,
        settings: settings,
        tombstones: tombstones,
      );
      final File file = await BackupExporter.write(bundle);
      if (!mounted) return;
      await showBackupResult(context, file: file, bundle: bundle);
    } on Object catch (e) {
      if (mounted) AppActions.snackError(context, e);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  /// 检查更新。
  ///
  /// 这里不做「静默自动检查」：这个应用打开就会去请求资源站，再叠一个启动
  /// 请求既慢又容易误报（GitHub 在部分网络下要几十秒才超时）。
  Future<void> _checkUpdate() async {
    if (_checkingUpdate) return;
    setState(() => _checkingUpdate = true);
    try {
      final UpdateInfo? info = await UpdateChecker.instance.latest();
      if (!mounted) return;
      setState(() => _latest = info);
      if (info == null || !info.isNewer) {
        AppActions.snack(context, '已是最新版本 ${K.appVersion}');
        return;
      }
      await showUpdatePrompt(context, info);
    } on VodException catch (e) {
      // 更新检查的失败原因基本都是「网络不通 / 服务返回异常」，
      // 直接把 message 给用户，比套一层「操作失败」更有用。
      if (mounted) AppActions.snack(context, e.message);
    } on Object catch (e) {
      if (mounted) AppActions.snackError(context, e);
    } finally {
      if (mounted) setState(() => _checkingUpdate = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppState app = context.watch<AppState>();
    final SourceStore sources = context.watch<SourceStore>();
    final SyncStore sync = context.watch<SyncStore>();

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: <Widget>[
          const _SectionLabel('外观'),
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: const Text('主题'),
            subtitle: Text(_themeLabel(app.themeMode)),
            onTap: () => _pickTheme(context, app),
          ),
          const _SectionLabel('播放'),
          ListTile(
            leading: const Icon(Icons.speed),
            title: const Text('默认倍速'),
            subtitle: Text('${app.defaultRate}x'),
            onTap: () => _pickRate(context, app),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.skip_next_outlined),
            title: const Text('自动播放下一集'),
            subtitle: const Text('当前集播完后自动切到下一集'),
            value: app.autoNextEpisode,
            onChanged: (bool v) => app.setAutoNextEpisode(v),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.restore_outlined),
            title: const Text('记忆播放进度'),
            subtitle: const Text('再次打开时从上次位置继续'),
            value: app.resumePlayback,
            onChanged: (bool v) => app.setResumePlayback(v),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.content_cut),
            title: const Text('自动跳过片头'),
            subtitle: const Text('在播放器里标记过片头的影片生效'),
            value: app.autoSkipIntro,
            onChanged: (bool v) => app.setAutoSkipIntro(v),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.fast_forward_outlined),
            title: const Text('自动跳过片尾'),
            subtitle: const Text('播到片尾标记直接进入下一集'),
            value: app.autoSkipOutro,
            onChanged: (bool v) => app.setAutoSkipOutro(v),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.bookmark_added_outlined),
            title: const Text('按片名记住片头片尾'),
            subtitle: const Text('换资源站或清空历史后，标记仍然生效'),
            value: app.rememberSkipMarks,
            onChanged: (bool v) => app.setRememberSkipMarks(v),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.lightbulb_outline),
            title: const Text('播放时保持屏幕常亮'),
            value: app.keepScreenOn,
            onChanged: (bool v) => app.setKeepScreenOn(v),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.touch_app_outlined),
            title: const Text('进入播放页时显示控制栏'),
            value: app.showControlsOnStart,
            onChanged: (bool v) => app.setShowControlsOnStart(v),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.memory_outlined),
            title: const Text('硬件解码'),
            subtitle: const Text('关闭后改用软解，兼容性更好但更耗 CPU'),
            value: app.hardwareDecode,
            onChanged: (bool v) => app.setHardwareDecode(v),
          ),
          if (PlatformInfo.isDesktop) ...<Widget>[
            const _SectionLabel('桌面'),
            SwitchListTile(
              secondary: const Icon(Icons.minimize),
              title: const Text('关闭窗口时收进托盘'),
              subtitle: Text(
                TrayService.instance.ready
                    ? '窗口藏到托盘，从托盘菜单「退出」才真正关闭'
                    : '当前系统托盘不可用，关闭按钮会直接退出',
              ),
              value: app.closeToTray,
              onChanged: (bool v) => app.setCloseToTray(v),
            ),
          ],
          const _SectionLabel('搜索'),
          SwitchListTile(
            secondary: const Icon(Icons.all_inclusive),
            title: const Text('默认搜索全部资源站'),
            subtitle: Text('当前已启用 ${sources.enabledSources.length} 个源'),
            value: app.multiSourceSearch,
            onChanged: (bool v) => app.setMultiSourceSearch(v),
          ),
          const _SectionLabel('同步'),
          ListTile(
            leading: const Icon(Icons.sync_outlined),
            title: const Text('数据同步'),
            subtitle: Text(_syncSubtitle(sync.lastSyncAt)),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SyncPage()),
            ),
          ),
          const _SectionLabel('数据'),
          ListTile(
            leading: const Icon(Icons.insights_outlined),
            title: const Text('观看统计'),
            subtitle: const Text('按天、按片名、按来源汇总本机观看时长'),
            onTap: () => AppRoutes.openStats(context),
          ),
          const _SectionLabel('存储'),
          ListTile(
            leading: const Icon(Icons.cached),
            title: const Text('图片缓存'),
            subtitle: Text(
              _cacheBytes == null ? '计算中…' : formatBytes(_cacheBytes!),
            ),
            trailing: TextButton(
              onPressed:
                  _cacheBytes == null || _cacheBytes == 0 ? null : _clearCache,
              child: const Text('清理'),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.save_alt),
            title: const Text('导出完整备份'),
            subtitle: const Text(
              '播放记录、收藏、资源站、搜索词与设置，写成单个 JSON 文件',
            ),
            trailing: _exporting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : null,
            onTap: _exporting ? null : _exportBackup,
          ),
          ListTile(
            leading: const Icon(Icons.history_toggle_off_outlined),
            title: const Text('清空观看记录'),
            onTap: () => _confirm(
              context,
              title: '清空观看记录？',
              content: '将删除全部播放记录与续播进度。',
              run: () => context.read<HistoryStore>().clear(),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.favorite_border),
            title: const Text('清空收藏'),
            onTap: () => _confirm(
              context,
              title: '清空收藏？',
              content: '将删除全部收藏记录。',
              run: () => context.read<FavoritesStore>().clear(),
            ),
          ),
          const _SectionLabel('关于'),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('版本'),
            subtitle: Text('${K.appVersion} · ${PlatformInfo.label}'),
          ),
          ListTile(
            leading: const Icon(Icons.system_update_alt),
            title: const Text('检查更新'),
            subtitle: Text(_updateSubtitle),
            trailing: _checkingUpdate
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : TextButton(
                    onPressed: _checkUpdate,
                    child: const Text('检查'),
                  ),
          ),
          const HintParagraph(
            '本应用本身不内置、不提供、不分发任何影片内容，'
            '仅作为一个 macCMS（苹果CMS）VOD 接口的播放器，'
            '所有内容均由用户自行添加的资源站提供。\n\n'
            '请仅用于播放你有权访问的内容。',
            padding: EdgeInsets.fromLTRB(16, 8, 16, 24),
          ),
        ],
      ),
    );
  }

  /// 检查更新那一行的副标题。
  String get _updateSubtitle {
    if (_checkingUpdate) return '正在查询最新发行版…';
    final UpdateInfo? info = _latest;
    if (info == null) return '从 GitHub 发行版页获取最新版本';
    if (!info.isNewer) return '已是最新版本';
    return '有新版本 ${info.version} 可下载';
  }

  /// 同步入口的副标题。
  ///
  /// 用相对时间而不是完整时间戳：这一行只是提示"上次同步过"，
  /// 精确到分钟毫无价值，反而占地方。
  String _syncSubtitle(DateTime? at) {
    if (at == null) return '把播放记录、收藏和源列表同步到其他设备';
    final Duration d = DateTime.now().difference(at);
    final String ago;
    if (d.inMinutes < 1) {
      ago = '刚刚';
    } else if (d.inHours < 1) {
      ago = '${d.inMinutes} 分钟前';
    } else if (d.inDays < 1) {
      ago = '${d.inHours} 小时前';
    } else if (d.inDays < 30) {
      ago = '${d.inDays} 天前';
    } else {
      ago = '${at.year}-${at.month.toString().padLeft(2, '0')}-'
          '${at.day.toString().padLeft(2, '0')}';
    }
    return '上次同步 $ago';
  }

  String _themeLabel(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return '浅色';
      case ThemeMode.dark:
        return '深色';
      case ThemeMode.system:
        return '跟随系统';
    }
  }

  Future<void> _pickTheme(BuildContext context, AppState app) async {
    final ThemeMode? result = await showDialog<ThemeMode>(
      context: context,
      builder: (BuildContext ctx) => SimpleDialog(
        title: const Text('主题'),
        children: <Widget>[
          RadioGroup<ThemeMode>(
            groupValue: app.themeMode,
            onChanged: (ThemeMode? v) => Navigator.of(ctx).pop(v),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                for (final ThemeMode mode in const <ThemeMode>[
                  ThemeMode.system,
                  ThemeMode.light,
                  ThemeMode.dark,
                ])
                  RadioListTile<ThemeMode>(
                    title: Text(_themeLabel(mode)),
                    value: mode,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    if (result != null) await app.setThemeMode(result);
  }

  Future<void> _pickRate(BuildContext context, AppState app) async {
    final double? result = await showDialog<double>(
      context: context,
      builder: (BuildContext ctx) => SimpleDialog(
        title: const Text('默认倍速'),
        children: <Widget>[
          RadioGroup<double>(
            groupValue: app.defaultRate,
            onChanged: (double? v) => Navigator.of(ctx).pop(v),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                for (final double rate in K.playRates)
                  RadioListTile<double>(
                    title: Text('${rate}x'),
                    value: rate,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    if (result != null) await app.setDefaultRate(result);
  }

  Future<void> _clearCache() async {
    final int freed = await AppDirs.clearImageCache();
    await _refreshCacheSize();
    if (mounted) {
      AppActions.snack(context, '已清理 ${formatBytes(freed)}');
    }
  }

  Future<void> _confirm(
    BuildContext context, {
    required String title,
    required String content,
    required Future<void> Function() run,
  }) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await run();
    if (context.mounted) AppActions.snack(context, '已完成');
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
      child: Text(
        text,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
