import '../../core/utils/formatter.dart';
import '../../core/utils/text_utils.dart';

/// 播放记录（同时承担"续播"职责）。
class PlayRecord {
  const PlayRecord({
    required this.key,
    required this.sourceId,
    required this.sourceName,
    required this.vodId,
    required this.vodName,
    this.vodPic = '',
    this.typeName = '',
    this.lineIndex = 0,
    this.episodeIndex = 0,
    this.lineName = '',
    this.episodeName = '',
    this.positionMs = 0,
    this.durationMs = 0,
    this.finished = false,
    this.introMs = 0,
    this.outroMs = 0,
    required this.updatedAt,
  });

  /// `sourceId|vodId`，同一影片跨线路 / 跨集只保留一条记录。
  final String key;
  final String sourceId;
  final String sourceName;
  final String vodId;
  final String vodName;
  final String vodPic;
  final String typeName;
  final int lineIndex;
  final int episodeIndex;
  final String lineName;
  final String episodeName;
  final int positionMs;
  final int durationMs;
  final bool finished;

  /// 片头结束点：从 0 播到这里之间的内容算片头。0 表示没标记。
  ///
  /// 和续播进度存在同一条记录里 —— 它天然是「这部片子」的属性，跟着记录
  /// 一起同步、一起删除，省掉一套独立的存储和墓碑。
  final int introMs;

  /// 片尾开始点：播到这里之后的字幕 / 预告算片尾。0 表示没标记。
  final int outroMs;

  final DateTime updatedAt;

  /// 是否标记过片头 / 片尾。
  bool get hasSkipMarks => introMs > 0 || outroMs > 0;

  factory PlayRecord.fromJson(Map<String, dynamic> json) {
    final String sourceId = strOf(json['sourceId']);
    final String vodId = strOf(json['vodId']);
    return PlayRecord(
      key: strOf(json['key'], '$sourceId|$vodId'),
      sourceId: sourceId,
      sourceName: strOf(json['sourceName']),
      vodId: vodId,
      vodName: strOf(json['vodName']),
      vodPic: strOf(json['vodPic']),
      typeName: strOf(json['typeName']),
      lineIndex: intOf(json['lineIndex']),
      episodeIndex: intOf(json['episodeIndex']),
      lineName: strOf(json['lineName']),
      episodeName: strOf(json['episodeName']),
      positionMs: intOf(json['positionMs']),
      durationMs: intOf(json['durationMs']),
      finished: json['finished'] == true,
      introMs: intOf(json['introMs']),
      outroMs: intOf(json['outroMs']),
      updatedAt: DateTime.tryParse(strOf(json['updatedAt'])) ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'key': key,
        'sourceId': sourceId,
        'sourceName': sourceName,
        'vodId': vodId,
        'vodName': vodName,
        'vodPic': vodPic,
        'typeName': typeName,
        'lineIndex': lineIndex,
        'episodeIndex': episodeIndex,
        'lineName': lineName,
        'episodeName': episodeName,
        'positionMs': positionMs,
        'durationMs': durationMs,
        'finished': finished,
        'introMs': introMs,
        'outroMs': outroMs,
        'updatedAt': updatedAt.toIso8601String(),
      };

  double get progress {
    if (finished) return 1;
    if (durationMs <= 0) return 0;
    return (positionMs / durationMs).clamp(0.0, 1.0);
  }

  /// 进度描述：`看到 01:23` 或 `已看完`。
  String get progressLabel {
    if (finished) return '已看完';
    if (durationMs <= 0 || positionMs <= 0) return '未开始';
    return '看到 ${formatDurationShort(Duration(milliseconds: positionMs))}';
  }

  String get episodeLabel {
    final String ep =
        episodeName.isEmpty ? '第${episodeIndex + 1}集' : episodeName;
    return lineName.isEmpty ? ep : '$lineName · $ep';
  }

  PlayRecord copyWith({
    int? lineIndex,
    int? episodeIndex,
    String? lineName,
    String? episodeName,
    int? positionMs,
    int? durationMs,
    bool? finished,
    int? introMs,
    int? outroMs,
    DateTime? updatedAt,
  }) =>
      PlayRecord(
        key: key,
        sourceId: sourceId,
        sourceName: sourceName,
        vodId: vodId,
        vodName: vodName,
        vodPic: vodPic,
        typeName: typeName,
        lineIndex: lineIndex ?? this.lineIndex,
        episodeIndex: episodeIndex ?? this.episodeIndex,
        lineName: lineName ?? this.lineName,
        episodeName: episodeName ?? this.episodeName,
        positionMs: positionMs ?? this.positionMs,
        durationMs: durationMs ?? this.durationMs,
        finished: finished ?? this.finished,
        introMs: introMs ?? this.introMs,
        outroMs: outroMs ?? this.outroMs,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}
