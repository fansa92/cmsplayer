import '../../core/utils/text_utils.dart';

/// 一个资源站的测速结果。
///
/// [latencyMs] 为 -1 表示这次没测通（超时 / 接口报错 / 域名打不开），
/// 和「延迟很高」是两回事：界面上不可用的源不该被排进「慢但能用」里。
class SourceHealth {
  const SourceHealth({
    required this.sourceId,
    required this.latencyMs,
    required this.checkedAt,
  });

  final String sourceId;
  final int latencyMs;
  final DateTime checkedAt;

  bool get ok => latencyMs >= 0;

  /// 速度档位。分界值按 macCMS 接口的常见体感取整：
  /// 300ms 内基本感觉不到等待，800ms 之后每次翻页都明显卡一下。
  SourceSpeed get speed {
    if (!ok) return SourceSpeed.dead;
    if (latencyMs <= 300) return SourceSpeed.fast;
    if (latencyMs <= 800) return SourceSpeed.normal;
    return SourceSpeed.slow;
  }

  String get latencyLabel => ok ? '$latencyMs ms' : '不可用';

  String get speedLabel => switch (speed) {
        SourceSpeed.fast => '很快',
        SourceSpeed.normal => '正常',
        SourceSpeed.slow => '偏慢',
        SourceSpeed.dead => '不可用',
      };

  factory SourceHealth.fromJson(Map<String, dynamic> json) {
    final int latency = intOf(json['latencyMs'], -1);
    return SourceHealth(
      sourceId: strOf(json['sourceId']),
      latencyMs: latency < 0 ? -1 : latency,
      checkedAt: DateTime.tryParse(strOf(json['checkedAt'])) ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'sourceId': sourceId,
        'latencyMs': latencyMs,
        'checkedAt': checkedAt.toIso8601String(),
      };
}

/// 测速档位，供界面选颜色与文案。
enum SourceSpeed { fast, normal, slow, dead }
