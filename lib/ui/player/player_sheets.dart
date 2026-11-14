import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../core/utils/formatter.dart';
import '../../data/models/play_line.dart';
import 'player_controls_binding.dart';

/// 播放器的底部弹层：倍速、选集、视频信息、音轨、定时关闭、片头片尾。
///
/// 抽到这里是因为它们只读控制器状态 + 一个回调，和手势、自动隐藏无关。
/// 几个弹层都显式限高：`showModalBottomSheet` 默认只给屏高 9/16，手机横屏
/// 时约 390px，选项多一点就放不下。

/// 倍速选择。
Future<void> showRateSheet(
  BuildContext context, {
  required double current,
  required Future<void> Function(double rate) onPick,
}) async {
  final double? result = await showModalBottomSheet<double>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (BuildContext ctx) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(ctx).height * 0.6,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 8),
          children: <Widget>[
            for (final double rate in K.playRates)
              ListTile(
                dense: true,
                leading: Icon(
                  rate == current ? Icons.check : Icons.speed,
                  size: 20,
                ),
                title: Text('${rate}x'),
                onTap: () => Navigator.of(ctx).pop(rate),
              ),
          ],
        ),
      ),
    ),
  );
  if (result != null) await onPick(result);
}

/// 选集：线路横排一行，选中线路的选集列在下面。
Future<void> showEpisodeSheet(
  BuildContext context, {
  required String title,
  required List<PlayLine> lines,
  required int lineIndex,
  required int episodeIndex,
  required void Function(int lineIndex, int episodeIndex) onPick,
}) async {
  if (lines.isEmpty) return;
  int lineIdx = lineIndex.clamp(0, lines.length - 1);

  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (BuildContext ctx) => StatefulBuilder(
      builder: (BuildContext ctx, void Function(void Function()) setSheet) {
        final PlayLine line = lines[lineIdx];
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(ctx).height * 0.65,
            ),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: 16),
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
                if (lines.length > 1)
                  SizedBox(
                    height: 40,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: lines.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (BuildContext c, int li) {
                        return ChoiceChip(
                          label: Text(
                            '${lines[li].name} (${lines[li].episodes.length})',
                          ),
                          selected: li == lineIdx,
                          onSelected: (_) => setSheet(() => lineIdx = li),
                        );
                      },
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                  child: Text(
                    line.name,
                    style: Theme.of(ctx).textTheme.labelLarge?.copyWith(
                          color: Theme.of(ctx).colorScheme.primary,
                        ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      for (int ei = 0; ei < line.episodes.length; ei++)
                        ActionChip(
                          label: Text(line.episodes[ei].name),
                          avatar: (lineIdx == lineIndex && ei == episodeIndex)
                              ? const Icon(Icons.play_arrow, size: 16)
                              : null,
                          onPressed: () {
                            Navigator.of(ctx).pop();
                            onPick(lineIdx, ei);
                          },
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

/// mpv track-list 的 `codec` 字段给的是短名（h264 / hevc / av1 / aac …），
/// 有时也会是 FourCC（avc1 / hvc1 / mp4a）。这里统一翻译成人看得懂的名字；
/// 认不出就原样显示，不瞎猜。
const Map<String, String> _codecNames = <String, String>{
  // 视频
  'avc1': 'H.264 / AVC',
  'avc3': 'H.264 / AVC',
  'h264': 'H.264 / AVC',
  'x264': 'H.264 / AVC',
  'hev1': 'H.265 / HEVC',
  'hvc1': 'H.265 / HEVC',
  'hevc': 'H.265 / HEVC',
  'h265': 'H.265 / HEVC',
  'x265': 'H.265 / HEVC',
  'vp09': 'VP9',
  'vp9': 'VP9',
  'vp8': 'VP8',
  'vp08': 'VP8',
  'av01': 'AV1',
  'av1': 'AV1',
  'mpeg2video': 'MPEG-2',
  'mpeg2': 'MPEG-2',
  'mpeg4': 'MPEG-4',
  'xvid': 'MPEG-4 (Xvid)',
  'theora': 'Theora',
  'vc1': 'VC-1',
  'wmv3': 'WMV3',
  // 音频
  'mp4a': 'AAC',
  'aac': 'AAC',
  'heaac': 'HE-AAC',
  'ac-3': 'AC-3',
  'ac3': 'AC-3',
  'ec-3': 'E-AC-3',
  'eac3': 'E-AC-3',
  'dts': 'DTS',
  'opus': 'Opus',
  'vorbis': 'Vorbis',
  'flac': 'FLAC',
  'mp3': 'MP3',
  'mp2': 'MP2',
  'alac': 'ALAC',
  'pcm': 'PCM',
  'pcm_s16le': 'PCM (16-bit)',
  'pcm_s24le': 'PCM (24-bit)',
  'truehd': 'TrueHD',
  'amr_nb': 'AMR-NB',
};

String describeCodec(String? raw) {
  if (raw == null || raw.isEmpty) return '';
  final String key = raw.trim().toLowerCase();
  if (key.isEmpty) return '';
  final String? name = _codecNames[key];
  return name == null ? raw : '$name（$raw）';
}

/// 视频信息面板：分辨率、帧率、编码、解码器、像素格式、音频参数。
///
/// mpv 要等文件真正打开并探测完才给得出这些值，纯音频或探测失败时大部分
/// 是 null —— 对应那几行干脆不显示，而不是摆一个「未知」占位。
Future<void> showInfoSheet(
  BuildContext context, {
  required String? resolution,
  required String? fps,
  required String? videoCodec,
  required String? videoDecoder,
  required String? pixelFormat,
  required String? audioCodec,
  required String? audioChannels,
  required int? audioSampleRate,
}) async {
  final List<List<String>> rows = <List<String>>[
    if (resolution != null) <String>['分辨率', resolution],
    if (fps != null) <String>['帧率', '$fps fps'],
    if (videoCodec != null) <String>['视频编码', describeCodec(videoCodec)],
    if (videoDecoder != null) <String>['解码器', videoDecoder],
    if (pixelFormat != null) <String>['像素格式', pixelFormat],
    if (audioCodec != null) <String>['音频编码', describeCodec(audioCodec)],
    if (audioChannels != null) <String>['声道', audioChannels],
    if (audioSampleRate != null)
      <String>['采样率', '${(audioSampleRate / 1000).toStringAsFixed(1)} kHz'],
  ];

  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (BuildContext ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '视频信息',
              style: Theme.of(ctx)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            if (rows.isEmpty)
              Text('暂无可用的流信息', style: Theme.of(ctx).textTheme.bodyMedium)
            else
              for (final List<String> row in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      SizedBox(
                        width: 76,
                        child: Text(
                          row[0],
                          style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                                color:
                                    Theme.of(ctx).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          row[1],
                          style: Theme.of(ctx).textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    ),
  );
}

/// 音轨选择。
///
/// 只有一条音轨时控制层不会显示入口，所以这里不需要处理「只有一个选项」的
/// 空转情况。
Future<void> showTrackSheet(
  BuildContext context,
  PlayerControlsBinding controller,
) async {
  final String? picked = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (BuildContext ctx) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(ctx).height * 0.6,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 12),
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                '音轨',
                style: Theme.of(ctx)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            for (final PlayerAudioTrack t in controller.audioTracks)
              ListTile(
                dense: true,
                leading: Icon(
                  t.id == controller.audioId ? Icons.check : Icons.audiotrack,
                  size: 20,
                ),
                title: Text(t.label),
                subtitle: t.codec.isEmpty ? null : Text(describeCodec(t.codec)),
                onTap: () => Navigator.of(ctx).pop(t.id),
              ),
          ],
        ),
      ),
    ),
  );
  if (picked != null) await controller.selectAudioTrack(picked);
}

/// 定时关闭的选择结果。
///
/// 三种状态互斥，用一个值对象表达比用「Duration? + bool」两个返回值清爽。
class SleepSelection {
  const SleepSelection.timer(this.duration) : atEnd = false;
  const SleepSelection.atEnd()
      : duration = null,
        atEnd = true;
  const SleepSelection.off()
      : duration = null,
        atEnd = false;

  final Duration? duration;
  final bool atEnd;

  bool get isOff => duration == null && !atEnd;
}

/// 定时关闭。选完立刻生效，不再回调确认。
Future<void> showSleepSheet(
  BuildContext context,
  PlayerControlsBinding controller,
) async {
  final Duration? remaining = controller.sleepRemaining;
  final bool atEnd = controller.sleepAtEnd;

  final SleepSelection? result = await showModalBottomSheet<SleepSelection>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (BuildContext ctx) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(ctx).height * 0.6,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 12),
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Text(
                '定时关闭',
                style: Theme.of(ctx)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            if (remaining != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  '还剩 ${formatDurationShort(remaining)} 自动暂停',
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
              ),
            ListTile(
              dense: true,
              leading: Icon(
                remaining == null && !atEnd ? Icons.check : Icons.timer_off,
                size: 20,
              ),
              title: const Text('关闭定时'),
              onTap: () => Navigator.of(ctx).pop(const SleepSelection.off()),
            ),
            for (final int minutes in K.sleepMinutes)
              ListTile(
                dense: true,
                leading: Icon(
                  remaining == Duration(minutes: minutes)
                      ? Icons.check
                      : Icons.timer_outlined,
                  size: 20,
                ),
                title: Text('$minutes 分钟'),
                onTap: () => Navigator.of(ctx).pop(
                  SleepSelection.timer(Duration(minutes: minutes)),
                ),
              ),
            ListTile(
              dense: true,
              leading: Icon(
                atEnd ? Icons.check : Icons.playlist_play,
                size: 20,
              ),
              title: const Text('本集播完'),
              subtitle: const Text('播完当前集就停，不自动连播'),
              onTap: () => Navigator.of(ctx).pop(const SleepSelection.atEnd()),
            ),
          ],
        ),
      ),
    ),
  );

  if (result == null) return;
  if (result.atEnd) {
    await controller.setSleepAtEnd(true);
    return;
  }
  await controller.setSleepTimer(result.duration);
}

/// 手动换源。
///
/// 查找要逐站搜索，慢的时候能拖十几秒，所以弹层自己接住加载态：先出标题，
/// 列表位置放一行「正在查找」，找到后原地换成候选列表。
Future<void> showSourceSheet(
  BuildContext context,
  PlayerControlsBinding controller,
) async {
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (BuildContext ctx) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(ctx).height * 0.6,
        ),
        child: _SourceSheetBody(controller: controller),
      ),
    ),
  );
}

class _SourceSheetBody extends StatefulWidget {
  const _SourceSheetBody({required this.controller});

  final PlayerControlsBinding controller;

  @override
  State<_SourceSheetBody> createState() => _SourceSheetBodyState();
}

class _SourceSheetBodyState extends State<_SourceSheetBody> {
  late Future<List<PlayerSourceOption>> _future = _load();

  Future<List<PlayerSourceOption>> _load() =>
      widget.controller.findAlternateSources();

  void _retry() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return FutureBuilder<List<PlayerSourceOption>>(
      future: _future,
      builder: (BuildContext ctx, AsyncSnapshot<List<PlayerSourceOption>> snap) {
        final bool loading = snap.connectionState != ConnectionState.done;
        final List<PlayerSourceOption> options =
            snap.data ?? const <PlayerSourceOption>[];

        return ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 12),
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Text(
                '切换资源站',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                '在其它已启用的资源站里找同一部片子的同一集',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            if (loading)
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: Row(
                  children: <Widget>[
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 12),
                    Text('正在其它资源站里查找…'),
                  ],
                ),
              )
            else if (snap.hasError)
              ListTile(
                leading: Icon(
                  Icons.error_outline,
                  color: theme.colorScheme.error,
                ),
                title: const Text('查找失败'),
                subtitle: Text('${snap.error}'),
                trailing: TextButton(
                  onPressed: _retry,
                  child: const Text('重试'),
                ),
              )
            else if (options.isEmpty)
              ListTile(
                leading: const Icon(Icons.search_off),
                title: const Text('其它资源站里没找到这部片子'),
                subtitle: const Text('片名、年代或集名对不上时不会列出来，避免播错内容'),
                trailing: TextButton(
                  onPressed: _retry,
                  child: const Text('重新查找'),
                ),
              )
            else
              for (final PlayerSourceOption option in options)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.swap_horiz, size: 20),
                  title: Text(option.label),
                  subtitle: option.episodeLabel.isEmpty
                      ? null
                      : Text(option.episodeLabel),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    widget.controller.switchToSource(option.id);
                  },
                ),
          ],
        );
      },
    );
  }
}

/// 字幕选择与外挂字幕加载。
///
/// 内嵌轨直接列出来；外挂字幕给两个入口（链接 / 本地路径），拉取和解码都在
/// 控制器里做，弹层只负责收集文本。没装文件选择器插件，桌面端粘绝对路径
/// 一样能用，移动端更适合用链接。
Future<void> showSubtitleSheet(
  BuildContext context,
  PlayerControlsBinding controller,
) async {
  final _SubtitleAction? action =
      await showModalBottomSheet<_SubtitleAction>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (BuildContext ctx) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(ctx).height * 0.7,
        ),
        child: ListenableBuilder(
          listenable: controller,
          builder: (BuildContext ctx, _) => ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.only(bottom: 12),
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                child: Text(
                  '字幕',
                  style: Theme.of(ctx)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              ListTile(
                dense: true,
                leading: Icon(
                  controller.subtitleId == 'no'
                      ? Icons.check
                      : Icons.subtitles_off,
                  size: 20,
                ),
                title: const Text('关闭字幕'),
                onTap: () => Navigator.of(ctx).pop(
                  const _SubtitleAction.pick('no'),
                ),
              ),
              if (controller.subtitleTracks.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
                  child: Text(
                    '当前视频没有内嵌字幕，可以加载外挂字幕。',
                    style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                          color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                        ),
                  ),
                )
              else
                for (final PlayerSubtitleTrack t in controller.subtitleTracks)
                  ListTile(
                    dense: true,
                    leading: Icon(
                      t.id == controller.subtitleId
                          ? Icons.check
                          : Icons.subtitles_outlined,
                      size: 20,
                    ),
                    title: Text(t.label),
                    subtitle: Text(
                      t.external ? '外挂字幕' : '内嵌字幕',
                    ),
                    onTap: () => Navigator.of(ctx).pop(
                      _SubtitleAction.pick(t.id),
                    ),
                  ),
              const Divider(height: 1),
              ListTile(
                dense: true,
                leading: const Icon(Icons.link, size: 20),
                title: const Text('从链接加载…'),
                subtitle: const Text('SRT / ASS / WebVTT 的直链'),
                onTap: () => Navigator.of(ctx).pop(
                  const _SubtitleAction.loadUrl(),
                ),
              ),
              ListTile(
                dense: true,
                leading: const Icon(Icons.folder_open, size: 20),
                title: const Text('从本地文件加载…'),
                subtitle: const Text('粘贴字幕文件的完整路径'),
                onTap: () => Navigator.of(ctx).pop(
                  const _SubtitleAction.loadPath(),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  if (action == null) return;
  if (action.pickId != null) {
    await controller.selectSubtitleTrack(action.pickId!);
    return;
  }
  if (!context.mounted) return;
  final String? input = await _promptSubtitleSource(
    context,
    title: action.url ? '字幕链接' : '字幕文件路径',
    hint: action.url ? 'https://example.com/sub.srt' : 'D:\\字幕\\sub.srt',
    keyboardType: action.url ? TextInputType.url : TextInputType.text,
  );
  if (input == null || input.trim().isEmpty) return;
  if (action.url) {
    await controller.loadSubtitleUrl(input);
  } else {
    await controller.loadSubtitlePath(input);
  }
}

/// 弹层选择结果：切轨，或走某个加载入口。
class _SubtitleAction {
  const _SubtitleAction.pick(this.pickId) : url = false;
  const _SubtitleAction.loadUrl()
      : pickId = null,
        url = true;
  const _SubtitleAction.loadPath()
      : pickId = null,
        url = false;

  final String? pickId;
  final bool url;
}

Future<String?> _promptSubtitleSource(
  BuildContext context, {
  required String title,
  required String hint,
  required TextInputType keyboardType,
}) {
  final TextEditingController input = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (BuildContext ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: input,
        autofocus: true,
        keyboardType: keyboardType,
        maxLines: 2,
        minLines: 1,
        decoration: InputDecoration(hintText: hint),
        onSubmitted: (String v) => Navigator.of(ctx).pop(v.trim()),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(input.text.trim()),
          child: const Text('加载'),
        ),
      ],
    ),
  );
}

/// 片头片尾标记。
///
/// 「设为当前」取的是**点下去那一刻**的进度，所以按钮在弹层里点、画面还在
/// 后台继续播也能标得准（弹层不暂停播放）。
Future<void> showSkipSheet(
  BuildContext context,
  PlayerControlsBinding controller,
) async {
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (BuildContext ctx) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(ctx).height * 0.7,
        ),
        child: ListenableBuilder(
          listenable: controller,
          builder: (BuildContext ctx, _) {
            final String now = formatDurationShort(controller.position);
            final String intro = controller.introMs > 0
                ? formatDurationShort(
                    Duration(milliseconds: controller.introMs),
                  )
                : '未标记';
            final String outro = controller.outroMs > 0
                ? formatDurationShort(
                    Duration(milliseconds: controller.outroMs),
                  )
                : '未标记';

            return ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: 12),
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                  child: Text(
                    '片头片尾',
                    style: Theme.of(ctx)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text(
                    '当前进度 $now',
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                ),
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.first_page, size: 20),
                  title: const Text('片头结束'),
                  subtitle: Text('播到 $intro 之前算片头'),
                  trailing: TextButton(
                    onPressed: () =>
                        controller.markIntroAt(controller.position),
                    child: const Text('设为当前'),
                  ),
                ),
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.last_page, size: 20),
                  title: const Text('片尾开始'),
                  subtitle: Text('播到 $outro 之后算片尾'),
                  trailing: TextButton(
                    onPressed: () =>
                        controller.markOutroAt(controller.position),
                    child: const Text('设为当前'),
                  ),
                ),
                SwitchListTile(
                  dense: true,
                  secondary: const Icon(Icons.skip_next_outlined, size: 20),
                  title: const Text('自动跳过片头'),
                  value: controller.autoSkipIntro,
                  onChanged: (bool v) => controller.setAutoSkipIntro(v),
                ),
                SwitchListTile(
                  dense: true,
                  secondary: const Icon(Icons.fast_forward_outlined, size: 20),
                  title: const Text('自动跳过片尾'),
                  subtitle: const Text('播到片尾直接进下一集'),
                  value: controller.autoSkipOutro,
                  onChanged: (bool v) => controller.setAutoSkipOutro(v),
                ),
                if (controller.introMs > 0 || controller.outroMs > 0)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.clear, size: 20),
                    title: const Text('清除标记'),
                    onTap: () => controller.clearSkipMarks(),
                  ),
              ],
            );
          },
        ),
      ),
    ),
  );
}
