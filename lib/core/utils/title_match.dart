/// 跨源片名比对。
///
/// macCMS 没有「按片名精确查同一部片子」的原子接口，跨源找片、全源对比
/// 都只能先搜索再本地比对。各个站对片名的写法差异很大：
///
///  * 全角空格、末尾的 `(2024)` / `【国语版】`；
///  * 「庆余年 第二季 高清」「庆余年第二季 国语」这类修饰尾巴。
///
/// 这里只做低成本的收敛，不做繁简转换 —— 那需要一张对照表，收益也不明显。
library;

/// 片名尾部的常见修饰词。从长到短匹配，避免「完整版」只削掉「版」。
const List<String> _noiseSuffixes = <String>[
  '在线观看',
  '免费观看',
  '完整版',
  '未删减',
  '国语版',
  '粤语版',
  '中字版',
  '高清版',
  '台配',
  '国语',
  '粤语',
  '高清',
  '完整',
  'HD',
  'hd',
];

final RegExp _spacePattern = RegExp(r'[\s\u3000]+');
final RegExp _bracketPattern = RegExp(r'[\(（\[【][^\)）\]】]*[\)）\]】]');

/// 把片名收敛成可比较的形式：小写、去空白、去括号内容、去修饰尾巴。
String normalizeTitle(String raw) {
  String text = raw.toLowerCase().trim();
  text = text.replaceAll(_spacePattern, '');
  text = text.replaceAll(_bracketPattern, '');
  bool changed = true;
  while (changed && text.isNotEmpty) {
    changed = false;
    for (final String suffix in _noiseSuffixes) {
      if (text.endsWith(suffix.toLowerCase()) && text.length > suffix.length) {
        text = text.substring(0, text.length - suffix.length);
        changed = true;
      }
    }
  }
  return text;
}

/// 两个片名是否算同一部片子。
///
/// 归一化后相等，或一方是另一方的前缀且只多出不超过 4 个字 —— 后者用于
/// 「庆余年」对「庆余年第二季」这类情况，宁可多给一个候选，也不要因为
/// 一个多余的字就认定不是同一部。
bool sameTitle(String a, String b) {
  final String x = normalizeTitle(a);
  final String y = normalizeTitle(b);
  if (x.isEmpty || y.isEmpty) return false;
  if (x == y) return true;
  if (x.startsWith(y) && x.length - y.length <= 4) return true;
  if (y.startsWith(x) && y.length - x.length <= 4) return true;
  return false;
}

/// 搜索时用的关键词：去掉括号内容与修饰尾缀，但**保留原大小写**。
///
/// 带着 `(2024)` 去搜索，很多站的关键词匹配会直接落空；而全小写交给
/// 关键词接口又可能把英文片名搜丢，所以这里单独走一遍只剥修饰的流程。
String searchTitle(String raw) {
  String text = raw.trim().replaceAll(_bracketPattern, '');
  text = text.replaceAll(_spacePattern, ' ').trim();
  bool changed = true;
  while (changed && text.isNotEmpty) {
    changed = false;
    for (final String suffix in _noiseSuffixes) {
      if (text.endsWith(suffix) && text.length > suffix.length) {
        text = text.substring(0, text.length - suffix.length).trim();
        changed = true;
      }
    }
  }
  return text.isEmpty ? raw.trim() : text;
}

/// 从集名里提取序号：`第01集` / `01` / `第 1 话` 都能取出 1。
int? episodeNumber(String name) {
  final RegExpMatch? match = RegExp(r'(\d+)').firstMatch(name);
  if (match == null) return null;
  return int.tryParse(match.group(1)!);
}

/// 两个年份是否可能属于同一部片子。
///
/// 任意一方缺失就认为可能 —— 很多站不填年代，卡太严会漏掉一半结果；
/// 两边都有且不同则基本可以断定是同名翻拍，不该混为一谈。
bool yearCompatible(String a, String b) {
  final String x = a.trim();
  final String y = b.trim();
  if (x.isEmpty || y.isEmpty) return true;
  return x == y;
}
