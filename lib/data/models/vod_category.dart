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

  /// 剔除父分类，只留下真正带内容的叶子分类。
  ///
  /// macCMS 的 `class` 是分层的：`type_pid == 0` 的是父分类（电影片 / 连续剧 /
  /// 综艺片 / 动漫片），条目全部挂在子分类下。父分类本身查询必然返回空列表
  /// （实测 `t=1` → `total:0, list:[]`），而 `class` 的排列顺序又是父分类在前，
  /// 直接取前 N 个会让前几个入口全部落空。
  ///
  /// 分类表没有分层时（没有 `type_pid`，或所有项都是叶子）原样返回；
  /// 结构异常导致筛完为空时也退回原列表，总比什么都不显示强。
  static List<VodCategory> leafOnly(List<VodCategory> categories) {
    if (categories.isEmpty) return categories;
    final Set<int> parents =
        categories.map((VodCategory e) => e.parentId).where((int p) => p > 0).toSet();
    if (parents.isEmpty) return categories;
    final List<VodCategory> leaves =
        categories.where((VodCategory e) => !parents.contains(e.id)).toList();
    return leaves.isEmpty ? categories : leaves;
  }

  @override
  bool operator ==(Object other) =>
      other is VodCategory && other.id == id && other.name == name;

  @override
  int get hashCode => Object.hash(id, name);

  @override
  String toString() => 'VodCategory($id, $name)';
}
