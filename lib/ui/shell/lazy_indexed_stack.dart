import 'package:flutter/material.dart';

/// 只挂载「访问过」的页签的 [IndexedStack]。
///
/// 原生 [IndexedStack] 会把所有 children 一次性 inflate。五个主页面同时存在时，
/// 冷启动会连着触发磁盘读取、搜索历史加载、收藏/历史整份网格构建和几百张海报
/// 请求，而用户此刻只看得见首页。这里给未访问的页放一个空盒子，第一次切过去
/// 才真正创建；已经访问过的页继续保活，回来时滚动位置和输入内容都不丢。
class LazyIndexedStack extends StatefulWidget {
  const LazyIndexedStack({
    super.key,
    required this.index,
    required this.itemCount,
    required this.builder,
  });

  final int index;
  final int itemCount;
  final Widget Function(int index) builder;

  @override
  State<LazyIndexedStack> createState() => _LazyIndexedStackState();
}

class _LazyIndexedStackState extends State<LazyIndexedStack> {
  late final Set<int> _visited = <int>{widget.index};

  @override
  void didUpdateWidget(LazyIndexedStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 切页发生在父级 setState 里，这里在新帧 build 之前先把目标页标为已访问。
    _visited.add(widget.index);
  }

  @override
  Widget build(BuildContext context) {
    return IndexedStack(
      index: widget.index,
      children: <Widget>[
        for (int i = 0; i < widget.itemCount; i++)
          _visited.contains(i) ? widget.builder(i) : const SizedBox.shrink(),
      ],
    );
  }
}
