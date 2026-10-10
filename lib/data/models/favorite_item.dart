import '../../core/utils/text_utils.dart';

/// 收藏条目。只存必要字段，详情页点开时再拉一次完整信息。
class FavoriteItem {
  const FavoriteItem({
    required this.key,
    required this.sourceId,
    required this.sourceName,
    required this.vodId,
    required this.vodName,
    this.vodPic = '',
    this.typeName = '',
    this.remarks = '',
    required this.createdAt,
  });

  /// `sourceId|vodId`。
  final String key;
  final String sourceId;
  final String sourceName;
  final String vodId;
  final String vodName;
  final String vodPic;
  final String typeName;
  final String remarks;
  final DateTime createdAt;

  factory FavoriteItem.fromVod({
    required String sourceId,
    required String sourceName,
    required int vodId,
    required String vodName,
    String vodPic = '',
    String typeName = '',
    String remarks = '',
    DateTime? createdAt,
  }) {
    final String id = vodId.toString();
    return FavoriteItem(
      key: '$sourceId|$id',
      sourceId: sourceId,
      sourceName: sourceName,
      vodId: id,
      vodName: vodName,
      vodPic: vodPic,
      typeName: typeName,
      remarks: remarks,
      createdAt: createdAt ?? DateTime.now(),
    );
  }

  factory FavoriteItem.fromJson(Map<String, dynamic> json) {
    final String sourceId = strOf(json['sourceId']);
    final String vodId = strOf(json['vodId']);
    return FavoriteItem(
      key: strOf(json['key'], '$sourceId|$vodId'),
      sourceId: sourceId,
      sourceName: strOf(json['sourceName']),
      vodId: vodId,
      vodName: strOf(json['vodName']),
      vodPic: strOf(json['vodPic']),
      typeName: strOf(json['typeName']),
      remarks: strOf(json['remarks']),
      createdAt: DateTime.tryParse(strOf(json['createdAt'])) ?? DateTime.now(),
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
        'remarks': remarks,
        'createdAt': createdAt.toIso8601String(),
      };
}
