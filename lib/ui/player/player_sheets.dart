import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../data/models/play_line.dart';

/// 播放器的三个底部弹层：倍速、选集、视频信息。
///
/// 抽到这里是因为它们只读控制器状态 + 一个回调，和手势、自动隐藏无关。
/// 三个弹层都显式限高：`showModalBottomSheet` 默认只给屏高 9/16，手机横屏
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
