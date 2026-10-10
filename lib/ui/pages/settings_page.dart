import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/storage/app_dirs.dart';
import '../../core/utils/formatter.dart';
import '../../core/utils/responsive.dart';
import '../../state/app_state.dart';
import '../../state/favorites_store.dart';
import '../../state/history_store.dart';
import '../../state/source_store.dart';
import '../actions.dart';

/// 设置页。
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  int? _cacheBytes;

  @override
  void initState() {
    super.initState();
    _refreshCacheSize();
  }

  Future<void> _refreshCacheSize() async {
    final int size = await AppDirs.imageCacheSize();
    if (mounted) setState(() => _cacheBytes = size);
  }

  @override
  Widget build(BuildContext context) {
    final AppState app = context.watch<AppState>();
    final SourceStore sources = context.watch<SourceStore>();

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

          const _SectionLabel('搜索'),
          SwitchListTile(
            secondary: const Icon(Icons.all_inclusive),
            title: const Text('默认搜索全部资源站'),
            subtitle: Text('当前已启用 ${sources.enabledSources.length} 个源'),
            value: app.multiSourceSearch,
            onChanged: (bool v) => app.setMultiSourceSearch(v),
          ),

          const _SectionLabel('存储'),
          ListTile(
            leading: const Icon(Icons.cached),
            title: const Text('图片缓存'),
            subtitle: Text(
              _cacheBytes == null ? '计算中…' : formatBytes(_cacheBytes!),
            ),
            trailing: TextButton(
              onPressed: _cacheBytes == null || _cacheBytes == 0
                  ? null
                  : _clearCache,
              child: const Text('清理'),
            ),
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
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: Text(
              '本应用本身不内置、不提供、不分发任何影片内容，'
              '仅作为一个 macCMS（苹果CMS）VOD 接口的播放器，'
              '所有内容均由用户自行添加的资源站提供。\n\n'
              '请仅用于播放你有权访问的内容。',
              style: TextStyle(fontSize: 12, height: 1.7),
            ),
          ),
        ],
      ),
    );
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
