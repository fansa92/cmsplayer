import 'package:flutter/material.dart';

import '../../core/utils/responsive.dart';

/// 网格加载时的海报骨架屏。
///
/// 页面级加载态原来一律是屏幕中间一个转圈：切分类、切资源站、重新搜索时
/// 内容整块消失又整块出现，视觉上像「闪一下」。骨架屏保持网格的形状和位置，
/// 数据回来后卡片在原位淡入。
///
/// [animate] 关掉后是纯静态占位，供 widget test 使用 —— 反复运行的
/// AnimationController 会让 `pumpAndSettle()` 永远等不到稳定帧。
class PosterGridSkeleton extends StatefulWidget {
  const PosterGridSkeleton({
    super.key,
    this.itemCount = 12,
    this.animate = true,
    this.padding = const EdgeInsets.fromLTRB(16, 8, 16, 24),
  });

  final int itemCount;
  final bool animate;
  final EdgeInsets padding;

  @override
  State<PosterGridSkeleton> createState() => _PosterGridSkeletonState();
}

class _PosterGridSkeletonState extends State<PosterGridSkeleton>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  @override
  void initState() {
    super.initState();
    if (widget.animate) {
      _controller = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1100),
      )..repeat();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Widget _shimmer({
    required Color base,
    required Color highlight,
    required double radius,
    double? width,
    double? height,
  }) {
    final Animation<double>? animation = _controller;
    final Widget box = SizedBox(width: width, height: height);

    if (animation == null) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: base,
          borderRadius: BorderRadius.circular(radius),
        ),
        child: box,
      );
    }

    return AnimatedBuilder(
      animation: animation,
      builder: (BuildContext context, Widget? child) {
        final double offset = animation.value * 2.4;
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            gradient: LinearGradient(
              begin: Alignment(-1.2 + offset, 0),
              end: Alignment(-0.2 + offset, 0),
              colors: <Color>[base, highlight, base],
            ),
          ),
          child: child,
        );
      },
      child: box,
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color base = theme.colorScheme.surfaceContainerHighest;
    final Color highlight = theme.colorScheme.surfaceContainerLow;

    return Semantics(
      label: '正在加载内容',
      child: ExcludeSemantics(
        child: GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          padding: widget.padding,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: context.gridColumns,
            mainAxisSpacing: 16,
            crossAxisSpacing: 12,
            childAspectRatio: 0.62,
          ),
          itemCount: widget.itemCount,
          itemBuilder: (BuildContext context, int index) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: _shimmer(
                    base: base,
                    highlight: highlight,
                    radius: 10,
                    width: double.infinity,
                    height: double.infinity,
                  ),
                ),
                const SizedBox(height: 6),
                _shimmer(
                  base: base,
                  highlight: highlight,
                  radius: 4,
                  width: double.infinity,
                  height: 12,
                ),
                const SizedBox(height: 4),
                _shimmer(
                  base: base,
                  highlight: highlight,
                  radius: 4,
                  width: 56,
                  height: 10,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
