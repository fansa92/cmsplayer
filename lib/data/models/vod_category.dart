import '../../core/utils/text_utils.dart';

/// 分类（macCMS 的 `class` 数组）。
class VodCategory {
  const VodCategory({
    required this.id,
    required this.name,
    this.parentId = 0,
  });

  final int id;
  final String name;
  final int parentId;

  factory VodCategory.fromJson(Map<String, dynamic> json) {
    return VodCategory(
      id: intOf(json['type_id']),
      name: strOf(json['type_name']),
      parentId: intOf(json['type_pid']),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'type_id': id,
        'type_name': name,
        'type_pid': parentId,
      };

  @override
  bool operator ==(Object other) =>
      other is VodCategory && other.id == id && other.name == name;

  @override
  int get hashCode => Object.hash(id, name);

  @override
  String toString() => 'VodCategory($id, $name)';
}
